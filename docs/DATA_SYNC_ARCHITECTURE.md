# 数据同步架构文档

## 概述

APIOK API Gateway 采用基于 Hash 变化检测的定时轮询机制，实现配置数据从数据库到各个 Worker 进程的同步。系统通过 **Privileged Agent 进程**定期查询数据库，检测数据变化，并通过 **Worker Events** 机制通知所有 Worker 进程更新数据。

## 版本要求

### OpenResty 版本
- **Privileged Agent 功能**：需要 OpenResty 1.9.3+ 版本支持
- **项目要求**：OpenResty 1.25.3.2+（推荐）
- **说明**：`ngx.process.enable_privileged_agent()` API 在 OpenResty 1.9.3 版本中引入

### 相关 API
- `ngx.process.enable_privileged_agent()` - 启用 Privileged Agent 进程
- `ngx.process.type()` - 获取当前进程类型（"worker"、"privileged agent" 等）

## 架构组件

### 1. 进程角色

#### Privileged Agent 进程
- **职责**：负责数据同步的核心逻辑
- **特点**：
  - 只有一个 Privileged Agent 进程运行
  - 不处理用户请求
  - 专门负责数据同步和协调
- **版本要求**：OpenResty 1.9.3+

#### Worker 进程
- **职责**：处理用户请求，接收数据更新通知
- **特点**：
  - 多个 Worker 进程并行运行
  - 每个进程独立处理请求
  - 通过事件机制接收数据更新

### 2. 数据存储

#### 数据表结构
- **apiok_data**：存储配置数据（services, routers, plugins, upstreams, certificates, upstream_nodes, global_plugins）
- **apiok_sync_hash**：存储同步哈希值，用于检测数据变化

#### Hash 机制
- **key**: `apiok/hash/sync/update`
- **value**: 
  ```lua
  {
    old = "hash_value_old",  -- 上次同步的哈希值
    new = "hash_value_new"   -- 当前数据的哈希值
  }
  ```

## 数据同步流程

### 1. 初始化阶段

```
Worker 进程启动
    ↓
init_worker() 被调用
    ↓
注册事件处理器（Worker 进程）
    ↓
启动定时器（Privileged Agent 进程）
    ↓
执行初始同步 init_sync_resource_data()
```

**关键代码位置**：
- `apiok/sys/router.lua:init_worker()` - Worker 初始化
- `apiok/sys/router.lua:init_sync_resource_data()` - 初始同步

### 2. 定时轮询机制

```
Privileged Agent 进程
    ↓
每 2 秒执行一次 automatic_sync_resource_data()
    ↓
查询 sync_hash 表获取 old_hash 和 new_hash
    ↓
比较 hash 值
    ├─ 相同 → 跳过同步
    └─ 不同 → 执行同步
```

**关键代码位置**：
- `apiok/sys/router.lua:automatic_sync_resource_data()` - 定时轮询函数
- 轮询间隔：2 秒（`ngx_timer_at(2, automatic_sync_resource_data)`）

### 3. 数据同步执行

当检测到数据变化时，执行 `do_sync_resource_data()` 函数：

```
do_sync_resource_data()
    ↓
1. 同步路由数据 (sync_update_router_data)
   ├─ 查询所有 services
   ├─ 查询每个 service 关联的 routers
   └─ 构建 service-router 关系
    ↓
2. 收集依赖资源
   ├─ 收集所有使用的 plugin names
   └─ 收集所有使用的 upstream names
    ↓
3. 同步插件数据 (sync_update_plugin_data)
   └─ 只同步实际使用的插件
    ↓
4. 同步全局插件数据 (sync_update_global_plugin_data)
   └─ 同步所有全局插件
    ↓
5. 同步上游数据 (sync_update_upstream_data)
   └─ 只同步实际使用的上游
    ↓
6. 同步 SSL 证书数据 (sync_update_ssl_data)
   └─ 同步所有证书
    ↓
7. 通过 events.post() 发送事件通知
   ├─ SSL 证书事件
   ├─ 上游事件
   ├─ 插件事件
   ├─ 全局插件事件
   └─ 路由事件
    ↓
8. 更新 sync_hash
   └─ 将 new_hash 赋值给 old_hash
```

**关键代码位置**：
- `apiok/sys/router.lua:do_sync_resource_data()` - 同步执行函数

### 4. 进程间通信

#### 事件发布（Privileged Agent）

```lua
events.post(event_source, event_type, data)
```

**事件类型**：
- `events_source_ssl` / `events_type_put_ssl` - SSL 证书更新
- `events_source_upstream` / `events_type_put_upstream` - 上游更新
- `events_source_plugin` / `events_type_put_plugin` - 插件更新
- `events_source_global_plugin` / `events_type_put_global_plugin` - 全局插件更新
- `events_source_router` / `events_type_put_router` - 路由更新

#### 事件订阅（Worker 进程）

```lua
events.register(handler, event_source, event_type)
```

**事件处理器**：
- `apiok/sys/router.lua:worker_event_router_handler_register()` - 路由事件处理
- `apiok/sys/plugin.lua:worker_event_plugin_handler_register()` - 插件事件处理
- `apiok/sys/plugin.lua:worker_event_global_plugin_handler_register()` - 全局插件事件处理
- `apiok/sys/balancer.lua` - 上游事件处理
- `apiok/sys/certificate.lua` - SSL 证书事件处理

### 5. 数据更新处理

当 Worker 进程接收到事件后：

```
事件到达 Worker 进程
    ↓
调用注册的事件处理器
    ↓
更新内存中的数据对象
    ├─ plugin_objects - 插件对象映射
    ├─ global_plugin_objects - 全局插件对象映射
    ├─ router_objects - 路由对象
    ├─ upstream_objects - 上游对象
    └─ ssl_objects - SSL 证书对象
    ↓
数据立即生效（无需重启）
```

## 数据同步的资源类型

### 1. Services（服务）
- **存储路径**: `apiok/data/services/{service_name}`
- **同步方式**: 通过 `sync_update_router_data()` 间接同步

### 2. Routers（路由）
- **存储路径**: `apiok/data/routers/{router_name}`
- **同步方式**: 通过 `sync_update_router_data()` 同步
- **特点**: 与 Service 关联，按 Service 分组

### 3. Plugins（插件）
- **存储路径**: `apiok/data/plugins/{plugin_name}`
- **同步方式**: 按需同步（只同步路由和服务中使用的插件）
- **优化**: 通过 `service_router_plugin_map` 收集实际使用的插件

### 4. Global Plugins（全局插件）
- **存储路径**: `apiok/data/global_plugins/{plugin_name}`
- **同步方式**: 同步所有全局插件
- **特点**: 独立于路由和服务，全局生效

### 5. Upstreams（上游）
- **存储路径**: `apiok/data/upstreams/{upstream_name}`
- **同步方式**: 按需同步（只同步路由中使用的上游）
- **优化**: 通过 `service_router_upstream_map` 收集实际使用的上游

### 6. Certificates（证书）
- **存储路径**: `apiok/data/certificates/{certificate_name}`
- **同步方式**: 同步所有证书
- **特点**: 用于 SSL/TLS 连接

### 7. Upstream Nodes（上游节点）
- **存储路径**: `apiok/data/upstream_nodes/{node_name}`
- **同步方式**: 通过 Upstream 间接同步

## Hash 变化检测机制

### Hash 生成

```lua
local millisecond = ngx.now()
local hash_key = "apiok/hash/sync/update:" .. millisecond .. random_number
local hash = md5(hash_key)
```

### Hash 更新时机

1. **控制面更新数据时**：
   - 调用 `common.update_sync_data_hash()` 更新 `new_hash`
   - 触发下一次轮询时检测到变化

2. **同步成功后**：
   - 调用 `dao.common.update_sync_data_hash(true)` 将 `new_hash` 赋值给 `old_hash`

### Hash 比较逻辑

```lua
if not sync_data.new or (sync_data.new ~= sync_data.old) then
    -- 数据有变化，执行同步
    do_sync_resource_data()
else
    -- 数据无变化，跳过同步
end
```

## 性能优化

### 1. 按需同步
- **插件**：只同步路由和服务中实际使用的插件
- **上游**：只同步路由中实际使用的上游
- **减少**：不必要的数据查询和传输

### 2. 批量查询
- 使用 `list_keys()` 批量查询同类型数据
- 减少数据库查询次数

### 3. 增量更新
- 通过 Hash 机制避免无变化时的全量同步
- 只在数据变化时执行同步

### 4. 异步处理
- 使用 `ngx.timer.at()` 异步定时器
- 不阻塞 Worker 进程的请求处理

## 错误处理

### 1. 数据库查询失败
- 记录错误日志
- 2 秒后重试

### 2. 事件发送失败

#### 2.1 共享内存不足（"no memory"）
- **原因**：`events.post()` 的数据大小超过共享内存限制
- **限制**：
  - 数据会被序列化为 JSON 存储在共享内存（shm）中
  - 单个事件的数据大小受共享内存配置限制
  - 通常限制在几 MB 到几十 MB（取决于 shm 配置）
- **表现**：
  - `events.post()` 返回 `nil, "no memory"` 错误
  - 日志中会显示 payload size 信息
- **处理**：
  - 记录错误日志（包含 payload size）
  - 返回 `false`，不更新 Hash
  - 下次轮询时重试
- **解决方案**：
  1. **增加共享内存大小**：在 Nginx 配置中增加 `lua_shared_dict` 的大小
     ```nginx
     lua_shared_dict worker_events 100m;  # 增加到 100MB 或更大
     ```
  2. **分批发送**：将大数据拆分成多个小事件分批发送
  3. **优化数据**：只同步必要的数据，减少数据量
  4. **增加重试次数**：配置 `shm_retries` 选项（默认可能不足以处理碎片化）

#### 2.2 其他错误
- 记录错误日志
- 返回 `false`，不更新 Hash
- 下次轮询时重试

### 3. 数据验证失败
- Schema 验证失败的数据会被跳过
- 记录错误日志
- 不影响其他数据的同步

### 4. 大数据处理建议

当配置数据量特别大时（如大量路由、插件、证书），建议：

1. **监控数据大小**：
   - 在 `do_sync_resource_data()` 中记录各类型数据的数量
   - 监控 JSON 序列化后的大小

2. **分批同步**：
   - 将大数据拆分成多个批次
   - 每个批次单独发送事件
   - Worker 进程合并多个批次的数据

3. **增量同步**：
   - 只同步变化的数据，而不是全量数据
   - 通过版本号或时间戳判断变化

4. **共享内存配置**：
   ```nginx
   # 在 nginx.conf 中配置足够大的共享内存
   lua_shared_dict worker_events 200m;  # 根据实际数据量调整
   ```

## 手动触发同步

### API 接口

```
POST /admin/sync/reload
```

**实现**：
```lua
-- apiok/admin/sync.lua
function _M.reload()
    local res, err = common.update_sync_data_hash()
    -- 更新 new_hash，触发下次轮询时同步
end
```

**流程**：
1. 更新 `sync_hash` 的 `new_hash` 值
2. 下次定时轮询时检测到变化
3. 自动执行同步

## 时序图

```
Privileged Agent          Database              Worker 1          Worker 2          Worker N
     |                       |                     |                 |                 |
     |--定时器触发(2秒)------|                     |                 |                 |
     |                       |                     |                 |                 |
     |--查询 sync_hash------>|                     |                 |                 |
     |<--返回 hash 值--------|                     |                 |                 |
     |                       |                     |                 |                 |
     |--比较 hash-----------|                     |                 |                 |
     |  (new != old)        |                     |                 |                 |
     |                       |                     |                 |                 |
     |--查询 services------->|                     |                 |                 |
     |<--返回数据------------|                     |                 |                 |
     |                       |                     |                 |                 |
     |--查询 routers-------->|                     |                 |                 |
     |<--返回数据------------|                     |                 |                 |
     |                       |                     |                 |                 |
     |--查询 plugins-------->|                     |                 |                 |
     |<--返回数据------------|                     |                 |                 |
     |                       |                     |                 |                 |
     |--发送路由事件-------->|                     |                 |                 |
     |                       |                     |<--接收事件------|                 |
     |                       |                     |--更新数据------|                 |
     |                       |                     |                 |<--接收事件------|
     |                       |                     |                 |--更新数据------|
     |                       |                     |                 |                 |
     |--发送插件事件-------->|                     |                 |                 |
     |                       |                     |<--接收事件------|                 |
     |                       |                     |--更新数据------|                 |
     |                       |                     |                 |<--接收事件------|
     |                       |                     |                 |--更新数据------|
     |                       |                     |                 |                 |
     |--更新 old_hash------->|                     |                 |                 |
     |<--确认更新------------|                     |                 |                 |
```

## 关键代码文件

- `apiok/sys/router.lua` - 路由同步和定时轮询逻辑
- `apiok/sys/plugin.lua` - 插件同步和事件处理
- `apiok/sys/balancer.lua` - 上游同步和事件处理
- `apiok/sys/certificate.lua` - SSL 证书同步和事件处理
- `apiok/admin/dao/common.lua` - Hash 管理函数
- `apiok/admin/sync.lua` - 手动触发同步接口
- `resty/worker/events.lua` - Worker Events 实现（第三方库）

## 注意事项

### 共享内存限制

`events.post()` 使用共享内存（shm）存储事件数据，存在以下限制：

1. **数据大小限制**：
   - 数据会被序列化为 JSON 格式存储在 shm 中
   - 单个事件的数据大小不能超过 shm 的可用空间
   - 如果数据太大，会出现 `"no memory"` 错误
   - 日志中会显示 payload size，便于诊断

2. **共享内存配置**：
   ```nginx
   # 在 nginx.conf 中配置足够大的共享内存
   # 根据实际数据量调整大小（建议至少 50MB，大数据场景建议 100MB+）
   lua_shared_dict worker_events 100m;
   ```

3. **监控和诊断**：
   - 当出现 `"no memory"` 错误时，检查日志中的 payload size
   - 监控各类型数据的数量，预估数据大小
   - 如果数据量持续增长，考虑优化数据结构

4. **最佳实践**：
   - **按需同步**：只同步实际使用的数据（已实现）
   - **数据精简**：避免在事件数据中包含冗余信息
   - **分批处理**：对于超大数据集，考虑分批同步策略
   - **增量同步**：只同步变化的数据，而不是全量数据

5. **错误处理**：
   - 当 `events.post()` 返回 `"no memory"` 错误时，系统会：
     - 记录错误日志（包含 payload size）
     - 不更新 Hash，下次轮询时重试
     - 如果持续失败，需要增加 shm 大小或优化数据

## 与其他方案的对比

### Apache APISIX 的数据同步方案

Apache APISIX 采用 **etcd + Watch 机制**实现数据同步，与当前 APISIX 方案的主要区别：

#### APISIX 方案特点

1. **配置中心**：使用 etcd 作为配置存储
2. **事件驱动**：通过 etcd 的 Watch 机制实时监听配置变化
3. **直接读取**：每个 Worker 进程直接从 etcd 读取配置，不通过共享内存传递
4. **实时同步**：配置变更后毫秒级同步，无需轮询

### LMDB 数据同步方案

一些项目使用 **LMDB（Lightning Memory-Mapped Database）** 作为数据同步方案：

#### LMDB 方案特点

1. **内存映射数据库**：
   - LMDB 是高性能的嵌入式键值数据库
   - 使用内存映射（mmap）技术
   - 多个进程可以同时读取同一数据库文件

2. **多进程共享读取**：
   - Worker 进程直接读取 LMDB 文件
   - 操作系统负责内存映射和缓存
   - 无需通过共享内存传递数据

3. **高性能**：
   - 读取性能接近内存速度
   - 支持事务和 ACID 特性
   - 适合读多写少的场景

4. **无大小限制**：
   - 数据库文件大小只受磁盘空间限制
   - 不受共享内存大小限制
   - 可以处理 GB 级别的配置数据

#### LMDB 方案的优势

1. **高性能读取**：
   - 内存映射提供接近内存的读取速度
   - 操作系统自动管理缓存
   - 适合高频读取场景

2. **无数据大小限制**：
   - 数据库文件可以很大（GB 级别）
   - 不受共享内存限制
   - 适合大规模配置数据

3. **简单可靠**：
   - 嵌入式数据库，无需额外服务
   - ACID 事务保证数据一致性
   - 崩溃恢复能力强

4. **多进程安全**：
   - 支持多进程并发读取
   - 写操作通过文件锁保证安全
   - 适合 Nginx Worker 进程模型

#### LMDB 方案的挑战

1. **变化检测**：
   - 需要轮询或文件监控检测变化
   - 或通过版本号/时间戳判断
   - 不如 Watch 机制实时

2. **写操作**：
   - 写操作需要文件锁
   - 多个写操作会串行化
   - 不适合高频写入场景

3. **部署复杂度**：
   - 需要管理数据库文件
   - 需要处理文件权限和路径
   - 需要考虑备份和恢复

#### 对比分析

| 特性 | APIOK（当前方案） | Apache APISIX | LMDB 方案 |
|------|------------------|---------------|-----------|
| **存储** | MySQL/Consul | etcd | LMDB 文件 |
| **同步方式** | 定时轮询 + Hash 检测 | Watch 事件通知 | 轮询/文件监控 |
| **数据传递** | 共享内存（shm） | 直接读取 etcd | 内存映射读取 |
| **数据大小限制** | 受 shm 大小限制 | 无限制（直接读取） | 无限制（文件大小） |
| **实时性** | 2 秒轮询间隔 | 毫秒级 | 取决于轮询间隔 |
| **读取性能** | 中等（需要序列化） | 中等（网络读取） | 高（内存映射） |
| **复杂度** | 中等（需要 Hash 管理） | 低（etcd 原生支持） | 中等（文件管理） |
| **依赖** | 数据库/Consul | etcd | LMDB 库 |
| **适用场景** | 中小规模配置 | 大规模实时配置 | 大规模读多写少 |

#### APISIX 方案的优势

1. **无数据大小限制**：
   - Worker 进程直接从 etcd 读取配置
   - 不通过共享内存传递数据
   - 可以处理任意大小的配置数据

2. **实时性更好**：
   - Watch 机制提供事件通知
   - 配置变更立即触发同步
   - 无需等待轮询间隔

3. **架构更简单**：
   - 无需 Hash 机制检测变化
   - 无需管理共享内存大小
   - etcd 原生支持 Watch

#### APISIX 方案的挑战

1. **etcd 压缩问题**：
   - etcd 定期压缩历史版本
   - 如果 Watch 的版本被压缩，会触发全量同步
   - 需要合理配置压缩策略

2. **频繁更新性能抖动**：
   - 频繁配置更新会导致路由树重建
   - 可能造成性能抖动
   - 需要控制更新频率

#### 改进方向

如果 APIOK 需要处理超大数据量，可以考虑以下改进：

1. **直接读取方案**：
   - Worker 进程直接从数据库读取配置
   - 通过版本号或时间戳判断变化
   - 避免通过共享内存传递大数据

2. **LMDB 方案**：
   - 使用 LMDB 作为配置存储
   - Worker 进程通过内存映射直接读取
   - 无数据大小限制，读取性能高
   - 适合读多写少的场景

3. **分批同步优化**：
   - 将大数据拆分成多个批次
   - 每个批次单独同步
   - Worker 进程合并批次数据

4. **增量同步**：
   - 只同步变化的数据
   - 通过版本号或时间戳判断
   - 减少数据传输量

5. **引入配置中心**：
   - 使用 etcd 或 Consul 的 Watch 机制
   - 实现事件驱动的实时同步
   - 避免共享内存限制

### LMDB + Privileged Agent 混合方案

结合 LMDB 和当前架构的**混合方案**：

#### 方案架构

```
Privileged Agent 进程
    ↓
定时轮询数据库（2秒）
    ↓
检测到数据变化
    ↓
将数据写入 LMDB
    ↓
通过 events.post() 发送通知事件（只传递版本号/时间戳）
    ↓
Worker 进程接收通知
    ↓
Worker 进程从 LMDB 读取最新数据
```

#### 方案特点

1. **Privileged Agent 负责写入**：
   - 只有一个进程写入 LMDB，避免并发写入冲突
   - 写入操作串行化，保证数据一致性
   - 写入频率低（2秒一次），性能影响小

2. **Worker 进程负责读取**：
   - 多个 Worker 进程并发读取 LMDB
   - 通过内存映射，读取性能高
   - 无数据大小限制

3. **轻量级通知**：
   - `events.post()` 只传递版本号或时间戳
   - 数据量小（几字节），不受 shm 限制
   - Worker 进程根据版本号判断是否需要重新读取

#### 方案优势

1. **解决数据大小限制**：
   - 大数据存储在 LMDB 中，不受 shm 限制
   - `events.post()` 只传递轻量级通知
   - 可以处理 GB 级别的配置数据

2. **保持现有架构**：
   - 仍然使用 Privileged Agent 定时轮询
   - 仍然使用 Hash 机制检测变化
   - 仍然使用 Worker Events 通知
   - 最小化架构改动

3. **高性能读取**：
   - Worker 进程通过内存映射读取 LMDB
   - 读取性能接近内存速度
   - 适合高频读取场景

4. **简单可靠**：
   - LMDB 是嵌入式数据库，无需额外服务
   - ACID 事务保证数据一致性
   - 崩溃恢复能力强

#### 实现要点

1. **版本号机制**：
   ```lua
   -- Privileged Agent 写入时
   local version = ngx.now() * 1000  -- 毫秒时间戳作为版本号
   lmdb:put("config_version", version)
   lmdb:put("config_data", json_data)
   
   -- 通知 Worker 进程
   events.post("config_source", "config_updated", {version = version})
   
   -- Worker 进程接收通知
   local current_version = lmdb:get("config_version")
   if current_version > cached_version then
       -- 重新读取配置
       local config = lmdb:get("config_data")
   end
   ```

2. **LMDB 文件位置**：
   - 建议放在共享存储位置（如 `/tmp/apiok_config.lmdb`）
   - 确保所有 Worker 进程可以访问
   - 考虑文件权限和路径配置

3. **错误处理**：
   - LMDB 写入失败时，记录错误日志
   - Worker 进程读取失败时，使用缓存数据
   - 提供降级方案

#### 对比其他方案

| 特性 | 当前方案 | LMDB 混合方案 | etcd Watch |
|------|---------|--------------|------------|
| **数据大小限制** | 受 shm 限制 | 无限制 | 无限制 |
| **通知数据量** | 全量数据 | 版本号（几字节） | 事件数据 |
| **读取性能** | 中等 | 高（内存映射） | 中等（网络） |
| **架构改动** | 无 | 小（添加 LMDB） | 大（引入 etcd） |
| **部署复杂度** | 低 | 中（需要 LMDB） | 高（需要 etcd） |
| **实时性** | 2秒 | 2秒 | 毫秒级 |

#### 适用场景

- **大规模配置数据**：路由、插件、证书数量很多
- **保持现有架构**：不想引入 etcd 等外部服务
- **读多写少**：配置更新频率低，读取频率高
- **性能要求高**：需要快速读取配置数据

### 方案选择建议

| 场景 | 推荐方案 | 理由 |
|------|---------|------|
| **中小规模配置**（< 10MB） | 当前方案（shm） | 简单可靠，无需额外依赖 |
| **大规模配置**（> 100MB） | LMDB 混合方案 | 无大小限制，保持现有架构 |
| **需要实时同步** | etcd/Consul Watch | 事件驱动，毫秒级同步 |
| **读多写少 + 大规模** | LMDB 混合方案 | 内存映射，读取性能最优 |
| **已有 etcd 基础设施** | etcd Watch | 利用现有资源，架构统一 |
| **简单部署** | 当前方案 | 无需额外组件，部署简单 |
| **大规模 + 保持架构** | LMDB 混合方案 | 最小改动，解决大小限制 |

## 总结

APIOK 的数据同步机制具有以下特点：

1. **高效**：通过 Hash 机制避免不必要的同步
2. **可靠**：定时轮询确保数据最终一致性
3. **灵活**：支持手动触发同步
4. **优化**：按需同步，减少资源消耗
5. **实时**：数据更新后 2 秒内生效（最坏情况）
6. **无感**：Worker 进程无需重启，数据热更新

### 适用场景

- **中小规模配置**：路由、插件、上游数量适中
- **MySQL/Consul 存储**：已有数据库基础设施
- **简单架构**：无需引入额外的配置中心组件

### 限制和注意事项

- **数据大小限制**：受共享内存大小限制
- **轮询延迟**：最坏情况 2 秒延迟
- **大数据场景**：需要考虑分批同步或改进方案

