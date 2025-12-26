local ngx = ngx
local pdk = require("apiok.pdk")
local shared = ngx.shared.prometheus_metrics

local plugin_common = require("apiok.plugin.plugin_common")

local plugin_name = "prometheus"

local _M = {}

local function escape_label_value(value)
    local str = tostring(value)
    str = string.gsub(str, '\\', '\\\\')
    str = string.gsub(str, '"', '\\"')
    str = string.gsub(str, '\n', '\\n')
    return str
end

local function get_metric_key(metric_name, labels)
    if not labels or not next(labels) then
        return metric_name
    end
    
    local label_parts = {}
    for k, v in pairs(labels) do
        table.insert(label_parts, k .. '="' .. escape_label_value(v) .. '"')
    end
    
    return metric_name .. "{" .. table.concat(label_parts, ",") .. "}"
end

local function inc_counter(metric_name, value, labels)
    value = value or 1
    local key = get_metric_key(metric_name, labels)
    local newval, err = shared:incr(key, value, 0)
    if err then
        pdk.log.error("metrics: failed to incr counter: " .. tostring(err))
    end
end

local function set_gauge(metric_name, value, labels)
    local key = get_metric_key(metric_name, labels)
    local ok, err = shared:set(key, value)
    if err then
        pdk.log.error("metrics: failed to set gauge: " .. tostring(err))
    end
end

local function get_status_code(status)
    if status >= 100 and status < 200 then
        return "1xx"
    elseif status >= 200 and status < 300 then
        return "2xx"
    elseif status >= 300 and status < 400 then
        return "3xx"
    elseif status >= 400 and status < 500 then
        return "4xx"
    elseif status >= 500 then
        return "5xx"
    else
        return "other"
    end
end

local function collect_request_metrics(ok_ctx)
    if not ok_ctx or not ok_ctx.matched then
        return
    end
    
    local matched = ok_ctx.matched
    local service_router = ok_ctx.config and ok_ctx.config.service_router
    local status = ngx.status
    local request_time = tonumber(ngx.var.request_time) or 0
    local bytes_sent = tonumber(ngx.var.bytes_sent) or 0
    local upstream_response_time = tonumber(ngx.var.upstream_response_time) or 0
    
    local status_code = get_status_code(status)
    
    local labels = {
        host = matched.host or "unknown",
        code = status_code,
    }
    
    inc_counter("apiok_http_requests_total", 1, labels)
    
    set_gauge("apiok_http_request_duration_seconds", request_time, labels)
    
    if upstream_response_time > 0 then
        set_gauge("apiok_upstream_response_time_seconds", upstream_response_time, labels)
    end
    
    set_gauge("apiok_http_response_size_bytes", bytes_sent, labels)
end

local function collect_shared_dict_metrics(dict_name, dict)
    local metrics = {}
    
    local capacity = dict:capacity()
    local free_space = dict:free_space()
    local used_space = capacity - free_space
    
    local keys = dict:get_keys(0)
    local key_count = keys and #keys or 0
    
    table.insert(metrics, {
        name = "apiok_shared_dict_capacity_bytes",
        labels = {dict = dict_name},
        value = capacity
    })
    
    table.insert(metrics, {
        name = "apiok_shared_dict_used_bytes",
        labels = {dict = dict_name},
        value = used_space
    })
    
    table.insert(metrics, {
        name = "apiok_shared_dict_free_bytes",
        labels = {dict = dict_name},
        value = free_space
    })
    
    table.insert(metrics, {
        name = "apiok_shared_dict_keys",
        labels = {dict = dict_name},
        value = key_count
    })
    
    return metrics
end

function _M.schema_config(config)
    local plugin_schema_err = plugin_common.plugin_config_schema(plugin_name, config)
    if plugin_schema_err then
        return plugin_schema_err
    end
    return nil
end

function _M.http_log(ok_ctx, plugin_config)
    if not plugin_config.enabled then
        return
    end
    
    collect_request_metrics(ok_ctx)
end

function _M.export_metrics()
    local metrics = {}
    
    local keys = shared:get_keys(0)
    
    for i = 1, #keys do
        local key = keys[i]
        local value = shared:get(key)
        
        if value then
            local metric_name = key
            local labels_str = ""
            
            local label_start = string.find(key, "{")
            if label_start then
                metric_name = string.sub(key, 1, label_start - 1)
                labels_str = string.sub(key, label_start)
            end
            
            if not string.find(key, "_count") and not string.find(key, "_sum") then
                table.insert(metrics, {
                    name = metric_name,
                    labels = labels_str,
                    value = value
                })
            end
        end
    end
    
    local shared_dicts = {
        prometheus_metrics = ngx.shared.prometheus_metrics,
        plugin_limit_conn = ngx.shared.plugin_limit_conn,
        plugin_limit_req = ngx.shared.plugin_limit_req,
        plugin_limit_count = ngx.shared.plugin_limit_count,
        upstream_health_check = ngx.shared.upstream_health_check,
        upstream_worker_event = ngx.shared.upstream_worker_event,
        worker_events = ngx.shared.worker_events,
    }
    
    for dict_name, dict in pairs(shared_dicts) do
        if dict then
            local dict_metrics = collect_shared_dict_metrics(dict_name, dict)
            for i = 1, #dict_metrics do
                table.insert(metrics, dict_metrics[i])
            end
        end
    end
    
    local output = {}
    
    local metric_map = {}
    for i = 1, #metrics do
        local m = metrics[i]
        local metric_key = m.name
        if m.labels and type(m.labels) == "table" then
            local label_parts = {}
            for k, v in pairs(m.labels) do
                table.insert(label_parts, k .. '="' .. escape_label_value(v) .. '"')
            end
            metric_key = m.name .. "{" .. table.concat(label_parts, ",") .. "}"
        elseif m.labels and type(m.labels) == "string" then
            metric_key = m.name .. m.labels
        end
        
        if not metric_map[m.name] then
            metric_map[m.name] = {}
        end
        table.insert(metric_map[m.name], {
            key = metric_key,
            labels = m.labels,
            value = m.value
        })
    end
    
    local metric_types = {
        ["apiok_http_requests_total"] = "counter",
        ["apiok_http_request_duration_seconds"] = "gauge",
        ["apiok_upstream_response_time_seconds"] = "gauge",
        ["apiok_http_response_size_bytes"] = "gauge",
        ["apiok_shared_dict_capacity_bytes"] = "gauge",
        ["apiok_shared_dict_used_bytes"] = "gauge",
        ["apiok_shared_dict_free_bytes"] = "gauge",
        ["apiok_shared_dict_keys"] = "gauge",
    }
    
    for metric_name, metric_list in pairs(metric_map) do
        local metric_type = metric_types[metric_name] or "gauge"
        table.insert(output, "# TYPE " .. metric_name .. " " .. metric_type)
        for i = 1, #metric_list do
            local m = metric_list[i]
            local line = metric_name
            if m.labels and type(m.labels) == "table" then
                local label_parts = {}
                for k, v in pairs(m.labels) do
                    table.insert(label_parts, k .. '="' .. escape_label_value(v) .. '"')
                end
                line = line .. "{" .. table.concat(label_parts, ",") .. "}"
            elseif m.labels and type(m.labels) == "string" and m.labels ~= "" then
                line = line .. m.labels
            end
            line = line .. " " .. tostring(m.value)
            table.insert(output, line)
        end
        table.insert(output, "")
    end
    
    return table.concat(output, "\n")
end

return _M

