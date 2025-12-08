local config = require("apiok.sys.config")
local resty_consul = require('resty.consul')
local pdk = require("apiok.pdk")

local _M = {
    _VERSION = '0.6.0',
    instance = {},
}

local DEFAULT_HOST            = "127.0.0.1"
local DEFAULT_PORT            = 8500
local DEFAULT_COONECT_TIMEOUT = 60*1000 -- 60s default timeout
local DEFAULT_READ_TIMEOUT    = 60*1000 -- 60s default timeout

function _M.init()

    local conf, err = config.query("consul")

    if err or conf == nil then
        return nil, "consul configuration not found"
    end

    local consul = resty_consul:new({
        host            = conf.host or DEFAULT_HOST,
        port            = conf.port or DEFAULT_PORT,
        connect_timeout = conf.connect_timeout or DEFAULT_COONECT_TIMEOUT, -- 60s
        read_timeout    = conf.read_timeout or DEFAULT_READ_TIMEOUT, -- 60s
        default_args    = {},
        ssl             = conf.ssl or false,
        ssl_verify      = conf.ssl_verify or true,
        sni_host        = conf.sni_host or nil,
    })

    _M.instance = consul
    return true, nil
end

-- 实现统一存储接口
function _M:get_key(key)
    local d, err = self.instance:get_key(key)
    
    if err then
        return nil, err
    end
    
    if type(d.body) ~= "table" then
        return nil, nil
    end
    
    if not d.body[1] or not d.body[1].Value then
        return nil, nil
    end
    
    return d.body[1].Value, nil
end

function _M:put_key(key, value, args)
    local value_str
    if type(value) == "string" then
        value_str = value
    else
        value_str = pdk.json.encode(value)
    end
    
    local d, err = self.instance:put_key(key, value_str, args)
    
    if err then
        return false, err
    end
    
    if d and (d.status == 200) then
        return d.body, nil
    end
    
    return false, ("[" .. (d and d.status or "unknown") .. "]" .. (d and d.reason or "unknown"))
end

function _M:delete_key(key)
    local d, err = self.instance:delete_key(key)
    
    if err then
        return nil, "failed to delete Key-Value with key [" .. key .. "], err[" .. tostring(err) .. "]"
    end
    
    return {}, nil
end

function _M:list_keys(prefix)
    local keys, err = self.instance:list_keys(prefix)
    
    if err then
        return nil, err
    end
    
    local res = {}
    
    if not keys or not keys.body then
        return { list = res }, nil
    end
    
    if type(keys.body) ~= "table" then
        return { list = res }, nil
    end
    
    for i = 1, #keys.body do
        local d, get_err = self:get_key(keys.body[i])
        
        if get_err == nil and d then
            local decoded = pdk.json.decode(d)
            if decoded then
                table.insert(res, decoded)
            end
        end
    end
    
    return { list = res }, nil
end

function _M:txn(payload)
    local res, err = self.instance:txn(payload)
    
    if err then
        return nil, "exec txn error, payload:[" .. pdk.json.encode(payload) .. "], err:[" .. tostring(err) .. "]"
    end
    
    if not res then
        return nil, "exec txn error, payload:[" .. pdk.json.encode(payload) .. "]"
    end
    
    local ret = {}
    
    if type(res.body) ~= "table" or type(res.body.Results) ~= "table" then
        return ret, "exec txn error"
    end
    
    for i = 1, #res.body.Results do
        ret[i] = res.body.Results[i]
    end
    
    return ret, nil
end

return _M