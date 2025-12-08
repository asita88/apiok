local stop  = require("apiok.cmd.stop")
local start = require("apiok.cmd.start")

local lapp = [[
Usage: apiok restart
]]

local function execute()

    pcall(stop.execute)

    pcall(start.execute)
end

return {
    lapp = lapp,
    execute = execute
}