#!/bin/bash
set -e

# OpenResty 版本和安装目录（可通过环境变量覆盖）
OPENRESTY_VERSION=${OPENRESTY_VERSION:-1.21.4.1}
OPENRESTY_PREFIX=${OPENRESTY_PREFIX:-/opt/apiok/openresty}

# 设置环境变量（无论是否安装都需要）
export PATH=${OPENRESTY_PREFIX}/bin:${OPENRESTY_PREFIX}/nginx/sbin:${OPENRESTY_PREFIX}/luajit/bin:$PATH
export LUA_PATH="${OPENRESTY_PREFIX}/luajit/share/luajit-2.1.0-beta3/?.lua;${OPENRESTY_PREFIX}/luajit/share/luajit-2.1.0-beta3/?/init.lua;${OPENRESTY_PREFIX}/lualib/?.lua;${OPENRESTY_PREFIX}/lualib/?/init.lua;;"
export LUA_CPATH="${OPENRESTY_PREFIX}/luajit/lib/lua/5.1/?.so;${OPENRESTY_PREFIX}/lualib/?.so;;"

# 安装 OpenResty（如果未安装）
if [ ! -f "${OPENRESTY_PREFIX}/bin/openresty" ]; then
    echo "[OpenResty] 编译安装 OpenResty ${OPENRESTY_VERSION}..."
    echo "[OpenResty] 安装目录: ${OPENRESTY_PREFIX}"
    
    BUILD_DIR=$(pwd)
    DEPS_DIR="${BUILD_DIR}/deps"
    OPENRESTY_TAR="openresty-${OPENRESTY_VERSION}.tar.gz"
    DEPS_TAR="${DEPS_DIR}/${OPENRESTY_TAR}"
    TMP_TAR="/tmp/${OPENRESTY_TAR}"
    
    # 创建 deps 目录（如果不存在）
    mkdir -p "${DEPS_DIR}"
    
    # 检查 deps 目录中是否存在 OpenResty 源码
    if [ -f "${DEPS_TAR}" ]; then
        echo "[OpenResty] 从 deps 目录使用已下载的源码: ${DEPS_TAR}"
        cp "${DEPS_TAR}" "${TMP_TAR}" || {
            echo "[OpenResty] 错误: 无法复制源码文件到 /tmp"
            exit 1
        }
    else
        echo "[OpenResty] deps 目录中未找到源码，开始下载..."
        cd /tmp || {
            echo "[OpenResty] 错误: 无法切换到 /tmp 目录"
            exit 1
        }
        
        wget -q https://openresty.org/download/${OPENRESTY_TAR} || {
            echo "[OpenResty] 错误: 下载失败"
            exit 1
        }
        
        echo "[OpenResty] 保存源码到 deps 目录..."
        cp "${TMP_TAR}" "${DEPS_TAR}" || {
            echo "[OpenResty] 警告: 无法保存到 deps 目录，继续使用临时文件"
        }
    fi
    
    cd /tmp || {
        echo "[OpenResty] 错误: 无法切换到 /tmp 目录"
        exit 1
    }
    
    echo "[OpenResty] 解压源码..."
    tar -xzf "${TMP_TAR}" || {
        echo "[OpenResty] 错误: 解压失败"
        exit 1
    }
    
    cd openresty-${OPENRESTY_VERSION} || {
        echo "[OpenResty] 错误: 无法进入源码目录"
        exit 1
    }
    
    echo "[OpenResty] 配置编译选项..."
    ./configure \
        --prefix=${OPENRESTY_PREFIX} \
        --with-pcre-jit \
        --with-http_ssl_module \
        --with-http_realip_module \
        --with-http_stub_status_module \
        --with-http_v2_module \
        --with-http_gzip_static_module \
        --with-http_secure_link_module \
        --with-http_auth_request_module \
        -j$(nproc) || {
        echo "[OpenResty] 错误: 配置失败"
        exit 1
    }
    
    echo "[OpenResty] 编译 OpenResty..."
    make -j$(nproc) || {
        echo "[OpenResty] 错误: 编译失败"
        exit 1
    }
    
    echo "[OpenResty] 安装 OpenResty..."
    make install || {
        echo "[OpenResty] 错误: 安装失败"
        exit 1
    }
    
    cd "${BUILD_DIR}" || cd /build || true
    rm -rf /tmp/openresty-${OPENRESTY_VERSION}* || true
    
    # 创建符号链接
    mkdir -p /usr/local/bin
    ln -sf ${OPENRESTY_PREFIX}/bin/openresty /usr/local/bin/openresty || true
    ln -sf ${OPENRESTY_PREFIX}/bin/resty /usr/local/bin/resty || true
    
    echo "[OpenResty] OpenResty ${OPENRESTY_VERSION} 安装完成！"
    echo ""
else
    echo "[OpenResty] OpenResty 已安装，跳过编译"
    echo ""
fi

