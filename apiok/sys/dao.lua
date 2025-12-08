local pdk     = require("apiok.pdk")
local dao     = require("apiok.dao")
local uuid    = require("resty.jit-uuid")
local storage = require("apiok.pdk.storage")
local process = require("ngx.process")

local ngx_timer_at = ngx.timer.at

local _M = {}


local function clear_sync_update_data()

    if process.type() ~= "privileged agent" then
        return
    end

    local sync_data, err = dao.common.get_sync_data()

    if err then
        pdk.log.error("[sys.dao] get sync data err: ", err)
    end

    if not sync_data then
        return
    end

    local _, err = dao.common.clear_sync_data()

    if err then
        pdk.log.error("[sys.dao] clear sync data err: ", err)
        return
    end
end

function _M.init_worker()

    uuid.seed()

    local ok, err = storage.init()
    if not ok then
        pdk.log.error("[sys.dao] storage init failed: ", err)
        return
    end

    ngx_timer_at(0, clear_sync_update_data)

end

return _M
