local ngx         = ngx
local rand        = math.random
local pdk         = require("apiok.pdk")
local config      = require("apiok.sys.config")
local storage     = require("apiok.pdk.storage")

local _M = {}

_M.APIOK_PREFIX = function()

    -- 兼容旧配置：优先从 storage 配置获取 prefix，如果没有则从 consul 配置获取
    local storage_conf, storage_err = config.query("storage")
    local consul_conf, consul_err = config.query("consul")
    
    if storage_conf and not storage_err and storage_conf.prefix then
        return storage_conf.prefix .. "/"
    end
    
    if consul_conf and not consul_err and consul_conf.prefix then
        return consul_conf.prefix .. "/"
    end

    return "apiok/"
end

_M.DATA_PREFIX   = _M.APIOK_PREFIX() .. "data/"
_M.HASH_PREFIX   = _M.APIOK_PREFIX() .. "system/hash/"

_M.PREFIX_MAP = {
    services       = _M.DATA_PREFIX .. pdk.const.CONSUL_PRFX_SERVICES .. "/",
    routers        = _M.DATA_PREFIX .. pdk.const.CONSUL_PRFX_ROUTERS .. "/",
    plugins        = _M.DATA_PREFIX .. pdk.const.CONSUL_PRFX_PLUGINS .. "/",
    upstreams      = _M.DATA_PREFIX .. pdk.const.CONSUL_PRFX_UPSTREAMS .. "/",
    certificates   = _M.DATA_PREFIX .. pdk.const.CONSUL_PRFX_CERTIFICATES .. "/",
    upstream_nodes = _M.DATA_PREFIX .. pdk.const.CONSUL_PRFX_UPSTREAM_NODES .. "/",
}

_M.HASH_PREFIX_MAP = {
    sync_update = _M.HASH_PREFIX .. "sync/update",
}

function _M.get_key(key)

    local d, err = storage.get_key(key)

    if err then
        return nil, err
    end

    return d, nil
end

function _M.put_key(key, value, args)

    local d, err = storage.put_key(key, value, args)

    if err then
        return false, err
    end

    return d, nil
end

function _M.list_keys(prefix)

    local keys, err = storage.list_keys(prefix)

    if err then
        return nil, err
    end

    return keys, nil
end

function _M.detail_key(key)

    local d, err = _M.get_key(key)

    if err then
        return nil, "failed to get Key-Value detail with key [" .. key .. "], err[" .. tostring(err) .. "]"
    end

    if not d then
        return nil, nil
    end

    return d, nil

end

function _M.batch_check_kv_exists(params, prefix)

    if type(params) ~= "table" then
        return nil, "params format error, err:[table expected, got " .. type(params) .. "]"
    end

    if #params == 0 then
        return nil, "parameter cannot be empty:[" .. pdk.json.encode(params, true) .. "]"
    end

    local exists_data, exists_id_map = {}, {}

    for _, item in ipairs(params) do

        repeat
            if not item.id and not item.name then
                break
            end

            local res, err = _M.check_kv_exists(item, prefix)

            if err then
                return nil, err
            end

            if not res then
                break
            end

            if exists_id_map[res.id] then
                break
            end

            table.insert(exists_data, res)
            exists_id_map[res.id] = 0

        until true
    end

    if next(exists_data) ~= nil then
        return exists_data, nil
    end

    return nil, nil
end

function _M.check_kv_exists(params, prefix)

    if type(params) ~= "table" then
        return nil, "the parameter must be a table:[" .. type(params) .. "][" .. pdk.json.encode(params) .. "]"
    end

    if next(params) == nil then
        return nil, "parameter cannot be empty:[" .. pdk.json.encode(params, true) .. "]"
    end

    if not params.id and not params.name then
        return nil, "the parameter must be one or both of the id and name passed:["
                .. pdk.json.encode(params, true) .. "]"
    end

    if params.id and not params.name then
        -- 直接通过 ID 查询 data 表
        local id_key = _M.PREFIX_MAP[prefix] .. params.id

        local id_res, id_err = _M.get_key(id_key)

        if id_err then
            return nil, "params-id failed to get with id [" .. id_key .. "], err:[" .. tostring(id_err) .. "]"
        end

        if not id_res then
            return nil, nil
        end

        return pdk.json.decode(id_res), nil
    end

    if not params.id and params.name then

        local name_key = _M.PREFIX_MAP[prefix] .. params.name

        local name_res, name_err = _M.get_key(name_key)

        if name_err then
            return nil, "params-name failed to get with name [" .. name_key .. "], err:[" .. tostring(name_err) .. "]"
        end

        if not name_res then
            return nil, nil
        end

        return pdk.json.decode(name_res), nil
    end

    if params.id and params.name then
        -- 通过 ID 和 name 分别查询，验证是否匹配
        local id_key = _M.PREFIX_MAP[prefix] .. params.id
        local name_key = _M.PREFIX_MAP[prefix] .. params.name

        local id_res, id_err = _M.get_key(id_key)

        if id_err then
            return nil, "params-id-name failed to get with id ["
                    .. id_key .. "|" .. name_key .. "], err:[" .. tostring(id_err) .. "]"
        end

        local name_res, name_err = _M.get_key(name_key)

        if name_err then
            return nil, "params-id-name failed to get with name [ "
                    .. id_key .. "|" .. name_key .. "], err:[" .. tostring(name_err) .. "]"
        end

        -- 验证 ID 和 name 是否指向同一个资源
        if not id_res or not name_res then
            return nil, nil
        end

        local id_obj = pdk.json.decode(id_res)
        local name_obj = pdk.json.decode(name_res)

        if not id_obj or not name_obj or id_obj.id ~= name_obj.id or id_obj.name ~= name_obj.name then
            return nil, nil
        end

        return name_obj, nil
    end

    return nil, nil
end

function _M.check_key_exists(name, prefix)

    local key = _M.PREFIX_MAP[prefix] .. name

    local p, err = _M.get_key(key)

    if err then
        return false
    end

    if not p then
        return false
    end

    return true
end


function _M.update_sync_data_hash(init)

    local hash_data, err = _M.get_sync_data()

    if err then
        return false, err
    end

    if not hash_data then
        hash_data = {}
    end

    local key = _M.HASH_PREFIX_MAP[pdk.const.CONSUL_SYNC_UPDATE]
    local millisecond = ngx.now()
    local hash_key = key .. ":" .. millisecond .. rand()
    local hash = pdk.string.md5(hash_key)

    hash_data.new = hash

    if init == true then
        hash_data.old = hash
    end

    local res, err = _M.put_key(key, hash_data)

    if err then
        return false, err
    end

    return res, nil
end

function _M.get_sync_data()

    local key = _M.HASH_PREFIX_MAP[pdk.const.CONSUL_SYNC_UPDATE]

    local hash_data, err = _M.get_key(key)

    if err then
        return nil, err
    end

    if hash_data and (type(hash_data) == "string") then
        return pdk.json.decode(hash_data), nil
    end

    return nil, nil
end

function _M.clear_sync_data()

    local key = _M.HASH_PREFIX_MAP[pdk.const.CONSUL_SYNC_UPDATE]

    local delete, err = storage.delete_key(key)

    if err then
        return nil, err
    end

    return delete, nil
end


return _M