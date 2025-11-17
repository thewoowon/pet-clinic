# Jenkins 서버 설정 가이드

## Jenkins 서버 정보

- **Jenkins URL**: http://13.124.230.63:8080
- **초기 Admin 비밀번호**: `94f39a7659bd4c2ab417ae9b0e8efbdb`
- **SSH 접속**: `ssh -i /tmp/jenkins-key.pem ec2-user@13.124.230.63`
- **Instance ID**: i-0c5e34a37cb534f76

---

## 1단계: Jenkins 초기 설정

### 1.1 브라우저에서 Jenkins 접속

1. 브라우저에서 http://13.124.230.63:8080 접속
2. "Unlock Jenkins" 화면에서 초기 비밀번호 입력: `94f39a7659bd4c2ab417ae9b0e8efbdb`
3. **"Install suggested plugins"** 선택 (약 5-10분 소요)
4. Admin 사용자 생성:
   - Username: `admin`
   - Password: (원하는 비밀번호 설정)
   - Full name: `Admin`
   - Email: (본인 이메일)
5. Jenkins URL 확인: `http://13.124.230.63:8080/` (그대로 유지)
6. **"Start using Jenkins"** 클릭

---

## 2단계: 필수 플러그인 추가 설치

### 2.1 Manage Jenkins → Plugins → Available plugins

다음 플러그인들을 검색하여 설치:

1. **Docker Pipeline** - Docker 빌드 및 푸시
2. **Amazon ECR** - AWS ECR 연동
3. **Pipeline: AWS Steps** - AWS CLI 명령어 실행
4. **CloudBees AWS Credentials** - AWS Credentials 관리
5. **Git** (이미 설치되어 있을 것)
6. **GitHub** - GitHub 연동

설치 후 **"Restart Jenkins when installation is complete"** 체크

---

## 3단계: Credentials 설정

### 3.1 AWS Credentials 추가

**Manage Jenkins → Credentials → System → Global credentials → Add Credentials**

1. **Kind**: `AWS Credentials`
2. **ID**: `aws-credentials`
3. **Description**: `AWS Access Key for ECR and ECS`
4. **Access Key ID**: (AWS IAM Access Key)
5. **Secret Access Key**: (AWS IAM Secret Key)
6. **Save**

### 3.2 GitHub Personal Access Token 추가

**Manage Jenkins → Credentials → System → Global credentials → Add Credentials**

1. **Kind**: `Username with password`
2. **Username**: (GitHub 사용자명)
3. **Password**: (GitHub Personal Access Token)
4. **ID**: `github-credentials`
5. **Description**: `GitHub Personal Access Token`
6. **Save**

**GitHub Personal Access Token 생성 방법:**
- GitHub → Settings → Developer settings → Personal access tokens → Generate new token
- 권한 선택: `repo` (전체), `admin:repo_hook`

---

## 4단계: Pipeline Job 생성

### 4.1 새 Pipeline Job 생성

1. **Dashboard → New Item**
2. **Item name**: `spring-petclinic-deploy`
3. **Type**: `Pipeline`
4. **OK** 클릭

### 4.2 Pipeline 설정

#### General 섹션
- **Description**: `Spring PetClinic CI/CD Pipeline`
- **GitHub project**: (체크) → `https://github.com/<your-username>/<your-repo>`

#### Build Triggers
- **GitHub hook trigger for GITScm polling** (체크)

#### Pipeline 섹션

**Definition**: `Pipeline script from SCM`

**SCM**: `Git`

**Repository URL**: `https://github.com/<your-username>/<your-repo>.git`

**Credentials**: `github-credentials` (위에서 생성한 것)

**Branch**: `*/main` (또는 `*/master`)

**Script Path**: `Jenkinsfile`

**Save** 클릭

---

## 5단계: Jenkinsfile 수정

프로젝트의 `Jenkinsfile`이 현재 상태에 맞게 설정되어 있는지 확인:

```groovy
pipeline {
    agent any

    environment {
        AWS_REGION = 'ap-northeast-2'
        ECR_REGISTRY = '205922933402.dkr.ecr.ap-northeast-2.amazonaws.com'
        ECS_CLUSTER = 'petclinic-cluster'
        AWS_CREDENTIALS = credentials('aws-credentials')
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build') {
            steps {
                sh './gradlew clean build -x test'
            }
        }

        stage('Docker Build') {
            steps {
                script {
                    sh "docker build -t front:latest -f Dockerfile ."
                    sh "docker build -t back1:latest -f Dockerfile ."
                    sh "docker build -t back2:latest -f Dockerfile ."
                }
            }
        }

        stage('ECR Login') {
            steps {
                sh '''
                    aws ecr get-login-password --region ${AWS_REGION} | \
                    docker login --username AWS --password-stdin ${ECR_REGISTRY}
                '''
            }
        }

        stage('Push to ECR') {
            parallel {
                stage('Push Front') {
                    steps {
                        sh '''
                            docker tag front:latest ${ECR_REGISTRY}/front:latest
                            docker push ${ECR_REGISTRY}/front:latest
                        '''
                    }
                }
                stage('Push Back1') {
                    steps {
                        sh '''
                            docker tag back1:latest ${ECR_REGISTRY}/back1:latest
                            docker push ${ECR_REGISTRY}/back1:latest
                        '''
                    }
                }
                stage('Push Back2') {
                    steps {
                        sh '''
                            docker tag back2:latest ${ECR_REGISTRY}/back2:latest
                            docker push ${ECR_REGISTRY}/back2:latest
                        '''
                    }
                }
            }
        }

        stage('Deploy to ECS') {
            parallel {
                stage('Deploy Front') {
                    steps {
                        sh '''
                            aws ecs update-service \
                                --cluster ${ECS_CLUSTER} \
                                --service front-service \
                                --force-new-deployment \
                                --region ${AWS_REGION}
                        '''
                    }
                }
                stage('Deploy Back1') {
                    steps {
                        sh '''
                            aws ecs update-service \
                                --cluster ${ECS_CLUSTER} \
                                --service back1-service \
                                --force-new-deployment \
                                --region ${AWS_REGION}
                        '''
                    }
                }
                stage('Deploy Back2') {
                    steps {
                        sh '''
                            aws ecs update-service \
                                --cluster ${ECS_CLUSTER} \
                                --service back2-service \
                                --force-new-deployment \
                                --region ${AWS_REGION}
                        '''
                    }
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                script {
                    sh '''
                        echo "Waiting for services to stabilize..."
                        sleep 30

                        for service in front-service back1-service back2-service; do
                            echo "Checking $service..."
                            aws ecs describe-services \
                                --cluster ${ECS_CLUSTER} \
                                --services $service \
                                --region ${AWS_REGION} \
                                --query 'services[0].[serviceName,runningCount,desiredCount]' \
                                --output table
                        done
                    '''
                }
            }
        }
    }

    post {
        success {
            echo 'Deployment successful!'
        }
        failure {
            echo 'Deployment failed!'
        }
    }
}
```

---

## 6단계: GitHub Webhook 설정 (선택사항)

GitHub에서 자동으로 Jenkins를 트리거하려면:

1. **GitHub 리포지토리 → Settings → Webhooks → Add webhook**
2. **Payload URL**: `http://13.124.230.63:8080/github-webhook/`
3. **Content type**: `application/json`
4. **Which events**: `Just the push event`
5. **Active** 체크
6. **Add webhook**

---

## 7단계: 첫 빌드 실행

### 7.1 수동 빌드

1. Jenkins Dashboard → `spring-petclinic-deploy` 클릭
2. **"Build Now"** 클릭
3. 빌드 진행 상황 확인 (Blue Ocean 또는 Console Output)

### 7.2 자동 빌드 (Webhook 설정 후)

Git Push하면 자동으로 빌드가 시작됩니다:

```bash
git add .
git commit -m "Test Jenkins CI/CD"
git push origin main
```

---

## 8단계: 배포 확인

빌드가 성공하면:

1. **ECS 서비스 확인**:
   ```bash
   ./scripts/check-ecs-status.sh
   ```

2. **애플리케이션 접속**:
   - Front: http://<front-public-ip>:8080
   - Back1: http://<back1-public-ip>:8080
   - Back2: http://<back2-public-ip>:8080

---

## 문제 해결

### Jenkins가 Docker 명령어를 실행할 수 없는 경우

```bash
ssh -i /tmp/jenkins-key.pem ec2-user@13.124.230.63
sudo usermod -a -G docker jenkins
sudo systemctl restart jenkins
```

### AWS CLI 권한 오류

EC2 Instance Profile (EC2AscenderRole)에 다음 권한이 있는지 확인:
- `AmazonEC2ContainerRegistryFullAccess`
- `AmazonECS_FullAccess`

### Jenkins 재시작

```bash
ssh -i /tmp/jenkins-key.pem ec2-user@13.124.230.63
sudo systemctl restart jenkins
```

---

## 다음 단계

1. ✅ Jenkins 서버 설치 완료
2. ✅ 초기 설정 완료
3. ⬜ 플러그인 설치
4. ⬜ Credentials 설정
5. ⬜ Pipeline Job 생성
6. ⬜ 첫 빌드 실행
7. ⬜ 배포 검증

---

## 참고 사항

- Jenkins 서버는 t3.medium (2 vCPU, 4GB RAM)으로 실행 중
- Docker 빌드는 메모리를 많이 사용하므로 필요시 인스턴스 타입 변경
- EC2 비용 절감을 위해 사용하지 않을 때는 인스턴스 중지
- 프로덕션 환경에서는 HTTPS 설정 및 보안 강화 필요
