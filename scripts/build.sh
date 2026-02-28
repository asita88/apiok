#!/bin/bash
set -e

dnf install -y gcc gcc-c++ make wget perl automake autoconf libtool \
  pcre-devel openssl-devel zlib-devel

mkdir -p /opt/apiok/openresty /opt/apiok/apiok

chmod +x scripts/*.sh
make build
make deps
make SKIP_SYSTEM_BIN=1 install

mkdir -p release
cp -r /opt/apiok/apiok /opt/apiok/openresty release/
