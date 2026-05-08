local stop  = require("apiok.cmd.stop")
local start = require("apiok.cmd.start")

local lapp = [[
Usage: apiok restart
]]

local function execute(args)
    pcall(function()
        stop.execute(args)
    end)
    pcall(function()
        start.execute(args)
    end)
end

return {
    lapp = lapp,
    execute = execute
}