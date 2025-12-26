local ngx = ngx
local pairs = pairs
local pdk = require("apiok.pdk")
local dao = require("apiok.dao")
local events = require("resty.worker.events")
local schema = require("apiok.schema")
local okrouting = require("apiok.sys.routing")
local sys_certificate = require("apiok.sys.certificate")
local sys_balancer = require("apiok.sys.balancer")
local sys_plugin = require("apiok.sys.plugin")
local ngx_process = require("ngx.process")
local ngx_sleep = ngx.sleep
local ngx_timer_at = ngx.timer.at
local ngx_worker_exiting = ngx.worker.exiting
local xpcall = xpcall
local debug_traceback = debug.traceback

local router_objects
local current_router_data

local events_source_router = "events_source_router"
local events_type_put_router = "events_type_put_router"

local _M = {}

local function build_service_router_list()
	local service_list, err = dao.common.list_keys(dao.common.PREFIX_MAP.services)

	if err then
		pdk.log.error("failed to get service list, err: " .. tostring(err))
		return nil
	end

	if not service_list or not service_list.list or (#service_list.list == 0) then
		pdk.log.warn("service list is empty")
		return nil
	end

	local router_list, err = dao.common.list_keys(dao.common.PREFIX_MAP.routers)

	if err then
		pdk.log.error("failed to get router list, err: " .. tostring(err))
		return nil
	end

	local valid_services = {}
	local service_schema_failed = 0
	local service_disabled = 0

	for i = 1, #service_list.list do
		repeat
			local _, err = pdk.schema.check(schema.service.service_data, service_list.list[i])

			if err then
				service_schema_failed = service_schema_failed + 1
				pdk.log.error("service schema check failed, service: " .. tostring(service_list.list[i].name) .. ", err: " .. err)
				break
			end

			if service_list.list[i].enabled == false then
				service_disabled = service_disabled + 1
				break
			end

			if not service_list.list[i].name then
				pdk.log.warn("service missing name, skip")
				break
			end

			valid_services[service_list.list[i].name] = {
				name = service_list.list[i].name,
				hosts = service_list.list[i].hosts,
				protocols = service_list.list[i].protocols,
				plugins = service_list.list[i].plugins,
				client_max_body_size = service_list.list[i].client_max_body_size,
				chunked_transfer_encoding = service_list.list[i].chunked_transfer_encoding,
				proxy_buffering = service_list.list[i].proxy_buffering,
				proxy_cache = service_list.list[i].proxy_cache,
				proxy_set_header = service_list.list[i].proxy_set_header,
				routers = {},
			}
		until true
	end

	if not next(valid_services) then
		pdk.log.warn("no valid service found, total: " .. #service_list.list .. ", schema_failed: " .. service_schema_failed .. ", disabled: " .. service_disabled)
		return nil
	end

	local router_schema_failed = 0
	local router_disabled = 0
	local router_no_service = 0
	local router_success = 0

	if router_list and router_list.list and (#router_list.list > 0) then
		for i = 1, #router_list.list do
			repeat
				local _, err = pdk.schema.check(schema.router.router_data, router_list.list[i])

				if err then
					router_schema_failed = router_schema_failed + 1
					pdk.log.error("router schema check failed, router: " .. tostring(router_list.list[i].name) .. ", err: " .. err)
					break
				end

				if router_list.list[i].enabled == false then
					router_disabled = router_disabled + 1
					break
				end

				if not router_list.list[i].service or not router_list.list[i].service.name then
					router_no_service = router_no_service + 1
					pdk.log.warn("router missing service.name, router: " .. tostring(router_list.list[i].name))
					break
				end

				local service_name = router_list.list[i].service.name
				if not valid_services[service_name] then
					router_no_service = router_no_service + 1
					break
				end

				router_success = router_success + 1
				table.insert(valid_services[service_name].routers, {
					paths = router_list.list[i].paths,
					methods = pdk.const.DEFAULT_METHODS(router_list.list[i].methods),
					headers = router_list.list[i].headers,
					upstream = router_list.list[i].upstream,
					plugins = router_list.list[i].plugins,
					client_max_body_size = router_list.list[i].client_max_body_size,
					chunked_transfer_encoding = router_list.list[i].chunked_transfer_encoding,
					proxy_buffering = router_list.list[i].proxy_buffering,
					proxy_cache = router_list.list[i].proxy_cache,
					proxy_set_header = router_list.list[i].proxy_set_header,
				})
			until true
		end
	end

	local service_router_list = {}
	local no_router_count = 0

	for _, service in pairs(valid_services) do
		if not next(service.routers) then
			no_router_count = no_router_count + 1
		else
			table.insert(service_router_list, service)
		end
	end

	pdk.log.debug("completed, services: " .. #service_list.list .. ", valid: " .. (#service_router_list + no_router_count) .. ", with_routers: " .. #service_router_list .. ", no_routers: " .. no_router_count .. ", router_total: " .. (router_list and router_list.list and #router_list.list or 0) .. ", router_success: " .. router_success .. ", router_schema_failed: " .. router_schema_failed .. ", router_disabled: " .. router_disabled .. ", router_no_service: " .. router_no_service)

	if #service_router_list == 0 then
		pdk.log.warn("no service with routers found")
		return nil
	end

	return service_router_list
end

local function do_sync_resource_data()
	pdk.log.debug("start sync resource data")

	local sync_router_data = build_service_router_list()
	if sync_router_data == nil then
		pdk.log.debug("sync_router_data is nil, no data to sync")
		return false
	end

	pdk.log.debug("sync_router_data count: [" .. #sync_router_data .. "]")

	local service_router_plugin_map, service_router_upstream_map = {}, {}

	for i = 1, #sync_router_data do
		local service_plugins = sync_router_data[i].plugins

		if service_plugins and (#service_plugins ~= 0) then
			for j = 1, #service_plugins do
				if
					service_plugins[j]
					and service_plugins[j].name
					and not service_router_plugin_map[service_plugins[j].name]
				then
					service_router_plugin_map[service_plugins[j].name] = 0
				end
			end
		end

		local service_routers = sync_router_data[i].routers

		if service_routers and (#service_routers ~= 0) then
			for k = 1, #service_routers do
				if service_routers[k].plugins and (#service_routers[k].plugins ~= 0) then
					for l = 1, #service_routers[k].plugins do
						if
							service_routers[k].plugins[l].name
							and not service_router_plugin_map[service_routers[k].plugins[l].name]
						then
							service_router_plugin_map[service_routers[k].plugins[l].name] = 1
						end
					end
				end

				if
					service_routers[k].upstream
					and service_routers[k].upstream.name
					and not service_router_upstream_map[service_routers[k].upstream.name]
				then
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
		pdk.log.debug("sync_plugin_data count: [" .. #sync_plugin_data .. "]")
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
		pdk.log.debug("sync_upstream_data count: [" .. #sync_upstream_data .. "]")
	end

	local sync_ssl_data = sys_certificate.sync_update_ssl_data()
	pdk.log.debug("sync_ssl_data count: [" .. (sync_ssl_data and #sync_ssl_data or 0) .. "]")

	local post_ssl, post_ssl_err =
		events.post(sys_certificate.events_source_ssl, sys_certificate.events_type_put_ssl, sync_ssl_data)

	local post_upstream, post_upstream_err =
		events.post(sys_balancer.events_source_upstream, sys_balancer.events_type_put_upstream, sync_upstream_data)

	local post_plugin, post_plugin_err =
		events.post(sys_plugin.events_source_plugin, sys_plugin.events_type_put_plugin, sync_plugin_data)

	local sync_global_plugin_data = sys_plugin.sync_update_global_plugin_data()
	pdk.log.debug(
		"sync_global_plugin_data count: ["
			.. (sync_global_plugin_data and #sync_global_plugin_data or 0)
			.. "]"
	)

	local post_global_plugin, post_global_plugin_err = events.post(
		sys_plugin.events_source_global_plugin,
		sys_plugin.events_type_put_global_plugin,
		sync_global_plugin_data or {}
	)

	pdk.log.debug("posting router event, data count: [" .. #sync_router_data .. "]")
	local post_router, post_router_err = events.post(events_source_router, events_type_put_router, sync_router_data)
	pdk.log.debug(
		"router event posted, result: ["
			.. tostring(post_router)
			.. "], err: ["
			.. tostring(post_router_err)
			.. "]"
	)

	if post_ssl_err then
		pdk.log.error("sync ssl data post err:[" .. tostring(post_ssl_err) .. "]")
	end

	if post_upstream_err then
		pdk.log.error("sync upstream data post err:[" .. tostring(post_upstream_err) .. "]")
	end

	if post_plugin_err then
		pdk.log.error("sync plugin data post err:[" .. tostring(post_plugin_err) .. "]")
	end

	if post_global_plugin_err then
		pdk.log.error(
			"sync global plugin data post err:[" .. tostring(post_global_plugin_err) .. "]"
		)
	end

	if post_router_err then
		pdk.log.error("sync router data post err:[" .. tostring(post_router_err) .. "]")
	end

	if post_ssl and post_upstream and post_plugin and post_global_plugin and post_router then
		pdk.log.debug("all data sync success")
		return true
	else
		pdk.log.warn(
			"some data sync failed, ssl: ["
				.. tostring(post_ssl)
				.. "], upstream: ["
				.. tostring(post_upstream)
				.. "], plugin: ["
				.. tostring(post_plugin)
				.. "], global_plugin: ["
				.. tostring(post_global_plugin)
				.. "], router: ["
				.. tostring(post_router)
				.. "]"
		)
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
		pdk.log.error("get_sync_data_err: [" .. tostring(err) .. "]")
		ngx_timer_at(2, automatic_sync_resource_data)
		return
	end

	if not sync_data then
		sync_data = {}
	end

	pdk.log.debug(
		"get_sync_data success, old_hash: ["
			.. tostring(sync_data.old)
			.. "], new_hash: ["
			.. tostring(sync_data.new)
			.. "]"
	)

	if not sync_data.new or (sync_data.new ~= sync_data.old) then
		pdk.log.debug("data changed, start sync resource data")
		local sync_success = do_sync_resource_data()
		if sync_success then
			dao.common.update_sync_data_hash(true)
		end
	else
		pdk.log.debug("data not changed, skip sync")
	end

	if not ngx_worker_exiting() then
		ngx_timer_at(2, automatic_sync_resource_data)
	end
end

local function generate_router_data(router_data)
	pdk.log.debug("start, router_data type: [" .. type(router_data) .. "]")

	if not router_data or type(router_data) ~= "table" then
		pdk.log.error("invalid data type")
		return nil,
			"generate_router_data: the data is empty or the data format is wrong["
				.. pdk.json.encode(router_data, true)
				.. "]"
	end

	pdk.log.debug(
		"checking fields, hosts: ["
			.. tostring(router_data.hosts ~= nil)
			.. "], routers: ["
			.. tostring(router_data.routers ~= nil)
			.. "]"
	)
	if router_data.hosts then
		pdk.log.debug("hosts count: [" .. #router_data.hosts .. "]")
	end
	if router_data.routers then
		pdk.log.debug("routers count: [" .. #router_data.routers .. "]")
	end

	if not router_data.hosts or not router_data.routers or (#router_data.hosts == 0) or (#router_data.routers == 0) then
		pdk.log.error("missing required fields")
		return nil, "generate_router_data: Missing data required fields[" .. pdk.json.encode(router_data, true) .. "]"
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
							plugins = router_data.plugins,
							protocols = router_data.protocols,
							host = router_data.hosts[i],
							client_max_body_size = router_data.client_max_body_size,
							chunked_transfer_encoding = router_data.chunked_transfer_encoding,
							proxy_buffering = router_data.proxy_buffering,
							proxy_cache = router_data.proxy_cache,
							proxy_set_header = router_data.proxy_set_header,
							router = {
								path = router_data.routers[j].paths[k],
								plugins = router_data.routers[j].plugins,
								upstream = upstream_copy,
								headers = router_data.routers[j].headers,
								methods = router_data.routers[j].methods,
								client_max_body_size = router_data.routers[j].client_max_body_size,
								chunked_transfer_encoding = router_data.routers[j].chunked_transfer_encoding,
								proxy_buffering = router_data.routers[j].proxy_buffering,
								proxy_cache = router_data.routers[j].proxy_cache,
								proxy_set_header = router_data.routers[j].proxy_set_header,
							},
						}

						local priority_num = 1
						if host_router_data.router.path == "/*" then
							priority_num = 0
						end

						table.insert(router_data_list, {
							path = host_router_data.host .. ":" .. host_router_data.router.path,
							method = host_router_data.router.methods,
							priority = priority_num,
							handler = function(params, ok_ctx)
								ok_ctx.matched.path = params

								ok_ctx.config = {}
								ok_ctx.config.service_router = host_router_data
							end,
						})
					until true
				end

			until true
		end
	end

	pdk.log.debug("generated router_data_list count: [" .. #router_data_list .. "]")
	if #router_data_list > 0 then
		return router_data_list, nil
	end

	pdk.log.warn("router_data_list is empty")
	return nil, nil
end

local function worker_event_router_handler_register()
	local router_handler = function(data, event, source)
		pdk.log.debug(
			"received event, source: [" .. tostring(source) .. "], event: [" .. tostring(event) .. "]"
		)

		if source ~= events_source_router then
			pdk.log.warn(
				"source mismatch, expected: ["
					.. events_source_router
					.. "], got: ["
					.. tostring(source)
					.. "]"
			)
			return
		end

		if event ~= events_type_put_router then
			pdk.log.warn(
				"event mismatch, expected: ["
					.. events_type_put_router
					.. "], got: ["
					.. tostring(event)
					.. "]"
			)
			return
		end

		if (type(data) ~= "table") or (#data == 0) then
			pdk.log.warn(
				"invalid data, type: ["
					.. type(data)
					.. "], length: ["
					.. (type(data) == "table" and #data or 0)
					.. "]"
			)
			return
		end

		pdk.log.debug("processing router data, count: [" .. #data .. "]")

		local ok_router_data = {}

		for i = 1, #data do
			repeat
				pdk.log.debug("generating router data for item [" .. i .. "]")
				local router_data, router_data_err = generate_router_data(data[i])

				if router_data_err then
					pdk.log.error("generate router data err: [" .. tostring(router_data_err) .. "]")
					break
				end

				if not router_data then
					pdk.log.warn("generate_router_data returned nil for item [" .. i .. "]")
					break
				end

				pdk.log.debug(
					"generated router data count: [" .. #router_data .. "] for item [" .. i .. "]"
				)
				for j = 1, #router_data do
					table.insert(ok_router_data, router_data[j])
				end

			until true
		end

		pdk.log.debug("total ok_router_data count: [" .. #ok_router_data .. "]")
		if #ok_router_data == 0 then
			pdk.log.error("no valid router data generated, router_objects will be nil")
			router_objects = nil
			current_router_data = nil
		else
			router_objects = okrouting.new(ok_router_data)
			current_router_data = pdk.json.decode(pdk.json.encode(data, true))
			if router_objects then
				pdk.log.debug("router_objects created successfully")
			else
				pdk.log.error("failed to create router_objects from ok_router_data")
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

	pdk.log.debug("start initial sync, force sync regardless of hash")

	local sync_success = do_sync_resource_data()
	if sync_success then
		pdk.log.debug("initial sync success")
	else
		pdk.log.warn("initial sync failed, will retry in timer")
	end
end

function _M.init_worker()
	pdk.log.debug("start, worker type: [" .. ngx_process.type() .. "]")

	worker_event_router_handler_register()
	pdk.log.debug("router handler registered")

	if ngx_process.type() == "privileged agent" then
		ngx_timer_at(0, init_sync_resource_data)
		pdk.log.debug("init_sync_resource_data scheduled for initial sync")
	end

	ngx_timer_at(0, automatic_sync_resource_data)
	pdk.log.debug("automatic_sync_resource_data timer scheduled")
end

function _M.parameter(ok_ctx)
	local env = pdk.request.header(pdk.const.REQUEST_API_ENV_KEY)
	if env then
		env = pdk.string.upper(env)
	else
		env = pdk.const.ENVIRONMENT_PROD
	end

	ok_ctx.matched = {}
	ok_ctx.matched.host = ngx.var.host
	ok_ctx.matched.uri = ngx.var.uri
	ok_ctx.matched.scheme = ngx.var.scheme
	ok_ctx.matched.query = pdk.request.query()
	ok_ctx.matched.method = pdk.request.get_method()
	ok_ctx.matched.header = pdk.request.header()

	ok_ctx.matched.header[pdk.const.REQUEST_API_ENV_KEY] = env
end

function _M.router_match(ok_ctx)
	if not ok_ctx.matched or not ok_ctx.matched.host or not ok_ctx.matched.uri then
		pdk.log.error("ok_ctx data format err: [" .. pdk.json.encode(ok_ctx, true) .. "]")
		return false
	end

	if not router_objects then
		pdk.log.error("router_objects is null, worker type: [" .. ngx_process.type() .. "]")
		return false
	end

	local match_path = ok_ctx.matched.host .. ":" .. ok_ctx.matched.uri

	local match, err = router_objects:dispatch(match_path, string.upper(ok_ctx.matched.method), ok_ctx)

	if err then
		pdk.log.error("router_objects dispatch err: [" .. tostring(err) .. "]")
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
