local pdk    = require("apiok.pdk")
local common = require("apiok.admin.dao.common")
local sys_router = require("apiok.sys.router")
local sys_plugin = require("apiok.sys.plugin")
local sys_balancer = require("apiok.sys.balancer")

local _M = {}

function _M.reload()
    local res, err = common.update_sync_data_hash()

    if err then
        pdk.log.error("sync-reload update_sync_data_hash err: [" .. err .. "]")
        pdk.response.exit(500, { message = "sync reload failed: " .. tostring(err) })
    end

    pdk.response.exit(200, { message = "sync reload success" })
end

function _M.get_router_info()
    local router_data = sys_router.get_router_info()
    
    if not router_data then
        pdk.response.exit(200, { data = {}, message = "no router data loaded" })
        return
    end

    pdk.response.exit(200, { data = router_data })
end

function _M.get_all_config()
    local config = {
        services = {},
        routers = {},
        plugins = {},
        upstreams = {},
        certificates = {},
        upstream_nodes = {},
        global_plugins = {},
    }

    local services_list, err = common.list_keys(common.PREFIX_MAP.services)
    if err then
        pdk.log.error("get_all_config: failed to get services, err: " .. tostring(err))
    elseif services_list and services_list.list then
        config.services = services_list.list
    end

    local routers_list, err = common.list_keys(common.PREFIX_MAP.routers)
    if err then
        pdk.log.error("get_all_config: failed to get routers, err: " .. tostring(err))
    elseif routers_list and routers_list.list then
        config.routers = routers_list.list
    end

    local plugins_list, err = common.list_keys(common.PREFIX_MAP.plugins)
    if err then
        pdk.log.error("get_all_config: failed to get plugins, err: " .. tostring(err))
    elseif plugins_list and plugins_list.list then
        config.plugins = plugins_list.list
    end

    local upstreams_list, err = common.list_keys(common.PREFIX_MAP.upstreams)
    if err then
        pdk.log.error("get_all_config: failed to get upstreams, err: " .. tostring(err))
    elseif upstreams_list and upstreams_list.list then
        config.upstreams = upstreams_list.list
    end

    local certificates_list, err = common.list_keys(common.PREFIX_MAP.certificates)
    if err then
        pdk.log.error("get_all_config: failed to get certificates, err: " .. tostring(err))
    elseif certificates_list and certificates_list.list then
        config.certificates = certificates_list.list
    end

    local upstream_nodes_list, err = common.list_keys(common.PREFIX_MAP.upstream_nodes)
    if err then
        pdk.log.error("get_all_config: failed to get upstream_nodes, err: " .. tostring(err))
    elseif upstream_nodes_list and upstream_nodes_list.list then
        config.upstream_nodes = upstream_nodes_list.list
    end

    local global_plugins_list, err = common.list_keys(common.PREFIX_MAP.global_plugins)
    if err then
        pdk.log.error("get_all_config: failed to get global_plugins, err: " .. tostring(err))
    elseif global_plugins_list and global_plugins_list.list then
        config.global_plugins = global_plugins_list.list
    end

    pdk.response.exit(200, { data = config })
end

function _M.get_active_config()
    local config = {
        routers = {},
        plugins = {},
        global_plugins = {},
        upstreams  = {},
    }

    local router_data = sys_router.get_router_info()
    if router_data then
        config.routers = router_data
    end

    local plugin_objects = sys_plugin.plugin_subjects()
    if plugin_objects then
        local plugins_list = {}
        for name, plugin_obj in pairs(plugin_objects) do
            table.insert(plugins_list, {
                name = name,
                key = plugin_obj.key,
                config = plugin_obj.config,
            })
        end
        config.plugins = plugins_list
    end

    local global_plugin_objects = sys_plugin.global_plugin_subjects()
    if global_plugin_objects then
        local global_plugins_list = {}
        for name, plugin_obj in pairs(global_plugin_objects) do
            table.insert(global_plugins_list, {
                name = name,
                key = plugin_obj.key,
                config = plugin_obj.config,
            })
        end
        config.global_plugins = global_plugins_list
    end

    local upstream_data = sys_balancer.get_upstream_info()
    if upstream_data then
        config.upstreams = upstream_data
    end

    pdk.response.exit(200, { data = config })
end

return _M

