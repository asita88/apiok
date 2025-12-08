local oakrouting = require("resty.oakrouting")
local admin      = require("apiok.admin")
local router

local _M = {}

function _M.init_worker()

    router = oakrouting.new()

    router:post("/apiok/admin/sync/reload", admin.sync.reload)

end

function _M.routers()
    return router
end

return _M
