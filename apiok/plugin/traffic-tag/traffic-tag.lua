local pdk = require("apiok.pdk")

local plugin_common = require("apiok.plugin.plugin_common")

local plugin_name = "traffic-tag"

local _M = {}

function _M.schema_config(config)

    local plugin_schema_err = plugin_common.plugin_config_schema(plugin_name, config)

    if plugin_schema_err then
        return plugin_schema_err
    end

    return nil
end

local function match_path(path_pattern, request_path)
    if not path_pattern or path_pattern == "" then
        return true
    end

    local match, err = ngx.re.match(request_path, path_pattern, "jo")
    return match ~= nil
end

local function match_method(method_pattern, request_method)
    if not method_pattern or method_pattern == "" then
        return true
    end

    if type(method_pattern) == "table" then
        for i = 1, #method_pattern do
            if pdk.string.upper(method_pattern[i]) == pdk.string.upper(request_method) then
                return true
            end
        end
        return false
    end

    return pdk.string.upper(method_pattern) == pdk.string.upper(request_method)
end

local function match_header(header_rules, request_headers)
    if not header_rules or not next(header_rules) then
        return true
    end

    for header_key, header_value in pairs(header_rules) do
        local req_header_value = request_headers[header_key]
        if not req_header_value then
            return false
        end

        if header_value ~= "" and req_header_value ~= header_value then
            return false
        end
    end

    return true
end

function _M.http_access(oak_ctx, plugin_config)

    local matched = oak_ctx.matched

    if not matched then
        return
    end

    local request_path = matched.path or ""
    local request_method = pdk.request.get_method()
    local request_headers = pdk.request.header()

    local match_rules = plugin_config.match_rules or {}

    local path_match = match_path(match_rules.path, request_path)
    if not path_match then
        return
    end

    local method_match = match_method(match_rules.method, request_method)
    if not method_match then
        return
    end

    local header_match = match_header(match_rules.headers, request_headers)
    if not header_match then
        return
    end

    local tags = plugin_config.tags or {}
    if next(tags) then
        local tags_json = pdk.json.encode(tags)
        if tags_json then
            pdk.request.add_header("X-Tags", tags_json)
        end

        for tag_key, tag_value in pairs(tags) do
            local header_name = "X-Tag-" .. tag_key
            pdk.request.add_header(header_name, tag_value)
        end
    end

end

return _M

