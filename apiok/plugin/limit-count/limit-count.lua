local ngx = ngx
local pdk = require("apiok.pdk")
local sys = require("apiok.sys")
local limit_count = require("resty.limit.count")
local ngx_var     = ngx.var

local plugin_common = require("apiok.plugin.plugin_common")

local plugin_name = "limit-count"

local _M = {}

function _M.schema_config(config)

    local plugin_schema_err = plugin_common.plugin_config_schema(plugin_name, config)

    if plugin_schema_err then
        return plugin_schema_err
    end

    return nil
end

local function create_limit_object(matched, plugin_config)

    local cache_key = pdk.string.format("%s:ROUTER:%s:%s", plugin_name, matched.host, matched.uri)

    local limit = sys.cache.get(cache_key)

    if not limit then

        local limit_new, err = limit_count.new("plugin_limit_count", plugin_config.count, plugin_config.time_window)

        if not limit_new then
            pdk.log.error("[limit-count] failed to instantiate a resty.limit.count object: ", err)
        else
            sys.cache.set(cache_key, limit_new, 86400)
        end

        limit = limit_new
    end

    return limit

end

function _M.http_access(ok_ctx, plugin_config)

    local matched = ok_ctx.matched

    if not matched.host or not matched.uri then
        pdk.response.exit(500, { message = "[limit-conn] Configuration data format error" }, nil,
                "[limit-count] Configuration data format error", "limit-count")
    end

    local limit = create_limit_object(matched, plugin_config)

    if not limit then
        pdk.response.exit(500, { message = "[limit-count] Failed to instantiate a Limit-Count object" }, nil,
                "[limit-count] Failed to instantiate a Limit-Count object", "limit-count")
    end

    local unique_key = ngx_var.remote_addr

    local delay, err = limit:incoming(unique_key, true)

    if not delay then

        if err == "rejected" then

            pdk.response.set_header("X-RateLimit-Limit", plugin_config.count)
            pdk.response.set_header("X-RateLimit-Remaining", 0)
            pdk.response.exit(503, { message = "[limit-count] Access denied" }, nil,
                    "[limit-count] Access denied", "limit-count")

        end

        pdk.response.exit(500, { message = "[limit-count] Failed to limit request, " .. err }, nil,
                "[limit-count] Failed to limit request, " .. err, "limit-count")
    end

    pdk.response.set_header("X-RateLimit-Limit", plugin_config.count)
    pdk.response.set_header("X-RateLimit-Remaining", err)

end

return _M