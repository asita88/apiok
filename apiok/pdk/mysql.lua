local config = require("apiok.sys.config")
local json = require("apiok.pdk.json")
local log = require("apiok.pdk.log")

local _M = {
    _VERSION = '0.6.0',
    instance = nil,
    pool = nil,
}

local DEFAULT_HOST = "127.0.0.1"
local DEFAULT_PORT = 3306
local DEFAULT_DATABASE = "apiok"
local DEFAULT_USER = "root"
local DEFAULT_PASSWORD = ""
local DEFAULT_POOL_SIZE = 100
local DEFAULT_BACKLOG = 100
local DEFAULT_TIMEOUT = 1000

-- MySQL 表名映射
local TABLE_MAPPING = {
    data = "apiok_data",
    sync_hash = "apiok_sync_hash",
}

local function parse_key(key)
    if not key or type(key) ~= "string" then
        log.error("parse_key: invalid key, type: " .. type(key))
        return nil, nil, nil, "invalid key"
    end
    
    local parts = {}
    for part in string.gmatch(key, "([^/]+)") do
        table.insert(parts, part)
    end
    
    if #parts < 3 then
        log.error("parse_key: invalid key format, key: " .. key .. ", parts: " .. #parts)
        return nil, nil, nil, "invalid key format"
    end
    
    local prefix = parts[1]
    local category = parts[2]
    local type_name = nil
    local name_or_id = nil
    
    if category == "data" then
        if #parts >= 4 then
            type_name = parts[3]
            name_or_id = parts[4]
        elseif #parts >= 3 then
            type_name = parts[3]
            name_or_id = nil
        end
        log.debug("parse_key: key: " .. key .. ", category: data, type: " .. tostring(type_name) .. ", name: " .. tostring(name_or_id))
        return "data", type_name, name_or_id, nil
    elseif category == "hash" then
        if #parts >= 4 then
            type_name = parts[3] .. "/" .. parts[4]
        elseif #parts >= 3 then
            type_name = parts[3]
        end
        log.debug("parse_key: key: " .. key .. ", category: hash, type: " .. tostring(type_name))
        return "hash", type_name, nil, nil
    end
    
    log.error("parse_key: unknown key category, key: " .. key .. ", category: " .. tostring(category))
    return nil, nil, nil, "unknown key category: " .. key
end

function _M.init()
    local mysql_conf, err = config.query("mysql")
    
    if err or not mysql_conf then
        return nil, "mysql configuration not found"
    end
    
    local mysql = require("resty.mysql")
    
    local db_conf = {
        host = mysql_conf.host or DEFAULT_HOST,
        port = mysql_conf.port or DEFAULT_PORT,
        database = mysql_conf.database or DEFAULT_DATABASE,
        user = mysql_conf.user or DEFAULT_USER,
        password = mysql_conf.password or DEFAULT_PASSWORD,
        pool_size = mysql_conf.pool_size or DEFAULT_POOL_SIZE,
        backlog = mysql_conf.backlog or DEFAULT_BACKLOG,
        timeout = mysql_conf.timeout or DEFAULT_TIMEOUT,
    }
    
    _M.pool = db_conf
    _M.instance = mysql
    
    return true, nil
end

-- 获取数据库连接
local function get_db()
    if not _M.instance then
        return nil, "mysql not initialized"
    end
    
    local db, err = _M.instance:new()
    if not db then
        return nil, "failed to create mysql connection: " .. (err or "unknown")
    end
    
    db:set_timeout(_M.pool.timeout)
    
    local ok, err, errcode, sqlstate = db:connect({
        host = _M.pool.host,
        port = _M.pool.port,
        database = _M.pool.database,
        user = _M.pool.user,
        password = _M.pool.password,
        charset = "utf8mb4",
        max_packet_size = 1024 * 1024,
    })
    
    if not ok then
        return nil, "failed to connect mysql: " .. (err or "unknown") .. 
                    ", errcode: " .. (errcode or "unknown") .. 
                    ", sqlstate: " .. (sqlstate or "unknown")
    end
    
    return db, nil
end

function _M:get_key(key)
    local category, type_name, name_or_id, err = parse_key(key)
    if err then
        return nil, err
    end
    
    local db, db_err = get_db()
    if db_err then
        return nil, db_err
    end
    
    local res, sql_err, errcode, sqlstate
    
    if category == "data" then
        if not type_name or not name_or_id then
            db:set_keepalive(10000, _M.pool.pool_size)
            return nil, "invalid key for data category"
        end
        -- 查询数据表，name 字段既可以是 name 也可以是 id（代码中同时写入两个 key）
        local sql = "SELECT data FROM " .. TABLE_MAPPING.data .. 
                    " WHERE type = " .. ngx.quote_sql_str(type_name) .. 
                    " AND name = " .. ngx.quote_sql_str(name_or_id)
        res, sql_err, errcode, sqlstate = db:query(sql)
    elseif category == "hash" then
        -- 查询哈希表
        local sql = "SELECT hash_value FROM " .. TABLE_MAPPING.sync_hash .. 
                    " WHERE hash_key = " .. ngx.quote_sql_str(type_name)
        res, sql_err, errcode, sqlstate = db:query(sql)
    else
        db:set_keepalive(10000, _M.pool.pool_size)
        return nil, "unknown category: " .. category
    end
    
    db:set_keepalive(10000, _M.pool.pool_size)
    
    if sql_err then
        return nil, "mysql query error: " .. sql_err .. 
                    ", errcode: " .. (errcode or "unknown") .. 
                    ", sqlstate: " .. (sqlstate or "unknown")
    end
    
    if not res or #res == 0 then
        return nil, nil
    end
    
    if category == "data" or category == "hash" then
        local value = res[1].data or res[1].hash_value
        if type(value) == "string" then
            return value, nil
        end
        return json.encode(value), nil
    end
    
    return nil, nil
end

function _M:put_key(key, value, args)
    local category, type_name, name_or_id, err = parse_key(key)
    if err then
        return false, err
    end
    
    local db, db_err = get_db()
    if db_err then
        return false, db_err
    end
    
    local value_str
    local value_obj
    if type(value) == "string" then
        value_str = value
        value_obj = json.decode(value)
    else
        value_obj = value
        value_str = json.encode(value)
    end
    
    local res, sql_err, errcode, sqlstate
    
    if category == "data" then
        if not type_name or not name_or_id then
            db:set_keepalive(10000, _M.pool.pool_size)
            return false, "invalid key for data category"
        end
        
        -- INSERT ... ON DUPLICATE KEY UPDATE
        local sql = "INSERT INTO " .. TABLE_MAPPING.data .. 
                    " (type, name, data) VALUES (" ..
                    ngx.quote_sql_str(type_name) .. ", " ..
                    ngx.quote_sql_str(name_or_id) .. ", " ..
                    ngx.quote_sql_str(value_str) .. ") " ..
                    "ON DUPLICATE KEY UPDATE data = VALUES(data), updated_at = NOW()"
        res, sql_err, errcode, sqlstate = db:query(sql)
    elseif category == "hash" then
        -- INSERT ... ON DUPLICATE KEY UPDATE
        local sql = "INSERT INTO " .. TABLE_MAPPING.sync_hash .. 
                    " (hash_key, hash_value) VALUES (" ..
                    ngx.quote_sql_str(type_name) .. ", " ..
                    ngx.quote_sql_str(value_str) .. ") " ..
                    "ON DUPLICATE KEY UPDATE hash_value = VALUES(hash_value), updated_at = NOW()"
        res, sql_err, errcode, sqlstate = db:query(sql)
    else
        db:set_keepalive(10000, _M.pool.pool_size)
        return false, "unknown category: " .. category
    end
    
    db:set_keepalive(10000, _M.pool.pool_size)
    
    if sql_err then
        return false, "mysql query error: " .. sql_err .. 
                     ", errcode: " .. (errcode or "unknown") .. 
                     ", sqlstate: " .. (sqlstate or "unknown")
    end
    
    return true, nil
end

function _M:delete_key(key)
    local category, type_name, name_or_id, err = parse_key(key)
    if err then
        return nil, err
    end
    
    local db, db_err = get_db()
    if db_err then
        return nil, db_err
    end
    
    local res, sql_err, errcode, sqlstate
    
    if category == "data" then
        if not type_name or not name_or_id then
            db:set_keepalive(10000, _M.pool.pool_size)
            return nil, "invalid key for data category"
        end
        -- 删除数据，name 字段既可以是 name 也可以是 id
        local sql = "DELETE FROM " .. TABLE_MAPPING.data .. 
                    " WHERE type = " .. ngx.quote_sql_str(type_name) .. 
                    " AND name = " .. ngx.quote_sql_str(name_or_id)
        res, sql_err, errcode, sqlstate = db:query(sql)
    elseif category == "hash" then
        local sql = "DELETE FROM " .. TABLE_MAPPING.sync_hash .. 
                    " WHERE hash_key = " .. ngx.quote_sql_str(type_name)
        res, sql_err, errcode, sqlstate = db:query(sql)
    else
        db:set_keepalive(10000, _M.pool.pool_size)
        return nil, "unknown category: " .. category
    end
    
    db:set_keepalive(10000, _M.pool.pool_size)
    
    if sql_err then
        return nil, "mysql query error: " .. sql_err .. 
                   ", errcode: " .. (errcode or "unknown") .. 
                   ", sqlstate: " .. (sqlstate or "unknown")
    end
    
    return {}, nil
end

function _M:list_keys(prefix)
    local category, type_name, name_or_id, err = parse_key(prefix)
    if err then
        return nil, err
    end
    
    local db, db_err = get_db()
    if db_err then
        return nil, db_err
    end
    
    local res, sql_err, errcode, sqlstate
    local result_list = {}
    
    if category == "data" then
        if not type_name then
            db:set_keepalive(10000, _M.pool.pool_size)
            return { list = {} }, nil
        end
        -- 查询所有匹配 type 的数据
        local sql = "SELECT data FROM " .. TABLE_MAPPING.data .. 
                    " WHERE type = " .. ngx.quote_sql_str(type_name)
        res, sql_err, errcode, sqlstate = db:query(sql)
        
        if not sql_err and res then
            for i = 1, #res do
                local data = res[i].data
                if data then
                    local decoded = json.decode(data)
                    if decoded then
                        table.insert(result_list, decoded)
                    end
                end
            end
        end
    elseif category == "mapping" then
        -- 映射表通常不需要列表查询
        db:set_keepalive(10000, _M.pool.pool_size)
        return { list = {} }, nil
    else
        db:set_keepalive(10000, _M.pool.pool_size)
        return { list = {} }, nil
    end
    
    db:set_keepalive(10000, _M.pool.pool_size)
    
    if sql_err then
        return nil, "mysql query error: " .. sql_err .. 
                   ", errcode: " .. (errcode or "unknown") .. 
                   ", sqlstate: " .. (sqlstate or "unknown")
    end
    
    return { list = result_list }, nil
end

function _M:txn(payload)
    if not payload or type(payload) ~= "table" or #payload == 0 then
        return nil, "invalid transaction payload"
    end
    
    local db, db_err = get_db()
    if db_err then
        return nil, db_err
    end
    
    -- 开始事务
    local ok, err = db:query("START TRANSACTION")
    if not ok then
        db:set_keepalive(10000, _M.pool.pool_size)
        return nil, "failed to start transaction: " .. (err or "unknown")
    end
    
    local results = {}
    local success = true
    local last_err = nil
    
    for i = 1, #payload do
        local op = payload[i]
        if op.KV then
            local kv = op.KV
            local verb = kv.Verb
            local key = kv.Key
            local value = kv.Value
            
            local category, type_name, name_or_id, parse_err = parse_key(key)
            if parse_err then
                success = false
                last_err = parse_err
                break
            end
            
            if verb == "set" then
                local put_ok, put_err = _M:put_key(key, value)
                if not put_ok then
                    success = false
                    last_err = put_err
                    break
                end
                table.insert(results, { KV = { Key = key, Value = value } })
            elseif verb == "delete" then
                local del_res, del_err = _M:delete_key(key)
                if del_err then
                    success = false
                    last_err = del_err
                    break
                end
                table.insert(results, { KV = { Key = key } })
            end
        end
    end
    
    if success then
        local commit_ok, commit_err = db:query("COMMIT")
        if not commit_ok then
            db:query("ROLLBACK")
            db:set_keepalive(10000, _M.pool.pool_size)
            return nil, "failed to commit transaction: " .. (commit_err or "unknown")
        end
        db:set_keepalive(10000, _M.pool.pool_size)
        return results, nil
    else
        db:query("ROLLBACK")
        db:set_keepalive(10000, _M.pool.pool_size)
        return nil, last_err or "transaction failed"
    end
end

return _M

