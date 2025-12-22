local ngx    = ngx
local pairs  = pairs
local pdk    = require("apiok.pdk")
local dao    = require("apiok.dao")
local events = require("resty.worker.events")
local schema = require("apiok.schema")
local okrouting           = require("apiok.sys.routing")
local sys_certificate     = require("apiok.sys.certificate")
local sys_balancer        = require("apiok.sys.balancer")
local sys_plugin          = require("apiok.sys.plugin")
local ngx_process         = require("ngx.process")
local ngx_sleep           = ngx.sleep
local ngx_timer_at        = ngx.timer.at
local ngx_worker_exiting  = ngx.worker.exiting
local xpcall              = xpcall
local debug_traceback     = debug.traceback

local router_objects
local current_router_data

local events_source_router     = "events_source_router"
local events_type_put_router   = "events_type_put_router"

local _M = {}

local function router_map_service()
    pdk.log.info("router_map_service: start")

    local list, err = dao.common.list_keys(dao.common.PREFIX_MAP.routers)

    if err then
        pdk.log.error("router_map_service: get router list FAIL [" .. tostring(err) .. "]")
        return nil
    end

    if not list or not list.list or (#list.list == 0) then
        pdk.log.warn("router_map_service: router list is empty, list: [" .. pdk.json.encode(list, true) .. "]")
        return nil
    end

    pdk.log.info("router_map_service: got router list, count: [" .. #list.list .. "]")

    local router_map_service = {}
    local schema_failed_count = 0
    local disabled_count = 0
    local no_service_name_count = 0
    local success_count = 0

    for i = 1, #list.list do

        repeat
            local _, err = pdk.schema.check(schema.router.router_data, list.list[i])

            if err then
                schema_failed_count = schema_failed_count + 1
                pdk.log.error("router_map_service: router schema check err:["
                                      .. err .. "][" .. tostring(list.list[i].name) .. "]")
                break
            end

            if list.list[i].enabled == false then
                disabled_count = disabled_count + 1
                pdk.log.info("router_map_service: router disabled, skip: [" .. tostring(list.list[i].name) .. "]")
                break
            end

            if not list.list[i].service then
                no_service_name_count = no_service_name_count + 1
                pdk.log.warn("router_map_service: router missing service field, skip: [" .. tostring(list.list[i].name) .. "], router data: [" .. pdk.json.encode(list.list[i], true) .. "]")
                break
            end

            if not list.list[i].service.name then
                no_service_name_count = no_service_name_count + 1
                pdk.log.warn("router_map_service: router missing service.name, skip: [" .. tostring(list.list[i].name) .. "], service: [" .. pdk.json.encode(list.list[i].service, true) .. "]")
                break
            end

            local service_key = list.list[i].service.name

            if not router_map_service[service_key] then
                router_map_service[service_key] = {}
            end

            success_count = success_count + 1
            table.insert(router_map_service[service_key], {
                paths    = list.list[i].paths,
                methods  = pdk.const.DEFAULT_METHODS(list.list[i].methods),
                headers  = list.list[i].headers,
                upstream = list.list[i].upstream,
                plugins  = list.list[i].plugins,
                client_max_body_size = list.list[i].client_max_body_size,
                chunked_transfer_encoding = list.list[i].chunked_transfer_encoding,
                proxy_buffering = list.list[i].proxy_buffering,
                proxy_cache = list.list[i].proxy_cache,
                proxy_set_header = list.list[i].proxy_set_header,
            })
        until true

    end

    pdk.log.info("router_map_service: success_count: [" .. success_count .. "], schema_failed: [" .. schema_failed_count .. "], disabled: [" .. disabled_count .. "], no_service_name: [" .. no_service_name_count .. "]")

    if next(router_map_service) then
        local service_count = 0
        for _ in pairs(router_map_service) do
            service_count = service_count + 1
        end
        pdk.log.info("router_map_service: router_map_service created, service_count: [" .. service_count .. "]")
        return router_map_service
    end

    pdk.log.warn("router_map_service: router_map_service is empty")
    return nil
end

local function sync_update_router_data()
    pdk.log.info("sync_update_router_data: start")

    local list, err = dao.common.list_keys(dao.common.PREFIX_MAP.services)

    if err then
        pdk.log.error("sync_update_router_data: get service list FAIL [" .. tostring(err) .. "]")
        return nil
    end

    if not list or not list.list or (#list.list == 0) then
        pdk.log.warn("sync_update_router_data: service list is empty, list: [" .. pdk.json.encode(list, true) .. "]")
        return nil
    end

    pdk.log.info("sync_update_router_data: got service list, count: [" .. #list.list .. "]")

    local service_list = {}
    local schema_failed_count = 0
    local disabled_count = 0

    for i = 1, #list.list do

        repeat
            local _, err = pdk.schema.check(schema.service.service_data, list.list[i])

            if err then
                schema_failed_count = schema_failed_count + 1
                pdk.log.error("sync_update_router_data: service schema check err:["
                                      .. err .. "][" .. tostring(list.list[i].name) .. "]")
                break
            end

            if list.list[i].enabled == false then
                disabled_count = disabled_count + 1
                pdk.log.info("sync_update_router_data: service disabled, skip: [" .. tostring(list.list[i].name) .. "]")
                break
            end

            table.insert(service_list, {
                name      = list.list[i].name,
                hosts     = list.list[i].hosts,
                protocols = list.list[i].protocols,
                plugins   = list.list[i].plugins,
                client_max_body_size = list.list[i].client_max_body_size,
                chunked_transfer_encoding = list.list[i].chunked_transfer_encoding,
                proxy_buffering = list.list[i].proxy_buffering,
                proxy_cache = list.list[i].proxy_cache,
                proxy_set_header = list.list[i].proxy_set_header,
            })
        until true

    end

    pdk.log.info("sync_update_router_data: service_list count: [" .. #service_list .. "], schema_failed: [" .. schema_failed_count .. "], disabled: [" .. disabled_count .. "]")

    if #service_list == 0 then
        pdk.log.warn("sync_update_router_data: no valid service found after filtering")
        return nil
    end

    local router_map = router_map_service()
    pdk.log.info("sync_update_router_data: router_map is " .. (router_map and "not nil" or "nil"))

    local service_router_list = {}
    local no_router_count = 0

    for j = 1, #service_list do

        repeat
            local routers = {}

            if not service_list[j].name then
                no_router_count = no_router_count + 1
                pdk.log.warn("sync_update_router_data: service missing name, skip")
                break
            end

            local service_key = service_list[j].name
            if router_map and router_map[service_key] then
                routers = router_map[service_key]
            end

            if not next(routers) then
                no_router_count = no_router_count + 1
                pdk.log.info("sync_update_router_data: service has no routers, skip: [" .. tostring(service_key) .. "]")
                break
            end

            service_list[j].routers = routers

            table.insert(service_router_list, service_list[j])

        until true
    end

    pdk.log.info("sync_update_router_data: service_router_list count: [" .. #service_router_list .. "], no_router_count: [" .. no_router_count .. "]")

    if #service_router_list == 0 then
        pdk.log.warn("sync_update_router_data: no service with routers found")
        return nil
    end

    return service_router_list
end

local function do_sync_resource_data()
    pdk.log.info("do_sync_resource_data: start sync resource data")

    local sync_router_data = sync_update_router_data()
    if sync_router_data == nil then
        pdk.log.info("do_sync_resource_data: sync_router_data is nil, no data to sync")
        return false
    end

    pdk.log.info("do_sync_resource_data: sync_router_data count: [" .. #sync_router_data .. "]")

    local service_router_plugin_map, service_router_upstream_map = {}, {}

    for i = 1, #sync_router_data do

        local service_plugins = sync_router_data[i].plugins

        if service_plugins and (#service_plugins ~= 0) then
            for j = 1, #service_plugins do
                if service_plugins[j] and service_plugins[j].name and
                        not service_router_plugin_map[service_plugins[j].name] then
                    service_router_plugin_map[service_plugins[j].name] = 0
                end
            end
        end

        local service_routers = sync_router_data[i].routers

        if service_routers and (#service_routers ~= 0) then
            for k = 1, #service_routers do

                if service_routers[k].plugins and (#service_routers[k].plugins ~= 0) then
                    for l = 1, #service_routers[k].plugins do
                        if service_routers[k].plugins[l].name and
                                not service_router_plugin_map[service_routers[k].plugins[l].name] then
                            service_router_plugin_map[service_routers[k].plugins[l].name] = 1
                        end
                    end
                end

                if service_routers[k].upstream and service_routers[k].upstream.name and
                        not service_router_upstream_map[service_routers[k].upstream.name] then
                    service_router_upstream_map[service_routers[k].upstream.name] = 1
                end
            end
        end
    end

    local sync_plugin_data = {}
    if next(service_router_plugin_map) ~= nil then
        local plugin_data = sys_plugin.sync_update_plugin_data()

        if plugin_data and (#plugin_data ~= 0) then
            for i = 1, #plugin_data do
                if plugin_data[i].name and service_router_plugin_map[plugin_data[i].name] then
                    table.insert(sync_plugin_data, plugin_data[i])
                end
            end
        end
        pdk.log.info("do_sync_resource_data: sync_plugin_data count: [" .. #sync_plugin_data .. "]")
    end

    local sync_upstream_data = {}
    if next(service_router_upstream_map) ~= nil then
        local upstream_data = sys_balancer.sync_update_upstream_data()

        if upstream_data and (#upstream_data ~= 0) then
            for k = 1, #upstream_data do
                if upstream_data[k].name and service_router_upstream_map[upstream_data[k].name] then
                    table.insert(sync_upstream_data, upstream_data[k])
                end
            end
        end
        pdk.log.info("do_sync_resource_data: sync_upstream_data count: [" .. #sync_upstream_data .. "]")
    end

    local sync_ssl_data = sys_certificate.sync_update_ssl_data()
    pdk.log.info("do_sync_resource_data: sync_ssl_data count: [" .. (sync_ssl_data and #sync_ssl_data or 0) .. "]")

    local post_ssl, post_ssl_err = events.post(
            sys_certificate.events_source_ssl, sys_certificate.events_type_put_ssl, sync_ssl_data)

    local post_upstream, post_upstream_err = events.post(
            sys_balancer.events_source_upstream, sys_balancer.events_type_put_upstream, sync_upstream_data)

    local post_plugin, post_plugin_err = events.post(
            sys_plugin.events_source_plugin, sys_plugin.events_type_put_plugin, sync_plugin_data)

    pdk.log.info("do_sync_resource_data: posting router event, data count: [" .. #sync_router_data .. "]")
    local post_router, post_router_err = events.post(
            events_source_router, events_type_put_router, sync_router_data)
    pdk.log.info("do_sync_resource_data: router event posted, result: [" .. tostring(post_router) .. "], err: [" .. tostring(post_router_err) .. "]")

    if post_ssl_err then
        pdk.log.error("do_sync_resource_data: sync ssl data post err:[" .. tostring(post_ssl_err) .. "]")
    end

    if post_upstream_err then
        pdk.log.error("do_sync_resource_data: sync upstream data post err:[" .. tostring(post_upstream_err) .. "]")
    end

    if post_plugin_err then
        pdk.log.error("do_sync_resource_data: sync plugin data post err:[" .. tostring(post_plugin_err) .. "]")
    end

    if post_router_err then
        pdk.log.error("do_sync_resource_data: sync router data post err:[" .. tostring(post_router_err) .. "]")
    end

    if post_ssl and post_upstream and post_plugin and post_router then
        pdk.log.info("do_sync_resource_data: all data sync success")
        return true
    else
        pdk.log.warn("do_sync_resource_data: some data sync failed, ssl: [" .. tostring(post_ssl) 
                .. "], upstream: [" .. tostring(post_upstream) .. "], plugin: [" .. tostring(post_plugin) 
                .. "], router: [" .. tostring(post_router) .. "]")
        return false
    end
end

local function automatic_sync_resource_data(premature)
    if premature then
        return
    end

    if ngx_process.type() ~= "privileged agent" then
        return
    end

    if ngx_worker_exiting() then
        return
    end

    local sync_data, err = dao.common.get_sync_data()

    if err then
        pdk.log.error("automatic_sync_resource_data: get_sync_data_err: [" .. tostring(err) .. "]")
        ngx_timer_at(2, automatic_sync_resource_data)
        return
    end

    if not sync_data then
        sync_data = {}
    end

    pdk.log.info("automatic_sync_resource_data: get_sync_data success, old_hash: [" 
            .. tostring(sync_data.old) .. "], new_hash: [" .. tostring(sync_data.new) .. "]")

    if not sync_data.new or (sync_data.new ~= sync_data.old) then
        pdk.log.info("automatic_sync_resource_data: data changed, start sync resource data")
        local sync_success = do_sync_resource_data()
        if sync_success then
            dao.common.update_sync_data_hash(true)
        end
    else
        pdk.log.info("automatic_sync_resource_data: data not changed, skip sync")
    end

    if not ngx_worker_exiting() then
        ngx_timer_at(2, automatic_sync_resource_data)
    end
end

local function generate_router_data(router_data)
    pdk.log.info("generate_router_data: start, router_data type: [" .. type(router_data) .. "]")

    if not router_data or type(router_data) ~= "table" then
        pdk.log.error("generate_router_data: invalid data type")
        return nil, "generate_router_data: the data is empty or the data format is wrong["
                .. pdk.json.encode(router_data, true) .. "]"
    end

    pdk.log.info("generate_router_data: checking fields, hosts: [" .. tostring(router_data.hosts ~= nil) .. "], routers: [" .. tostring(router_data.routers ~= nil) .. "]")
    if router_data.hosts then
        pdk.log.info("generate_router_data: hosts count: [" .. #router_data.hosts .. "]")
    end
    if router_data.routers then
        pdk.log.info("generate_router_data: routers count: [" .. #router_data.routers .. "]")
    end

    if not router_data.hosts or not router_data.routers or (#router_data.hosts == 0) or (#router_data.routers == 0) then
        pdk.log.error("generate_router_data: missing required fields")
        return nil, "generate_router_data: Missing data required fields["
                .. pdk.json.encode(router_data, true) .. "]"
    end

    local router_data_list = {}

    for i = 1, #router_data.hosts do

        for j = 1, #router_data.routers do

            repeat
                if (type(router_data.routers[j].paths) ~= "table") or (#router_data.routers[j].paths == 0) then
                    break
                end

                for k = 1, #router_data.routers[j].paths do
                    repeat

                        if #router_data.routers[j].paths[k] == 0 then
                            break
                        end

                        local upstream_copy = nil
                        if router_data.routers[j].upstream then
                            upstream_copy = pdk.json.decode(pdk.json.encode(router_data.routers[j].upstream, true))
                        end

                        local host_router_data = {
                            plugins   = router_data.plugins,
                            protocols = router_data.protocols,
                            host      = router_data.hosts[i],
                            client_max_body_size = router_data.client_max_body_size,
                            chunked_transfer_encoding = router_data.chunked_transfer_encoding,
                            proxy_buffering = router_data.proxy_buffering,
                            proxy_cache = router_data.proxy_cache,
                            proxy_set_header = router_data.proxy_set_header,
                            router    = {
                                path     = router_data.routers[j].paths[k],
                                plugins  = router_data.routers[j].plugins,
                                upstream = upstream_copy,
                                headers  = router_data.routers[j].headers,
                                methods  = router_data.routers[j].methods,
                                client_max_body_size = router_data.routers[j].client_max_body_size,
                                chunked_transfer_encoding = router_data.routers[j].chunked_transfer_encoding,
                                proxy_buffering = router_data.routers[j].proxy_buffering,
                                proxy_cache = router_data.routers[j].proxy_cache,
                                proxy_set_header = router_data.routers[j].proxy_set_header,
                            }
                        }

                        local priority_num = 1
                        if host_router_data.router.path == "/*" then
                            priority_num = 0
                        end

                        table.insert(router_data_list, {
                            path     = host_router_data.host .. ":" .. host_router_data.router.path,
                            method   = host_router_data.router.methods,
                            priority = priority_num,
                            handler  = function(params, ok_ctx)

                                ok_ctx.matched.path = params

                                ok_ctx.config = {}
                                ok_ctx.config.service_router = host_router_data
                            end
                        })
                    until true
                end

            until true
        end
    end

    pdk.log.info("generate_router_data: generated router_data_list count: [" .. #router_data_list .. "]")
    if #router_data_list > 0 then
        return router_data_list, nil
    end

    pdk.log.warn("generate_router_data: router_data_list is empty")
    return nil, nil
end

local function worker_event_router_handler_register()

    local router_handler = function(data, event, source)
        pdk.log.info("router_handler: received event, source: [" .. tostring(source) .. "], event: [" .. tostring(event) .. "]")

        if source ~= events_source_router then
            pdk.log.warn("router_handler: source mismatch, expected: [" .. events_source_router .. "], got: [" .. tostring(source) .. "]")
            return
        end

        if event ~= events_type_put_router then
            pdk.log.warn("router_handler: event mismatch, expected: [" .. events_type_put_router .. "], got: [" .. tostring(event) .. "]")
            return
        end

        if (type(data) ~= "table") or (#data == 0) then
            pdk.log.warn("router_handler: invalid data, type: [" .. type(data) .. "], length: [" .. (type(data) == "table" and #data or 0) .. "]")
            return
        end

        pdk.log.info("router_handler: processing router data, count: [" .. #data .. "]")

        local ok_router_data = {}

        for i = 1, #data do

            repeat
                pdk.log.info("router_handler: generating router data for item [" .. i .. "]")
                local router_data, router_data_err = generate_router_data(data[i])

                if router_data_err then
                    pdk.log.error("router_handler: generate router data err: ["
                                          .. tostring(router_data_err) .. "]")
                    break
                end

                if not router_data then
                    pdk.log.warn("router_handler: generate_router_data returned nil for item [" .. i .. "]")
                    break
                end

                pdk.log.info("router_handler: generated router data count: [" .. #router_data .. "] for item [" .. i .. "]")
                for j = 1, #router_data do
                    table.insert(ok_router_data, router_data[j])
                end

            until true
        end

        pdk.log.info("router_handler: total ok_router_data count: [" .. #ok_router_data .. "]")
        if #ok_router_data == 0 then
            pdk.log.error("router_handler: no valid router data generated, router_objects will be nil")
            router_objects = nil
            current_router_data = nil
        else
            router_objects = okrouting.new(ok_router_data)
            current_router_data = pdk.json.decode(pdk.json.encode(data, true))
            if router_objects then
                pdk.log.info("router_handler: router_objects created successfully")
            else
                pdk.log.error("router_handler: failed to create router_objects from ok_router_data")
            end
        end
    end

    if ngx_process.type() ~= "privileged agent" then
        events.register(router_handler, events_source_router, events_type_put_router)
    end
end

local function init_sync_resource_data(premature)
    if premature then
        return
    end

    if ngx_process.type() ~= "privileged agent" then
        return
    end

    pdk.log.info("init_sync_resource_data: start initial sync, force sync regardless of hash")

    local sync_success = do_sync_resource_data()
    if sync_success then
        pdk.log.info("init_sync_resource_data: initial sync success")
    else
        pdk.log.warn("init_sync_resource_data: initial sync failed, will retry in timer")
    end
end

function _M.init_worker()
    pdk.log.info("router.init_worker: start, worker type: [" .. ngx_process.type() .. "]")

    worker_event_router_handler_register()
    pdk.log.info("router.init_worker: router handler registered")

    if ngx_process.type() == "privileged agent" then
        ngx_timer_at(0, init_sync_resource_data)
        pdk.log.info("router.init_worker: init_sync_resource_data scheduled for initial sync")
    end

    ngx_timer_at(0, automatic_sync_resource_data)
    pdk.log.info("router.init_worker: automatic_sync_resource_data timer scheduled")

end

function _M.parameter(ok_ctx)
    local env = pdk.request.header(pdk.const.REQUEST_API_ENV_KEY)
    if env then
        env = pdk.string.upper(env)
    else
        env = pdk.const.ENVIRONMENT_PROD
    end

    ok_ctx.matched = {}
    ok_ctx.matched.host   = ngx.var.host
    ok_ctx.matched.uri    = ngx.var.uri
    ok_ctx.matched.scheme = ngx.var.scheme
    ok_ctx.matched.query  = pdk.request.query()
    ok_ctx.matched.method = pdk.request.get_method()
    ok_ctx.matched.header = pdk.request.header()

    ok_ctx.matched.header[pdk.const.REQUEST_API_ENV_KEY] = env
end

function _M.router_match(ok_ctx)

    if not ok_ctx.matched or not ok_ctx.matched.host or not ok_ctx.matched.uri then
        pdk.log.error("router_match: ok_ctx data format err: [" .. pdk.json.encode(ok_ctx, true) .. "]")
        return false
    end

    if not router_objects then
        pdk.log.error("router_match: router_objects is null, worker type: [" .. ngx_process.type() .. "]")
        return false
    end

    local match_path = ok_ctx.matched.host .. ":" .. ok_ctx.matched.uri

    local match, err = router_objects:dispatch(match_path, string.upper(ok_ctx.matched.method), ok_ctx)

    if err then
        pdk.log.error("router_match: router_objects dispatch err: [" .. tostring(err) .. "]")
        return false
    end

    if not match then
        return false
    end

    local service_router = ok_ctx.config.service_router
    local matched = ok_ctx.matched

    local match_protocols = false

    if service_router.protocols and matched.scheme then
        for i = 1, #service_router.protocols do
            if pdk.string.lower(service_router.protocols[i]) == pdk.string.lower(matched.scheme) then
                match_protocols = true
            end
        end
    end

    if not match_protocols then
        return false
    end

    if service_router.router.headers and next(service_router.router.headers) then
        local match_header = true

        for h_key, h_value in pairs(service_router.router.headers) do
            local matched_header_value = matched.header[h_key]

            if matched_header_value ~= h_value then
                match_header = false
            end
        end

        if not match_header then
            return false
        end

    end

    return true
end

function _M.get_router_info()
    return current_router_data
end

return _M
