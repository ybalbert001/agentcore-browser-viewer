# AgentCore Browser Viewer - AWS 部署指南

## 快速部署

### 一键部署命令

```bash
# 给脚本执行权限
chmod +x deploy.sh

# 执行部署
./deploy.sh
```

## 部署架构

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   用户浏览器     │───▶│   App Runner     │───▶│  Parameter Store │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌─────────────────┐
                       │      ECR        │
                       └─────────────────┘
```

## 部署步骤详解

### 1. 前置条件检查

脚本会自动检查：
- ✅ AWS CLI 已安装且配置
- ✅ Docker 已安装并运行
- ✅ AWS 凭证有效

### 2. 创建 ECR 仓库

```bash
# 仓库名称: agentcore-browser-viewer
# 区域: us-east-1 (可配置)
# 加密: AES256
# 漏洞扫描: 启用
```

### 3. 构建和推送镜像

脚本会：
1. 构建包含 DCV SDK 的 Docker 镜像
2. 登录到 ECR
3. 推送镜像到仓库

### 4. 创建 IAM 权限

自动创建角色 `AgentCoreBrowserAppRunnerRole`，包含权限：
- Parameter Store 读写 (`/browser-session/*`)
- Amazon Bedrock 访问
- ECR 镜像拉取

### 5. 部署到 App Runner

- **CPU**: 0.25 vCPU
- **内存**: 0.5 GB
- **端口**: 8000
- **健康检查**: `/api/session-info`
- **自动扩缩**: 启用

## 使用方式

### 部署成功后访问

```
https://xxxxx.us-east-1.awsapprunner.com/?browser_session_id=YOUR_SESSION_ID
```

### 配置选项

```bash
# 指定区域
./deploy.sh -r us-west-2

# 查看帮助
./deploy.sh --help

# 清理所有资源
./deploy.sh --cleanup
```

## 成本估算

### App Runner 成本 (按使用付费)
- **计算**: $0.007/vCPU 小时 + $0.0008/GB 内存小时
- **月估算**: ~$5-15 (轻度使用)

### ECR 成本
- **存储**: $0.10/GB/月
- **传输**: 每月前 1GB 免费

### 总月成本: ~$6-20

## 监控和日志

### CloudWatch 指标

App Runner 自动提供：
- CPU 利用率
- 内存利用率
- 请求数量和延迟
- 4xx/5xx 错误率

### 查看日志

```bash
# 通过 AWS CLI 查看日志
aws logs describe-log-groups --log-group-name-prefix /aws/apprunner/agentcore-browser

# 或在 AWS 控制台查看
# CloudWatch → Log groups → /aws/apprunner/agentcore-browser-service
```

## 故障排除

### 常见问题

1. **部署失败**
   ```bash
   # 检查 AWS 凭证
   aws sts get-caller-identity

   # 检查权限
   aws iam get-user
   ```

2. **服务启动失败**
   ```bash
   # 查看服务状态
   aws apprunner describe-service --service-arn <SERVICE_ARN>

   # 查看构建日志
   aws logs get-log-events --log-group-name <LOG_GROUP>
   ```

3. **DCV 连接问题**
   - 确保 browser_session_id 存在于 Parameter Store
   - 检查 `/browser-session/{session_id}` 参数
   - 验证 live_view_url 有效性

### 手动验证

```bash
# 1. 测试服务健康状态
curl https://YOUR_APP_URL/api/session-info

# 2. 检查 Parameter Store
aws ssm get-parameter --name "/browser-session/test-session" --with-decryption

# 3. 验证 ECR 镜像
aws ecr describe-images --repository-name agentcore-browser-viewer
```

## 更新部署

```bash
# 重新运行脚本即可更新
./deploy.sh
```

脚本会：
- 检测到已存在的服务
- 构建新镜像
- 推送到 ECR
- 更新 App Runner 服务

## 安全最佳实践

### IAM 权限最小化
- 只授予必要的 Parameter Store 路径权限
- 限制 Bedrock 访问（如需要）

### 网络安全
- App Runner 服务运行在 AWS 托管 VPC
- 支持自定义 VPC 配置（企业需求）

### 数据保护
- ECR 镜像加密
- Parameter Store 值加密
- HTTPS 强制访问

## 高级配置

### 自定义域名

```bash
# 1. 在 App Runner 控制台配置自定义域
# 2. 添加 CNAME 记录到您的 DNS
# 3. 等待 SSL 证书验证
```

### 环境变量

修改 `deploy.sh` 中的环境变量配置：

```bash
"RuntimeEnvironmentVariables": {
    "AWS_DEFAULT_REGION": "$REGION",
    "LOG_LEVEL": "INFO",
    "CUSTOM_VAR": "value"
}
```

### 资源配置

调整 App Runner 实例大小：

```bash
"InstanceConfiguration": {
    "Cpu": "0.5 vCPU",      # 或 1 vCPU
    "Memory": "1 GB"        # 或 2 GB
}
```

## 支持

如有问题，请检查：
1. AWS 服务状态页面
2. CloudWatch 日志
3. App Runner 服务事件