local common  = require "apiok/cmd/utils/common"
local io_open = io.open

local lapp = [[
Usage: apiok env
]]

local config

local function get_config()
    local res, err = io.open(common.apiok_home .. "/conf/apiok.yaml", "r")
    if not res then
        print("Config Loading         ...FAIL(" .. err ..")")
        os.exit(1)
    else
        print("Config Loading         ...OK")
    end

    local config_content = res:read("*a")
    res:close()

    local yaml = require("tinyyaml")
    local config_table = yaml.parse(config_content)
    if not config_table or type(config_table) ~= "table" then
        print("Config Parse           ...FAIL")
        os.exit(1)
    else
        print("Config Parse           ...OK")
    end

    return config_table, nil
end

local function validate_storage()
    local res, err = get_config()
    
    -- 检查存储引擎配置
    local storage_conf = res.storage
    local engine = "mysql"  -- 默认使用 mysql
    
    if storage_conf and storage_conf.engine then
        engine = storage_conf.engine
    elseif not storage_conf then
        -- 如果没有配置 storage，检查是否有 mysql 配置
        if res.mysql then
            engine = "mysql"
        elseif res.consul then
            engine = "consul"
        end
    end
    
    print("Storage Engine         ..." .. engine:upper())
    
    if engine == "mysql" then
        -- 验证 MySQL 配置
        if not res.mysql then
            print("Config MySQL           ...FAIL (mysql configuration not found)")
            os.exit(1)
        else
            print("Config MySQL           ...OK")
        end
        
        local mysql_conf = res.mysql
        
        -- 尝试连接 MySQL
        local mysql = require("resty.mysql")
        local db, db_err = mysql:new()
        
        if not db then
            print("MySQL Connect          ...FAIL (" .. (db_err or "unknown") .. ")")
            os.exit(1)
        end
        
        db:set_timeout(1000)
        
        local ok, err, errcode, sqlstate = db:connect({
            host = mysql_conf.host or '127.0.0.1',
            port = mysql_conf.port or 3306,
            database = mysql_conf.database or 'apiok',
            user = mysql_conf.user or 'root',
            password = mysql_conf.password or '',
            charset = "utf8mb4",
        })
        
        if not ok then
            print("MySQL Connect          ...FAIL (" .. (err or "unknown") .. ")")
            os.exit(1)
        else
            print("MySQL Connect          ...OK")
        end
        
        -- 检查表是否存在
        local res_tables, err_tables = db:query("SHOW TABLES LIKE 'apiok_%'")
        if err_tables then
            print("MySQL Tables           ...WARN (" .. err_tables .. ")")
        else
            if res_tables and #res_tables > 0 then
                print("MySQL Tables           ...OK (" .. #res_tables .. " tables found)")
            else
                print("MySQL Tables           ...WARN (no apiok tables found, please run sql/apiok_mysql_init.sql)")
            end
        end
        
        db:set_keepalive(10000, 100)
        
    elseif engine == "consul" then
        -- 验证 Consul 配置
        if not res.consul then
            print("Config Consul          ...FAIL (consul configuration not found)")
            os.exit(1)
        else
            print("Config Consul          ...OK")
        end

        local conf = res.consul

        local resty_consul = require("resty.consul")
        local consul = resty_consul:new({
            host            = conf.host or '127.0.0.1',
            port            = conf.port or 8500,
            connect_timeout = conf.connect_timeout or 60*1000, -- 60s
            read_timeout    = conf.read_timeout or 60*1000, -- 60s
            default_args    = {},
            ssl             = conf.ssl or false,
            ssl_verify      = conf.ssl_verify or true,
            sni_host        = conf.sni_host or nil,
        })

        local agent_config, err = consul:get('/agent/self')

        if not agent_config then
            print("Consul Connect         ...FAIL (".. err ..")")
            os.exit(1)
        else
            print("Consul Connect         ...OK")
        end

        if agent_config.status ~= 200 then
            print("Consul Config          ...FAIL(" .. agent_config.status ..
                    ": " .. string.gsub(agent_config.body, "\n", "") ..")")
            os.exit(1)
        end

        local consul_version_num = tonumber(string.match(agent_config.body.Config.Version, "^%d+%.%d+"))
        if consul_version_num < 1.13 then
            print("Consul Version         ...FAIL (consul version be greater than 1.13)")
            os.exit(1)
        else
            print("Consul Version         ...OK")
        end
    else
        print("Storage Engine         ...FAIL (unsupported engine: " .. engine .. ")")
        os.exit(1)
    end

    config = res
end

local function validate_plugin()

    local plugins = config.plugins

    local err_plugins = {}

    for i = 1, #plugins do

        local file_path = common.apiok_home .. "/apiok/plugin/" .. plugins[i] .. "/" .. plugins[i] .. ".lua"

        local _, err = io_open(file_path, "r")

        if err then
            table.insert(err_plugins, {
                name = plugins[i],
                path = file_path,
                error = err
            })
        end

    end

    if next(err_plugins) then
        print("Plugin Check           ...FAIL")
        for i = 1, #err_plugins do
            local plugin_err = err_plugins[i]
            print("  Plugin: " .. plugin_err.name)
            print("  Path: " .. plugin_err.path)
            print("  Error: " .. plugin_err.error)
        end
        os.exit(1)
    else
        print("Plugin Check           ...OK")
    end
end

local function execute()
    local nginx_path = common.trim(common.execute_cmd("which openresty"))
    if not nginx_path then
        print("OpenResty PATH         ...FAIL(OpenResty not found in system PATH)")
        os.exit(1)
    else
        print("OpenResty PATH         ...OK")
    end


    if ngx.config.nginx_version < 1015008 then
        print("OpenResty Version      ...FAIL(OpenResty version must be greater than 1.15.8)")
        os.exit(1)
    else

        print("OpenResty Version      ...OK")
    end

    validate_storage()

    validate_plugin()
end

return {
    lapp = lapp,
    execute = execute
}