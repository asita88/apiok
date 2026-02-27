#!/bin/bash
set -e

sudo apt-get update
sudo apt-get install -y build-essential gcc g++ wget make perl \
  libpcre3-dev libssl-dev zlib1g-dev automake autoconf libtool

sudo mkdir -p /opt/apiok/openresty /opt/apiok/apiok

chmod +x scripts/*.sh
sudo make build
make deps
sudo make SKIP_SYSTEM_BIN=1 install

mkdir -p release
sudo cp -r /opt/apiok/apiok /opt/apiok/openresty release/
