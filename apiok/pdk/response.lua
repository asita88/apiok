local ngx = ngx
local type = type
local ngx_say     = ngx.say
local ngx_exit    = ngx.exit
local ngx_header  = ngx.header
local const = require("apiok.pdk.const")
local json  = require("apiok.pdk.json")

local _M = {}

function _M.exit(code, body, content_type, block_reason, block_rule)
    if code and type(code) == "number" then
        ngx.status = code
    else
        code = nil
    end

    local ok_ctx = ngx.ctx.ok_ctx
    
    if not block_reason and ok_ctx and body then
        if type(body) == "table" then
            block_reason = body.message or body.err_message or body.reason or nil
            block_rule = block_rule or body.rule or nil
        elseif type(body) == "string" then
            block_reason = body
        end
    end
    
    if ok_ctx then
        if block_reason then
            ok_ctx.block_reason = block_reason
        end
        if block_rule then
            ok_ctx.block_rule = block_rule
        end
    end
    
    if block_reason then
        ngx.var.block_reason = block_reason
    end
    if block_rule then
        ngx.var.block_rule = block_rule
    end

    if body then
        if type(body) == "table" then
            local res, err = json.encode(body, true)
            if err then
                ngx_header[const.CONTENT_TYPE] = const.CONTENT_TYPE_HTML
                ngx_say(err)
            else
                ngx_header[const.CONTENT_TYPE] = content_type or const.CONTENT_TYPE_JSON
                ngx_say(res)
            end
        else
            ngx_header[const.CONTENT_TYPE] = content_type or const.CONTENT_TYPE_HTML
            ngx_say(body)
        end
    end

    if code then
        ngx_exit(code)
    end
end

function _M.say(code, body)
    if code and type(code) == "number" then
        ngx.status = code
    end
    ngx_header[const.CONTENT_TYPE] = const.CONTENT_TYPE_HTML
    ngx_say(body)
end

function _M.set_header(key, value)
    ngx_header[key] = value
end

return _M
