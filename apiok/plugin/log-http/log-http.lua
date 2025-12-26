local ngx = ngx
local pdk = require("apiok.pdk")
local json = require("apiok.pdk.json")
local http = require("resty.http")

local plugin_common = require("apiok.plugin.plugin_common")

local plugin_name = "log-http"

local _M = {}

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
            log_data.request.body = matched.body
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
            log_data.response.body = response_body
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

local function send_log_to_http(premature, plugin_config, log_message)
    if premature then
        return
    end
    
    local httpc = http.new()
    httpc:set_timeout(plugin_config.timeout or 5000)
    
    local parsed_uri = httpc:parse_uri(plugin_config.url, false)
    if not parsed_uri then
        pdk.log.error("[log-http] failed to parse URL: ", plugin_config.url)
        return
    end
    
    local scheme, host, port, path, query = unpack(parsed_uri)
    
    local ok, err = httpc:connect(host, port)
    if not ok then
        pdk.log.error("[log-http] failed to connect: ", err)
        return
    end
    
    if scheme == "https" then
        local ok, err = httpc:ssl_handshake(false, host, false)
        if not ok then
            pdk.log.error("[log-http] failed to SSL handshake: ", err)
            httpc:close()
            return
        end
    end
    
    local request_headers = {}
    if plugin_config.headers then
        for k, v in pairs(plugin_config.headers) do
            request_headers[k] = v
        end
    end
    
    if not request_headers["Content-Type"] then
        if plugin_config.log_format == "text" then
            request_headers["Content-Type"] = "text/plain"
        else
            request_headers["Content-Type"] = "application/json"
        end
    end
    
    local res, err = httpc:request({
        path = path,
        query = query,
        method = plugin_config.method or "POST",
        headers = request_headers,
        body = log_message,
    })
    
    if not res then
        pdk.log.error("[log-http] failed to send request: ", err)
        httpc:close()
        return
    end
    
    local res_body, err = res:read_body()
    if not res_body then
        pdk.log.error("[log-http] failed to read response: ", err)
        httpc:close()
        return
    end
    
    if res.status < 200 or res.status >= 300 then
        pdk.log.error("[log-http] HTTP error: ", res.status, ", body: ", res_body)
    end
    
    local keepalive_timeout = plugin_config.keepalive_timeout or 60000
    local keepalive_pool = plugin_config.keepalive_pool or 10
    local ok, err = httpc:set_keepalive(keepalive_timeout, keepalive_pool)
    if not ok then
        pdk.log.error("[log-http] failed to set keepalive: ", err)
        httpc:close()
    end
end

function _M.http_log(ok_ctx, plugin_config)
    if not plugin_config.enabled then
        return
    end
    
    local log_data = collect_log_data(ok_ctx, plugin_config)
    
    local log_message
    if plugin_config.log_format == "text" then
        log_message = string.format(
            "[%s] %s %s %s %s %s %s %s",
            os.date("%Y-%m-%d %H:%M:%S", log_data.timestamp),
            log_data.request.remote_addr,
            log_data.request.method,
            log_data.request.uri,
            log_data.response.status,
            log_data.bytes_sent,
            log_data.request_time,
            log_data.request.host or ""
        )
    else
        log_message = json.encode(log_data)
    end
    
    local ok, err = ngx.timer.at(0, send_log_to_http, plugin_config, log_message)
    if not ok then
        pdk.log.error("[log-http] failed to create timer: ", err)
    end
end

return _M

