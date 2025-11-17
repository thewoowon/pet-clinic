# GitHub Actions 자동 배포 가이드

## 📌 개요

Jenkins 대신 GitHub Actions를 사용한 CI/CD 자동 배포 방법입니다.

**장점:**
- ✅ EC2 Jenkins 서버 불필요 (비용 절감)
- ✅ 설정이 간단함
- ✅ GitHub과 완벽한 통합
- ✅ 무료 (월 2,000분)

---

## 🚀 빠른 시작

### 1단계: GitHub Repository 생성

```bash
# GitHub에서 새 Repository 생성
# Repository 이름: spring-petclinic (또는 원하는 이름)

# 로컬 코드를 GitHub에 푸시
cd /Users/aepeul/dev/server/spring-petclinic-main
git init
git add .
git commit -m "feat: Initial commit - Spring PetClinic with CI/CD"
git branch -M main
git remote add origin https://github.com/<username>/spring-petclinic.git
git push -u origin main
```

### 2단계: AWS Credentials를 GitHub Secrets에 등록

GitHub Repository → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

다음 2개의 Secret을 추가:

| Name | Value | 설명 |
|------|-------|------|
| `AWS_ACCESS_KEY_ID` | `AKIA...` | AWS Access Key ID |
| `AWS_SECRET_ACCESS_KEY` | `***` | AWS Secret Access Key |

**AWS Access Key 생성 방법:**
```bash
# AWS CLI로 생성
aws iam create-access-key --user-name <your-iam-user>

# 또는 AWS 콘솔에서:
# IAM → Users → <your-user> → Security credentials → Create access key
```

**필요한 IAM 권한:**
- `AmazonEC2ContainerRegistryFullAccess`
- `AmazonECS_FullAccess`
- `AmazonEC2ContainerRegistryPowerUser`

### 3단계: AWS 리소스 생성

GitHub Actions가 작동하려면 다음 AWS 리소스가 필요합니다:

```bash
# 자동 생성 스크립트 실행
./scripts/create-aws-resources.sh

# 또는 수동으로 생성 (README-DEVOPS.md 참고)
```

**필수 리소스:**
- ✅ ECR 리포지토리: `front`, `back1`, `back2`
- ✅ ECS 클러스터: `petclinic-cluster`
- ✅ ECS 서비스: `front-service`, `back1-service`, `back2-service`
- ✅ ALB (Application Load Balancer)
- ✅ RDS PostgreSQL
- ✅ VPC & Subnets
- ✅ Security Groups
- ✅ IAM Roles

---

## 🔄 자동 배포 플로우

```
Git Push (main 브랜치)
   ↓
GitHub Actions 자동 실행
   ↓
1. Checkout 코드
   ↓
2. JDK 17 설정
   ↓
3. Gradle 빌드 (bootJar)
   ↓
4. AWS 자격증명 설정
   ↓
5. ECR 로그인
   ↓
6. Docker 이미지 빌드
   ↓
7. ECR에 이미지 푸시 (3개: front, back1, back2)
   ↓
8. ECS 서비스 업데이트 (3개 동시)
   ↓
9. 서비스 안정화 대기
   ↓
✅ 배포 완료!
```

---

## 📂 파일 구조

```
.github/
└── workflows/
    └── deploy.yml    # GitHub Actions 워크플로우 정의
```

### deploy.yml 주요 설정

```yaml
name: Deploy to AWS ECS

on:
  push:
    branches:
      - main          # main 브랜치에 푸시할 때 실행
  workflow_dispatch:  # 수동 실행 허용

env:
  AWS_REGION: ap-northeast-2
  AWS_ACCOUNT_ID: 205922933402
  ECR_REGISTRY: 205922933402.dkr.ecr.ap-northeast-2.amazonaws.com
  ECS_CLUSTER: petclinic-cluster
  IMAGE_TAG: ${{ github.run_number }}  # 빌드 번호를 이미지 태그로 사용
```

---

## 🧪 테스트 방법

### 로컬에서 변경 후 배포 테스트

```bash
# 1. 코드 수정
echo "# Test GitHub Actions" >> README.md

# 2. Git 커밋 & 푸시
git add .
git commit -m "test: GitHub Actions 테스트"
git push origin main

# 3. GitHub에서 확인
# Repository → Actions 탭에서 워크플로우 실행 상태 확인
```

### 수동 실행

GitHub Repository → **Actions** → **Deploy to AWS ECS** → **Run workflow**

---

## 📊 워크플로우 모니터링

### GitHub Actions 실행 로그 확인

1. **GitHub Repository** → **Actions** 탭
2. 최근 워크플로우 실행 클릭
3. 각 단계별 로그 확인

### 주요 확인 포인트

| 단계 | 확인 사항 | 예상 시간 |
|------|-----------|-----------|
| Build with Gradle | `BUILD SUCCESSFUL` | 2-3분 |
| Build Docker Image | 이미지 빌드 완료 | 3-5분 |
| Push to ECR | 3개 이미지 푸시 성공 | 2-3분 |
| Deploy to ECS | 서비스 업데이트 시작 | 10초 |
| Wait for stable | 서비스 안정화 완료 | 2-5분 |

**총 소요 시간: 약 10-15분**

---

## 🔧 트러블슈팅

### 문제 1: AWS 자격증명 오류

**증상:**
```
Error: Unable to locate credentials
```

**해결:**
1. GitHub Secrets에 `AWS_ACCESS_KEY_ID`와 `AWS_SECRET_ACCESS_KEY`가 올바르게 등록되어 있는지 확인
2. IAM User에 필요한 권한이 있는지 확인

### 문제 2: ECR 푸시 실패

**증상:**
```
Error: denied: User not authenticated
```

**해결:**
```bash
# ECR 리포지토리 생성 확인
aws ecr describe-repositories --region ap-northeast-2

# 리포지토리가 없다면 생성
aws ecr create-repository --repository-name front --region ap-northeast-2
aws ecr create-repository --repository-name back1 --region ap-northeast-2
aws ecr create-repository --repository-name back2 --region ap-northeast-2
```

### 문제 3: ECS 서비스 업데이트 실패

**증상:**
```
Error: Service not found
```

**해결:**
```bash
# ECS 클러스터 및 서비스 존재 확인
aws ecs list-services --cluster petclinic-cluster --region ap-northeast-2

# 서비스가 없다면 먼저 AWS 리소스 생성 필요
./scripts/create-aws-resources.sh
```

### 문제 4: Gradle 빌드 실패

**증상:**
```
BUILD FAILED
```

**해결:**
- 로컬에서 먼저 빌드 테스트: `./gradlew clean bootJar -x test`
- Java 버전 확인: build.gradle의 toolchain 설정이 17인지 확인
- 의존성 문제: `./gradlew dependencies` 실행

---

## 🔒 보안 모범 사례

### 1. AWS Credentials 관리
- ✅ GitHub Secrets 사용 (절대 코드에 하드코딩 금지)
- ✅ IAM 최소 권한 원칙 적용
- ✅ Access Key 정기적 로테이션

### 2. 이미지 태그 관리
- ✅ `github.run_number` 사용 (버전 추적)
- ✅ `latest` 태그와 버전 태그 병행 사용

### 3. 브랜치 보호
```yaml
# main 브랜치만 배포
on:
  push:
    branches:
      - main
```

---

## 📈 성능 최적화

### 1. Gradle 캐싱
```yaml
- name: Set up JDK 17
  uses: actions/setup-java@v4
  with:
    cache: 'gradle'  # Gradle 캐싱 활성화
```

### 2. Docker Layer 캐싱
```yaml
- name: Build Docker Image
  uses: docker/build-push-action@v5
  with:
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

### 3. 병렬 실행
```yaml
# 이미지 푸시를 병렬로 실행하려면 job matrix 사용
strategy:
  matrix:
    service: [front, back1, back2]
```

---

## 🆚 GitHub Actions vs Jenkins 비교

| 항목 | GitHub Actions | Jenkins |
|------|----------------|---------|
| **서버** | 불필요 (GitHub 호스팅) | EC2 필요 (비용 발생) |
| **설정** | YAML 파일 | Groovy 스크립트 |
| **비용** | 무료 (월 2,000분) | EC2 비용 (약 $20/월) |
| **유지보수** | 불필요 | 서버 관리 필요 |
| **통합** | GitHub 네이티브 | Webhook 설정 필요 |
| **플러그인** | Marketplace | 직접 설치 |
| **보안** | GitHub Secrets | Jenkins Credentials |
| **속도** | 빠름 | 서버 스펙에 따라 다름 |

---

## 📚 참고 자료

- [GitHub Actions 공식 문서](https://docs.github.com/en/actions)
- [AWS Actions for GitHub](https://github.com/aws-actions)
- [ECS 배포 가이드](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-types.html)

---

## 🎯 다음 단계

1. **모니터링 설정**
   - CloudWatch 알람
   - Slack 알림 연동

2. **테스트 자동화**
   - Unit 테스트 실행
   - Integration 테스트

3. **배포 전략 개선**
   - Blue/Green 배포
   - Canary 배포

4. **성능 개선**
   - Docker 캐싱
   - 빌드 최적화

---

**작성일**: 2025년
**프로젝트**: Spring PetClinic DevOps CI/CD
