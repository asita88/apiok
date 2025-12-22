#!/bin/bash
set -x

# 直接从 GitHub 下载 Resty 模块到 resty 目录
# 不使用 luarocks，直接下载源码文件
# 下载的 tar.gz 文件保存在 deps/，解压后的文件放在 resty/

RESTY_DIR=${RESTY_DIR:-./resty}
DEPS_DIR=${DEPS_DIR:-./deps}

echo "=========================================="
echo "下载 Resty 模块到 resty 目录"
echo "=========================================="
echo ""

# 创建目录结构
mkdir -p "${RESTY_DIR}"
mkdir -p "${DEPS_DIR}"  # 保存下载的原始文件

# 定义模块列表：模块名:GitHub仓库:版本/标签
declare -a MODULES=(
    "lua-resty-consul:hamishforbes/lua-resty-consul:v0.3.2"
    "lua-resty-mysql:openresty/lua-resty-mysql:0.26"
    "lua-resty-jit-uuid:thibaultcha/lua-resty-jit-uuid:0.0.7"
    "lua-resty-http:ledgetech/lua-resty-http:v0.16"
    "lua-resty-worker-events:Kong/lua-resty-worker-events:2.0.1"
    "lua-resty-dns:openresty/lua-resty-dns:v0.21"
    "lua-resty-balancer:openresty/lua-resty-balancer:0.05"
    "lua-resty-lrucache:openresty/lua-resty-lrucache:v0.09"
    "lua-resty-jwt:SkyLothar/lua-resty-jwt:v0.1.11"
    "lua-resty-limit-traffic:openresty/lua-resty-limit-traffic:v0.07"
    "lua-tinyyaml:peposso/lua-tinyyaml:1.0"
    "Penlight:lunarmodules/Penlight:1.13.1"
    "lua-multipart:Kong/lua-multipart:0.5.11-1"
    "jsonschema:api7/jsonschema:0.9.9"
    "neturl:golgote/neturl:1.2-1"
    "lua-resty-healthcheck:Kong/lua-resty-healthcheck:3.1.1"
    "lua-resty-timer:Kong/lua-resty-timer:1.1.0"
)

# 下载函数
download_module() {
    local module_name=$1
    local repo=$2
    local version=$3
    
    echo "下载 $module_name ($version)..."
    
    # 保存当前目录和目录的绝对路径
    local original_dir=$(pwd)
    local resty_abs_dir=$(cd "${RESTY_DIR}" 2>/dev/null && pwd || echo "${RESTY_DIR}")
    local deps_abs_dir=$(cd "${DEPS_DIR}" 2>/dev/null && pwd || echo "${DEPS_DIR}")
    
    # 创建临时目录
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"

    # 检查 deps 目录中是否已存在下载的文件
    local archive_file="${deps_abs_dir}/${module_name}-${version}.tar.gz"
    
    if [ -f "$archive_file" ]; then
        echo "  → 使用已存在的文件: deps/${module_name}-${version}.tar.gz"
        cp "$archive_file" "${module_name}.tar.gz"
    else
        # 下载并解压（使用 -L 跟随重定向，GitHub 会返回 302）
        # 使用 --server-response 显示服务器响应头（包括 302 重定向地址）
        # 响应头会输出到 stderr，我们过滤显示重定向信息
        if wget --server-response -L "https://github.com/${repo}/archive/refs/tags/${version}.tar.gz" -O "${module_name}.tar.gz" 2>&1 | tee /tmp/wget_${module_name}.log | grep -q "saved"; then
            # 显示重定向信息
            grep -E "(HTTP|Location|302|301)" /tmp/wget_${module_name}.log 2>/dev/null || true
            rm -f /tmp/wget_${module_name}.log
            
            # 保存下载的文件到 deps 目录
            mkdir -p "${deps_abs_dir}"
            cp "${module_name}.tar.gz" "$archive_file" 2>/dev/null && {
                echo "  → 已保存到 deps/${module_name}-${version}.tar.gz"
            } || true
        else
            echo "  ✗ $module_name 下载失败"
            # 显示错误信息
            grep -E "(HTTP|Location|302|301|error|failed)" /tmp/wget_${module_name}.log 2>/dev/null || true
            rm -f /tmp/wget_${module_name}.log
            cd - > /dev/null
            rm -rf "$temp_dir"
            return 1
        fi
    fi
    
    tar -xzf "${module_name}.tar.gz" 2>/dev/null || {
        echo "  ✗ $module_name 解压失败"
        cd - > /dev/null
        rm -rf "$temp_dir"
        return 1
    }
    
    # 查找解压后的目录
    local extracted_dir=$(find . -maxdepth 1 -type d -name "${module_name}*" | head -1)
    if [ -z "$extracted_dir" ]; then
        extracted_dir=$(find . -maxdepth 1 -type d ! -name . | head -1)
    fi
    
    if [ -z "$extracted_dir" ] || [ ! -d "$extracted_dir" ]; then
        echo "  ✗ $module_name 找不到解压目录"
        cd - > /dev/null
        rm -rf "$temp_dir"
        return 1
    fi
    
    # 对于 Penlight，特殊处理（直接安装到 resty/pl/ 目录）
    if [ "$module_name" == "Penlight" ]; then
        if [ -d "$extracted_dir/lua/pl" ]; then
            # 复制到 resty/pl/ 目录
            mkdir -p "${resty_abs_dir}/pl"
            cp -r "$extracted_dir/lua/pl/"* "${resty_abs_dir}/pl/" 2>/dev/null || true
            echo "  ✓ $module_name 安装完成（安装到 resty/pl/）"
            cd - > /dev/null
            rm -rf "$temp_dir"
            return 0
        elif [ -d "$extracted_dir/pl" ]; then
            # 如果直接有 pl 目录
            mkdir -p "${resty_abs_dir}/pl"
            cp -r "$extracted_dir/pl/"* "${resty_abs_dir}/pl/" 2>/dev/null || true
            echo "  ✓ $module_name 安装完成（安装到 resty/pl/）"
            cd - > /dev/null
            rm -rf "$temp_dir"
            return 0
        fi
    fi
    
    # 对于 multipart，特殊处理（src 目录下的文件直接复制到 resty 根目录）
    if [ "$module_name" == "lua-multipart" ]; then
        if [ -d "$extracted_dir/src" ]; then
            # 复制 src 目录下的所有 .lua 文件直接到 resty 目录（不保留 src/ 路径）
            find "$extracted_dir/src" -name "*.lua" -type f | while read -r file; do
                local filename=$(basename "$file")
                cp "$file" "${resty_abs_dir}/${filename}"
            done
            echo "  ✓ $module_name 安装完成（从 src 目录安装到 resty/）"
            cd - > /dev/null
            rm -rf "$temp_dir"
            return 0
        fi
    fi
    
    # 所有模块都复制到 resty 目录
    local target_dir="${resty_abs_dir}"
    
    # 创建目标目录
    mkdir -p "$target_dir"
    
    # 查找并复制 resty 目录下的文件
    if [ -d "$extracted_dir/lib/resty" ]; then
        # 如果存在 lib/resty 目录，直接复制
        cp -r "$extracted_dir/lib/resty/"* "$target_dir/" 2>/dev/null || true
    elif [ -d "$extracted_dir/resty" ]; then
        # 如果存在 resty 目录，直接复制
        cp -r "$extracted_dir/resty/"* "$target_dir/" 2>/dev/null || true
    elif [ -d "$extracted_dir/lib" ]; then
        # 如果存在 lib 目录，查找其中的 lua 文件
        find "$extracted_dir/lib" -name "*.lua" -type f | while read -r file; do
            local rel_path="${file#$extracted_dir/lib/}"
            local dest_file="${target_dir}/${rel_path}"
            mkdir -p "$(dirname "$dest_file")"
            cp "$file" "$dest_file"
        done
    else
        # 直接查找所有 .lua 文件
        find "$extracted_dir" -name "*.lua" -type f | while read -r file; do
            local rel_path="${file#$extracted_dir/}"
            # 跳过测试文件和示例文件
            if [[ "$rel_path" == *"/test/"* ]] || [[ "$rel_path" == *"/example"* ]] || [[ "$rel_path" == *"/t/"* ]]; then
                continue
            fi
            local dest_file="${target_dir}/${rel_path}"
            mkdir -p "$(dirname "$dest_file")"
            cp "$file" "$dest_file"
        done
    fi
    
    # 对于 tinyyaml，特殊处理（不是 resty 模块）
    if [ "$module_name" == "lua-tinyyaml" ]; then
        if [ -d "$extracted_dir/lib" ]; then
            mkdir -p "${resty_abs_dir}/share/lua/5.1/"
            cp -r "$extracted_dir/lib/"* "${resty_abs_dir}/share/lua/5.1/" 2>/dev/null || true
        fi
    fi
    
    # 对于 lua-resty-url，特殊处理（提供 resty.url 模块）
    if [ "$module_name" == "lua-resty-url" ]; then
        # 复制 resty.url 模块
        if [ -d "$extracted_dir/lib/resty" ]; then
            cp -r "$extracted_dir/lib/resty/"* "${resty_abs_dir}/" 2>/dev/null || true
        fi
        echo "  ✓ $module_name 安装完成（安装到 resty/）"
        cd - > /dev/null
        rm -rf "$temp_dir"
        return 0
    fi
    
    # 对于 lua-net-url，特殊处理（提供 net.url 模块，jsonschema 的依赖）
    if [ "$module_name" == "lua-net-url" ]; then
        # 查找并复制 net/url.lua 文件
        if [ -f "$extracted_dir/net/url.lua" ]; then
            mkdir -p "${resty_abs_dir}/net"
            cp "$extracted_dir/net/url.lua" "${resty_abs_dir}/net/url.lua" 2>/dev/null || true
        elif [ -f "$extracted_dir/src/net/url.lua" ]; then
            mkdir -p "${resty_abs_dir}/net"
            cp "$extracted_dir/src/net/url.lua" "${resty_abs_dir}/net/url.lua" 2>/dev/null || true
        elif [ -d "$extracted_dir/lib/net" ]; then
            mkdir -p "${resty_abs_dir}/net"
            cp -r "$extracted_dir/lib/net/"* "${resty_abs_dir}/net/" 2>/dev/null || true
        else
            # 查找所有 net 相关的文件
            find "$extracted_dir" -path "*/net/*" -name "*.lua" -type f | while read -r file; do
                local rel_path="${file#$extracted_dir/}"
                local dest_file="${resty_abs_dir}/${rel_path}"
                mkdir -p "$(dirname "$dest_file")"
                cp "$file" "$dest_file"
            done
        fi
        echo "  ✓ $module_name 安装完成（安装到 resty/net/）"
        cd - > /dev/null
        rm -rf "$temp_dir"
        return 0
    fi
    
    cd - > /dev/null
    rm -rf "$temp_dir"
    
    echo "  ✓ $module_name 安装完成"
    return 0
}

# 下载所有模块
success_count=0
fail_count=0

echo "准备下载 ${#MODULES[@]} 个模块..."
echo ""

# 临时禁用 set -e，确保循环能继续执行


for module_info in "${MODULES[@]}"; do
    IFS=':' read -r module_name repo version <<< "$module_info"
    
    echo "[$((success_count + fail_count + 1))/${#MODULES[@]}] 处理模块: $module_name"
    
    download_module "$module_name" "$repo" "$version"
    result=$?
    
    if [ "$result" -eq 0 ]; then
        ((success_count++)) || true
    else
        ((fail_count++)) || true
        echo "  ⚠ $module_name 下载失败，继续处理下一个模块..."
    fi
    echo ""
done



echo ""
echo "=========================================="
echo "安装完成！"
echo "成功: $success_count, 失败: $fail_count"
echo "=========================================="
echo ""
echo "模块已保存到: ${RESTY_DIR}/"
echo "原始文件已保存到: ${DEPS_DIR}/"
echo ""

# 如果有失败的模块，返回非零退出码
if [ "$fail_count" -gt 0 ]; then
    exit 1
else
    exit 0
fi

