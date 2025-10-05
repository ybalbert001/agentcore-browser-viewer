FROM python:3.11-slim

# 设置工作目录
WORKDIR /app

# 安装系统依赖
RUN apt-get update && apt-get install -y \
    curl \
    unzip \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 复制依赖文件并安装Python依赖
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 复制应用代码
COPY . .

# 创建静态文件目录
RUN mkdir -p static/dcvjs

# DCV SDK 文件已经包含在项目中，无需额外下载

# 设置环境变量
ENV PYTHONPATH=/app
ENV AWS_DEFAULT_REGION=us-east-1

# 暴露端口
EXPOSE 8000

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/api/session-info || exit 1

# 启动命令
CMD ["python", "run_live_viewer.py", "--port", "8000"]