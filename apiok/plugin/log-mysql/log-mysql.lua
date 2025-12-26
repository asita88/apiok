local ngx = ngx
local pdk = require("apiok.pdk")
local json = require("apiok.pdk.json")
local mysql = require("resty.mysql")

local plugin_common = require("apiok.plugin.plugin_common")

local plugin_name = "log-mysql"

local _M = {}

local mysql_pools = {}

local function get_mysql_pool(plugin_config)
    local pool_key = plugin_config.host .. ":" .. plugin_config.port .. ":" .. plugin_config.database
    local pool = mysql_pools[pool_key]
    
    if not pool then
        pool = {
            host = plugin_config.host,
            port = plugin_config.port,
            database = plugin_config.database,
            user = plugin_config.user,
            password = plugin_config.password,
            timeout = plugin_config.timeout or 5000,
            pool_size = plugin_config.pool_size or 100,
        }
        mysql_pools[pool_key] = pool
    end
    
    return pool
end

local function get_mysql_connection(pool)
    local db, err = mysql:new()
    if not db then
        return nil, "failed to instantiate mysql: " .. (err or "unknown")
    end
    
    db:set_timeout(pool.timeout)
    
    local ok, err, errcode, sqlstate = db:connect({
        host = pool.host,
        port = pool.port,
        database = pool.database,
        user = pool.user,
        password = pool.password,
    })
    
    if not ok then
        return nil, "failed to connect: " .. (err or "unknown") .. ", errcode: " .. (errcode or "unknown") .. ", sqlstate: " .. (sqlstate or "unknown")
    end
    
    return db, nil
end

local function should_include_header(header_name, include_headers, exclude_headers)
    if exclude_headers then
        for _, exclude in ipairs(exclude_headers) do
            if string.lower(header_name) == string.lower(exclude) then
                return false
            end
        end
    end
    
    if include_headers and #include_headers > 0 then
        for _, include in ipairs(include_headers) do
            if string.lower(header_name) == string.lower(include) then
                return true
            end
        end
        return false
    end
    
    return true
end

local function filter_headers(headers, include_headers, exclude_headers)
    if not headers then
        return {}
    end
    
    local filtered = {}
    for k, v in pairs(headers) do
        if should_include_header(k, include_headers, exclude_headers) then
            filtered[k] = v
        end
    end
    
    return filtered
end

local function collect_log_data(ok_ctx, plugin_config)
    local matched = ok_ctx.matched or {}
    local ngx_var = ngx.var
    
    local log_data = {
        timestamp = ngx.time(),
        request = {
            method = ngx.req.get_method(),
            uri = matched.uri or ngx_var.request_uri,
            path = matched.path or ngx_var.uri,
            query_string = matched.query_string or ngx_var.query_string or "",
            protocol = ngx_var.server_protocol,
            remote_addr = ngx_var.remote_addr,
            remote_port = ngx_var.remote_port,
            server_addr = ngx_var.server_addr,
            server_port = ngx_var.server_port,
            host = matched.host or ngx_var.host,
            headers = filter_headers(matched.header, plugin_config.include_headers, plugin_config.exclude_headers),
        },
        response = {
            status = ngx.status,
            headers = {},
        },
        upstream = {
            response_time = ngx_var.upstream_response_time or nil,
            connect_time = ngx_var.upstream_connect_time or nil,
        },
        request_time = tonumber(ngx_var.request_time) or 0,
        bytes_sent = tonumber(ngx_var.bytes_sent) or 0,
        block_reason = ok_ctx and ok_ctx.block_reason or nil,
        block_rule = ok_ctx and ok_ctx.block_rule or nil,
    }
    
    if plugin_config.include_request_body and matched.body then
        if type(matched.body) == "string" then
            if #matched.body > 10000 then
                log_data.request.body = string.sub(matched.body, 1, 10000) .. "...(truncated)"
            else
                log_data.request.body = matched.body
            end
        else
            log_data.request.body = json.encode(matched.body)
        end
    end
    
    if plugin_config.include_response_body and ngx.ctx.response_body then
        local response_body = ngx.ctx.response_body
        if type(response_body) == "string" then
            if #response_body > 10000 then
                log_data.response.body = string.sub(response_body, 1, 10000) .. "...(truncated)"
            else
                log_data.response.body = response_body
            end
        else
            log_data.response.body = json.encode(response_body)
        end
    end
    
    local response_headers = {}
    for k, v in pairs(ngx.header) do
        if should_include_header(k, plugin_config.include_headers, plugin_config.exclude_headers) then
            response_headers[k] = v
        end
    end
    log_data.response.headers = response_headers
    
    if matched.args then
        log_data.request.args = matched.args
    end
    
    if ok_ctx.config and ok_ctx.config.service_router then
        local service_router = ok_ctx.config.service_router
        if service_router.service then
            log_data.service = {
                name = service_router.service.name,
            }
        end
        if service_router.router then
            log_data.router = {
                name = service_router.router.name,
            }
        end
    end
    
    return log_data
end

function _M.schema_config(config)
    local plugin_schema_err = plugin_common.plugin_config_schema(plugin_name, config)
    if plugin_schema_err then
        return plugin_schema_err
    end
    return nil
end

function _M.http_body_filter(ok_ctx, plugin_config)
    if not plugin_config.enabled or not plugin_config.include_response_body then
        return
    end
    
    local chunk, eof = ngx.arg[1], ngx.arg[2]
    
    if not ngx.ctx.response_body then
        ngx.ctx.response_body = ""
    end
    
    if chunk and chunk ~= "" then
        ngx.ctx.response_body = ngx.ctx.response_body .. chunk
    end
    
    if eof then
        if #ngx.ctx.response_body > 100000 then
            ngx.ctx.response_body = string.sub(ngx.ctx.response_body, 1, 100000) .. "...(truncated)"
        end
    end
end

local function insert_log_to_mysql(premature, plugin_config, log_data)
    if premature then
        return
    end
    
    pdk.log.info("[log-mysql] connecting to mysql, host: " .. tostring(plugin_config.host) .. ", port: " .. tostring(plugin_config.port) .. ", database: " .. tostring(plugin_config.database) .. ", user: " .. tostring(plugin_config.user))
    
    local pool = get_mysql_pool(plugin_config)
    local db, err = get_mysql_connection(pool)
    
    if not db then
        pdk.log.error("[log-mysql] failed to connect to mysql, host: " .. tostring(plugin_config.host) .. ", port: " .. tostring(plugin_config.port) .. ", database: " .. tostring(plugin_config.database) .. ", user: " .. tostring(plugin_config.user) .. ", err: " .. tostring(err))
        return
    end
    
    local request_headers_json = json.encode(log_data.request.headers) or "{}"
    local response_headers_json = json.encode(log_data.response.headers) or "{}"
    local request_args_json = log_data.request.args and json.encode(log_data.request.args) or "{}"
    local request_body = log_data.request.body or ""
    local response_body = log_data.response.body or ""
    local service_name = log_data.service and log_data.service.name or ""
    local router_name = log_data.router and log_data.router.name or ""
    local upstream_response_time = log_data.upstream.response_time or ""
    local upstream_connect_time = log_data.upstream.connect_time or ""
    
    local block_reason = log_data.block_reason or ""
    local block_rule = log_data.block_rule or ""
    
    local function to_string(value)
        if value == nil then
            return ""
        elseif type(value) == "table" then
            return json.encode(value) or ""
        else
            return tostring(value)
        end
    end
    
    local table_name = "`" .. string.gsub(plugin_config.table_name, "`", "``") .. "`"
    
    local sql = string.format(
        "INSERT INTO %s (timestamp, request_method, request_uri, request_path, request_query_string, request_protocol, " ..
        "remote_addr, remote_port, server_addr, server_port, request_host, request_headers, request_args, request_body, " ..
        "response_status, response_headers, response_body, upstream_response_time, upstream_connect_time, " ..
        "request_time, bytes_sent, service_name, router_name, block_reason, block_rule) VALUES (" ..
        "%d, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %d, %s, %s, %s, %s, %f, %d, %s, %s, %s, %s)",
        table_name,
        log_data.timestamp,
        ngx.quote_sql_str(to_string(log_data.request.method)),
        ngx.quote_sql_str(to_string(log_data.request.uri)),
        ngx.quote_sql_str(to_string(log_data.request.path)),
        ngx.quote_sql_str(to_string(log_data.request.query_string)),
        ngx.quote_sql_str(to_string(log_data.request.protocol)),
        ngx.quote_sql_str(to_string(log_data.request.remote_addr)),
        ngx.quote_sql_str(to_string(log_data.request.remote_port)),
        ngx.quote_sql_str(to_string(log_data.request.server_addr)),
        ngx.quote_sql_str(to_string(log_data.request.server_port)),
        ngx.quote_sql_str(to_string(log_data.request.host)),
        ngx.quote_sql_str(request_headers_json),
        ngx.quote_sql_str(request_args_json),
        ngx.quote_sql_str(to_string(request_body)),
        log_data.response.status,
        ngx.quote_sql_str(response_headers_json),
        ngx.quote_sql_str(to_string(response_body)),
        ngx.quote_sql_str(to_string(upstream_response_time)),
        ngx.quote_sql_str(to_string(upstream_connect_time)),
        log_data.request_time,
        log_data.bytes_sent,
        ngx.quote_sql_str(to_string(service_name)),
        ngx.quote_sql_str(to_string(router_name)),
        ngx.quote_sql_str(to_string(block_reason)),
        ngx.quote_sql_str(to_string(block_rule))
    )
    
    local res, err, errcode, sqlstate = db:query(sql)
    
    db:set_keepalive(10000, pool.pool_size)
    
    if not res then
        pdk.log.error("[log-mysql] failed to insert log: ", err, ", errcode: ", errcode, ", sqlstate: ", sqlstate)
    end
end

function _M.http_log(ok_ctx, plugin_config)
    if not plugin_config.enabled then
        return
    end
    
    local log_data = collect_log_data(ok_ctx, plugin_config)
    
    local ok, err = ngx.timer.at(0, insert_log_to_mysql, plugin_config, log_data)
    if not ok then
        pdk.log.error("[log-mysql] failed to create timer: ", err)
    end
end

return _M

