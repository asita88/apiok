local config = require("apiok.sys.config")

local _M = {
    _VERSION = '0.6.0',
    instance = nil,
    engine = nil,
}

-- 存储引擎接口定义
-- 所有存储引擎必须实现以下方法：
--   init()           - 初始化存储引擎
--   get_key(key)     - 获取键值，返回 value, err
--   put_key(key, value, args) - 设置键值，返回 result, err
--   delete_key(key)  - 删除键值，返回 result, err
--   list_keys(prefix) - 列出前缀匹配的所有键，返回 {list = {...}}, err
--   txn(payload)     - 执行事务，返回 result, err

function _M.init()
    local storage_conf, err = config.query("storage")
    
    if err or not storage_conf then
        -- 兼容旧配置：如果没有 storage 配置，优先检查 mysql，再检查 consul
        local mysql_conf, mysql_err = config.query("mysql")
        if mysql_conf and not mysql_err then
            _M.engine = "mysql"
            local mysql = require("apiok.pdk.mysql")
            local ok, init_err = mysql.init()
            if ok then
                _M.instance = mysql
                return true, nil
            end
        end
        
        -- 如果 mysql 不可用，尝试使用 consul
        local consul_conf, consul_err = config.query("consul")
        if consul_conf and not consul_err then
            _M.engine = "consul"
            local consul = require("apiok.pdk.consul")
            consul.init()
            _M.instance = consul
            return true, nil
        end
        
        -- 默认使用 mysql
        _M.engine = "mysql"
        local mysql = require("apiok.pdk.mysql")
        local ok, init_err = mysql.init()
        if ok then
            _M.instance = mysql
            return true, nil
        end
        
        return nil, "storage configuration not found and default mysql init failed"
    end
    
    _M.engine = storage_conf.engine or "mysql"
    
    if _M.engine == "mysql" then
        local mysql = require("apiok.pdk.mysql")
        local ok, err = mysql.init()
        if not ok then
            return nil, err
        end
        _M.instance = mysql
    elseif _M.engine == "consul" then
        local consul = require("apiok.pdk.consul")
        consul.init()
        _M.instance = consul
    else
        return nil, "unsupported storage engine: " .. _M.engine
    end
    
    return true, nil
end

-- 统一接口方法，委托给具体存储引擎
function _M.get_key(key)
    if not _M.instance then
        return nil, "storage engine not initialized"
    end
    return _M.instance:get_key(key)
end

function _M.put_key(key, value, args)
    if not _M.instance then
        return nil, "storage engine not initialized"
    end
    return _M.instance:put_key(key, value, args)
end

function _M.delete_key(key)
    if not _M.instance then
        return nil, "storage engine not initialized"
    end
    return _M.instance:delete_key(key)
end

function _M.list_keys(prefix)
    if not _M.instance then
        return nil, "storage engine not initialized"
    end
    return _M.instance:list_keys(prefix)
end

function _M.txn(payload)
    if not _M.instance then
        return nil, "storage engine not initialized"
    end
    return _M.instance:txn(payload)
end

return _M

