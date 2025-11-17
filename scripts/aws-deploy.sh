#!/bin/bash

# AWS ECS 수동 배포 스크립트 (Jenkins 없이 테스트용)

set -e

echo "======================================"
echo "AWS ECS Manual Deployment Script"
echo "======================================"

# 설정
AWS_REGION="ap-northeast-2"
AWS_ACCOUNT_ID="205922933402"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
ECS_CLUSTER="petclinic-cluster"
IMAGE_TAG=$(date +%Y%m%d-%H%M%S)

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 1. Gradle 빌드
echo -e "${YELLOW}[1/6] Building application with Gradle...${NC}"
./gradlew clean bootJar -x test --no-daemon
echo -e "${GREEN}✓ Build completed${NC}"

# 2. Docker 이미지 빌드
echo -e "${YELLOW}[2/6] Building Docker image...${NC}"
docker build -t ${ECR_REGISTRY}/front:${IMAGE_TAG} .
docker tag ${ECR_REGISTRY}/front:${IMAGE_TAG} ${ECR_REGISTRY}/front:latest
docker tag ${ECR_REGISTRY}/front:${IMAGE_TAG} ${ECR_REGISTRY}/back1:${IMAGE_TAG}
docker tag ${ECR_REGISTRY}/front:${IMAGE_TAG} ${ECR_REGISTRY}/back1:latest
docker tag ${ECR_REGISTRY}/front:${IMAGE_TAG} ${ECR_REGISTRY}/back2:${IMAGE_TAG}
docker tag ${ECR_REGISTRY}/front:${IMAGE_TAG} ${ECR_REGISTRY}/back2:latest
echo -e "${GREEN}✓ Docker images built${NC}"

# 3. ECR 로그인
echo -e "${YELLOW}[3/6] Logging in to ECR...${NC}"
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin ${ECR_REGISTRY}
echo -e "${GREEN}✓ ECR login successful${NC}"

# 4. ECR에 푸시
echo -e "${YELLOW}[4/6] Pushing images to ECR...${NC}"

echo -e "${BLUE}Pushing front image...${NC}"
docker push ${ECR_REGISTRY}/front:${IMAGE_TAG}
docker push ${ECR_REGISTRY}/front:latest

echo -e "${BLUE}Pushing back1 image...${NC}"
docker push ${ECR_REGISTRY}/back1:${IMAGE_TAG}
docker push ${ECR_REGISTRY}/back1:latest

echo -e "${BLUE}Pushing back2 image...${NC}"
docker push ${ECR_REGISTRY}/back2:${IMAGE_TAG}
docker push ${ECR_REGISTRY}/back2:latest

echo -e "${GREEN}✓ All images pushed to ECR${NC}"

# 5. ECS 서비스 업데이트
echo -e "${YELLOW}[5/6] Updating ECS services...${NC}"

echo -e "${BLUE}Updating front-service...${NC}"
aws ecs update-service \
  --cluster ${ECS_CLUSTER} \
  --service front-service \
  --force-new-deployment \
  --region ${AWS_REGION} > /dev/null

echo -e "${BLUE}Updating back1-service...${NC}"
aws ecs update-service \
  --cluster ${ECS_CLUSTER} \
  --service back1-service \
  --force-new-deployment \
  --region ${AWS_REGION} > /dev/null

echo -e "${BLUE}Updating back2-service...${NC}"
aws ecs update-service \
  --cluster ${ECS_CLUSTER} \
  --service back2-service \
  --force-new-deployment \
  --region ${AWS_REGION} > /dev/null

echo -e "${GREEN}✓ ECS services updated${NC}"

# 6. 배포 확인
echo -e "${YELLOW}[6/6] Waiting for services to stabilize...${NC}"
echo "This may take a few minutes..."

aws ecs wait services-stable \
  --cluster ${ECS_CLUSTER} \
  --services front-service back1-service back2-service \
  --region ${AWS_REGION}

echo -e "${GREEN}✓ All services are stable${NC}"

# 배포 정보 출력
echo ""
echo "======================================"
echo -e "${GREEN}Deployment Completed!${NC}"
echo "======================================"
echo ""
echo "Image Tag: ${IMAGE_TAG}"
echo ""
echo "Deployed Images:"
echo "  - ${ECR_REGISTRY}/front:${IMAGE_TAG}"
echo "  - ${ECR_REGISTRY}/back1:${IMAGE_TAG}"
echo "  - ${ECR_REGISTRY}/back2:${IMAGE_TAG}"
echo ""
echo "To check service status:"
echo "  aws ecs describe-services --cluster ${ECS_CLUSTER} --services front-service"
echo ""
echo "To check ALB endpoint:"
echo "  aws elbv2 describe-load-balancers --names petclinic-alb"
echo ""

# ALB DNS 이름 가져오기
ALB_DNS=$(aws elbv2 describe-load-balancers --names petclinic-alb --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null || echo "N/A")
if [ "$ALB_DNS" != "N/A" ]; then
    echo "Application URL: http://${ALB_DNS}"
fi
