#!/bin/bash

# APIOK 日志轮转安装脚本

LOGS_DIR="/usr/local/apiok/logs"
PID_FILE="$LOGS_DIR/nginx.pid"
ACCESS_LOG="$LOGS_DIR/access.log"
ERROR_LOG="$LOGS_DIR/error.log"

# 检查 logrotate 是否安装
if ! command -v logrotate &> /dev/null; then
    echo "错误: logrotate 未安装"
    echo "请先安装 logrotate:"
    echo "  Ubuntu/Debian: sudo apt-get install logrotate"
    echo "  CentOS/RHEL: sudo yum install logrotate"
    exit 1
fi

# 创建 logrotate 配置
LOGROTATE_CONF="/etc/logrotate.d/apiok"
TEMP_CONF=$(mktemp)

cat > "$TEMP_CONF" <<EOF
$ACCESS_LOG
$ERROR_LOG {
    daily
    rotate 3
    missingok
    notifempty
    compress
    delaycompress
    dateext
    dateformat -%Y%m%d
    sharedscripts
    postrotate
        if [ -f $PID_FILE ]; then
            kill -USR1 \`cat $PID_FILE\`
        fi
    endscript
}
EOF

# 复制配置文件
echo "安装 logrotate 配置到 $LOGROTATE_CONF"
sudo cp "$TEMP_CONF" "$LOGROTATE_CONF"
sudo chmod 644 "$LOGROTATE_CONF"
rm "$TEMP_CONF"

# 测试配置
echo "测试 logrotate 配置..."
sudo logrotate -d "$LOGROTATE_CONF"

if [ $? -eq 0 ]; then
    echo "✓ logrotate 配置安装成功"
    echo ""
    echo "配置说明:"
    echo "  - 日志文件: $ACCESS_LOG, $ERROR_LOG"
    echo "  - 轮转频率: 每天"
    echo "  - 保留天数: 3天"
    echo "  - 压缩: 延迟压缩（第二天压缩）"
    echo ""
    echo "手动测试: sudo logrotate -f $LOGROTATE_CONF"
else
    echo "✗ logrotate 配置测试失败"
    exit 1
fi

