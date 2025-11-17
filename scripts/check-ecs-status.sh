#!/bin/bash

# ECS 서비스 상태 빠른 확인

AWS_REGION="ap-northeast-2"
ECS_CLUSTER="petclinic-cluster"

echo "=========================================="
echo "ECS 서비스 상태 확인"
echo "=========================================="
echo ""

echo "서비스 목록:"
aws ecs list-services --cluster $ECS_CLUSTER --region $AWS_REGION --query 'serviceArns[]' --output table

echo ""
echo "서비스 상태:"
aws ecs describe-services \
  --cluster $ECS_CLUSTER \
  --services front-service back1-service back2-service \
  --region $AWS_REGION \
  --query 'services[*].[serviceName,status,runningCount,desiredCount,deployments[0].rolloutState]' \
  --output table 2>/dev/null || echo "일부 서비스를 찾을 수 없습니다."

echo ""
echo "Task 목록:"
TASKS=$(aws ecs list-tasks --cluster $ECS_CLUSTER --region $AWS_REGION --query 'taskArns[]' --output text)

if [ -z "$TASKS" ]; then
    echo "실행 중인 Task가 없습니다."
else
    echo "Task ARNs:"
    echo "$TASKS"
    echo ""

    # 첫 번째 Task 상세 정보
    FIRST_TASK=$(echo $TASKS | awk '{print $1}')
    echo "Task 상세 정보 (첫 번째):"
    aws ecs describe-tasks \
      --cluster $ECS_CLUSTER \
      --tasks $FIRST_TASK \
      --region $AWS_REGION \
      --query 'tasks[0].[lastStatus,healthStatus,stoppedReason,containers[0].lastStatus]' \
      --output table
fi

echo ""
echo "이벤트 (문제 확인):"
aws ecs describe-services \
  --cluster $ECS_CLUSTER \
  --services front-service \
  --region $AWS_REGION \
  --query 'services[0].events[:3]' \
  --output table 2>/dev/null || echo "서비스를 찾을 수 없습니다."

echo ""
echo "CloudWatch Logs 확인:"
echo "  aws logs tail /ecs/petclinic-front --follow --region $AWS_REGION"
