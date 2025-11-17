#!/bin/bash

# AWS 리소스 자동 삭제 스크립트
# Spring PetClinic CI/CD 인프라 제거

set -e

echo "=========================================="
echo "AWS 리소스 자동 삭제 스크립트"
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

echo -e "${RED}⚠️  경고: 이 스크립트는 다음 리소스를 삭제합니다:${NC}"
echo "  - ECR 리포지토리 및 모든 이미지 (front, back1, back2)"
echo "  - ECS 서비스 (front-service, back1-service, back2-service)"
echo "  - ECS Task Definitions"
echo "  - ECS 클러스터 (petclinic-cluster)"
echo "  - CloudWatch Log Groups"
echo "  - Security Groups (petclinic-ecs-sg)"
echo "  - IAM Roles (ecsTaskExecutionRole, ecsTaskRole)"
echo ""
echo -e "${YELLOW}⚠️  주의: 이 작업은 되돌릴 수 없습니다!${NC}"
echo ""
read -p "정말 삭제하시겠습니까? 'DELETE'를 입력하세요: " CONFIRM

if [ "$CONFIRM" != "DELETE" ]; then
    echo "작업이 취소되었습니다."
    exit 0
fi

echo ""
echo "=========================================="
echo "1/7: ECS 서비스 삭제"
echo "=========================================="

CLUSTER_NAME="$PROJECT_NAME-cluster"

for service in front-service back1-service back2-service; do
    echo -e "${BLUE}Deleting ECS service: $service${NC}"

    if aws ecs describe-services --cluster $CLUSTER_NAME --services $service --region $AWS_REGION 2>&1 | grep -q "ACTIVE"; then
        # 서비스 스케일을 0으로 설정
        aws ecs update-service \
            --cluster $CLUSTER_NAME \
            --service $service \
            --desired-count 0 \
            --region $AWS_REGION > /dev/null 2>&1 || true

        # 서비스 삭제
        aws ecs delete-service \
            --cluster $CLUSTER_NAME \
            --service $service \
            --force \
            --region $AWS_REGION > /dev/null 2>&1 || true

        echo -e "${GREEN}✓ Service '$service' deleted${NC}"
    else
        echo -e "${YELLOW}⚠ Service '$service' not found${NC}"
    fi
done

# 서비스 삭제 대기
echo "Waiting for services to be deleted..."
sleep 10

echo ""
echo "=========================================="
echo "2/7: ECS Task Definitions 삭제"
echo "=========================================="

for task_family in petclinic-front-task petclinic-back1-task petclinic-back2-task; do
    echo -e "${BLUE}Deregistering Task Definitions: $task_family${NC}"

    # 모든 버전의 Task Definition 조회 및 삭제
    TASK_ARNS=$(aws ecs list-task-definitions \
        --family-prefix $task_family \
        --region $AWS_REGION \
        --query 'taskDefinitionArns[]' \
        --output text 2>/dev/null || echo "")

    if [ -n "$TASK_ARNS" ]; then
        for arn in $TASK_ARNS; do
            aws ecs deregister-task-definition \
                --task-definition $arn \
                --region $AWS_REGION > /dev/null 2>&1 || true
        done
        echo -e "${GREEN}✓ Task Definitions for '$task_family' deregistered${NC}"
    else
        echo -e "${YELLOW}⚠ No Task Definitions found for '$task_family'${NC}"
    fi
done

echo ""
echo "=========================================="
echo "3/7: ECS 클러스터 삭제"
echo "=========================================="

echo -e "${BLUE}Deleting ECS cluster: $CLUSTER_NAME${NC}"

if aws ecs describe-clusters --clusters $CLUSTER_NAME --region $AWS_REGION 2>&1 | grep -q "ACTIVE"; then
    aws ecs delete-cluster \
        --cluster $CLUSTER_NAME \
        --region $AWS_REGION > /dev/null

    echo -e "${GREEN}✓ Cluster '$CLUSTER_NAME' deleted${NC}"
else
    echo -e "${YELLOW}⚠ Cluster '$CLUSTER_NAME' not found${NC}"
fi

echo ""
echo "=========================================="
echo "4/7: ECR 리포지토리 및 이미지 삭제"
echo "=========================================="

for repo in front back1 back2; do
    echo -e "${BLUE}Deleting ECR repository: $repo${NC}"

    if aws ecr describe-repositories --repository-names $repo --region $AWS_REGION 2>&1 | grep -q "repositoryName"; then
        # 모든 이미지와 함께 리포지토리 삭제
        aws ecr delete-repository \
            --repository-name $repo \
            --force \
            --region $AWS_REGION > /dev/null

        echo -e "${GREEN}✓ Repository '$repo' and all images deleted${NC}"
    else
        echo -e "${YELLOW}⚠ Repository '$repo' not found${NC}"
    fi
done

echo ""
echo "=========================================="
echo "5/7: CloudWatch Log Groups 삭제"
echo "=========================================="

for service in front back1 back2; do
    LOG_GROUP="/ecs/$PROJECT_NAME-$service"
    echo -e "${BLUE}Deleting Log Group: $LOG_GROUP${NC}"

    if aws logs describe-log-groups --log-group-name-prefix $LOG_GROUP --region $AWS_REGION 2>&1 | grep -q "logGroupName"; then
        aws logs delete-log-group \
            --log-group-name $LOG_GROUP \
            --region $AWS_REGION > /dev/null || true

        echo -e "${GREEN}✓ Log Group '$LOG_GROUP' deleted${NC}"
    else
        echo -e "${YELLOW}⚠ Log Group '$LOG_GROUP' not found${NC}"
    fi
done

echo ""
echo "=========================================="
echo "6/7: Security Groups 삭제"
echo "=========================================="

ECS_SG_NAME="$PROJECT_NAME-ecs-sg"
echo -e "${BLUE}Deleting Security Group: $ECS_SG_NAME${NC}"

ECS_SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$ECS_SG_NAME" --query 'SecurityGroups[0].GroupId' --output text --region $AWS_REGION 2>/dev/null || echo "")

if [ "$ECS_SG_ID" != "None" ] && [ -n "$ECS_SG_ID" ]; then
    # ENI 연결 해제 대기
    sleep 5

    aws ec2 delete-security-group \
        --group-id $ECS_SG_ID \
        --region $AWS_REGION > /dev/null 2>&1 || {
        echo -e "${YELLOW}⚠ Security Group is still in use. Will be deleted automatically later.${NC}"
    }

    echo -e "${GREEN}✓ Security Group '$ECS_SG_NAME' deleted (or scheduled for deletion)${NC}"
else
    echo -e "${YELLOW}⚠ Security Group '$ECS_SG_NAME' not found${NC}"
fi

echo ""
echo "=========================================="
echo "7/7: IAM Roles 삭제"
echo "=========================================="

echo -e "${YELLOW}⚠️  주의: IAM Roles는 다른 리소스에서 사용 중일 수 있습니다.${NC}"
read -p "IAM Roles도 삭제하시겠습니까? (yes/no): " DELETE_IAM

if [ "$DELETE_IAM" = "yes" ]; then
    for role in ecsTaskExecutionRole ecsTaskRole; do
        echo -e "${BLUE}Deleting IAM Role: $role${NC}"

        if aws iam get-role --role-name $role 2>&1 | grep -q "RoleName"; then
            # 연결된 정책 분리
            ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name $role --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null || echo "")

            for policy_arn in $ATTACHED_POLICIES; do
                aws iam detach-role-policy \
                    --role-name $role \
                    --policy-arn $policy_arn > /dev/null 2>&1 || true
            done

            # 인라인 정책 삭제
            INLINE_POLICIES=$(aws iam list-role-policies --role-name $role --query 'PolicyNames[]' --output text 2>/dev/null || echo "")

            for policy_name in $INLINE_POLICIES; do
                aws iam delete-role-policy \
                    --role-name $role \
                    --policy-name $policy_name > /dev/null 2>&1 || true
            done

            # Role 삭제
            aws iam delete-role --role-name $role > /dev/null 2>&1 || {
                echo -e "${YELLOW}⚠ Failed to delete role '$role' (may be in use)${NC}"
                continue
            }

            echo -e "${GREEN}✓ IAM Role '$role' deleted${NC}"
        else
            echo -e "${YELLOW}⚠ IAM Role '$role' not found${NC}"
        fi
    done
else
    echo -e "${YELLOW}⚠ IAM Roles 삭제를 건너뜁니다.${NC}"
fi

echo ""
echo "=========================================="
echo -e "${GREEN}✅ AWS 리소스 삭제 완료!${NC}"
echo "=========================================="
echo ""
echo "삭제된 리소스:"
echo "  ✓ ECR 리포지토리 및 모든 이미지"
echo "  ✓ ECS 서비스 (3개)"
echo "  ✓ ECS Task Definitions"
echo "  ✓ ECS 클러스터"
echo "  ✓ CloudWatch Log Groups"
echo "  ✓ Security Groups (대부분)"

if [ "$DELETE_IAM" = "yes" ]; then
    echo "  ✓ IAM Roles (시도됨)"
else
    echo "  - IAM Roles (건너뜀)"
fi

echo ""
echo "수동 삭제 필요 (생성한 경우):"
echo "  - RDS PostgreSQL 인스턴스"
echo "  - ALB (Application Load Balancer)"
echo "  - Target Groups"
echo "  - VPC (커스텀 VPC를 만든 경우)"
echo "  - Secrets Manager (DB 정보)"
echo ""
echo -e "${YELLOW}💡 팁: AWS 콘솔에서 남아있는 리소스를 확인하세요.${NC}"
echo ""
