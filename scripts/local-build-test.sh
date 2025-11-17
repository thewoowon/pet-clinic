#!/bin/bash

# Spring PetClinic 로컬 빌드 및 테스트 스크립트

set -e  # 에러 발생 시 스크립트 중단

echo "======================================"
echo "Spring PetClinic Local Build Test"
echo "======================================"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 1. Gradle 빌드
echo -e "${YELLOW}[1/5] Building with Gradle...${NC}"
chmod +x gradlew
./gradlew clean bootJar -x test --no-daemon

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Gradle build succeeded${NC}"
else
    echo -e "${RED}✗ Gradle build failed${NC}"
    exit 1
fi

# 2. Docker 이미지 빌드
echo -e "${YELLOW}[2/5] Building Docker image...${NC}"
docker build -t petclinic-test:local .

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Docker build succeeded${NC}"
else
    echo -e "${RED}✗ Docker build failed${NC}"
    exit 1
fi

# 3. PostgreSQL 컨테이너 시작
echo -e "${YELLOW}[3/5] Starting PostgreSQL container...${NC}"
docker-compose up -d postgres

echo "Waiting for PostgreSQL to be ready..."
sleep 10

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ PostgreSQL started${NC}"
else
    echo -e "${RED}✗ PostgreSQL failed to start${NC}"
    exit 1
fi

# 4. 애플리케이션 컨테이너 시작
echo -e "${YELLOW}[4/5] Starting application container...${NC}"
docker run -d \
  --name petclinic-test \
  --network spring-petclinic-main_petclinic-network \
  -p 9090:8080 \
  -e SPRING_PROFILES_ACTIVE=prod \
  -e DB_URL=jdbc:postgresql://postgres:5432/petclinic \
  -e DB_USERNAME=petclinic \
  -e DB_PASSWORD=petclinic \
  petclinic-test:local

echo "Waiting for application to start..."
sleep 30

# 5. 헬스체크
echo -e "${YELLOW}[5/5] Running health check...${NC}"
HEALTH_STATUS=$(curl -s http://localhost:9090/actuator/health | grep -o '"status":"[^"]*"' | cut -d'"' -f4)

if [ "$HEALTH_STATUS" = "UP" ]; then
    echo -e "${GREEN}✓ Health check passed: $HEALTH_STATUS${NC}"
    echo ""
    echo "======================================"
    echo -e "${GREEN}All tests passed!${NC}"
    echo "======================================"
    echo ""
    echo "Application is running at: http://localhost:9090"
    echo ""
    echo "To view logs:"
    echo "  docker logs -f petclinic-test"
    echo ""
    echo "To stop:"
    echo "  docker stop petclinic-test"
    echo "  docker rm petclinic-test"
    echo "  docker-compose down"
else
    echo -e "${RED}✗ Health check failed: $HEALTH_STATUS${NC}"
    echo ""
    echo "Logs:"
    docker logs petclinic-test

    # Cleanup
    docker stop petclinic-test
    docker rm petclinic-test
    docker-compose down
    exit 1
fi
