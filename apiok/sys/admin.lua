local okrouting  = require("apiok.sys.routing")
local admin      = require("apiok.admin")
local router

local _M = {}

function _M.init_worker()

    router = okrouting.new()

    router:post("/apiok/admin/sync/reload", admin.sync.reload)
    router:get("/apiok/admin/router/info", admin.sync.get_router_info)
    router:get("/apiok/admin/config/all", admin.sync.get_all_config)
    router:get("/apiok/admin/config/active", admin.sync.get_active_config)
    router:get("/apiok/admin/metrics", admin.metrics.export)

end

function _M.routers()
    return router
end

return _M
