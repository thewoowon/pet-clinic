pipeline {
    agent any

    environment {
        // AWS 설정
        AWS_DEFAULT_REGION = 'ap-northeast-2'
        AWS_ACCOUNT_ID = '205922933402'

        // ECR 설정
        ECR_REGISTRY = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"
        ECR_REPO_FRONT = 'front'
        ECR_REPO_BACK1 = 'back1'
        ECR_REPO_BACK2 = 'back2'

        // 이미지 태그
        IMAGE_TAG = "${env.BUILD_NUMBER}"

        // Jenkins Credentials
        AWS_CREDENTIALS = 'aws-cred'

        // ECS 설정
        ECS_CLUSTER = 'petclinic-cluster'
        ECS_SERVICE_FRONT = 'front-service'
        ECS_SERVICE_BACK1 = 'back1-service'
        ECS_SERVICE_BACK2 = 'back2-service'
    }

    stages {
        stage('Checkout') {
            steps {
                echo '========== Git Checkout =========='
                git branch: 'main', url: 'https://github.com/thewoowon/pet-clinic.git'
            }
        }

        stage('Build Application') {
            steps {
                echo '========== Building Spring Boot Application =========='
                script {
                    sh '''
                        chmod +x gradlew
                        export JAVA_HOME=/usr/lib/jvm/java-21-amazon-corretto
                        export PATH=$JAVA_HOME/bin:$PATH
                        java -version

                        # Build with Java 21
                        ./gradlew clean bootJar -x test --no-daemon \
                            -Dorg.gradle.java.home=$JAVA_HOME

                        echo "Build completed successfully!"
                    '''
                }
            }
        }

        stage('Build Docker Images') {
            steps {
                echo '========== Building Docker Images =========='
                script {
                    // 동일한 Dockerfile로 3개 이미지 빌드 (태그만 다름)
                    sh """
                        docker build -t ${ECR_REGISTRY}/${ECR_REPO_FRONT}:${IMAGE_TAG} .
                        docker tag ${ECR_REGISTRY}/${ECR_REPO_FRONT}:${IMAGE_TAG} ${ECR_REGISTRY}/${ECR_REPO_FRONT}:latest
                        docker tag ${ECR_REGISTRY}/${ECR_REPO_FRONT}:${IMAGE_TAG} ${ECR_REGISTRY}/${ECR_REPO_BACK1}:${IMAGE_TAG}
                        docker tag ${ECR_REGISTRY}/${ECR_REPO_FRONT}:${IMAGE_TAG} ${ECR_REGISTRY}/${ECR_REPO_BACK1}:latest
                        docker tag ${ECR_REGISTRY}/${ECR_REPO_FRONT}:${IMAGE_TAG} ${ECR_REGISTRY}/${ECR_REPO_BACK2}:${IMAGE_TAG}
                        docker tag ${ECR_REGISTRY}/${ECR_REPO_FRONT}:${IMAGE_TAG} ${ECR_REGISTRY}/${ECR_REPO_BACK2}:latest
                    """
                }
            }
        }

        stage('Login to ECR') {
            steps {
                echo '========== Logging in to Amazon ECR =========='
                withAWS(credentials: "${AWS_CREDENTIALS}", region: "${AWS_DEFAULT_REGION}") {
                    script {
                        sh """
                            aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | \
                            docker login --username AWS --password-stdin ${ECR_REGISTRY}
                        """
                    }
                }
            }
        }

        stage('Push to ECR') {
            steps {
                echo '========== Pushing Images to ECR =========='
                withAWS(credentials: "${AWS_CREDENTIALS}", region: "${AWS_DEFAULT_REGION}") {
                    script {
                        // Parallel push for faster deployment
                        parallel(
                            front: {
                                sh """
                                    docker push ${ECR_REGISTRY}/${ECR_REPO_FRONT}:${IMAGE_TAG}
                                    docker push ${ECR_REGISTRY}/${ECR_REPO_FRONT}:latest
                                """
                            },
                            back1: {
                                sh """
                                    docker push ${ECR_REGISTRY}/${ECR_REPO_BACK1}:${IMAGE_TAG}
                                    docker push ${ECR_REGISTRY}/${ECR_REPO_BACK1}:latest
                                """
                            },
                            back2: {
                                sh """
                                    docker push ${ECR_REGISTRY}/${ECR_REPO_BACK2}:${IMAGE_TAG}
                                    docker push ${ECR_REGISTRY}/${ECR_REPO_BACK2}:latest
                                """
                            }
                        )
                    }
                }
            }
        }

        stage('Deploy to ECS') {
            steps {
                echo '========== Deploying Services to ECS =========='
                withAWS(credentials: "${AWS_CREDENTIALS}", region: "${AWS_DEFAULT_REGION}") {
                    script {
                        // Parallel deployment for faster rollout
                        parallel(
                            front: {
                                sh """
                                    aws ecs update-service \
                                        --cluster ${ECS_CLUSTER} \
                                        --service ${ECS_SERVICE_FRONT} \
                                        --force-new-deployment \
                                        --region ${AWS_DEFAULT_REGION}
                                """
                            },
                            back1: {
                                sh """
                                    aws ecs update-service \
                                        --cluster ${ECS_CLUSTER} \
                                        --service ${ECS_SERVICE_BACK1} \
                                        --force-new-deployment \
                                        --region ${AWS_DEFAULT_REGION}
                                """
                            },
                            back2: {
                                sh """
                                    aws ecs update-service \
                                        --cluster ${ECS_CLUSTER} \
                                        --service ${ECS_SERVICE_BACK2} \
                                        --force-new-deployment \
                                        --region ${AWS_DEFAULT_REGION}
                                """
                            }
                        )
                    }
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                echo '========== Verifying ECS Deployment =========='
                withAWS(credentials: "${AWS_CREDENTIALS}", region: "${AWS_DEFAULT_REGION}") {
                    script {
                        sh """
                            echo "Waiting for services to stabilize..."
                            aws ecs wait services-stable \
                                --cluster ${ECS_CLUSTER} \
                                --services ${ECS_SERVICE_FRONT} ${ECS_SERVICE_BACK1} ${ECS_SERVICE_BACK2} \
                                --region ${AWS_DEFAULT_REGION}
                            echo "All services are stable!"
                        """
                    }
                }
            }
        }
    }

    post {
        success {
            echo '========== Pipeline Succeeded =========='
            echo "Successfully deployed version ${IMAGE_TAG} to ECS"
            echo "Front: ${ECR_REGISTRY}/${ECR_REPO_FRONT}:${IMAGE_TAG}"
            echo "Back1: ${ECR_REGISTRY}/${ECR_REPO_BACK1}:${IMAGE_TAG}"
            echo "Back2: ${ECR_REGISTRY}/${ECR_REPO_BACK2}:${IMAGE_TAG}"
        }
        failure {
            echo '========== Pipeline Failed =========='
            echo 'Deployment failed. Check logs for details.'
        }
        always {
            echo '========== Cleaning up Docker Images =========='
            sh '''
                docker system prune -f
            '''
        }
    }
}
