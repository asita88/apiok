local ngx = ngx
local pdk = require("apiok.pdk")
local json = require("apiok.pdk.json")
local http = require("resty.http")

local plugin_common = require("apiok.plugin.plugin_common")

local plugin_name = "log-es"

local _M = {}

local es_buffers = {}

local function get_es_buffer(plugin_config)
    local buffer_key = plugin_config.host .. ":" .. plugin_config.port
    local buffer = es_buffers[buffer_key]
    
    if not buffer then
        buffer = {
            host = plugin_config.host,
            port = plugin_config.port,
            scheme = plugin_config.scheme or "http",
            index_prefix = plugin_config.index_prefix or "apiok",
            index_type = plugin_config.index_type or "logs",
            username = plugin_config.username,
            password = plugin_config.password,
            timeout = plugin_config.timeout or 5000,
            batch_size = plugin_config.batch_size or 100,
            batch_timeout = plugin_config.batch_timeout or 5000,
            logs = {},
            last_flush = ngx.now() * 1000,
        }
        es_buffers[buffer_key] = buffer
    end
    
    return buffer
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
        "@timestamp" = ngx_var.time_iso8601 or os.date("!%Y-%m-%dT%H:%M:%S+00:00", ngx.time()),
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
            addr = ngx_var.upstream_addr or nil,
            status = ngx_var.upstream_status or nil,
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

local function get_index_name(plugin_config)
    local index_prefix = plugin_config.index_prefix or "apiok"
    local date_format = plugin_config.date_format or "%Y.%m.%d"
    local date_str = os.date(date_format)
    return index_prefix .. "-" .. date_str
end

local function flush_es_buffer(premature, buffer)
    if premature then
        return
    end
    
    if #buffer.logs == 0 then
        return
    end
    
    local httpc = http.new()
    httpc:set_timeout(buffer.timeout)
    
    local ok, err = httpc:connect(buffer.host, buffer.port)
    if not ok then
        pdk.log.error("failed to connect to ES, err: [" .. tostring(err) .. "]")
        buffer.logs = {}
        return
    end
    
    if buffer.scheme == "https" then
        local ok, err = httpc:ssl_handshake(false, buffer.host, false)
        if not ok then
            pdk.log.error("failed to SSL handshake, err: [" .. tostring(err) .. "]")
            httpc:close()
            buffer.logs = {}
            return
        end
    end
    
    local bulk_body = ""
    local index_name = get_index_name(buffer)
    for _, log_data in ipairs(buffer.logs) do
        local action = {
            index = {
                _index = index_name,
                _type = buffer.index_type,
            }
        }
        bulk_body = bulk_body .. json.encode(action) .. "\n"
        bulk_body = bulk_body .. json.encode(log_data) .. "\n"
    end
    
    local request_headers = {
        ["Content-Type"] = "application/x-ndjson",
    }
    
    if buffer.username and buffer.password then
        local auth = ngx.encode_base64(buffer.username .. ":" .. buffer.password)
        request_headers["Authorization"] = "Basic " .. auth
    end
    
    local res, err = httpc:request({
        path = "/_bulk",
        method = "POST",
        headers = request_headers,
        body = bulk_body,
    })
    
    if not res then
        pdk.log.error("failed to send request to ES, err: [" .. tostring(err) .. "]")
        httpc:close()
        buffer.logs = {}
        return
    end
    
    local res_body, err = res:read_body()
    if not res_body then
        pdk.log.error("failed to read ES response, err: [" .. tostring(err) .. "]")
        httpc:close()
        buffer.logs = {}
        return
    end
    
    if res.status < 200 or res.status >= 300 then
        pdk.log.error("ES bulk API error, status: [" .. res.status .. "], body: [" .. res_body .. "]")
    end
    
    local keepalive_timeout = buffer.keepalive_timeout or 60000
    local keepalive_pool = buffer.keepalive_pool or 10
    local ok, err = httpc:set_keepalive(keepalive_timeout, keepalive_pool)
    if not ok then
        pdk.log.error("failed to set keepalive, err: [" .. tostring(err) .. "]")
        httpc:close()
    end
    
    buffer.logs = {}
    buffer.last_flush = ngx.now() * 1000
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

function _M.http_log(ok_ctx, plugin_config)
    if not plugin_config.enabled then
        return
    end
    
    local log_data = collect_log_data(ok_ctx, plugin_config)
    
    local buffer = get_es_buffer(plugin_config)
    table.insert(buffer.logs, log_data)
    
    local should_flush = false
    local now = ngx.now() * 1000
    
    if #buffer.logs >= buffer.batch_size then
        should_flush = true
    elseif (now - buffer.last_flush) >= buffer.batch_timeout then
        should_flush = true
    end
    
    if should_flush then
        local ok, err = ngx.timer.at(0, flush_es_buffer, buffer)
        if not ok then
            pdk.log.error("failed to create timer, err: [" .. tostring(err) .. "]")
        end
    end
end

return _M

