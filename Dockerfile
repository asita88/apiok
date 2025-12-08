# APIOK Dockerfile for Build
# 用于在 Docker 容器中编译 APIOK，并将编译产物输出到本地目录

FROM ubuntu:20.04

# 设置环境变量，避免交互式安装
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

# 设置工作目录
WORKDIR /build

# 安装构建依赖和调试工具
RUN apt-get update && apt-get install -y \
    build-essential \
    gcc \
    g++ \
    git \
    curl \
    wget \
    automake \
    autoconf \
    libtool \
    libpcre3-dev \
    libssl-dev \
    zlib1g-dev \
    software-properties-common \
    lsb-release \
    ca-certificates \
    make \
    perl \
    unzip \
    vim \
    less \
    tree \
    htop \
    strace \
    && rm -rf /var/lib/apt/lists/*

# 注意：OpenResty 将在构建时通过 make build-openresty 编译安装
# 可以通过环境变量 OPENRESTY_VERSION 和 OPENRESTY_PREFIX 控制版本和安装目录

# 创建输出目录和安装目录
RUN mkdir -p /output && \
    mkdir -p /usr/local/openresty && \
    mkdir -p /usr/local/apiok

# 复制项目文件到构建目录
COPY Makefile /build/Makefile
COPY apiok /build/apiok
COPY bin /build/bin
COPY conf /build/conf
COPY scripts /build/scripts
COPY resty /build/resty
COPY deps /build/deps

# 设置脚本执行权限（但不自动执行）
RUN chmod +x /build/scripts/*.sh

# 构建 APIOK
RUN /build/scripts/docker-build.sh

# 设置工作目录为 /build
WORKDIR /build

EXPOSE 80 443 8080

# 启动交互式 shell，方便手动执行编译过程
# 使用方法：
#   docker run -it --rm apiok:latest
#   然后在容器内手动执行：
#     cd /build
#     make build-openresty
#     make deps
#     make install
#     或者直接执行: /build/scripts/docker-build.sh
# CMD ["/bin/bash"]

# 启动 Nginx
CMD ["/usr/local/openresty/nginx/sbin/nginx", "-p", "/usr/local/apiok", "-c", "/usr/local/apiok/conf/nginx.conf", "-g", "daemon off;"]
# CMD ["bash", "-c", "/usr/local/openresty/nginx/sbin/nginx -p /usr/local/apiok -c /usr/local/apiok/conf/nginx.conf -g 'daemon off;'"]