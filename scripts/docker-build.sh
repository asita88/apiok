#!/bin/bash
set -e

echo "=========================================="
echo "APIOK Docker 构建脚本"
echo "=========================================="
echo ""

# [1/4] 编译安装 OpenResty
echo "[1/4] 编译安装 OpenResty..."
make build || {
    echo "错误: OpenResty 编译失败"
    exit 1
}

# [2/4] 下载依赖模块
echo "[2/4] 下载依赖模块..."
make deps || {
    echo "错误: 依赖模块下载失败"
    exit 1
}

# [3/4] 安装 APIOK
echo "[3/4] 安装 APIOK..."
make install || {
    echo "错误: APIOK 安装失败"
    exit 1
}


# [4/4] 打包并复制到输出目录
echo "[4/4] 打包并复制到输出目录..."
OUTPUT_DIR=${OUTPUT_DIR:-/output/apiok}
mkdir -p ${OUTPUT_DIR}
if [ ! -d "/opt/apiok/apiok" ]; then
    echo "错误: APIOK 安装目录不存在: /opt/apiok/apiok"
    exit 1
fi
if [ ! -d "/opt/apiok/openresty" ]; then
    echo "错误: OpenResty 安装目录不存在: /opt/apiok/openresty"
    exit 1
fi
echo "复制 APIOK..."
cp -a /opt/apiok/apiok ${OUTPUT_DIR}/
echo "复制 OpenResty..."
cp -a /opt/apiok/openresty ${OUTPUT_DIR}/
echo "构建产物已复制到: ${OUTPUT_DIR}"

echo ""
echo "=========================================="
echo "构建完成！"
echo "=========================================="
echo "编译产物已保存到: /output/apiok/"
echo ""
ls -lh /output/apiok/

