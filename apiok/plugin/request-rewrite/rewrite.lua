local ngx = ngx
local pdk = require("apiok.pdk")

local plugin_common = require("apiok.plugin.plugin_common")

local plugin_name = "request-rewrite"

local _M = {}

function _M.schema_config(config)
    local plugin_schema_err = plugin_common.plugin_config_schema(plugin_name, config)

    if plugin_schema_err then
        return plugin_schema_err
    end

    return nil
end

local function startswith(str, prefix)
    return string.sub(str, 1, #prefix) == prefix
end

local function endswith(str, suffix)
    return #str >= #suffix and string.sub(str, -#suffix) == suffix
end

function _M.http_access(ok_ctx, plugin_config)
    if not plugin_config.enabled then
        return
    end

    local matched = ok_ctx.matched
    if not matched or not matched.uri then
        return
    end

    local original_uri = matched.uri
    local new_uri = original_uri

    if plugin_config.uri_rewrite then
        local rewrite_type = plugin_config.uri_rewrite.type
        local rewrite_value = plugin_config.uri_rewrite.value

        if rewrite_type == "regex" and rewrite_value and rewrite_value.pattern and rewrite_value.replacement then
            local pattern = rewrite_value.pattern
            local replacement = rewrite_value.replacement
            local flags = rewrite_value.flags or "jo"

            local new_uri_m, err = ngx.re.gsub(original_uri, pattern, replacement, flags)
            if err then
                pdk.log.error("[request-rewrite] regex replace error: " .. tostring(err))
                return
            end
            new_uri = new_uri_m
        elseif rewrite_type == "replace" and rewrite_value and rewrite_value.from and rewrite_value.to then
            new_uri = pdk.string.replace(original_uri, rewrite_value.from, rewrite_value.to)
        elseif rewrite_type == "prefix" and rewrite_value then
            if rewrite_value.remove then
                if startswith(original_uri, rewrite_value.remove) then
                    new_uri = string.sub(original_uri, #rewrite_value.remove + 1)
                end
            elseif rewrite_value.add then
                new_uri = rewrite_value.add .. original_uri
            end
        elseif rewrite_type == "suffix" and rewrite_value then
            if rewrite_value.remove then
                if endswith(original_uri, rewrite_value.remove) then
                    new_uri = string.sub(original_uri, 1, #original_uri - #rewrite_value.remove)
                end
            elseif rewrite_value.add then
                new_uri = original_uri .. rewrite_value.add
            end
        end
    end

    if new_uri ~= original_uri then
        matched.uri = new_uri
        local current_upstream_uri = ngx.var.upstream_uri
        if current_upstream_uri then
            local query_start = string.find(current_upstream_uri, "?", 1, true)
            if query_start then
                local query_part = string.sub(current_upstream_uri, query_start)
                ngx.var.upstream_uri = new_uri .. query_part
            else
                ngx.var.upstream_uri = new_uri
            end
        else
            ngx.var.upstream_uri = new_uri
        end
        pdk.log.info("[rewrite] URI rewritten: " .. original_uri .. " -> " .. new_uri)
    end

    if plugin_config.headers and next(plugin_config.headers) then
        for header_name, header_value in pairs(plugin_config.headers) do
            if header_value == nil or header_value == "" then
                ngx.req.clear_header(header_name)
            else
                pdk.request.add_header(header_name, tostring(header_value))
            end
        end
    end

    if plugin_config.query_args and next(plugin_config.query_args) then
        local current_args = ngx.req.get_uri_args()
        for query_name, query_value in pairs(plugin_config.query_args) do
            if query_value == nil or query_value == "" then
                current_args[query_name] = nil
            else
                current_args[query_name] = query_value
            end
        end
        ngx.req.set_uri_args(current_args)
    end
end

return _M

