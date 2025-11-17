#!/bin/bash

# AWS 리소스 자동 생성 스크립트
# Spring PetClinic CI/CD 인프라 구축

set -e

echo "=========================================="
echo "AWS 리소스 자동 생성 스크립트"
echo "=========================================="
echo ""

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 설정
AWS_REGION="ap-northeast-2"
AWS_ACCOUNT_ID="205922933402"
PROJECT_NAME="petclinic"

echo -e "${YELLOW}⚠️  경고: 이 스크립트는 AWS 리소스를 생성하여 비용이 발생할 수 있습니다.${NC}"
echo ""
read -p "계속하시겠습니까? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "작업이 취소되었습니다."
    exit 0
fi

echo ""
echo "=========================================="
echo "1/7: ECR 리포지토리 생성"
echo "=========================================="

for repo in front back1 back2; do
    echo -e "${BLUE}Creating ECR repository: $repo${NC}"
    if aws ecr describe-repositories --repository-names $repo --region $AWS_REGION 2>&1 | grep -q "repositoryName"; then
        echo -e "${GREEN}✓ Repository '$repo' already exists${NC}"
    else
        aws ecr create-repository \
            --repository-name $repo \
            --region $AWS_REGION \
            --image-scanning-configuration scanOnPush=true \
            --encryption-configuration encryptionType=AES256

        # 라이프사이클 정책 설정 (최근 10개 이미지만 보관)
        aws ecr put-lifecycle-policy \
            --repository-name $repo \
            --region $AWS_REGION \
            --lifecycle-policy-text '{
                "rules": [{
                    "rulePriority": 1,
                    "description": "Keep last 10 images",
                    "selection": {
                        "tagStatus": "any",
                        "countType": "imageCountMoreThan",
                        "countNumber": 10
                    },
                    "action": { "type": "expire" }
                }]
            }'

        echo -e "${GREEN}✓ Repository '$repo' created${NC}"
    fi
done

echo ""
echo "=========================================="
echo "2/7: VPC 및 서브넷 확인/생성"
echo "=========================================="

# Default VPC 사용 (이미 존재)
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text --region $AWS_REGION)

if [ "$VPC_ID" != "None" ] && [ -n "$VPC_ID" ]; then
    echo -e "${GREEN}✓ Using default VPC: $VPC_ID${NC}"

    # 서브넷 가져오기
    SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[*].SubnetId' --output text --region $AWS_REGION)
    SUBNET_ARRAY=($SUBNET_IDS)
    SUBNET_1=${SUBNET_ARRAY[0]}
    SUBNET_2=${SUBNET_ARRAY[1]}

    echo -e "${GREEN}✓ Using subnets: $SUBNET_1, $SUBNET_2${NC}"
else
    echo -e "${RED}✗ Default VPC not found. Please create a VPC first.${NC}"
    exit 1
fi

echo ""
echo "=========================================="
echo "3/7: Security Groups 생성"
echo "=========================================="

# ECS Security Group
ECS_SG_NAME="$PROJECT_NAME-ecs-sg"
ECS_SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$ECS_SG_NAME" --query 'SecurityGroups[0].GroupId' --output text --region $AWS_REGION 2>/dev/null || echo "")

if [ "$ECS_SG_ID" != "None" ] && [ -n "$ECS_SG_ID" ]; then
    echo -e "${GREEN}✓ Security Group '$ECS_SG_NAME' already exists: $ECS_SG_ID${NC}"
else
    ECS_SG_ID=$(aws ec2 create-security-group \
        --group-name $ECS_SG_NAME \
        --description "Security group for ECS tasks" \
        --vpc-id $VPC_ID \
        --region $AWS_REGION \
        --output text --query 'GroupId')

    # 인바운드 규칙: 모든 트래픽 허용 (간단한 데모용)
    aws ec2 authorize-security-group-ingress \
        --group-id $ECS_SG_ID \
        --protocol tcp \
        --port 8080 \
        --cidr 0.0.0.0/0 \
        --region $AWS_REGION

    aws ec2 authorize-security-group-ingress \
        --group-id $ECS_SG_ID \
        --protocol tcp \
        --port 5432 \
        --cidr 0.0.0.0/0 \
        --region $AWS_REGION

    echo -e "${GREEN}✓ Security Group '$ECS_SG_NAME' created: $ECS_SG_ID${NC}"
fi

echo ""
echo "=========================================="
echo "4/7: IAM Roles 생성"
echo "=========================================="

# ECS Task Execution Role
EXECUTION_ROLE_NAME="ecsTaskExecutionRole"
if aws iam get-role --role-name $EXECUTION_ROLE_NAME 2>&1 | grep -q "RoleName"; then
    echo -e "${GREEN}✓ IAM Role '$EXECUTION_ROLE_NAME' already exists${NC}"
else
    echo -e "${BLUE}Creating IAM Role: $EXECUTION_ROLE_NAME${NC}"

    # Trust policy 생성
    cat > /tmp/ecs-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ecs-tasks.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
EOF

    aws iam create-role \
        --role-name $EXECUTION_ROLE_NAME \
        --assume-role-policy-document file:///tmp/ecs-trust-policy.json

    aws iam attach-role-policy \
        --role-name $EXECUTION_ROLE_NAME \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

    aws iam attach-role-policy \
        --role-name $EXECUTION_ROLE_NAME \
        --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite

    echo -e "${GREEN}✓ IAM Role '$EXECUTION_ROLE_NAME' created${NC}"
fi

# ECS Task Role
TASK_ROLE_NAME="ecsTaskRole"
if aws iam get-role --role-name $TASK_ROLE_NAME 2>&1 | grep -q "RoleName"; then
    echo -e "${GREEN}✓ IAM Role '$TASK_ROLE_NAME' already exists${NC}"
else
    echo -e "${BLUE}Creating IAM Role: $TASK_ROLE_NAME${NC}"

    aws iam create-role \
        --role-name $TASK_ROLE_NAME \
        --assume-role-policy-document file:///tmp/ecs-trust-policy.json

    echo -e "${GREEN}✓ IAM Role '$TASK_ROLE_NAME' created${NC}"
fi

rm -f /tmp/ecs-trust-policy.json

echo ""
echo "=========================================="
echo "5/7: ECS 클러스터 생성"
echo "=========================================="

CLUSTER_NAME="$PROJECT_NAME-cluster"
if aws ecs describe-clusters --clusters $CLUSTER_NAME --region $AWS_REGION 2>&1 | grep -q "ACTIVE"; then
    echo -e "${GREEN}✓ ECS Cluster '$CLUSTER_NAME' already exists${NC}"
else
    aws ecs create-cluster \
        --cluster-name $CLUSTER_NAME \
        --region $AWS_REGION

    echo -e "${GREEN}✓ ECS Cluster '$CLUSTER_NAME' created${NC}"
fi

echo ""
echo "=========================================="
echo "6/7: CloudWatch Log Groups 생성"
echo "=========================================="

for service in front back1 back2; do
    LOG_GROUP="/ecs/$PROJECT_NAME-$service"
    if aws logs describe-log-groups --log-group-name-prefix $LOG_GROUP --region $AWS_REGION 2>&1 | grep -q "logGroupName"; then
        echo -e "${GREEN}✓ Log Group '$LOG_GROUP' already exists${NC}"
    else
        aws logs create-log-group \
            --log-group-name $LOG_GROUP \
            --region $AWS_REGION

        # 로그 보존 기간 설정 (7일)
        aws logs put-retention-policy \
            --log-group-name $LOG_GROUP \
            --retention-in-days 7 \
            --region $AWS_REGION

        echo -e "${GREEN}✓ Log Group '$LOG_GROUP' created${NC}"
    fi
done

echo ""
echo "=========================================="
echo "7/7: ECS Task Definitions 등록"
echo "=========================================="

for service in front back1 back2; do
    TASK_DEF_FILE="ecs-task-definition-$service.json"

    if [ -f "$TASK_DEF_FILE" ]; then
        echo -e "${BLUE}Registering Task Definition: $PROJECT_NAME-$service-task${NC}"

        aws ecs register-task-definition \
            --cli-input-json file://$TASK_DEF_FILE \
            --region $AWS_REGION > /dev/null

        echo -e "${GREEN}✓ Task Definition '$PROJECT_NAME-$service-task' registered${NC}"
    else
        echo -e "${YELLOW}⚠ Task Definition file not found: $TASK_DEF_FILE${NC}"
    fi
done

echo ""
echo "=========================================="
echo -e "${GREEN}✅ AWS 리소스 생성 완료!${NC}"
echo "=========================================="
echo ""
echo "생성된 리소스:"
echo "  - ECR 리포지토리: front, back1, back2"
echo "  - Security Group: $ECS_SG_ID"
echo "  - IAM Roles: ecsTaskExecutionRole, ecsTaskRole"
echo "  - ECS 클러스터: $CLUSTER_NAME"
echo "  - CloudWatch Log Groups: 3개"
echo "  - ECS Task Definitions: 3개"
echo ""
echo "다음 단계:"
echo "  1. RDS PostgreSQL 생성 (수동 또는 콘솔)"
echo "  2. Secrets Manager에 DB 정보 저장"
echo "  3. ALB 생성 및 Target Groups 설정"
echo "  4. ECS 서비스 생성 (front-service, back1-service, back2-service)"
echo "  5. GitHub Actions 또는 Jenkins 배포 테스트"
echo ""
echo "자세한 가이드:"
echo "  - README-DEVOPS.md"
echo "  - GITHUB-ACTIONS-가이드.md"
echo ""
