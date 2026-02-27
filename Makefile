UNAME            ?= $(shell uname)
INSTALL          ?= install
REMOVE           ?= rm -rf
COPY             ?= cp -rf
CHMOD            ?= chmod -R
DOWNLOAD         ?= wget
UNTAG            ?= tar -zxvf
INST_OK_PRODIR  ?= /opt/apiok/apiok
INST_OK_BINDIR  ?= /usr/bin
# OpenResty 相关变量
OPENRESTY_VERSION ?= 1.25.3.2
OPENRESTY_PREFIX ?= /opt/apiok/openresty

# 默认目标：执行完整的构建和安装流程
.PHONY: all
all: deps build install
	@echo "APIOK 构建和安装完成！"

# 编译安装 OpenResty
.PHONY: build
build:
	@echo "编译安装 OpenResty..."
	@if [ -f scripts/build-openresty.sh ]; then \
		chmod +x scripts/build-openresty.sh && \
		OPENRESTY_VERSION=$(OPENRESTY_VERSION) OPENRESTY_PREFIX=$(OPENRESTY_PREFIX) ./scripts/build-openresty.sh; \
	else \
		echo "错误: scripts/build-openresty.sh 不存在"; \
		exit 1; \
	fi

# 不再使用 luarocks，所有依赖通过 download-deps-modules.sh 直接下载
.PHONY: deps
deps:
	@echo "下载依赖模块..."
	@if [ -f scripts/download-deps-modules.sh ]; then \
		chmod +x scripts/download-deps-modules.sh && \
		RESTY_DIR=./resty ./scripts/download-deps-modules.sh; \
	else \
		echo "错误: scripts/download-deps-modules.sh 不存在"; \
		exit 1; \
	fi
	@echo "编译 lua-resty-balancer 的 C 扩展..."
	@if [ -f deps/lua-resty-balancer-0.05.tar.gz ]; then \
		TMP_DIR=$$(mktemp -d) && \
		cd $$TMP_DIR && \
		tar -xzf $(shell pwd)/deps/lua-resty-balancer-0.05.tar.gz 2>/dev/null && \
		cd lua-resty-balancer-* && \
		if [ -f Makefile ]; then \
			make LUA_INCLUDE_DIR=$(OPENRESTY_PREFIX)/luajit/include/luajit-2.1 \
			     LUA_LIB_DIR=$(OPENRESTY_PREFIX)/luajit/lib \
			     LDFLAGS="-shared -fPIC" || \
			make LUA_INCLUDE_DIR=$(OPENRESTY_PREFIX)/luajit/include/luajit-2.1 || true; \
		elif [ -f chash.c ]; then \
			$$(which gcc || which cc) -shared -fPIC -o librestychash.so chash.c \
				-I$(OPENRESTY_PREFIX)/luajit/include/luajit-2.1 \
				-L$(OPENRESTY_PREFIX)/luajit/lib -lluajit-5.1 || true; \
		fi && \
		if [ -f librestychash.so ]; then \
			mkdir -p $(shell pwd)/resty && \
			cp librestychash.so $(shell pwd)/resty/ && \
			echo "  ✓ librestychash.so 编译完成并安装到 resty/"; \
		else \
			echo "  ⚠ 警告: librestychash.so 编译失败，可能需要手动编译"; \
		fi && \
		cd - && rm -rf $$TMP_DIR 2>/dev/null || true; \
	fi


.PHONY: install
install:
	$(INSTALL) -d $(INST_OK_PRODIR)/apiok
	$(INSTALL) -d $(INST_OK_PRODIR)/apiok/admin
	$(INSTALL) -d $(INST_OK_PRODIR)/apiok/admin/dao
	$(INSTALL) -d $(INST_OK_PRODIR)/apiok/admin/schema
	$(INSTALL) -d $(INST_OK_PRODIR)/apiok/cmd
	$(INSTALL) -d $(INST_OK_PRODIR)/apiok/cmd/utils
	$(INSTALL) -d $(INST_OK_PRODIR)/apiok/pdk
	$(INSTALL) -d $(INST_OK_PRODIR)/apiok/plugin
	$(INSTALL) -d $(INST_OK_PRODIR)/apiok/plugin/cors
	$(INSTALL) -d $(INST_OK_PRODIR)/apiok/plugin/jwt-auth
	$(INSTALL) -d $(INST_OK_PRODIR)/apiok/plugin/key-auth
	$(INSTALL) -d $(INST_OK_PRODIR)/apiok/plugin/limit-conn
	$(INSTALL) -d $(INST_OK_PRODIR)/apiok/plugin/limit-count
	$(INSTALL) -d $(INST_OK_PRODIR)/apiok/plugin/limit-req
	$(INSTALL) -d $(INST_OK_PRODIR)/apiok/plugin/log-es
	$(INSTALL) -d $(INST_OK_PRODIR)/apiok/plugin/log-http
	$(INSTALL) -d $(INST_OK_PRODIR)/apiok/plugin/log-kafka
	$(INSTALL) -d $(INST_OK_PRODIR)/apiok/plugin/log-mysql
	$(INSTALL) -d $(INST_OK_PRODIR)/apiok/plugin/mock
	$(INSTALL) -d $(INST_OK_PRODIR)/apiok/plugin/prometheus
	$(INSTALL) -d $(INST_OK_PRODIR)/apiok/plugin/request-rewrite
	$(INSTALL) -d $(INST_OK_PRODIR)/apiok/plugin/response-rewrite
	$(INSTALL) -d $(INST_OK_PRODIR)/apiok/plugin/traffic-tag
	$(INSTALL) -d $(INST_OK_PRODIR)/apiok/plugin/waf
	$(INSTALL) -d $(INST_OK_PRODIR)/apiok/sys
	$(INSTALL) -d $(INST_OK_PRODIR)/bin
	$(INSTALL) -d $(INST_OK_PRODIR)/conf
	$(INSTALL) -d $(INST_OK_PRODIR)/conf/cert
	$(INSTALL) -d $(INST_OK_PRODIR)/logs
	$(INSTALL) -d $(INST_OK_PRODIR)/resty
	$(INSTALL) -d $(INST_OK_PRODIR)/deps/share/lua/5.1

	$(INSTALL) apiok/*.lua        			   $(INST_OK_PRODIR)/apiok/
	$(INSTALL) apiok/admin/*.lua  			   $(INST_OK_PRODIR)/apiok/admin/
	$(INSTALL) apiok/admin/dao/*.lua 		   $(INST_OK_PRODIR)/apiok/admin/dao/
	$(INSTALL) apiok/admin/schema/*.lua 	   $(INST_OK_PRODIR)/apiok/admin/schema/
	$(INSTALL) apiok/cmd/*.lua 			   $(INST_OK_PRODIR)/apiok/cmd/
	$(INSTALL) apiok/cmd/utils/*.lua 		   $(INST_OK_PRODIR)/apiok/cmd/utils/
	$(INSTALL) apiok/pdk/*.lua    			   $(INST_OK_PRODIR)/apiok/pdk/
	$(INSTALL) apiok/plugin/*.lua 			   $(INST_OK_PRODIR)/apiok/plugin/
	$(INSTALL) apiok/plugin/cors/*.lua 	   $(INST_OK_PRODIR)/apiok/plugin/cors/
	$(INSTALL) apiok/plugin/jwt-auth/*.lua    $(INST_OK_PRODIR)/apiok/plugin/jwt-auth/
	$(INSTALL) apiok/plugin/key-auth/*.lua    $(INST_OK_PRODIR)/apiok/plugin/key-auth/
	$(INSTALL) apiok/plugin/limit-conn/*.lua  $(INST_OK_PRODIR)/apiok/plugin/limit-conn/
	$(INSTALL) apiok/plugin/limit-count/*.lua $(INST_OK_PRODIR)/apiok/plugin/limit-count/
	$(INSTALL) apiok/plugin/limit-req/*.lua   $(INST_OK_PRODIR)/apiok/plugin/limit-req/
	$(INSTALL) apiok/plugin/log-es/*.lua 	   $(INST_OK_PRODIR)/apiok/plugin/log-es/
	$(INSTALL) apiok/plugin/log-http/*.lua 	   $(INST_OK_PRODIR)/apiok/plugin/log-http/
	$(INSTALL) apiok/plugin/log-kafka/*.lua   $(INST_OK_PRODIR)/apiok/plugin/log-kafka/
	$(INSTALL) apiok/plugin/log-mysql/*.lua   $(INST_OK_PRODIR)/apiok/plugin/log-mysql/
	$(INSTALL) apiok/plugin/mock/*.lua 	   $(INST_OK_PRODIR)/apiok/plugin/mock/
	$(INSTALL) apiok/plugin/prometheus/*.lua   $(INST_OK_PRODIR)/apiok/plugin/prometheus/
	$(INSTALL) apiok/plugin/request-rewrite/*.lua $(INST_OK_PRODIR)/apiok/plugin/request-rewrite/
	$(INSTALL) apiok/plugin/response-rewrite/*.lua $(INST_OK_PRODIR)/apiok/plugin/response-rewrite/
	$(INSTALL) apiok/plugin/traffic-tag/*.lua  $(INST_OK_PRODIR)/apiok/plugin/traffic-tag/
	$(INSTALL) apiok/plugin/waf/*.lua 	   $(INST_OK_PRODIR)/apiok/plugin/waf/
	$(INSTALL) apiok/sys/*.lua    			   $(INST_OK_PRODIR)/apiok/sys/

	$(INSTALL) bin/apiok $(INST_OK_PRODIR)/bin/apiok
ifndef SKIP_SYSTEM_BIN
	$(INSTALL) bin/apiok $(INST_OK_BINDIR)/apiok
endif

	$(INSTALL) conf/mime.types  $(INST_OK_PRODIR)/conf/mime.types
	$(INSTALL) conf/apiok.yaml $(INST_OK_PRODIR)/conf/apiok.yaml
	$(INSTALL) conf/nginx.conf  $(INST_OK_PRODIR)/conf/nginx.conf

	$(INSTALL) conf/cert/apiok.crt $(INST_OK_PRODIR)/conf/cert/apiok.crt
	$(INSTALL) conf/cert/apiok.key $(INST_OK_PRODIR)/conf/cert/apiok.key

	# $(INSTALL) README.md    $(INST_OK_PRODIR)/README.md
	# $(INSTALL) README_CN.md $(INST_OK_PRODIR)/README_CN.md
	# $(INSTALL) COPYRIGHT    $(INST_OK_PRODIR)/COPYRIGHT
	# $(INSTALL) LICENSE      $(INST_OK_PRODIR)/LICENSE
	$(COPY) resty/*       	$(INST_OK_PRODIR)/resty/ 2>/dev/null || true
	# 安装 Penlight 到 deps/share/lua/5.1/pl/ 目录（nginx.conf 中的 lua_package_path 需要）
	$(COPY) resty/pl      	$(INST_OK_PRODIR)/deps/share/lua/5.1/pl 2>/dev/null || true
	$(COPY) sql           	$(INST_OK_PRODIR)/sql/ 2>/dev/null || true
	$(COPY) doc           	$(INST_OK_PRODIR)/doc/ 2>/dev/null || true

.PHONY: install-logrotate
install-logrotate:
	@echo "安装 logrotate 配置..."
	@if [ ! -f conf/apiok-logrotate.conf ]; then \
		echo "错误: conf/apiok-logrotate.conf 不存在"; \
		exit 1; \
	fi
	@if ! command -v logrotate &> /dev/null; then \
		echo "错误: logrotate 未安装"; \
		echo "请先安装 logrotate:"; \
		echo "  Ubuntu/Debian: sudo apt-get install logrotate"; \
		echo "  CentOS/RHEL: sudo yum install logrotate"; \
		exit 1; \
	fi
	@$(INSTALL) -m 644 conf/apiok-logrotate.conf /etc/logrotate.d/apiok
	@echo "✓ logrotate 配置已安装到 /etc/logrotate.d/apiok"
	@echo "测试配置..."
	@logrotate -d /etc/logrotate.d/apiok > /dev/null 2>&1 && \
		echo "✓ logrotate 配置测试通过" || \
		echo "⚠ 警告: logrotate 配置测试失败，请检查配置"

.PHONY: uninstall
uninstall:
	$(REMOVE) $(INST_OK_PRODIR)
	$(REMOVE) $(INST_OK_BINDIR)/apiok
	@if [ -f /etc/logrotate.d/apiok ]; then \
		echo "删除 logrotate 配置..."; \
		$(REMOVE) /etc/logrotate.d/apiok; \
		echo "✓ logrotate 配置已删除"; \
	fi

.PHONY: clean
clean:
	@echo "清理安装目录..."
	@if [ -d "$(INST_OK_PRODIR)" ]; then \
		echo "删除 APIOK 安装目录: $(INST_OK_PRODIR)"; \
		$(REMOVE) $(INST_OK_PRODIR); \
	fi
	@if [ -f "$(INST_OK_BINDIR)/apiok" ]; then \
		echo "删除 APIOK 可执行文件: $(INST_OK_BINDIR)/apiok"; \
		$(REMOVE) $(INST_OK_BINDIR)/apiok; \
	fi
	@echo "清理完成"

.PHONY: clean-all
clean-all: clean
	@echo "清理 OpenResty 安装目录..."
	@if [ -d "$(OPENRESTY_PREFIX)" ]; then \
		echo "删除 OpenResty 安装目录: $(OPENRESTY_PREFIX)"; \
		$(REMOVE) $(OPENRESTY_PREFIX); \
	fi
	@echo "完全清理完成"
