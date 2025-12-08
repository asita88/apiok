local pdk    = require("apiok.pdk")
local common = require("apiok.admin.dao.common")

local _M = {}

function _M.reload()
    local res, err = common.update_sync_data_hash()

    if err then
        pdk.log.error("sync-reload update_sync_data_hash err: [" .. err .. "]")
        pdk.response.exit(500, { message = "sync reload failed: " .. tostring(err) })
    end

    pdk.response.exit(200, { message = "sync reload success" })
end

return _M

