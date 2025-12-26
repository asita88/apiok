local ngx = ngx
local pdk = require("apiok.pdk")

local plugin_common = require("apiok.plugin.plugin_common")

local plugin_name = "waf"

local _M = {}

-- 验证插件配置是否符合 schema
-- @param config 插件配置对象
-- @return nil 如果配置有效，否则返回错误信息
function _M.schema_config(config)
    local plugin_schema_err = plugin_common.plugin_config_schema(plugin_name, config)
    if plugin_schema_err then
        return plugin_schema_err
    end
    return nil
end

-- 使用正则表达式匹配文本
-- @param text 要匹配的文本
-- @param patterns 正则表达式模式数组
-- @return boolean 如果匹配成功返回 true，否则返回 false
local function match_pattern(text, patterns)
    if not text or type(text) ~= "string" then
        return false
    end
    
    text = string.lower(text)
    
    for _, pattern in ipairs(patterns) do
        -- ngx.re.find 正则匹配
        -- flags: "joi" = j(使用JIT编译) + o(只编译一次) + i(忽略大小写)
        local m, err = ngx.re.find(text, pattern, "joi")
        if m then
            return true
        end
    end
    
    return false
end

-- 精确匹配文本（用于 HTTP 方法匹配）
-- @param text 要匹配的文本
-- @param patterns 精确匹配的模式数组
-- @return boolean 如果匹配成功返回 true，否则返回 false
local function match_exact(text, patterns)
    if not text or type(text) ~= "string" then
        return false
    end
    
    text = string.upper(text)
    
    for _, pattern in ipairs(patterns) do
        if text == string.upper(pattern) then
            return true
        end
    end
    
    return false
end

-- 检查 IP 是否在列表中（支持通配符）
-- @param ip 要检查的 IP 地址
-- @param list IP 列表，支持通配符（如 192.168.1.*）
-- @return boolean 如果 IP 在列表中返回 true，否则返回 false
local function check_ip_list(ip, list)
    if not list or #list == 0 then
        return false
    end
    
    for _, item in ipairs(list) do
        if ip == item then
            return true
        end
        if string.find(item, "*") then
            -- 将 IP 通配符转换为正则表达式
            -- 例如: 192.168.1.* -> ^192\.168\.1\..*$
            -- 转义点号: . -> \.
            -- 通配符: * -> .*
            local pattern = "^" .. string.gsub(string.gsub(item, "%.", "%%."), "%*", ".*") .. "$"
            if string.match(ip, pattern) then
                return true
            end
        end
    end
    
    return false
end

-- 根据 match_type 获取匹配数据
-- @param ok_ctx 请求上下文对象
-- @param condition 条件配置对象
-- @return table 返回匹配数据的数组
-- 对于 args 和 header，返回 "key=value" 格式
-- 对于 method、uri、body、request_size，返回对应的值
local function get_match_data(ok_ctx, condition)
    local match_type = condition.match_type or "all"
    local matched = ok_ctx.matched
    
    if match_type == "method" then
        return {ngx.req.get_method()}
    elseif match_type == "request_size" then
        return {tonumber(ngx.var.content_length) or 0}
    elseif match_type == "uri" then
        return {matched.uri or ""}
    elseif match_type == "args" then
        local data = {}
        if matched.args and condition.patterns then
            -- patterns 用于匹配参数名（key）
            -- 匹配到的参数会返回 "key=value" 格式
            for _, key_pattern in ipairs(condition.patterns) do
                for k, v in pairs(matched.args) do
                    local key_match = false
                    -- 使用正则匹配参数名
                    -- flags: "joi" = j(使用JIT编译) + o(只编译一次) + i(忽略大小写)
                    local m, err = ngx.re.find(k, key_pattern, "joi")
                    if m then
                        key_match = true
                    end
                    if key_match then
                        if type(v) == "string" then
                            table.insert(data, k .. "=" .. v)
                        elseif type(v) == "table" then
                            for _, vv in ipairs(v) do
                                if type(vv) == "string" then
                                    table.insert(data, k .. "=" .. vv)
                                end
                            end
                        end
                    end
                end
            end
        end
        return data
    elseif match_type == "header" then
        local data = {}
        if matched.header then
            if condition.patterns then
                -- patterns 用于匹配 header 名（key）
                -- 匹配到的 header 会返回 "key=value" 格式
                for _, header_pattern in ipairs(condition.patterns) do
                    for k, v in pairs(matched.header) do
                        local header_match = false
                        -- 使用正则匹配 header 名
                        -- flags: "joi" = j(使用JIT编译) + o(只编译一次) + i(忽略大小写)
                        local m, err = ngx.re.find(k, header_pattern, "joi")
                        if m then
                            header_match = true
                        end
                        if header_match and type(v) == "string" then
                            table.insert(data, k .. "=" .. v)
                        end
                    end
                end
            else
                -- 如果没有 patterns，返回所有 header 的 "key=value" 格式
                for k, v in pairs(matched.header) do
                    if type(v) == "string" then
                        table.insert(data, k .. "=" .. v)
                    end
                end
            end
        end
        return data
    elseif match_type == "body" then
        return {matched.body and type(matched.body) == "string" and matched.body or ""}
    elseif match_type == "all" then
        -- 返回所有匹配数据：uri、args、header、body
        -- args 和 header 返回 "key=value" 格式
        local data = {}
        if matched.uri then
            table.insert(data, matched.uri)
        end
        if matched.args then
            for k, v in pairs(matched.args) do
                if type(v) == "string" then
                    table.insert(data, k .. "=" .. v)
                elseif type(v) == "table" then
                    for _, vv in ipairs(v) do
                        if type(vv) == "string" then
                            table.insert(data, k .. "=" .. vv)
                        end
                    end
                end
            end
        end
        if matched.header then
            for k, v in pairs(matched.header) do
                if type(v) == "string" then
                    table.insert(data, k .. "=" .. v)
                end
            end
        end
        if matched.body and type(matched.body) == "string" then
            table.insert(data, matched.body)
        end
        return data
    end
    
    return {}
end

-- 检查单个条件是否匹配
-- @param ok_ctx 请求上下文对象
-- @param condition 条件配置对象
-- @param remote_addr 客户端 IP 地址（用于日志）
-- @return boolean 如果条件匹配返回 true，否则返回 false
local function check_condition(ok_ctx, condition, remote_addr)
    local match_type = condition.match_type or "all"
    local operator = condition.operator or "match"
    local match_data = get_match_data(ok_ctx, condition)
    
    if not match_data or #match_data == 0 then
        return false
    end
    
    if not condition.patterns or #condition.patterns == 0 then
        return false
    end
    
    -- 遍历匹配数据，检查是否匹配 patterns
    local matched = false
    for _, value in ipairs(match_data) do
        if match_type == "method" then
            -- HTTP 方法使用精确匹配
            if match_exact(value, condition.patterns) then
                matched = true
                break
            end
        else
            -- 其他类型使用正则匹配
            if match_pattern(value, condition.patterns) then
                matched = true
                break
            end
        end
    end
    
    -- 根据操作符返回结果
    if operator == "match" then
        return matched
    elseif operator == "not_match" then
        return not matched
    end
    
    return false
end

-- 检查规则组是否匹配（所有条件都必须满足，AND 关系）
-- @param ok_ctx 请求上下文对象
-- @param rule_group 规则组配置对象
-- @param remote_addr 客户端 IP 地址（用于日志）
-- @return boolean, string, string 如果匹配返回 true、原因和规则名称，否则返回 false、nil、nil
local function check_rule_group(ok_ctx, rule_group, remote_addr)
    if not rule_group.conditions or #rule_group.conditions == 0 then
        return false, nil, nil
    end
    
    -- 所有条件都必须满足（AND 关系）
    for _, condition in ipairs(rule_group.conditions) do
        if not check_condition(ok_ctx, condition, remote_addr) then
            return false, nil, nil
        end
    end
    
    local rule_name = rule_group.name or "unknown"
    pdk.log.warn("[waf] Rule group matched: " .. rule_name .. " from " .. remote_addr)
    
    -- 根据第一个条件的类型生成错误原因
    local reason = rule_name .. " detected"
    if rule_group.conditions[1] then
        local first_condition = rule_group.conditions[1]
        if first_condition.match_type == "method" then
            reason = "Method not allowed"
        elseif first_condition.match_type == "request_size" then
            reason = "Request entity too large"
        end
    end
    
    return true, reason, rule_name
end

-- 检查所有规则组
-- @param ok_ctx 请求上下文对象
-- @param rules_config 规则配置对象
-- @return boolean, string, string 如果有规则匹配且 action 为 block 返回 true、原因和规则名称，否则返回 false、nil、nil
local function check_rules(ok_ctx, rules_config)
    if not rules_config then
        return false, nil, nil
    end
    
    local remote_addr = ngx.var.remote_addr
    
    -- 遍历所有规则组，找到第一个匹配的规则组
    if rules_config.rule_list and #rules_config.rule_list > 0 then
        for _, rule_group in ipairs(rules_config.rule_list) do
            local matched, reason, rule_name = check_rule_group(ok_ctx, rule_group, remote_addr)
            if matched then
                -- 如果 action 是 block，立即返回
                if rule_group.action == "block" then
                    return true, reason, rule_name
                end
                -- 如果 action 是 log，继续检查其他规则组
            end
        end
    end
    
    return false, nil, nil
end

-- HTTP 访问阶段处理函数
-- 执行顺序：1. IP 白名单检查（通过则跳过所有检查） 2. IP 黑名单检查 3. 规则检查
-- @param ok_ctx 请求上下文对象
-- @param plugin_config 插件配置对象
function _M.http_access(ok_ctx, plugin_config)
    if not plugin_config.enabled then
        return
    end
    
    local remote_addr = ngx.var.remote_addr
    
    -- 1. 检查 IP 白名单（如果匹配，跳过所有后续检查）
    if plugin_config.ip_whitelist and plugin_config.ip_whitelist.enabled then
        if check_ip_list(remote_addr, plugin_config.ip_whitelist.ip_list) then
            pdk.log.info("[waf] IP in whitelist, bypass all checks: " .. remote_addr)
            return
        end
    end
    
    -- 2. 检查 IP 黑名单（如果匹配，直接拒绝）
    if plugin_config.ip_blacklist and plugin_config.ip_blacklist.enabled then
        if check_ip_list(remote_addr, plugin_config.ip_blacklist.ip_list) then
            pdk.log.warn("[waf] IP blocked: " .. remote_addr)
            pdk.response.exit(403, { message = "Access denied" }, nil, "Access denied", "ip_blacklist")
        end
    end
    
    -- 3. 检查规则（如果匹配且 action 为 block，根据原因返回相应的 HTTP 状态码）
    if plugin_config.rules then
        local blocked, reason, rule_name = check_rules(ok_ctx, plugin_config.rules)
        if blocked then
            local response_body = { message = reason }
            if reason == "Method not allowed" then
                pdk.response.exit(405, response_body, nil, reason, rule_name)
            elseif reason == "Request entity too large" then
                pdk.response.exit(413, response_body, nil, reason, rule_name)
            else
                pdk.response.exit(403, response_body, nil, reason, rule_name)
            end
        end
    end
end

return _M
