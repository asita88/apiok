local nginx_signals = require "apiok/cmd/utils/nginx_signals"
local env           = require"apiok/cmd/env"

local lapp = [[
Usage: apiok start
]]

local function execute(args)
    env.execute(args)
    print("----------------------------")

    nginx_signals.start(args.apiok_home)

    print("Apiok started successfully!")
end

return {
    lapp = lapp,
    execute = execute
}