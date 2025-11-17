#!/bin/bash

# AWS 리소스 확인 스크립트

set -e

echo "========================================"
echo "AWS 리소스 상태 확인"
echo "========================================"
echo ""

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

AWS_REGION="ap-northeast-2"
AWS_ACCOUNT_ID="556152726180"

# AWS CLI 설치 확인
echo -e "${BLUE}[1/10] AWS CLI 확인...${NC}"
if command -v aws &> /dev/null; then
    AWS_VERSION=$(aws --version)
    echo -e "${GREEN}✓ AWS CLI 설치됨: $AWS_VERSION${NC}"
else
    echo -e "${RED}✗ AWS CLI가 설치되지 않았습니다${NC}"
    echo "설치 방법: https://aws.amazon.com/cli/"
    exit 1
fi
echo ""

# AWS 자격증명 확인
echo -e "${BLUE}[2/10] AWS 자격증명 확인...${NC}"
if aws sts get-caller-identity &> /dev/null; then
    CALLER_IDENTITY=$(aws sts get-caller-identity --output json)
    ACCOUNT_ID=$(echo $CALLER_IDENTITY | grep -o '"Account": "[^"]*"' | cut -d'"' -f4)
    USER_ARN=$(echo $CALLER_IDENTITY | grep -o '"Arn": "[^"]*"' | cut -d'"' -f4)
    echo -e "${GREEN}✓ AWS 자격증명 유효${NC}"
    echo "  Account ID: $ACCOUNT_ID"
    echo "  User ARN: $USER_ARN"
else
    echo -e "${RED}✗ AWS 자격증명이 설정되지 않았습니다${NC}"
    echo "설정 방법: aws configure"
    exit 1
fi
echo ""

# ECR 리포지토리 확인
echo -e "${BLUE}[3/10] ECR 리포지토리 확인...${NC}"
ECR_REPOS=$(aws ecr describe-repositories --region $AWS_REGION 2>&1)
if echo "$ECR_REPOS" | grep -q "repositoryName"; then
    echo -e "${GREEN}✓ ECR 리포지토리 발견:${NC}"
    echo "$ECR_REPOS" | grep -o '"repositoryName": "[^"]*"' | cut -d'"' -f4 | while read repo; do
        echo "  - $repo"
    done

    # front, back1, back2 리포지토리 확인
    for repo in front back1 back2; do
        if echo "$ECR_REPOS" | grep -q "\"repositoryName\": \"$repo\""; then
            echo -e "  ${GREEN}✓ $repo 리포지토리 존재${NC}"
        else
            echo -e "  ${YELLOW}⚠ $repo 리포지토리 없음 (생성 필요)${NC}"
        fi
    done
else
    echo -e "${YELLOW}⚠ ECR 리포지토리 없음 (생성 필요)${NC}"
fi
echo ""

# ECS 클러스터 확인
echo -e "${BLUE}[4/10] ECS 클러스터 확인...${NC}"
ECS_CLUSTERS=$(aws ecs list-clusters --region $AWS_REGION 2>&1)
if echo "$ECS_CLUSTERS" | grep -q "petclinic-cluster"; then
    echo -e "${GREEN}✓ ECS 클러스터 'petclinic-cluster' 존재${NC}"

    # 클러스터 상세 정보
    CLUSTER_INFO=$(aws ecs describe-clusters --clusters petclinic-cluster --region $AWS_REGION 2>&1)
    echo "$CLUSTER_INFO" | grep -o '"runningTasksCount": [0-9]*' | head -1
    echo "$CLUSTER_INFO" | grep -o '"pendingTasksCount": [0-9]*' | head -1
else
    echo -e "${YELLOW}⚠ ECS 클러스터 'petclinic-cluster' 없음 (생성 필요)${NC}"
fi
echo ""

# ECS 서비스 확인
echo -e "${BLUE}[5/10] ECS 서비스 확인...${NC}"
if echo "$ECS_CLUSTERS" | grep -q "petclinic-cluster"; then
    ECS_SERVICES=$(aws ecs list-services --cluster petclinic-cluster --region $AWS_REGION 2>&1)
    if echo "$ECS_SERVICES" | grep -q "service"; then
        echo -e "${GREEN}✓ ECS 서비스 발견:${NC}"
        echo "$ECS_SERVICES" | grep -o 'service/[^"]*' | while read service; do
            echo "  - $service"
        done
    else
        echo -e "${YELLOW}⚠ ECS 서비스 없음 (생성 필요)${NC}"
    fi
else
    echo -e "${YELLOW}⚠ ECS 클러스터가 없어 서비스 확인 불가${NC}"
fi
echo ""

# VPC 확인
echo -e "${BLUE}[6/10] VPC 확인...${NC}"
VPCS=$(aws ec2 describe-vpcs --region $AWS_REGION --query 'Vpcs[*].[VpcId,CidrBlock,Tags[?Key==`Name`].Value|[0]]' --output text 2>&1)
if [ -n "$VPCS" ]; then
    echo -e "${GREEN}✓ VPC 발견:${NC}"
    echo "$VPCS" | head -5 | while read line; do
        echo "  - $line"
    done
else
    echo -e "${YELLOW}⚠ VPC 없음 (생성 필요)${NC}"
fi
echo ""

# ALB 확인
echo -e "${BLUE}[7/10] ALB (Application Load Balancer) 확인...${NC}"
ALBS=$(aws elbv2 describe-load-balancers --region $AWS_REGION 2>&1)
if echo "$ALBS" | grep -q "LoadBalancerName"; then
    echo -e "${GREEN}✓ ALB 발견:${NC}"
    echo "$ALBS" | grep -o '"LoadBalancerName": "[^"]*"' | cut -d'"' -f4 | while read alb; do
        echo "  - $alb"
    done
else
    echo -e "${YELLOW}⚠ ALB 없음 (생성 필요)${NC}"
fi
echo ""

# RDS 확인
echo -e "${BLUE}[8/10] RDS 인스턴스 확인...${NC}"
RDS_INSTANCES=$(aws rds describe-db-instances --region $AWS_REGION 2>&1)
if echo "$RDS_INSTANCES" | grep -q "DBInstanceIdentifier"; then
    echo -e "${GREEN}✓ RDS 인스턴스 발견:${NC}"
    echo "$RDS_INSTANCES" | grep -o '"DBInstanceIdentifier": "[^"]*"' | cut -d'"' -f4 | while read db; do
        echo "  - $db"
    done
else
    echo -e "${YELLOW}⚠ RDS 인스턴스 없음 (생성 필요)${NC}"
fi
echo ""

# Secrets Manager 확인
echo -e "${BLUE}[9/10] Secrets Manager 확인...${NC}"
SECRETS=$(aws secretsmanager list-secrets --region $AWS_REGION 2>&1)
if echo "$SECRETS" | grep -q "petclinic"; then
    echo -e "${GREEN}✓ PetClinic 관련 Secret 발견:${NC}"
    echo "$SECRETS" | grep -o '"Name": "[^"]*petclinic[^"]*"' | cut -d'"' -f4 | while read secret; do
        echo "  - $secret"
    done
else
    echo -e "${YELLOW}⚠ PetClinic 관련 Secret 없음 (생성 필요)${NC}"
fi
echo ""

# IAM Role 확인
echo -e "${BLUE}[10/10] IAM Role 확인...${NC}"
IAM_ROLES=$(aws iam list-roles --query 'Roles[?contains(RoleName, `ecs`) || contains(RoleName, `ECS`)].RoleName' --output text 2>&1)
if [ -n "$IAM_ROLES" ]; then
    echo -e "${GREEN}✓ ECS 관련 IAM Role 발견:${NC}"
    echo "$IAM_ROLES" | tr '\t' '\n' | while read role; do
        if [ -n "$role" ]; then
            echo "  - $role"
        fi
    done

    # 필수 Role 확인
    if echo "$IAM_ROLES" | grep -q "ecsTaskExecutionRole"; then
        echo -e "  ${GREEN}✓ ecsTaskExecutionRole 존재${NC}"
    else
        echo -e "  ${YELLOW}⚠ ecsTaskExecutionRole 없음 (생성 필요)${NC}"
    fi
else
    echo -e "${YELLOW}⚠ ECS 관련 IAM Role 없음 (생성 필요)${NC}"
fi
echo ""

# 요약
echo "========================================"
echo -e "${BLUE}요약${NC}"
echo "========================================"
echo ""

echo "다음 단계:"
echo "1. 빠진 리소스가 있다면 생성 필요"
echo "2. AWS 콘솔 또는 README-DEVOPS.md의 가이드 참고"
echo "3. GitHub Actions 워크플로우 작성"
echo ""
echo "자세한 구축 가이드:"
echo "  - README-DEVOPS.md"
echo "  - 배포과정설명.md"
echo ""
