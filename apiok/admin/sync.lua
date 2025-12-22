local pdk    = require("apiok.pdk")
local common = require("apiok.admin.dao.common")
local sys_router = require("apiok.sys.router")

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

return _M

