local ngx = ngx
local pdk = require("apiok.pdk")

local plugin_common = require("apiok.plugin.plugin_common")

local plugin_name = "response-rewrite"

local _M = {}

function _M.schema_config(config)
    local plugin_schema_err = plugin_common.plugin_config_schema(plugin_name, config)

    if plugin_schema_err then
        return plugin_schema_err
    end

    return nil
end

function _M.http_header_filter(ok_ctx, plugin_config)
    if not plugin_config.enabled then
        return
    end

    if plugin_config.headers and next(plugin_config.headers) then
        for header_name, header_value in pairs(plugin_config.headers) do
            if header_value == nil or header_value == "" then
                ngx.header[header_name] = nil
            else
                pdk.response.set_header(header_name, tostring(header_value))
            end
        end
    end

    if plugin_config.status_code and type(plugin_config.status_code) == "number" then
        ngx.status = plugin_config.status_code
    end
end

local function startswith(str, prefix)
    return string.sub(str, 1, #prefix) == prefix
end

local function endswith(str, suffix)
    return #str >= #suffix and string.sub(str, -#suffix) == suffix
end

function _M.http_body_filter(ok_ctx, plugin_config)
    if not plugin_config.enabled then
        return
    end

    if not plugin_config.body_rewrite then
        return
    end

    local chunk, eof = ngx.arg[1], ngx.arg[2]

    if not ngx.ctx.response_body_chunks then
        ngx.ctx.response_body_chunks = {}
    end

    if chunk and chunk ~= "" then
        table.insert(ngx.ctx.response_body_chunks, chunk)
    end

    if not eof then
        ngx.arg[1] = chunk
        return
    end

    local full_body = table.concat(ngx.ctx.response_body_chunks, "")
    local new_body = full_body

    local rewrite_type = plugin_config.body_rewrite.type
    local rewrite_value = plugin_config.body_rewrite.value

    if rewrite_type == "regex" and rewrite_value and rewrite_value.pattern and rewrite_value.replacement then
        local pattern = rewrite_value.pattern
        local replacement = rewrite_value.replacement
        local flags = rewrite_value.flags or "jo"

        local new_body_m, err = ngx.re.gsub(full_body, pattern, replacement, flags)
        if err then
            pdk.log.error("[response-rewrite] regex replace error: " .. tostring(err))
            ngx.arg[1] = full_body
            return
        end
        new_body = new_body_m
    elseif rewrite_type == "replace" and rewrite_value and rewrite_value.from and rewrite_value.to then
        new_body = pdk.string.replace(full_body, rewrite_value.from, rewrite_value.to)
    elseif rewrite_type == "prefix" and rewrite_value then
        if rewrite_value.remove then
            if startswith(full_body, rewrite_value.remove) then
                new_body = string.sub(full_body, #rewrite_value.remove + 1)
            end
        elseif rewrite_value.add then
            new_body = rewrite_value.add .. full_body
        end
    elseif rewrite_type == "suffix" and rewrite_value then
        if rewrite_value.remove then
            if endswith(full_body, rewrite_value.remove) then
                new_body = string.sub(full_body, 1, #full_body - #rewrite_value.remove)
            end
        elseif rewrite_value.add then
            new_body = full_body .. rewrite_value.add
        end
    end

    if new_body ~= full_body then
        pdk.log.info("[response-rewrite] body rewritten, length: " .. #full_body .. " -> " .. #new_body)
    end

    ngx.arg[1] = new_body
    ngx.ctx.response_body_chunks = nil
end

return _M

