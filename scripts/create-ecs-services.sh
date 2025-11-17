#!/bin/bash

# ECS 서비스 생성 스크립트
# Task Definition이 이미 등록된 상태에서 실행

set -e

echo "=========================================="
echo "ECS 서비스 생성 스크립트"
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
PROJECT_NAME="petclinic"
ECS_CLUSTER="${PROJECT_NAME}-cluster"

echo -e "${BLUE}1. VPC 및 서브넷 확인...${NC}"

# Default VPC 사용
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text --region $AWS_REGION)

if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
    echo -e "${RED}✗ Default VPC not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ VPC: $VPC_ID${NC}"

# 서브넷 가져오기 (최소 2개 필요)
SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[*].SubnetId' --output text --region $AWS_REGION)
SUBNET_ARRAY=($SUBNET_IDS)

if [ ${#SUBNET_ARRAY[@]} -lt 2 ]; then
    echo -e "${RED}✗ Need at least 2 subnets${NC}"
    exit 1
fi

SUBNET_1=${SUBNET_ARRAY[0]}
SUBNET_2=${SUBNET_ARRAY[1]}

echo -e "${GREEN}✓ Subnets: $SUBNET_1, $SUBNET_2${NC}"

echo ""
echo -e "${BLUE}2. Security Group 확인...${NC}"

# Security Group 찾기
SG_NAME="${PROJECT_NAME}-ecs-sg"
SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$SG_NAME" --query 'SecurityGroups[0].GroupId' --output text --region $AWS_REGION 2>/dev/null || echo "")

if [ "$SG_ID" = "None" ] || [ -z "$SG_ID" ]; then
    echo -e "${RED}✗ Security Group not found. Run create-aws-resources.sh first${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Security Group: $SG_ID${NC}"

echo ""
echo -e "${BLUE}3. ECS 클러스터 확인...${NC}"

if ! aws ecs describe-clusters --clusters $ECS_CLUSTER --region $AWS_REGION 2>&1 | grep -q "ACTIVE"; then
    echo -e "${RED}✗ ECS Cluster not found. Run create-aws-resources.sh first${NC}"
    exit 1
fi

echo -e "${GREEN}✓ ECS Cluster: $ECS_CLUSTER${NC}"

echo ""
echo "=========================================="
echo "ECS 서비스 생성 시작"
echo "=========================================="
echo ""

# 서비스 생성 함수
create_service() {
    local SERVICE_NAME=$1
    local TASK_FAMILY=$2
    local CONTAINER_NAME=$3

    echo -e "${BLUE}Creating service: $SERVICE_NAME${NC}"

    # 서비스가 이미 있는지 확인
    if aws ecs describe-services --cluster $ECS_CLUSTER --services $SERVICE_NAME --region $AWS_REGION 2>&1 | grep -q "ACTIVE"; then
        echo -e "${YELLOW}⚠ Service '$SERVICE_NAME' already exists${NC}"
        return 0
    fi

    # 서비스 생성
    aws ecs create-service \
        --cluster $ECS_CLUSTER \
        --service-name $SERVICE_NAME \
        --task-definition $TASK_FAMILY \
        --desired-count 1 \
        --launch-type FARGATE \
        --platform-version LATEST \
        --network-configuration "awsvpcConfiguration={
            subnets=[$SUBNET_1,$SUBNET_2],
            securityGroups=[$SG_ID],
            assignPublicIp=ENABLED
        }" \
        --region $AWS_REGION > /dev/null

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Service '$SERVICE_NAME' created${NC}"
    else
        echo -e "${RED}✗ Failed to create service '$SERVICE_NAME'${NC}"
        return 1
    fi
}

# 3개 서비스 생성
create_service "front-service" "petclinic-front-task" "petclinic-front"
echo ""
create_service "back1-service" "petclinic-back1-task" "petclinic-back1"
echo ""
create_service "back2-service" "petclinic-back2-task" "petclinic-back2"

echo ""
echo "=========================================="
echo -e "${BLUE}서비스 시작 대기 중...${NC}"
echo "=========================================="
echo ""

# 서비스가 안정화될 때까지 대기 (약 2-3분 소요)
echo "This may take 2-3 minutes..."
aws ecs wait services-stable \
    --cluster $ECS_CLUSTER \
    --services front-service back1-service back2-service \
    --region $AWS_REGION

echo ""
echo "=========================================="
echo -e "${GREEN}✅ ECS 서비스 생성 완료!${NC}"
echo "=========================================="
echo ""

# 서비스 상태 확인
echo "서비스 상태:"
aws ecs describe-services \
    --cluster $ECS_CLUSTER \
    --services front-service back1-service back2-service \
    --region $AWS_REGION \
    --query 'services[*].[serviceName,status,runningCount,desiredCount]' \
    --output table

echo ""
echo "Task 정보:"
for service in front-service back1-service back2-service; do
    TASK_ARN=$(aws ecs list-tasks --cluster $ECS_CLUSTER --service-name $service --region $AWS_REGION --query 'taskArns[0]' --output text)

    if [ "$TASK_ARN" != "None" ] && [ -n "$TASK_ARN" ]; then
        TASK_IP=$(aws ecs describe-tasks --cluster $ECS_CLUSTER --tasks $TASK_ARN --region $AWS_REGION --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text)

        if [ -n "$TASK_IP" ]; then
            ENI_ID=$TASK_IP
            PUBLIC_IP=$(aws ec2 describe-network-interfaces --network-interface-ids $ENI_ID --region $AWS_REGION --query 'NetworkInterfaces[0].Association.PublicIp' --output text 2>/dev/null || echo "N/A")

            echo "  - $service: $PUBLIC_IP"
        fi
    fi
done

echo ""
echo "다음 단계:"
echo "  1. Task가 실행될 때까지 대기 (약 2-3분)"
echo "  2. Public IP로 접속 테스트: http://<PUBLIC_IP>:8080"
echo "  3. Health Check: http://<PUBLIC_IP>:8080/actuator/health"
echo ""
echo "모니터링:"
echo "  - ECS 콘솔: https://console.aws.amazon.com/ecs/v2/clusters/$ECS_CLUSTER/services"
echo "  - CloudWatch Logs: https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#logsV2:log-groups"
echo ""
