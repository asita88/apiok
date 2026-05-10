#!/usr/bin/env bash
set -euo pipefail

: "${APP_DIR:?missing APP_DIR}"
: "${CURRENT_DIR:?missing CURRENT_DIR}"
: "${RELEASE_DIR:?missing RELEASE_DIR}"
OLD_DIR="${OLD_DIR:-}"

echo "[deploy.sh] app_dir=$APP_DIR current=$CURRENT_DIR release=$RELEASE_DIR old=${OLD_DIR:-<none>} at=$(date -Is) host=$(hostname)"

"$APP_ROOT/openresty/nginx/sbin/nginx" -s reload -p "$APP_ROOT/apiok" -c "$APP_ROOT/apiok/conf/nginx.conf" 2>/dev/null || true