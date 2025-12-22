local ngx      = ngx
local pdk      = require("apiok.pdk")
local dao      = require("apiok.dao")
local schema   = require("apiok.schema")
local events   = require("resty.worker.events")
local cache    = require("apiok.sys.cache")
local resolver = require("resty.dns.resolver")
local math_random        = math.random
local ngx_process        = require("ngx.process")
local balancer           = require("ngx.balancer")
local balancer_round     = require('resty.roundrobin')
local balancer_chash     = require('resty.chash')
local healthcheck_module = require("apiok.sys.healthcheck")

local resolver_address_cache_prefix = "resolver_address_cache_prefix"

local upstream_objects = {}
local resolver_client

local _M = {}

_M.events_source_upstream   = "events_source_upstream"
_M.events_type_put_upstream = "events_type_put_upstream"

function _M.sync_update_upstream_data()

    local upstream_list, err = dao.common.list_keys(dao.common.PREFIX_MAP.upstreams)

    if err then
        pdk.log.error("sync_update_upstream_data: get upstream list FAIL [".. err .."]")
        return nil
    end

    if not upstream_list or not upstream_list.list or (#upstream_list.list == 0) then
        pdk.log.error("sync_update_upstream_data: upstream list null ["
                              .. pdk.json.encode(upstream_list, true) .. "]")
        return nil
    end

    local node_list, err = dao.common.list_keys(dao.common.PREFIX_MAP.upstream_nodes)

    if err then
        pdk.log.error("sync_update_upstream_data: get upstream node list FAIL [".. err .."]")
        return nil
    end

    local node_map_by_name = {}

    if node_list and node_list.list and (#node_list.list > 0) then

        local constants = require("apiok.admin.dao.constants")
        local health = constants.UPSTREAM_NODE_DEFAULT_HEALTH

        for i = 1, #node_list.list do

            repeat
                local _, err = pdk.schema.check(schema.upstream_node.upstream_node_data, node_list.list[i])

                if err then
                    pdk.log.error("sync_update_upstream_data: upstream node schema check err:[" .. err .. "]["
                                          .. pdk.json.encode(node_list.list[i], true) .. "]")
                    break
                end

                if node_list.list[i].health ~= health then
                    break
                end

                if not node_list.list[i].name then
                    pdk.log.warn("sync_update_upstream_data: upstream node missing name, skip")
                    break
                end

                node_map_by_name[node_list.list[i].name] = {
                    name    = node_list.list[i].name,
                    address = node_list.list[i].address,
                    port    = node_list.list[i].port,
                    weight  = node_list.list[i].weight,
                    check   = node_list.list[i].check,
                    health  = node_list.list[i].health,
                    tags    = node_list.list[i].tags or {},
                }
            until true

        end

    end

    local all_balancer_map = {}

    for i = 1, #pdk.const.ALL_BALANCERS do
        all_balancer_map[pdk.const.ALL_BALANCERS[i]] = 0
    end

    local upstreams_nodes_list = {}

    for j = 1, #upstream_list.list do

        repeat
            local _, err = pdk.schema.check(schema.upstream.upstream_data, upstream_list.list[j])

            if err then
                pdk.log.error("sync_update_upstream_data: upstream schema check err:[" .. err .. "]["
                                      .. pdk.json.encode(upstream_list.list[j], true) .. "]")
                break
            end

            if not all_balancer_map[upstream_list.list[j].algorithm] then
                break
            end

            local upstream_nodes = {}

            for k = 1, #upstream_list.list[j].nodes do

                repeat
                    local node_key = upstream_list.list[j].nodes[k].name
                    if not node_key then
                        pdk.log.warn("sync_update_upstream_data: upstream node reference missing name, skip")
                        break
                    end

                    local node = node_map_by_name[node_key]

                    if not node then
                        pdk.log.warn("sync_update_upstream_data: upstream node not found: [" .. tostring(node_key) .. "]")
                        break
                    end

                    table.insert(upstream_nodes, node)
                until true

            end

            if #upstream_nodes == 0 then
                pdk.log.error("sync_update_upstream_data: the upstream node does not match the data: ["
                                      .. pdk.json.encode(upstream_list.list[j], true) .. "]")
                break
            end

            table.insert(upstreams_nodes_list, {
                name            = upstream_list.list[j].name,
                nodes           = upstream_nodes,
                algorithm       = upstream_list.list[j].algorithm,
                read_timeout    = upstream_list.list[j].read_timeout,
                write_timeout   = upstream_list.list[j].write_timeout,
                connect_timeout = upstream_list.list[j].connect_timeout,
            })

        until true
    end

    if next(upstreams_nodes_list) then
        -- 更新健康检测器
        healthcheck_module.sync_update_checkers(upstreams_nodes_list)
        return upstreams_nodes_list
    end

    return nil
end

local function generate_upstream_balancer(upstream_data)

    if not upstream_data or (type(upstream_data) ~= "table") then
        return nil
    end

    local nodes = upstream_data.nodes

    local node_list = {}
    local node_info_map = {}

    if nodes and (#nodes > 0) then

        for j = 1, #nodes do
            -- 如果启用了健康检测，只添加健康的节点
            local is_healthy = true
            if upstream_data.name then
                is_healthy = healthcheck_module.is_target_healthy(
                    upstream_data.name, nodes[j].address, nodes[j].port)
            end
            
            if is_healthy then
                local node_key = nodes[j].address .. '|' .. nodes[j].port
                node_list[node_key] = nodes[j].weight
                node_info_map[node_key] = {
                    address = nodes[j].address,
                    port    = nodes[j].port,
                    tags    = nodes[j].tags or {},
                }
            end
        end

    end

    local upstream_balancer = {
        algorithm       = upstream_data.algorithm,
        read_timeout    = upstream_data.read_timeout,
        write_timeout   = upstream_data.write_timeout,
        connect_timeout = upstream_data.connect_timeout,
        node_info_map   = node_info_map,
    }

    if next(node_list) then

        if  upstream_balancer.algorithm == pdk.const.BALANCER_ROUNDROBIN then
            upstream_balancer.handler = balancer_round:new(node_list)
        elseif upstream_balancer.algorithm == pdk.const.BALANCER_CHASH then
            upstream_balancer.handler = balancer_chash:new(node_list)
        end

    end

    return upstream_balancer
end

local function renew_upstream_balancer_object(new_upstream_objects)

    if not new_upstream_objects or not next(new_upstream_objects) then
        return
    end

    for upstream_id, _ in pairs(upstream_objects) do

        if not new_upstream_objects[upstream_id] then

            upstream_objects[upstream_id] = nil

        else

            if new_upstream_objects[upstream_id].write_timeout ~= upstream_objects[upstream_id].write_timeout then
                upstream_objects[upstream_id].write_timeout = new_upstream_objects[upstream_id].write_timeout
            end

            if new_upstream_objects[upstream_id].read_timeout ~= upstream_objects[upstream_id].read_timeout then
                upstream_objects[upstream_id].read_timeout = new_upstream_objects[upstream_id].read_timeout
            end

            if new_upstream_objects[upstream_id].connect_timeout ~= upstream_objects[upstream_id].connect_timeout then
                upstream_objects[upstream_id].connect_timeout = new_upstream_objects[upstream_id].connect_timeout
            end

            if new_upstream_objects[upstream_id].node_info_map then
                upstream_objects[upstream_id].node_info_map = new_upstream_objects[upstream_id].node_info_map
            end

            if new_upstream_objects[upstream_id].algorithm ~= upstream_objects[upstream_id].algorithm then
                upstream_objects[upstream_id].algorithm = new_upstream_objects[upstream_id].algorithm
                upstream_objects[upstream_id].handler   = new_upstream_objects[upstream_id].handler
            else

                local handler = upstream_objects[upstream_id].handler
                local new_handler = new_upstream_objects[upstream_id].handler

                local nodes, new_nodes = handler.nodes, new_handler.nodes

                for new_id, new_weight in pairs(new_nodes) do

                    if not nodes[new_id] then
                        handler:set(new_id, new_weight)
                    end

                end

                for id, weight in pairs(nodes) do

                    local new_weight = new_nodes[id]

                    if not new_weight then
                        handler:delete(id)
                    else
                        if new_weight ~= weight then
                            handler:set(id, new_weight)
                        end
                    end

                end

            end
        end
    end

    for upstream_id, object in pairs(new_upstream_objects) do

        if not upstream_objects[upstream_id] then
            upstream_objects[upstream_id] = object
        end

    end

end

local function worker_event_upstream_handler_register()

    local upstream_balancer_handler = function(data, event, source)

        if source ~= _M.events_source_upstream then
            return
        end

        if event ~= _M.events_type_put_upstream then
            return
        end

        if (type(data) ~= "table") or (#data == 0) then
            return
        end

        local new_upstream_object = {}

        for i = 1, #data do
            new_upstream_object[data[i].name] = generate_upstream_balancer(data[i])
        end

        renew_upstream_balancer_object(new_upstream_object)
        
        -- 更新健康检测器
        healthcheck_module.sync_update_checkers(data)

    end

    if ngx_process.type() ~= "privileged agent" then
        events.register(upstream_balancer_handler, _M.events_source_upstream, _M.events_type_put_upstream)
    end
end

function _M.init_worker()

    worker_event_upstream_handler_register()

end

function _M.init_resolver()

    local client, err = resolver:new{
        nameservers = { {"114.114.114.114", 53}, "8.8.8.8" },
        retrans = 3,  -- 3 retransmissions on receive timeout
        timeout = 500,  -- 500 ms
        no_random = false, -- always start with first nameserver
    }

    if err then
        pdk.log.error("init resolver error: [" .. tostring(err) .. "]")
        return
    end

    resolver_client = client
end

function _M.check_replenish_upstream(ok_ctx)

    if not ok_ctx.config or not ok_ctx.config.service_router or not ok_ctx.config.service_router.router then
        pdk.log.error("check_replenish_upstream: ok_ctx data format error: ["
                              .. pdk.json.encode(ok_ctx, true) .. "]")
        return
    end

    local service_router = ok_ctx.config.service_router

    if service_router.router.upstream and service_router.router.upstream.name and
            upstream_objects[service_router.router.upstream.name] then
        return
    end

    if not resolver_client or not ok_ctx.matched or not ok_ctx.matched.host or (#ok_ctx.matched.host == 0) then
        return
    end

    local address_cache_key = resolver_address_cache_prefix .. ":" .. ok_ctx.matched.host

    local address_cache = cache.get(address_cache_key)

    if address_cache then
        service_router.router.upstream.address = address_cache
        service_router.router.upstream.port    = 80
        return
    end

    local answers, err = resolver_client:query(ok_ctx.matched.host, nil, {})

    if err then
        pdk.log.error("failed to query the DNS server: [" .. pdk.json.encode(err, true) .. "]")
        return
    end

    local answers_list = {}

    for i = 1, #answers do

        if (answers[i].type == resolver_client.TYPE_A) or (answers[i].type == resolver_client.TYPE_AAAA) then
            pdk.table.insert(answers_list, answers[i])
        end

    end

    local resolver_result = answers[math_random(1, #answers)]

    if not resolver_result or not next(resolver_result) then
        return
    end

    cache.set(address_cache_key, resolver_result.address, 60)

    service_router.router.upstream.address = resolver_result.address
    service_router.router.upstream.port    = 80

end

function _M.gogogo(ok_ctx)

    if not ok_ctx.config or not ok_ctx.config.service_router or not ok_ctx.config.service_router.router or
            not ok_ctx.config.service_router.router.upstream or
            not next(ok_ctx.config.service_router.router.upstream) then
        pdk.log.error("[sys.balancer.gogogo] ok_ctx.config.service_router.router.upstream is null!")
        return
    end

    local upstream = ok_ctx.config.service_router.router.upstream

    local address, port

    local timeout = {
        read_timeout    = pdk.const.UPSTREAM_DEFAULT_TIMEOUT,
        write_timeout   = pdk.const.UPSTREAM_DEFAULT_TIMEOUT,
        connect_timeout = pdk.const.UPSTREAM_DEFAULT_TIMEOUT,
    }

    if upstream.name then

        local upstream_object = upstream_objects[upstream.name]

        if not upstream_object then
            pdk.log.error("[sys.balancer.gogogo] upstream undefined, upstream_object is null!")
            return
        end

        if not upstream_object.read_timeout then
            timeout.read_timeout = upstream_object.read_timeout
        end
        if not upstream_object.write_timeout then
            timeout.write_timeout = upstream_object.write_timeout
        end
        if not upstream_object.connect_timeout then
            timeout.connect_timeout = upstream_object.connect_timeout
        end

        local request_tags = {}
        local request_headers = pdk.request.header()
        
        local x_tags_header = request_headers["X-Tags"]
        if x_tags_header then
            local tags_json = pdk.json.decode(x_tags_header)
            if tags_json and type(tags_json) == "table" then
                request_tags = tags_json
            end
        else
            for header_key, header_value in pairs(request_headers) do
                local match, _ = ngx.re.match(header_key, "^X%-Tag%-(.+)$", "jo")
                if match then
                    local tag_key = match[1]
                    request_tags[tag_key] = header_value
                end
            end
        end

        local address_port
        local max_retries = 3
        local retry_count = 0
        local matched_nodes = {}
        local use_tag_matching = false

        if next(request_tags) and upstream_object.node_info_map then
            local handler_nodes = upstream_object.handler.nodes
            for node_key, _ in pairs(handler_nodes) do
                local node_info = upstream_object.node_info_map[node_key]
                if node_info then
                    local node_tags = node_info.tags or {}
                    local match = true
                    for tag_key, tag_value in pairs(request_tags) do
                        if not node_tags[tag_key] or node_tags[tag_key] ~= tag_value then
                            match = false
                            break
                        end
                    end
                    if match then
                        pdk.table.insert(matched_nodes, node_key)
                    end
                end
            end
            use_tag_matching = (#matched_nodes > 0)
        end

        repeat
            if use_tag_matching and #matched_nodes > 0 then
                local selected_idx = math_random(1, #matched_nodes)
                address_port = matched_nodes[selected_idx]
                pdk.table.remove(matched_nodes, selected_idx)
            else
                use_tag_matching = false
                if upstream_object.algorithm == pdk.const.BALANCER_ROUNDROBIN then
                    address_port = upstream_object.handler:find()
                elseif upstream_object.algorithm == pdk.const.BALANCER_CHASH then
                    address_port = upstream_object.handler:find(ok_ctx.config.service_router.host)
                end
            end

            if not address_port then
                pdk.log.error("[sys.balancer.gogogo] upstream undefined, upstream_object find null!")
                return
            end

            local address_port_table = pdk.string.split(address_port, "|")
            if #address_port_table == 2 then
                local check_address = address_port_table[1]
                local check_port = tonumber(address_port_table[2])
                
                -- 检查节点健康状态
                if upstream.name and healthcheck_module.is_target_healthy(upstream.name, check_address, check_port) then
                    break
                else
                    -- 节点不健康，从负载均衡器中移除并重试
                    retry_count = retry_count + 1
                    if retry_count >= max_retries then
                        pdk.log.error("[sys.balancer.gogogo] no healthy upstream nodes available after " .. max_retries .. " retries")
                        return
                    end
                    -- 从负载均衡器中临时移除不健康的节点
                    upstream_object.handler:delete(address_port)
                    if use_tag_matching and #matched_nodes == 0 then
                        use_tag_matching = false
                    end
                end
            else
                break
            end
        until false

        local address_port_table = pdk.string.split(address_port, "|")

        if #address_port_table ~= 2 then
            pdk.log.error("[sys.balancer.gogogo] address port format error: ["
                                  .. pdk.json.encode(address_port_table, true) .. "]")
            return
        end

        address = address_port_table[1]
        port    = tonumber(address_port_table[2])

    else

        if not upstream.address or not upstream.port then
            pdk.log.error("[sys.balancer.gogogo] upstream address and port undefined")
            return
        end

        address = upstream.address
        port    = upstream.port

    end

    if not address or not port or (address == ngx.null) or (port == ngx.null) then
        pdk.log.error("[sys.balancer.gogogo] address or port is null ["
                              .. pdk.json.encode(address, true) .. "]["
                              ..  pdk.json.encode(port, true) .. "]")
        return
    end

    local _, err = pdk.schema.check(schema.upstream_node.schema_ip, address)

    if err then
        pdk.log.error("[sys.balancer.gogogo] address schema check err:[" .. address .. "][" .. err .. "]")
        return
    end

    local _, err = pdk.schema.check(schema.upstream_node.schema_port, port)

    if err then
        pdk.log.error("[sys.balancer.gogogo] port schema check err:[" .. port .. "][" .. err .. "]")
        return
    end

    local ok, err = balancer.set_timeouts(
            timeout.connect_timeout / 1000, timeout.write_timeout / 1000, timeout.read_timeout / 1000)

    if not ok then
        pdk.log.error("[sys.balancer] could not set upstream timeouts: [" .. pdk.json.encode(err, true) .. "]")
        return
    end

    local ok, err = balancer.set_current_peer(address, port)

    if not ok then
        pdk.log.error("[sys.balancer] failed to set the current peer: ", err)
        return
    end
end

return _M
