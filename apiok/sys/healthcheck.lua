local ngx           = ngx
local pdk           = require("apiok.pdk")
local dao           = require("apiok.dao")
local schema        = require("apiok.schema")
local healthcheck   = require("resty.healthcheck")
local ngx_timer_at  = ngx.timer.at
local ngx_process   = require("ngx.process")

local _M = {}

-- 健康检测对象缓存
local healthcheckers = {}

-- 默认健康检测配置
local DEFAULT_CHECK_INTERVAL = 1  -- 秒
local DEFAULT_CHECK_TIMEOUT = 1  -- 秒
local DEFAULT_CHECK_SUCCESSES = 2
local DEFAULT_CHECK_FAILURES = 3

-- 初始化健康检测器
local function init_healthchecker(upstream_id, nodes)
    if not upstream_id or not nodes or #nodes == 0 then
        return nil, "invalid upstream_id or nodes"
    end

    -- 如果已经存在，先清理旧的
    if healthcheckers[upstream_id] then
        healthcheckers[upstream_id] = nil
    end

    local checker, err = healthcheck.new({
        name = "upstream_" .. upstream_id,
        shm_name = "upstream_health_check",
        type = "http",
        checks = {
            active = {
                type = "http",
                http_path = "/",
                healthy = {
                    interval = DEFAULT_CHECK_INTERVAL,
                    successes = DEFAULT_CHECK_SUCCESSES,
                },
                unhealthy = {
                    interval = DEFAULT_CHECK_INTERVAL,
                    http_failures = DEFAULT_CHECK_FAILURES,
                    tcp_failures = DEFAULT_CHECK_FAILURES,
                    timeouts = DEFAULT_CHECK_FAILURES,
                },
                timeout = DEFAULT_CHECK_TIMEOUT,
            },
            passive = {
                type = "http",
                healthy = {
                    successes = DEFAULT_CHECK_SUCCESSES,
                },
                unhealthy = {
                    http_failures = DEFAULT_CHECK_FAILURES,
                    tcp_failures = DEFAULT_CHECK_FAILURES,
                    timeouts = DEFAULT_CHECK_FAILURES,
                },
            },
        },
    })

    if err then
        pdk.log.error("healthcheck.new failed: ", err)
        return nil, err
    end

    -- 添加所有节点
    for i = 1, #nodes do
        local node = nodes[i]
        local ok, err = checker:add_target(node.address, node.port, nil)
        if not ok then
            pdk.log.error("checker:add_target failed for ", node.address, ":", node.port, " error: ", err)
        end
    end

    healthcheckers[upstream_id] = checker
    return checker, nil
end

-- 根据节点配置初始化健康检测器
local function init_healthchecker_with_config(upstream_id, nodes, node_configs)
    if not upstream_id or not nodes or #nodes == 0 then
        return nil, "invalid upstream_id or nodes"
    end

    -- 检查是否有节点启用了健康检测
    local has_enabled_check = false
    for i = 1, #node_configs do
        if node_configs[i].check and node_configs[i].check.enabled then
            has_enabled_check = true
            break
        end
    end

    if not has_enabled_check then
        -- 没有启用健康检测，返回 nil
        return nil, nil
    end

    -- 使用第一个节点的配置作为参考（通常同一 upstream 的节点配置相同）
    local check_config = node_configs[1].check
    local check_interval = check_config.interval or DEFAULT_CHECK_INTERVAL
    local check_timeout = check_config.timeout or DEFAULT_CHECK_TIMEOUT

    -- 如果已经存在，先清理旧的
    if healthcheckers[upstream_id] then
        healthcheckers[upstream_id] = nil
    end

    -- 读取健康检测参数
    local healthy_http_statuses = check_config.healthy_http_statuses or {200, 302}
    local healthy_successes = check_config.healthy_successes or DEFAULT_CHECK_SUCCESSES
    local unhealthy_http_statuses = check_config.unhealthy_http_statuses or {429, 404, 500, 501, 502, 503, 504, 505}
    local unhealthy_http_failures = check_config.unhealthy_http_failures or DEFAULT_CHECK_FAILURES
    local unhealthy_tcp_failures = check_config.unhealthy_tcp_failures or DEFAULT_CHECK_FAILURES
    local unhealthy_timeouts = check_config.unhealthy_timeouts or DEFAULT_CHECK_FAILURES

    local checker_config = {
        name = "upstream_" .. upstream_id,
        shm_name = "upstream_health_check",
        type = check_config.tcp and "tcp" or "http",
        checks = {
            active = {
                type = check_config.tcp and "tcp" or "http",
                http_path = check_config.uri or "/",
                http_host = check_config.host or nil,
                healthy = {
                    interval = check_interval,
                    successes = healthy_successes,
                    http_statuses = healthy_http_statuses,
                },
                unhealthy = {
                    interval = check_interval,
                    http_failures = unhealthy_http_failures,
                    tcp_failures = unhealthy_tcp_failures,
                    timeouts = unhealthy_timeouts,
                    http_statuses = unhealthy_http_statuses,
                },
                timeout = check_timeout,
            },
            passive = {
                type = check_config.tcp and "tcp" or "http",
                healthy = {
                    successes = healthy_successes,
                    http_statuses = healthy_http_statuses,
                },
                unhealthy = {
                    http_failures = unhealthy_http_failures,
                    tcp_failures = unhealthy_tcp_failures,
                    timeouts = unhealthy_timeouts,
                    http_statuses = unhealthy_http_statuses,
                },
            },
        },
    }

    -- 如果是 HTTP 健康检测，设置 method
    if not check_config.tcp and check_config.method then
        checker_config.checks.active.http_method = check_config.method
    end

    local checker, err = healthcheck.new(checker_config)

    if err then
        pdk.log.error("healthcheck.new failed: ", err)
        return nil, err
    end

    -- 添加所有节点
    for i = 1, #nodes do
        local node = nodes[i]
        local ok, err = checker:add_target(node.address, node.port, nil)
        if not ok then
            pdk.log.error("checker:add_target failed for ", node.address, ":", node.port, " error: ", err)
        end
    end

    healthcheckers[upstream_id] = checker
    return checker, nil
end

-- 获取健康检测器
function _M.get_checker(upstream_id)
    return healthcheckers[upstream_id]
end

-- 检查节点是否健康
function _M.is_target_healthy(upstream_id, address, port)
    local checker = healthcheckers[upstream_id]
    if not checker then
        -- 如果没有健康检测器，默认认为健康
        return true
    end

    local target = checker:get_target_status(address, port)
    if not target then
        return false
    end

    return target == "healthy"
end

-- 更新健康检测器
function _M.update_checker(upstream_id, nodes, node_configs)
    if not upstream_id or not nodes or #nodes == 0 then
        -- 清理旧的检测器
        if healthcheckers[upstream_id] then
            healthcheckers[upstream_id] = nil
        end
        return
    end

    -- 检查是否有节点启用了健康检测
    local has_enabled_check = false
    if node_configs then
        for i = 1, #node_configs do
            if node_configs[i].check and node_configs[i].check.enabled then
                has_enabled_check = true
                break
            end
        end
    end

    if not has_enabled_check then
        -- 没有启用健康检测，清理旧的检测器
        if healthcheckers[upstream_id] then
            healthcheckers[upstream_id] = nil
        end
        return
    end

    -- 初始化或更新健康检测器
    local checker, err
    if node_configs and #node_configs > 0 then
        checker, err = init_healthchecker_with_config(upstream_id, nodes, node_configs)
    else
        checker, err = init_healthchecker(upstream_id, nodes)
    end

    if err then
        pdk.log.error("update_checker failed for upstream_id: ", upstream_id, " error: ", err)
    end
end

-- 同步更新所有健康检测器
function _M.sync_update_checkers(upstreams_data)
    if not upstreams_data or #upstreams_data == 0 then
        return
    end

    -- 获取所有节点数据
    local node_list, err = dao.common.list_keys(dao.common.PREFIX_MAP.upstream_nodes)
    if err then
        pdk.log.error("sync_update_checkers: get upstream node list FAIL [", err, "]")
        return
    end

    local node_map_by_id = {}
    if node_list and node_list.list and (#node_list.list > 0) then
        for i = 1, #node_list.list do
            local node_data, err = dao.common.get_key(dao.common.PREFIX_MAP.upstream_nodes .. node_list.list[i])
            if not err and node_data then
                local node_obj = pdk.json.decode(node_data)
                if node_obj and node_obj.id then
                    node_map_by_id[node_obj.id] = node_obj
                end
            end
        end
    end

    -- 更新每个 upstream 的健康检测器
    for i = 1, #upstreams_data do
        local upstream = upstreams_data[i]
        if upstream.id and upstream.nodes and #upstream.nodes > 0 then
            -- 获取节点配置（nodes 中已经包含了 id）
            local node_configs = {}
            for j = 1, #upstream.nodes do
                local node_id = upstream.nodes[j].id
                if node_id and node_map_by_id[node_id] then
                    table.insert(node_configs, node_map_by_id[node_id])
                end
            end

            _M.update_checker(upstream.id, upstream.nodes, node_configs)
        end
    end
end

-- 初始化 worker
function _M.init_worker()
    -- 健康检测器会在 balancer 同步数据时自动创建
    -- 这里可以做一些初始化工作
end

return _M

