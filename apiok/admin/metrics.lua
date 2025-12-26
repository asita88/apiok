local pdk = require("apiok.pdk")
local plugin_key = "prometheus"
local prometheus_metrics = require("apiok.plugin." .. plugin_key .. "." .. plugin_key)

local _M = {}

function _M.export()
    local metrics_data = prometheus_metrics.export_metrics()
    pdk.response.exit(200, metrics_data, "text/plain; version=0.0.4")
end

return _M
