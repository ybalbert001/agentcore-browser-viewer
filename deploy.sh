#!/bin/bash

# AgentCore Browser Viewer - AWS 自动化部署脚本
# 该脚本会创建ECR仓库、构建镜像、推送到ECR，并部署到App Runner

set -e

# 配置变量
REGION=${AWS_REGION:-"us-east-1"}
REPOSITORY_NAME="agentcore-browser-viewer"
SERVICE_NAME="agentcore-browser-service"
APP_RUNNER_ROLE_NAME="AgentCoreBrowserAppRunnerRole"
ECR_ACCESS_ROLE_NAME="AppRunnerECRAccessRole"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查必要的工具
check_prerequisites() {
    log_info "检查必要的工具..."

    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI 未安装，请先安装 AWS CLI"
        exit 1
    fi

    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi

    # 检查 AWS 凭证
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS 凭证未配置，请运行 'aws configure'"
        exit 1
    fi

    log_success "所有必要工具已安装"
}

# 获取 AWS 账号 ID
get_account_id() {
    aws sts get-caller-identity --query Account --output text
}

# 创建 ECR 仓库
create_ecr_repository() {
    log_info "创建 ECR 仓库: $REPOSITORY_NAME"

    if aws ecr describe-repositories --repository-names $REPOSITORY_NAME --region $REGION &> /dev/null; then
        log_warning "ECR 仓库 $REPOSITORY_NAME 已存在"
        return 0
    fi

    aws ecr create-repository \
        --repository-name $REPOSITORY_NAME \
        --region $REGION \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256

    log_success "ECR 仓库创建成功"
}

# 构建和推送 Docker 镜像
build_and_push_image() {
    log_info "构建 Docker 镜像..."

    ACCOUNT_ID=$(get_account_id)
    ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPOSITORY_NAME}"

    # 登录到 ECR
    log_info "登录到 ECR..."
    aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_URI

    # 构建镜像 (强制使用 amd64 架构以兼容 AWS App Runner)
    log_info "构建镜像..."
    docker build --platform linux/amd64 -t $REPOSITORY_NAME .

    # 标记镜像
    docker tag $REPOSITORY_NAME:latest $ECR_URI:latest

    # 推送镜像
    log_info "推送镜像到 ECR..."
    docker push $ECR_URI:latest

    log_success "镜像推送成功: $ECR_URI:latest"
    echo $ECR_URI:latest
}

# 创建 ECR 访问角色
create_ecr_access_role() {
    log_info "创建 ECR 访问角色: $ECR_ACCESS_ROLE_NAME"

    # 检查角色是否存在
    if aws iam get-role --role-name $ECR_ACCESS_ROLE_NAME &> /dev/null; then
        log_warning "ECR 访问角色 $ECR_ACCESS_ROLE_NAME 已存在"
    else
        # 创建 ECR 访问角色
        aws iam create-role \
            --role-name $ECR_ACCESS_ROLE_NAME \
            --path /service-role/ \
            --assume-role-policy-document '{
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {
                            "Service": "build.apprunner.amazonaws.com"
                        },
                        "Action": "sts:AssumeRole"
                    }
                ]
            }'

        # 附加 ECR 访问策略
        aws iam attach-role-policy \
            --role-name $ECR_ACCESS_ROLE_NAME \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess

        log_success "ECR 访问角色创建成功"
    fi
}

# 创建 IAM 角色 (如果不存在)
create_iam_role() {
    log_info "创建 IAM 角色: $APP_RUNNER_ROLE_NAME"

    # 检查角色是否存在
    if aws iam get-role --role-name $APP_RUNNER_ROLE_NAME &> /dev/null; then
        log_warning "IAM 角色 $APP_RUNNER_ROLE_NAME 已存在"
        return 0
    fi

    # 信任策略
    TRUST_POLICY='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "Service": [
                        "tasks.apprunner.amazonaws.com",
                        "build.apprunner.amazonaws.com"
                    ]
                },
                "Action": "sts:AssumeRole"
            }
        ]
    }'

    # 创建角色
    aws iam create-role \
        --role-name $APP_RUNNER_ROLE_NAME \
        --assume-role-policy-document "$TRUST_POLICY"

    # 权限策略
    POLICY_DOCUMENT='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "ssm:GetParameter",
                    "ssm:PutParameter",
                    "ssm:DeleteParameter"
                ],
                "Resource": [
                    "arn:aws:ssm:'$REGION':*:parameter/browser-session/*"
                ]
            },
            {
                "Effect": "Allow",
                "Action": [
                    "bedrock:*"
                ],
                "Resource": "*"
            },
            {
                "Effect": "Allow",
                "Action": [
                    "ecr:GetAuthorizationToken",
                    "ecr:BatchCheckLayerAvailability",
                    "ecr:GetDownloadUrlForLayer",
                    "ecr:BatchGetImage"
                ],
                "Resource": "*"
            }
        ]
    }'

    # 创建策略
    POLICY_ARN=$(aws iam create-policy \
        --policy-name "${APP_RUNNER_ROLE_NAME}Policy" \
        --policy-document "$POLICY_DOCUMENT" \
        --query 'Policy.Arn' --output text)

    # 附加策略到角色
    aws iam attach-role-policy \
        --role-name $APP_RUNNER_ROLE_NAME \
        --policy-arn $POLICY_ARN

    log_success "IAM 角色创建成功"
}

# 部署到 App Runner
deploy_to_app_runner() {
    log_info "部署到 App Runner..."

    ACCOUNT_ID=$(get_account_id)
    ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPOSITORY_NAME}:latest"
    ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${APP_RUNNER_ROLE_NAME}"
    ECR_ACCESS_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/service-role/${ECR_ACCESS_ROLE_NAME}"

    # 检查服务是否存在
    if aws apprunner describe-service --service-arn $(aws apprunner list-services --query "ServiceSummaryList[?ServiceName=='$SERVICE_NAME'].ServiceArn" --output text) &> /dev/null; then
        log_warning "App Runner 服务 $SERVICE_NAME 已存在，正在更新..."

        # 更新服务
        aws apprunner update-service \
            --service-arn $(aws apprunner list-services --query "ServiceSummaryList[?ServiceName=='$SERVICE_NAME'].ServiceArn" --output text) \
            --source-configuration "{
                \"ImageRepository\": {
                    \"ImageIdentifier\": \"$ECR_URI\",
                    \"ImageRepositoryType\": \"ECR\",
                    \"ImageConfiguration\": {
                        \"Port\": \"8000\",
                        \"RuntimeEnvironmentVariables\": {
                            \"AWS_DEFAULT_REGION\": \"$REGION\"
                        }
                    }
                },
                \"AutoDeploymentsEnabled\": false,
                \"AuthenticationConfiguration\": {
                    \"AccessRoleArn\": \"$ECR_ACCESS_ROLE_ARN\"
                }
            }"
    else
        log_info "创建新的 App Runner 服务..."

        # 创建服务
        aws apprunner create-service \
            --service-name $SERVICE_NAME \
            --source-configuration "{
                \"ImageRepository\": {
                    \"ImageIdentifier\": \"$ECR_URI\",
                    \"ImageRepositoryType\": \"ECR\",
                    \"ImageConfiguration\": {
                        \"Port\": \"8000\",
                        \"RuntimeEnvironmentVariables\": {
                            \"AWS_DEFAULT_REGION\": \"$REGION\"
                        }
                    }
                },
                \"AutoDeploymentsEnabled\": false,
                \"AuthenticationConfiguration\": {
                    \"AccessRoleArn\": \"$ECR_ACCESS_ROLE_ARN\"
                }
            }" \
            --instance-configuration "{
                \"Cpu\": \"2 vCPU\",
                \"Memory\": \"4 GB\",
                \"InstanceRoleArn\": \"$ROLE_ARN\"
            }" \
            --health-check-configuration "{
                \"Protocol\": \"HTTP\",
                \"Path\": \"/api/session-info\",
                \"Interval\": 20,
                \"Timeout\": 10,
                \"HealthyThreshold\": 3,
                \"UnhealthyThreshold\": 5
            }"
    fi
}

# 获取服务状态和 URL
get_service_info() {
    log_info "获取服务信息..."

    # 等待服务就绪
    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        SERVICE_STATUS=$(aws apprunner describe-service \
            --service-arn $(aws apprunner list-services --query "ServiceSummaryList[?ServiceName=='$SERVICE_NAME'].ServiceArn" --output text) \
            --query 'Service.Status' --output text)

        if [ "$SERVICE_STATUS" = "RUNNING" ]; then
            break
        fi

        log_info "服务状态: $SERVICE_STATUS (等待中... $attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done

    if [ "$SERVICE_STATUS" != "RUNNING" ]; then
        log_error "服务启动超时，当前状态: $SERVICE_STATUS"
        return 1
    fi

    # 获取服务 URL
    SERVICE_URL=$(aws apprunner describe-service \
        --service-arn $(aws apprunner list-services --query "ServiceSummaryList[?ServiceName=='$SERVICE_NAME'].ServiceArn" --output text) \
        --query 'Service.ServiceUrl' --output text)

    log_success "服务部署成功！"
    echo ""
    echo "=========================================="
    echo "部署信息:"
    echo "=========================================="
    echo "服务名称: $SERVICE_NAME"
    echo "服务状态: $SERVICE_STATUS"
    echo "服务 URL: https://$SERVICE_URL"
    echo "访问示例: https://$SERVICE_URL/?browser_session_id=YOUR_SESSION_ID"
    echo "=========================================="
}

# 清理函数
cleanup() {
    log_info "清理临时文件..."
    # 这里可以添加清理逻辑
}

# 主函数
main() {
    log_info "开始部署 AgentCore Browser Viewer..."
    echo ""

    trap cleanup EXIT

    check_prerequisites
    create_ecr_repository
    IMAGE_URI=$(build_and_push_image)
    create_ecr_access_role
    create_iam_role
    deploy_to_app_runner
    get_service_info

    log_success "部署完成！"
}

# 帮助信息
show_help() {
    cat << EOF
AgentCore Browser Viewer 部署脚本

用法: $0 [选项]

选项:
    -h, --help          显示此帮助信息
    -r, --region        指定 AWS 区域 (默认: us-east-1)
    --cleanup           清理资源 (删除 ECR 仓库和 App Runner 服务)

环境变量:
    AWS_REGION         AWS 区域 (默认: us-east-1)

示例:
    $0                  # 使用默认设置部署
    $0 -r us-west-2     # 部署到 us-west-2 区域
    $0 --cleanup        # 清理所有资源

EOF
}

# 清理资源函数
cleanup_resources() {
    log_warning "正在清理所有资源..."

    # 删除 App Runner 服务
    SERVICE_ARN=$(aws apprunner list-services --query "ServiceSummaryList[?ServiceName=='$SERVICE_NAME'].ServiceArn" --output text)
    if [ -n "$SERVICE_ARN" ]; then
        log_info "删除 App Runner 服务..."
        aws apprunner delete-service --service-arn $SERVICE_ARN
        log_success "App Runner 服务删除请求已提交"
    fi

    # 删除 ECR 仓库
    if aws ecr describe-repositories --repository-names $REPOSITORY_NAME --region $REGION &> /dev/null; then
        log_info "删除 ECR 仓库..."
        aws ecr delete-repository --repository-name $REPOSITORY_NAME --region $REGION --force
        log_success "ECR 仓库删除成功"
    fi

    # 删除 ECR 访问角色
    if aws iam get-role --role-name $ECR_ACCESS_ROLE_NAME &> /dev/null; then
        log_info "删除 ECR 访问角色..."

        # 分离策略
        aws iam detach-role-policy \
            --role-name $ECR_ACCESS_ROLE_NAME \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess || true

        # 删除角色
        aws iam delete-role --role-name $ECR_ACCESS_ROLE_NAME
        log_success "ECR 访问角色删除成功"
    fi

    # 删除 IAM 角色和策略
    if aws iam get-role --role-name $APP_RUNNER_ROLE_NAME &> /dev/null; then
        log_info "删除 IAM 角色..."

        # 分离策略
        POLICY_ARN="arn:aws:iam::$(get_account_id):policy/${APP_RUNNER_ROLE_NAME}Policy"
        aws iam detach-role-policy --role-name $APP_RUNNER_ROLE_NAME --policy-arn $POLICY_ARN || true

        # 删除策略
        aws iam delete-policy --policy-arn $POLICY_ARN || true

        # 删除角色
        aws iam delete-role --role-name $APP_RUNNER_ROLE_NAME
        log_success "IAM 角色删除成功"
    fi

    log_success "清理完成！"
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        --cleanup)
            cleanup_resources
            exit 0
            ;;
        *)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done

# 执行主函数
main