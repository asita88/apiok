# APIOK

基于 OpenResty 的高性能 API 网关

## 特性

- **高性能**: 基于 OpenResty/Nginx，支持高并发请求处理
- **插件化架构**: 丰富的插件生态，支持自定义扩展
- **多存储引擎**: 支持 Consul 和 MySQL 作为配置存储
- **负载均衡**: 支持轮询和一致性哈希算法
- **健康检查**: 自动检测上游节点健康状态
- **流量打标**: 支持基于标签的智能路由
- **限流保护**: 支持连接数、请求数、请求频率限制
- **认证授权**: 支持 Key Auth 和 JWT 认证
- **日志记录**: 支持 Kafka 和 MySQL 日志输出

## 系统要求

- Linux/Unix 系统
- OpenResty 1.21.4.1+
- MySQL 5.7+ 或 Consul
- GCC 编译环境

## 快速开始

### 安装

```bash
# 克隆仓库
git clone https://github.com/your-org/apiok.git
cd apiok

# 编译安装
make all
```

### 配置

编辑 `conf/apiok.yaml` 配置文件：

```yaml
storage:
  engine: mysql  # 或 consul

mysql:
  host: 127.0.0.1
  port: 3306
  database: apiok
  user: root
  password: your_password

plugins:
  - cors
  - key-auth
  - jwt-auth
  - limit-req
  - traffic-tag
```

### 启动

```bash
# 启动服务
apiok start

# 查看状态
apiok status

# 停止服务
apiok stop

# 重载配置
apiok reload
```

## 核心功能

### 路由管理

支持基于 Host、Path、Method、Header 的路由匹配

### 上游节点

- 支持节点健康检查
- 支持节点标签（tags）
- 支持权重配置
- 自动故障转移

### 流量打标

通过 `traffic-tag` 插件为请求添加标签，实现智能路由：

```json
{
  "match_rules": {
    "path": "^/api/.*",
    "method": ["GET", "POST"],
    "headers": {
      "User-Agent": ".*Chrome.*"
    }
  },
  "tags": {
    "env": "prod",
    "version": "v1"
  }
}
```

标签会添加到请求头中：
- `X-Tags`: JSON 格式的所有标签
- `X-Tag-{key}`: 单个标签值

### 标签路由

上游节点配置标签后，路由转发时会优先选择标签匹配的节点：

```json
{
  "name": "node-1",
  "address": "127.0.0.1",
  "port": 8080,
  "weight": 100,
  "tags": {
    "env": "prod",
    "version": "v1"
  }
}
```

如果请求头中包含匹配的标签，会优先路由到对应节点；如果没有匹配的节点，会自动回退到所有可用节点。

## 插件列表

- **cors**: 跨域资源共享
- **key-auth**: Key 认证
- **jwt-auth**: JWT 认证
- **limit-req**: 请求频率限制
- **limit-conn**: 连接数限制
- **limit-count**: 请求数限制
- **traffic-tag**: 流量打标
- **mock**: Mock 响应
- **log-kafka**: Kafka 日志输出
- **log-mysql**: MySQL 日志输出
- **waf**: Web 应用防火墙

## 开发

### 项目结构

```
apiok/
├── apiok/              # 核心代码
│   ├── admin/          # 管理接口
│   ├── plugin/         # 插件目录
│   ├── sys/            # 系统模块
│   └── pdk/            # 开发工具包
├── bin/                # 可执行文件
├── conf/               # 配置文件
├── resty/              # 第三方库
└── scripts/            # 构建脚本
```

### 自定义插件

创建插件目录和文件：

```lua
-- apiok/plugin/my-plugin/my-plugin.lua
local pdk = require("apiok.pdk")
local plugin_common = require("apiok.plugin.plugin_common")

local plugin_name = "my-plugin"
local _M = {}

function _M.schema_config(config)
    local plugin_schema_err = plugin_common.plugin_config_schema(plugin_name, config)
    if plugin_schema_err then
        return plugin_schema_err
    end
    return nil
end

function _M.http_access(ok_ctx, plugin_config)
    -- 插件逻辑
end

return _M
```

```lua
-- apiok/plugin/my-plugin/schema-my-plugin.lua
local _M = {}

_M.schema = {
    type = "object",
    properties = {
        -- 配置项定义
    }
}

return _M
```

## Docker

```bash
# 构建镜像
docker build -t apiok:latest .

# 运行容器
docker run -d -p 80:80 -p 443:443 apiok:latest
```

## 许可证

查看 [LICENSE](LICENSE) 文件

## 贡献

欢迎提交 Issue 和 Pull Request

