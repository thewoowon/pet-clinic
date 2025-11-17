# 📜 스크립트 사용 가이드

## 📦 스크립트 목록

| 스크립트 | 용도 | 비용 발생 |
|---------|------|----------|
| `check-aws-resources.sh` | AWS 리소스 상태 확인 | ❌ |
| `create-aws-resources.sh` | AWS 리소스 생성 | ⚠️ 예 |
| `destroy-aws-resources.sh` | AWS 리소스 삭제 | ❌ |
| `local-build-test.sh` | 로컬 빌드 및 테스트 | ❌ |
| `aws-deploy.sh` | AWS ECS 수동 배포 | ❌ |

---

## 🔍 1. check-aws-resources.sh

### 용도
현재 AWS 계정에 어떤 리소스가 있는지 확인

### 사용법
```bash
./scripts/check-aws-resources.sh
```

### 확인 항목
- AWS CLI 설치 여부
- AWS 자격증명 유효성
- ECR 리포지토리 (front, back1, back2)
- ECS 클러스터 및 서비스
- VPC
- ALB
- RDS 인스턴스
- Secrets Manager
- IAM Roles

### 출력 예시
```
✓ AWS CLI 설치됨
✓ AWS 자격증명 유효
⚠ ECR 리포지토리 없음 (생성 필요)
⚠ ECS 클러스터 없음 (생성 필요)
```

---

## 🚀 2. create-aws-resources.sh

### 용도
CI/CD에 필요한 AWS 리소스 자동 생성

### ⚠️ 주의사항
- **비용 발생**: ECS, ECR 등 일부 리소스는 사용량에 따라 비용 발생
- **한 번만 실행**: 중복 실행하면 이미 있는 리소스는 건너뜀
- **실행 시간**: 약 2-3분 소요

### 사용법
```bash
./scripts/create-aws-resources.sh
```

### 확인 메시지
```
⚠️  경고: 이 스크립트는 AWS 리소스를 생성하여 비용이 발생할 수 있습니다.

계속하시겠습니까? (yes/no):
```

### 생성되는 리소스
1. **ECR 리포지토리** (3개)
   - front
   - back1
   - back2
   - 이미지 스캔 활성화
   - 라이프사이클 정책 (최근 10개 이미지만 보관)

2. **VPC 및 서브넷**
   - Default VPC 사용
   - 기존 서브넷 활용

3. **Security Groups**
   - petclinic-ecs-sg
   - 포트 8080, 5432 오픈

4. **IAM Roles**
   - ecsTaskExecutionRole
   - ecsTaskRole
   - 필요한 정책 자동 연결

5. **ECS 클러스터**
   - petclinic-cluster

6. **CloudWatch Log Groups** (3개)
   - /ecs/petclinic-front
   - /ecs/petclinic-back1
   - /ecs/petclinic-back2
   - 보존 기간: 7일

7. **ECS Task Definitions** (3개)
   - petclinic-front-task
   - petclinic-back1-task
   - petclinic-back2-task

### 비용 예상
- **ECR**: 저장된 이미지 크기에 따라 (첫 1GB는 무료)
- **ECS**: Task 실행 시간에 따라 (Fargate)
- **CloudWatch Logs**: 로그 저장량에 따라 (처음 5GB 무료)
- **총 예상**: 테스트 목적이면 월 $5-10 정도

---

## 🔥 3. destroy-aws-resources.sh

### 용도
생성한 AWS 리소스를 자동으로 삭제 (비용 절감)

### ⚠️ 주의사항
- **되돌릴 수 없음**: 삭제된 리소스는 복구 불가
- **데이터 손실**: ECR 이미지, CloudWatch 로그 모두 삭제됨
- **확인 필요**: `DELETE` 입력 필요

### 사용법
```bash
./scripts/destroy-aws-resources.sh
```

### 확인 메시지
```
⚠️  경고: 이 스크립트는 다음 리소스를 삭제합니다:
  - ECR 리포지토리 및 모든 이미지 (front, back1, back2)
  - ECS 서비스 (front-service, back1-service, back2-service)
  - ECS Task Definitions
  - ECS 클러스터 (petclinic-cluster)
  - CloudWatch Log Groups
  - Security Groups (petclinic-ecs-sg)
  - IAM Roles (ecsTaskExecutionRole, ecsTaskRole)

⚠️  주의: 이 작업은 되돌릴 수 없습니다!

정말 삭제하시겠습니까? 'DELETE'를 입력하세요:
```

### 삭제 순서
1. ECS 서비스 (스케일 0 → 삭제)
2. ECS Task Definitions (모든 버전)
3. ECS 클러스터
4. ECR 리포지토리 및 모든 이미지
5. CloudWatch Log Groups
6. Security Groups
7. IAM Roles (선택)

### IAM Roles 삭제 확인
```
⚠️  주의: IAM Roles는 다른 리소스에서 사용 중일 수 있습니다.
IAM Roles도 삭제하시겠습니까? (yes/no):
```

### 수동 삭제 필요한 리소스
- RDS PostgreSQL 인스턴스
- ALB (Application Load Balancer)
- Target Groups
- 커스텀 VPC (만든 경우)
- Secrets Manager (DB 정보)

### 실행 시간
약 1-2분 소요

---

## 🧪 4. local-build-test.sh

### 용도
로컬 환경에서 전체 빌드 및 배포 프로세스 테스트

### 사용법
```bash
./scripts/local-build-test.sh
```

### 실행 단계
1. Gradle 빌드 (bootJar)
2. Docker 이미지 빌드
3. PostgreSQL 컨테이너 시작
4. 애플리케이션 컨테이너 시작
5. Health Check 확인

### 출력 예시
```
[1/5] Building with Gradle...
✓ Gradle build succeeded

[2/5] Building Docker image...
✓ Docker build succeeded

[3/5] Starting PostgreSQL container...
✓ PostgreSQL started

[4/5] Starting application container...
Waiting for application to start...

[5/5] Running health check...
✓ Health check passed: UP

=====================================
All tests passed!
=====================================

Application is running at: http://localhost:9090
```

---

## 📦 5. aws-deploy.sh

### 용도
Jenkins 없이 AWS ECS에 수동으로 배포

### 사용법
```bash
./scripts/aws-deploy.sh
```

### 실행 단계
1. Gradle 빌드
2. Docker 이미지 빌드
3. ECR 로그인
4. ECR에 이미지 푸시 (3개: front, back1, back2)
5. ECS 서비스 업데이트 (병렬)
6. 서비스 안정화 대기

### 이미지 태그
- 타임스탬프 형식: `YYYYMMDD-HHMMSS`
- 예: `20250117-213045`

### 실행 시간
약 10-15분 소요

---

## 🔁 일반적인 워크플로우

### 처음 시작할 때
```bash
# 1. AWS 리소스 확인
./scripts/check-aws-resources.sh

# 2. AWS 리소스 생성
./scripts/create-aws-resources.sh

# 3. 로컬 테스트
./scripts/local-build-test.sh

# 4. AWS 배포 (수동)
./scripts/aws-deploy.sh
```

### 개발 중
```bash
# 로컬 테스트만
./scripts/local-build-test.sh

# 또는 docker-compose 사용
docker-compose up -d front
```

### 테스트 완료 후
```bash
# AWS 리소스 삭제 (비용 절감)
./scripts/destroy-aws-resources.sh
```

---

## 🛠️ 트러블슈팅

### "Permission denied" 에러
```bash
chmod +x scripts/*.sh
```

### AWS CLI 에러
```bash
# AWS CLI 설치 확인
aws --version

# AWS 자격증명 설정
aws configure
```

### Docker 에러
```bash
# Docker 실행 확인
docker ps

# Docker 재시작
# Mac: Docker Desktop 재시작
# Linux: sudo systemctl restart docker
```

---

## 💡 팁

1. **비용 절감**
   - 테스트 후에는 `destroy-aws-resources.sh` 실행
   - ECR 이미지가 쌓이면 수동 삭제

2. **로그 확인**
   ```bash
   # 로컬
   docker logs -f <container-name>

   # AWS
   aws logs tail /ecs/petclinic-front --follow
   ```

3. **빠른 재배포**
   ```bash
   # GitHub Actions 사용 시
   git push origin main

   # 수동 배포 시
   ./scripts/aws-deploy.sh
   ```

4. **리소스 상태 확인**
   ```bash
   # 생성 전
   ./scripts/check-aws-resources.sh

   # 생성 후
   ./scripts/check-aws-resources.sh

   # 삭제 후
   ./scripts/check-aws-resources.sh
   ```

---

## 📞 도움말

### 스크립트 에러 발생 시
1. 스크립트 권한 확인: `ls -la scripts/`
2. AWS CLI 설정 확인: `aws configure list`
3. AWS 자격증명 확인: `aws sts get-caller-identity`

### AWS 콘솔에서 확인
- **ECR**: https://console.aws.amazon.com/ecr
- **ECS**: https://console.aws.amazon.com/ecs
- **CloudWatch**: https://console.aws.amazon.com/cloudwatch

---

**작성일**: 2025년
**프로젝트**: Spring PetClinic DevOps CI/CD
