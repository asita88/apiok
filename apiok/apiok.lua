local ngx    = ngx
local pairs  = pairs
local pdk    = require("apiok.pdk")
local sys    = require("apiok.sys")

local function run_plugin(phase, ok_ctx)
    if ok_ctx == nil or ok_ctx.config == nil then
        return
    end

    local config = ok_ctx.config

    if not config then
        pdk.log.error("run_plugin plugin data not ready!")
        pdk.response.exit(500, { message = "config not ready" })
    end

    local service_router  = config.service_router
    local service_plugins = service_router.plugins
    local router_plugins  = service_router.router.plugins

    local plugin_objects = sys.plugin.plugin_subjects()

    local router_plugin_keys_map = {}

    if #router_plugins > 0 then

        for i = 1, #router_plugins do

            repeat

                if not plugin_objects[router_plugins[i].id] then
                    break
                end

                local router_plugin_object = plugin_objects[router_plugins[i].id]

                router_plugin_keys_map[router_plugin_object.key] = 0

                if not router_plugin_object.handler[phase] then
                    break
                end

                router_plugin_object.handler[phase](ok_ctx, router_plugin_object.config)

            until true
        end

    end

    if #service_plugins > 0 then

        for j = 1, #service_plugins do

            repeat

                if not plugin_objects[service_plugins[j].id] then
                    break
                end

                local service_plugin_object = plugin_objects[service_plugins[j].id]

                if router_plugin_keys_map[service_plugin_object.key] then
                    break
                end

                if not service_plugin_object.handler[phase] then
                    break
                end

                service_plugin_object.handler[phase](ok_ctx, service_plugin_object.config)

            until true
        end

    end

end

local function options_request_handle()
    if pdk.request.get_method() == "OPTIONS" then
        pdk.response.exit(200, {
            err_message = "Welcome to APIOK"
        })
    end
end

local function enable_cors_handle()
    pdk.response.set_header("Access-Control-Allow-Origin", "*")
    pdk.response.set_header("Access-Control-Allow-Credentials", "true")
    pdk.response.set_header("Access-Control-Expose-Headers", "*")
    pdk.response.set_header("Access-Control-Max-Age", "3600")
end

local APIOK = {}

function APIOK.init()
    require("resty.core")
    if require("ffi").os == "Linux" then
        require("ngx.re").opt("jit_stack_size", 200 * 1024)
    end

    require("jit.opt").start("minstitch=2", "maxtrace=4000",
            "maxrecord=8000", "sizemcode=64",
            "maxmcode=4000", "maxirconst=1000")

    local process = require("ngx.process")
    local ok, err = process.enable_privileged_agent()
    if not ok then
        pdk.log.error("failed to enable privileged process, error: ", err)
    end
end

function APIOK.init_worker()

    sys.config.init_worker()

    sys.admin.init_worker()

    sys.dao.init_worker()

    sys.cache.init_worker()

    sys.certificate.init_worker()

    sys.balancer.init_worker()

    sys.healthcheck.init_worker()

    sys.plugin.init_worker()

    sys.router.init_worker()

end

function APIOK.ssl_certificate()

    local ngx_ssl = require("ngx.ssl")
    local server_name = ngx_ssl.server_name()

    local ok_ctx = {
        matched = {
            host = server_name
        }
    }
    sys.certificate.ssl_match(ok_ctx)
end

function APIOK.http_access()

    options_request_handle()

    local ngx_ctx = ngx.ctx
    local ok_ctx = ngx_ctx.ok_ctx
    if not ok_ctx then
        ok_ctx = pdk.pool.fetch("ok_ctx", 0, 64)
        ngx_ctx.ok_ctx = ok_ctx
    end

    sys.router.parameter(ok_ctx)

    local match_succeed = sys.router.router_match(ok_ctx)

    if not match_succeed then
        pdk.response.exit(404, { err_message = "\"URI\" Undefined" })
    end

    -- 动态检查 client_max_body_size
    -- 优先级：路由配置 > 服务配置 > 默认值（0 = 无限制）
    local service_router = ok_ctx.config.service_router
    if service_router then
        local body_size = nil
        
        -- 优先使用路由级别的配置
        if service_router.router and service_router.router.client_max_body_size then
            body_size = service_router.router.client_max_body_size
        -- 其次使用服务级别的配置
        elseif service_router.client_max_body_size then
            body_size = service_router.client_max_body_size
        end
        
        -- 如果配置了 body_size，检查请求体大小
        if body_size then
            -- 解析 body_size（支持数字或字符串，如 "10m", "100k", "1g"）
            local size_limit = nil
            if type(body_size) == "number" then
                size_limit = body_size
            elseif type(body_size) == "string" then
                -- 解析带单位的字符串
                local num, unit = string.match(body_size, "^([%d%.]+)([kmgKMG]?)$")
                if num then
                    num = tonumber(num)
                    if num then
                        unit = string.lower(unit or "")
                        if unit == "k" then
                            size_limit = num * 1024
                        elseif unit == "m" then
                            size_limit = num * 1024 * 1024
                        elseif unit == "g" then
                            size_limit = num * 1024 * 1024 * 1024
                        else
                            size_limit = num
                        end
                    end
                end
            end
            
            -- 检查请求体大小（size_limit > 0 表示有限制）
            if size_limit and size_limit > 0 then
                local headers = ngx.req.get_headers()
                local content_length = headers["content-length"]
                
                if content_length then
                    -- 有 Content-Length 头，直接检查
                    local length = tonumber(content_length)
                    if length and length > size_limit then
                        pdk.log.warn("request body size exceeds limit: [" .. tostring(length) .. "] > [" .. tostring(size_limit) .. "]")
                        pdk.response.exit(413, { err_message = "Request Entity Too Large: body size " .. tostring(length) .. " exceeds limit " .. tostring(size_limit) })
                        return
                    end
                else
                    -- 没有 Content-Length（可能是 chunked encoding），需要读取请求体后检查
                    -- 先尝试读取请求体（如果还没有读取）
                    ngx.req.read_body()
                    local body_data = ngx.req.get_body_data()
                    
                    if body_data then
                        local body_size_actual = #body_data
                        if body_size_actual > size_limit then
                            pdk.log.warn("request body size exceeds limit: [" .. tostring(body_size_actual) .. "] > [" .. tostring(size_limit) .. "]")
                            pdk.response.exit(413, { err_message = "Request Entity Too Large: body size " .. tostring(body_size_actual) .. " exceeds limit " .. tostring(size_limit) })
                            return
                        end
                    end
                end
            end
        end
        
        -- 动态设置 chunked_transfer_encoding（请求）
        -- 优先级：路由配置 > 服务配置 > 默认行为
        local chunked_encoding = nil
        
        -- 优先使用路由级别的配置
        if service_router.router and service_router.router.chunked_transfer_encoding ~= nil then
            chunked_encoding = service_router.router.chunked_transfer_encoding
        -- 其次使用服务级别的配置
        elseif service_router.chunked_transfer_encoding ~= nil then
            chunked_encoding = service_router.chunked_transfer_encoding
        end
        
        -- 如果配置了 chunked_transfer_encoding，设置请求的 Transfer-Encoding
        if chunked_encoding ~= nil then
            -- 保存到 ok_ctx 中，供 header_filter 阶段使用
            ok_ctx.chunked_transfer_encoding = chunked_encoding
            
            if chunked_encoding then
                -- 启用 chunked encoding：设置 Transfer-Encoding 头部
                ngx.req.set_header("Transfer-Encoding", "chunked")
                -- 移除 Content-Length（如果存在），因为 chunked 和 Content-Length 不能同时存在
                ngx.req.clear_header("Content-Length")
            else
                -- 禁用 chunked encoding：移除 Transfer-Encoding 头部
                ngx.req.clear_header("Transfer-Encoding")
            end
        end
    end

    sys.balancer.init_resolver()

    sys.balancer.check_replenish_upstream(ok_ctx)

    local matched  = ok_ctx.matched

    local upstream_uri = matched.uri

    for path_key, path_val in pairs(matched.path) do
        upstream_uri = pdk.string.replace(upstream_uri, "{" .. path_key .. "}", path_val)
    end

    for header_key, header_val in pairs(matched.header) do
        pdk.request.add_header(header_key, header_val)
    end
    
    -- 动态设置 proxy_set_header
    -- 优先级：路由配置 > 服务配置
    -- 合并路由和服务级别的配置（路由配置会覆盖服务配置）
    local service_router = ok_ctx.config.service_router
    if service_router then
        local proxy_headers = {}
        
        -- 先添加服务级别的头部
        if service_router.proxy_set_header and type(service_router.proxy_set_header) == "table" then
            for header_name, header_value in pairs(service_router.proxy_set_header) do
                proxy_headers[header_name] = header_value
            end
        end
        
        -- 再添加路由级别的头部（会覆盖服务级别的同名头部）
        if service_router.router and service_router.router.proxy_set_header and type(service_router.router.proxy_set_header) == "table" then
            for header_name, header_value in pairs(service_router.router.proxy_set_header) do
                proxy_headers[header_name] = header_value
            end
        end
        
        -- 设置所有配置的头部
        for header_name, header_value in pairs(proxy_headers) do
            if header_name and header_value then
                -- 解析 Nginx 变量（如果值以 $ 开头）
                local resolved_value = header_value
                if type(header_value) == "string" and string.sub(header_value, 1, 1) == "$" then
                    -- 提取变量名（去掉 $ 前缀）
                    local var_name = string.sub(header_value, 2)
                    -- 尝试从 ngx.var 获取变量值
                    local var_value = ngx.var[var_name]
                    if var_value then
                        resolved_value = var_value
                    else
                        -- 如果变量不存在，保持原值（让 Nginx 处理）
                        resolved_value = header_value
                    end
                end
                
                -- 设置请求头（这些头部会被传递给上游服务器）
                ngx.req.set_header(header_name, resolved_value)
            end
        end
    end

    local query_args = {}

    for query_key, query_val in pairs(matched.query) do
        if query_val == true then
            query_val = ""
        end
        pdk.table.insert(query_args, query_key .. "=" .. query_val)
    end

    if #query_args > 0 then
        upstream_uri = upstream_uri .. "?" .. pdk.table.concat(query_args, "&")
    end

    pdk.request.set_method(matched.method)

    ngx.var.upstream_uri = upstream_uri

    ngx.var.upstream_host = matched.host
    
    -- 动态设置 proxy_buffering
    -- 优先级：路由配置 > 服务配置 > 默认值（on）
    local service_router = ok_ctx.config.service_router
    if service_router then
        local proxy_buffering = nil
        
        -- 优先使用路由级别的配置
        if service_router.router and service_router.router.proxy_buffering ~= nil then
            proxy_buffering = service_router.router.proxy_buffering
        -- 其次使用服务级别的配置
        elseif service_router.proxy_buffering ~= nil then
            proxy_buffering = service_router.proxy_buffering
        end
        
        -- 如果配置了 proxy_buffering，动态设置
        if proxy_buffering ~= nil then
            if proxy_buffering then
                ngx.var.proxy_buffering_var = "on"
            else
                ngx.var.proxy_buffering_var = "off"
            end
        end
        
        -- 动态设置 proxy_cache
        -- 优先级：路由配置 > 服务配置 > 默认值（禁用）
        local proxy_cache_config = nil
        
        -- 优先使用路由级别的配置
        if service_router.router and service_router.router.proxy_cache then
            proxy_cache_config = service_router.router.proxy_cache
        -- 其次使用服务级别的配置
        elseif service_router.proxy_cache then
            proxy_cache_config = service_router.proxy_cache
        end
        
        -- 如果配置了 proxy_cache，动态设置
        if proxy_cache_config and proxy_cache_config.enabled then
            -- 启用缓存
            ngx.var.proxy_cache_var = "apiok_cache"
            
            -- 设置缓存键（默认：$scheme$proxy_host$request_uri）
            if proxy_cache_config.cache_key and proxy_cache_config.cache_key ~= "" then
                ngx.var.proxy_cache_key_var = proxy_cache_config.cache_key
            else
                ngx.var.proxy_cache_key_var = "$scheme$proxy_host$request_uri"
            end
            
            -- 设置缓存有效期（必须设置，否则缓存不会生效）
            if proxy_cache_config.cache_valid and proxy_cache_config.cache_valid ~= "" then
                ngx.var.proxy_cache_valid_var = proxy_cache_config.cache_valid
            else
                -- 默认缓存有效期：200 302 10m, 404 1m, any 5m
                ngx.var.proxy_cache_valid_var = "200 302 10m 404 1m any 5m"
            end
            
            -- 设置缓存绕过条件（可选）
            if proxy_cache_config.cache_bypass and type(proxy_cache_config.cache_bypass) == "table" and #proxy_cache_config.cache_bypass > 0 then
                ngx.var.proxy_cache_bypass_var = pdk.table.concat(proxy_cache_config.cache_bypass, " ")
            else
                ngx.var.proxy_cache_bypass_var = ""
            end
            
            -- 设置不缓存条件（可选）
            if proxy_cache_config.no_cache and type(proxy_cache_config.no_cache) == "table" and #proxy_cache_config.no_cache > 0 then
                ngx.var.proxy_no_cache_var = pdk.table.concat(proxy_cache_config.no_cache, " ")
            else
                ngx.var.proxy_no_cache_var = ""
            end
        else
            -- 禁用缓存：清空所有缓存相关变量（Nginx 会忽略空的 proxy_cache 变量）
            ngx.var.proxy_cache_var = ""
            ngx.var.proxy_cache_key_var = ""
            ngx.var.proxy_cache_valid_var = ""
            ngx.var.proxy_cache_bypass_var = ""
            ngx.var.proxy_no_cache_var = ""
        end
    end

    run_plugin("http_access", ok_ctx)
end

function APIOK.http_balancer()
    local ok_ctx = ngx.ctx.ok_ctx
    sys.balancer.gogogo(ok_ctx)
end

function APIOK.http_header_filter()
    local ok_ctx = ngx.ctx.ok_ctx
    
    -- 动态设置 chunked_transfer_encoding（响应）
    if ok_ctx and ok_ctx.chunked_transfer_encoding ~= nil then
        local chunked_encoding = ok_ctx.chunked_transfer_encoding
        
        if chunked_encoding then
            -- 启用 chunked encoding：设置 Transfer-Encoding 头部
            ngx.header["Transfer-Encoding"] = "chunked"
            -- 移除 Content-Length（如果存在），因为 chunked 和 Content-Length 不能同时存在
            ngx.header["Content-Length"] = nil
        else
            -- 禁用 chunked encoding：移除 Transfer-Encoding 头部
            ngx.header["Transfer-Encoding"] = nil
            -- Content-Length 应该由上游服务器或 Nginx 自动设置
        end
    end
    
    run_plugin("http_header_filter", ok_ctx)
end

function APIOK.http_body_filter()
    local ok_ctx = ngx.ctx.ok_ctx
    run_plugin("http_body_filter", ok_ctx)
end

function APIOK.http_log()
    local ok_ctx = ngx.ctx.ok_ctx
    run_plugin("http_log", ok_ctx)
    if ok_ctx then
        pdk.pool.release("ok_ctx", ok_ctx)
    end
end

function APIOK.http_admin()

    options_request_handle()

    enable_cors_handle()

    local admin_routers = sys.admin.routers()
    local ok = admin_routers:dispatch(ngx.var.uri, ngx.req.get_method())
    if not ok then
        ngx.exit(404)
    end
end

return APIOK
