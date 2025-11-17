# Spring PetClinic DevOps CI/CD 프로젝트

## 📌 프로젝트 개요

Spring PetClinic 애플리케이션을 AWS 클라우드 환경에서 완전 자동화된 CI/CD 파이프라인으로 배포하는 DevOps 프로젝트입니다.

### 기술 스택
- **애플리케이션**: Spring Boot 4.0, Java 17, PostgreSQL
- **컨테이너**: Docker, Multi-stage Build
- **CI/CD**: Jenkins Pipeline
- **AWS 서비스**: ECS Fargate, ECR, ALB, RDS, VPC, CloudWatch
- **빌드 도구**: Gradle

---

## 🚀 빠른 시작

### 1. 로컬 개발 환경 실행

#### Docker Compose로 실행 (권장)
```bash
# PostgreSQL + 3개 애플리케이션 서비스 실행
docker-compose up -d

# 로그 확인
docker-compose logs -f

# 접속
# Front: http://localhost:8080
# Back1: http://localhost:8081
# Back2: http://localhost:8082

# 종료
docker-compose down
```

#### Gradle로 직접 실행
```bash
# PostgreSQL 먼저 실행
docker-compose up -d postgres

# 애플리케이션 실행
./gradlew bootRun

# 접속
# http://localhost:8080
```

---

## 📁 프로젝트 구조

```
spring-petclinic-main/
├── src/
│   └── main/
│       ├── java/                          # Java 소스 코드
│       └── resources/
│           ├── application.properties     # 기본 설정
│           ├── application-prod.properties # 운영 환경 설정
│           └── db/postgres/               # PostgreSQL 스키마
│
├── Dockerfile                             # Docker 이미지 빌드 설정
├── .dockerignore                          # Docker 빌드 제외 파일
├── docker-compose.yml                     # 로컬 테스트용 구성
├── Jenkinsfile                            # CI/CD 파이프라인 정의
│
├── ecs-task-definition-front.json        # ECS Front 서비스 정의
├── ecs-task-definition-back1.json        # ECS Back1 서비스 정의
├── ecs-task-definition-back2.json        # ECS Back2 서비스 정의
│
├── 배포과정설명.md                         # 배포 흐름 상세 문서
└── README-DEVOPS.md                       # 본 문서
```

---

## 🏗️ AWS 인프라 구축 단계

### 사전 준비사항
- AWS 계정
- AWS CLI 설치 및 구성
- Docker 설치
- Jenkins 서버 (EC2)

### Step 1: VPC 및 네트워크 구성

```bash
# VPC 생성
aws ec2 create-vpc --cidr-block 10.0.0.0/16

# Public Subnet 생성 (2개, 2AZ)
aws ec2 create-subnet --vpc-id <vpc-id> --cidr-block 10.0.1.0/24 --availability-zone ap-northeast-2a
aws ec2 create-subnet --vpc-id <vpc-id> --cidr-block 10.0.2.0/24 --availability-zone ap-northeast-2b

# Private Subnet 생성 (4개, ECS용 2개 + RDS용 2개)
aws ec2 create-subnet --vpc-id <vpc-id> --cidr-block 10.0.10.0/24 --availability-zone ap-northeast-2a
aws ec2 create-subnet --vpc-id <vpc-id> --cidr-block 10.0.11.0/24 --availability-zone ap-northeast-2b
aws ec2 create-subnet --vpc-id <vpc-id> --cidr-block 10.0.20.0/24 --availability-zone ap-northeast-2a
aws ec2 create-subnet --vpc-id <vpc-id> --cidr-block 10.0.21.0/24 --availability-zone ap-northeast-2b

# Internet Gateway 생성 및 연결
aws ec2 create-internet-gateway
aws ec2 attach-internet-gateway --vpc-id <vpc-id> --internet-gateway-id <igw-id>

# NAT Gateway 생성 (각 Public Subnet에)
aws ec2 create-nat-gateway --subnet-id <public-subnet-1> --allocation-id <eip-alloc-id>
aws ec2 create-nat-gateway --subnet-id <public-subnet-2> --allocation-id <eip-alloc-id>
```

### Step 2: 보안 그룹 생성

```bash
# ALB Security Group
aws ec2 create-security-group --group-name petclinic-alb-sg \
  --description "Security group for ALB" --vpc-id <vpc-id>
aws ec2 authorize-security-group-ingress --group-id <alb-sg-id> \
  --protocol tcp --port 80 --cidr 0.0.0.0/0

# ECS Security Group
aws ec2 create-security-group --group-name petclinic-ecs-sg \
  --description "Security group for ECS" --vpc-id <vpc-id>
aws ec2 authorize-security-group-ingress --group-id <ecs-sg-id> \
  --protocol tcp --port 8080 --source-group <alb-sg-id>

# RDS Security Group
aws ec2 create-security-group --group-name petclinic-rds-sg \
  --description "Security group for RDS" --vpc-id <vpc-id>
aws ec2 authorize-security-group-ingress --group-id <rds-sg-id> \
  --protocol tcp --port 5432 --source-group <ecs-sg-id>
```

### Step 3: ECR 리포지토리 생성

```bash
# 3개 리포지토리 생성
aws ecr create-repository --repository-name front --region ap-northeast-2
aws ecr create-repository --repository-name back1 --region ap-northeast-2
aws ecr create-repository --repository-name back2 --region ap-northeast-2

# 라이프사이클 정책 설정 (최근 10개 이미지만 보관)
aws ecr put-lifecycle-policy --repository-name front \
  --lifecycle-policy-text file://ecr-lifecycle-policy.json
```

**ecr-lifecycle-policy.json**:
```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep last 10 images",
      "selection": {
        "tagStatus": "any",
        "countType": "imageCountMoreThan",
        "countNumber": 10
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
```

### Step 4: RDS PostgreSQL 생성

```bash
# DB Subnet Group 생성
aws rds create-db-subnet-group \
  --db-subnet-group-name petclinic-db-subnet \
  --db-subnet-group-description "Subnet group for PetClinic RDS" \
  --subnet-ids <private-subnet-3> <private-subnet-4>

# RDS 인스턴스 생성 (Multi-AZ)
aws rds create-db-instance \
  --db-instance-identifier petclinic-db \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version 14.7 \
  --master-username petclinic \
  --master-user-password <your-password> \
  --allocated-storage 20 \
  --vpc-security-group-ids <rds-sg-id> \
  --db-subnet-group-name petclinic-db-subnet \
  --multi-az \
  --backup-retention-period 7 \
  --publicly-accessible false
```

### Step 5: Secrets Manager에 DB 정보 저장

```bash
# DB URL
aws secretsmanager create-secret \
  --name petclinic/db/url \
  --secret-string "jdbc:postgresql://<rds-endpoint>:5432/petclinic"

# DB Username
aws secretsmanager create-secret \
  --name petclinic/db/username \
  --secret-string "petclinic"

# DB Password
aws secretsmanager create-secret \
  --name petclinic/db/password \
  --secret-string "<your-password>"
```

### Step 6: ECS 클러스터 생성

```bash
# Fargate 클러스터 생성
aws ecs create-cluster --cluster-name petclinic-cluster --region ap-northeast-2

# CloudWatch Log Group 생성
aws logs create-log-group --log-group-name /ecs/petclinic-front
aws logs create-log-group --log-group-name /ecs/petclinic-back1
aws logs create-log-group --log-group-name /ecs/petclinic-back2
```

### Step 7: IAM Role 생성

#### ECS Task Execution Role
```bash
aws iam create-role --role-name ecsTaskExecutionRole \
  --assume-role-policy-document file://ecs-task-execution-trust-policy.json

aws iam attach-role-policy --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

# Secrets Manager 접근 권한 추가
aws iam attach-role-policy --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite
```

**ecs-task-execution-trust-policy.json**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

### Step 8: ECS Task Definition 등록

```bash
# 3개 Task Definition 등록
aws ecs register-task-definition --cli-input-json file://ecs-task-definition-front.json
aws ecs register-task-definition --cli-input-json file://ecs-task-definition-back1.json
aws ecs register-task-definition --cli-input-json file://ecs-task-definition-back2.json
```

### Step 9: ALB 생성

```bash
# ALB 생성
aws elbv2 create-load-balancer \
  --name petclinic-alb \
  --subnets <public-subnet-1> <public-subnet-2> \
  --security-groups <alb-sg-id> \
  --scheme internet-facing \
  --type application

# Target Group 생성 (3개)
aws elbv2 create-target-group \
  --name petclinic-front-tg \
  --protocol HTTP \
  --port 8080 \
  --vpc-id <vpc-id> \
  --target-type ip \
  --health-check-path /actuator/health \
  --health-check-interval-seconds 30

# 동일하게 back1-tg, back2-tg 생성

# Listener 생성
aws elbv2 create-listener \
  --load-balancer-arn <alb-arn> \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=<front-tg-arn>
```

### Step 10: ECS Service 생성

```bash
# Front Service 생성
aws ecs create-service \
  --cluster petclinic-cluster \
  --service-name front-service \
  --task-definition petclinic-front-task \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[<private-subnet-1>,<private-subnet-2>],securityGroups=[<ecs-sg-id>]}" \
  --load-balancers "targetGroupArn=<front-tg-arn>,containerName=petclinic-front,containerPort=8080"

# 동일하게 back1-service, back2-service 생성
```

---

## 🔧 Jenkins 설정

### 1. Jenkins 플러그인 설치
- Docker Pipeline
- AWS Steps
- GitHub Integration
- Pipeline

### 2. Credentials 설정
Jenkins > Manage Jenkins > Credentials에서 추가:

- **aws-cred**: AWS Access Key & Secret Key
  - Kind: AWS Credentials
  - ID: `aws-cred`
  - Access Key ID: `<your-access-key>`
  - Secret Access Key: `<your-secret-key>`

- **github-token**: GitHub Personal Access Token
  - Kind: Secret text
  - ID: `github-token`
  - Secret: `<your-github-token>`

### 3. Jenkins Job 생성
1. New Item > Pipeline 선택
2. Pipeline section:
   - Definition: Pipeline script from SCM
   - SCM: Git
   - Repository URL: `https://github.com/<username>/spring-petclinic.git`
   - Branch: `main`
   - Script Path: `Jenkinsfile`
3. Build Triggers:
   - GitHub hook trigger for GITScm polling 체크

### 4. GitHub Webhook 설정
GitHub Repository > Settings > Webhooks > Add webhook
- Payload URL: `http://<jenkins-server>:8080/github-webhook/`
- Content type: `application/json`
- Events: Just the push event

---

## 🧪 테스트 및 검증

### 로컬 Docker 빌드 테스트
```bash
# 이미지 빌드
docker build -t petclinic-test .

# 컨테이너 실행
docker run -d -p 8080:8080 \
  -e SPRING_PROFILES_ACTIVE=prod \
  -e DB_URL=jdbc:postgresql://<rds-endpoint>:5432/petclinic \
  -e DB_USERNAME=petclinic \
  -e DB_PASSWORD=<password> \
  petclinic-test

# 헬스체크
curl http://localhost:8080/actuator/health

# 로그 확인
docker logs <container-id>
```

### CI/CD 파이프라인 테스트
```bash
# 코드 변경 후 푸시
echo "# Test" >> README.md
git add .
git commit -m "test: CI/CD 파이프라인 테스트"
git push origin main

# Jenkins에서 빌드 확인
# http://<jenkins-server>:8080/job/<job-name>/

# ECS 배포 확인
aws ecs list-tasks --cluster petclinic-cluster

# ALB 엔드포인트 접속
curl http://<alb-dns-name>/
```

---

## 📊 모니터링

### CloudWatch Logs 확인
```bash
# Front 서비스 로그
aws logs tail /ecs/petclinic-front --follow

# 특정 시간대 로그 조회
aws logs filter-log-events \
  --log-group-name /ecs/petclinic-front \
  --start-time $(date -d "1 hour ago" +%s)000 \
  --filter-pattern "ERROR"
```

### ECS 서비스 상태 확인
```bash
# 서비스 상태
aws ecs describe-services --cluster petclinic-cluster --services front-service

# Task 상태
aws ecs list-tasks --cluster petclinic-cluster --service-name front-service
aws ecs describe-tasks --cluster petclinic-cluster --tasks <task-id>

# Target Group Health
aws elbv2 describe-target-health --target-group-arn <tg-arn>
```

---

## 🔒 보안 체크리스트

- [ ] RDS는 Private Subnet에 위치
- [ ] ECS Task는 Private Subnet에 위치
- [ ] Secrets Manager로 민감 정보 관리
- [ ] Security Group 최소 권한 원칙 적용
- [ ] Jenkins에 AWS Credentials 안전하게 저장
- [ ] ALB에 HTTPS 설정 (선택사항)
- [ ] WAF 설정 (선택사항)

---

## 🛠️ 트러블슈팅

### 문제: Task가 시작되지 않음
```bash
# Task 실패 이유 확인
aws ecs describe-tasks --cluster petclinic-cluster --tasks <task-id>

# 주요 원인:
# 1. ECR 이미지를 Pull할 수 없음 → IAM Role 권한 확인
# 2. Subnet에 NAT Gateway 없음 → 라우팅 테이블 확인
# 3. Secrets Manager 접근 불가 → IAM Role 권한 확인
```

### 문제: Health Check 실패
```bash
# Target Health 확인
aws elbv2 describe-target-health --target-group-arn <tg-arn>

# Task에 직접 접속해서 확인
aws ecs execute-command --cluster petclinic-cluster \
  --task <task-id> \
  --container petclinic-front \
  --interactive \
  --command "/bin/sh"

# 컨테이너 내부에서
curl localhost:8080/actuator/health
```

### 문제: DB 연결 실패
```bash
# RDS 엔드포인트 확인
aws rds describe-db-instances --db-instance-identifier petclinic-db

# Security Group 확인
aws ec2 describe-security-groups --group-ids <rds-sg-id>

# Task에서 DB 연결 테스트
psql -h <rds-endpoint> -U petclinic -d petclinic
```

---

## 📚 참고 자료

- [Spring PetClinic 공식 문서](https://github.com/spring-projects/spring-petclinic)
- [AWS ECS Fargate 문서](https://docs.aws.amazon.com/ecs/index.html)
- [Jenkins Pipeline 문서](https://www.jenkins.io/doc/book/pipeline/)
- [Docker 베스트 프랙티스](https://docs.docker.com/develop/dev-best-practices/)

---

## 📞 문의

프로젝트 관련 문의사항은 GitHub Issues에 등록해주세요.

**작성일**: 2025년
**프로젝트**: Spring PetClinic DevOps CI/CD
