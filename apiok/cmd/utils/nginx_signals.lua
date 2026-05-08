local function trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function strip_slash(s)
    return (s:gsub("/+$", ""))
end

local function dirname(p)
    p = p:gsub("\\", "/")
    local d = p:match("^(.*)/[^/]+$")
    return d or "."
end

local function openresty_launch(apiok_home)
    assert(apiok_home and apiok_home ~= "", "openresty_launch: missing home")
    apiok_home = strip_slash(trim(apiok_home))
    local openresty_root = dirname(apiok_home) .. "/openresty"
    print("openresty_root: " .. openresty_root)
    local bin = openresty_root .. "/bin/openresty"
    print("bin: " .. bin)
    return bin .. [[  -p ]] .. apiok_home .. [[ -c ]] .. apiok_home .. [[/conf/nginx.conf]]
end

local _M = {}

function _M.start(apiok_home)
    local cmd = openresty_launch(apiok_home)
    os.execute(cmd)
end

function _M.stop(apiok_home)
    local cmd = openresty_launch(apiok_home)
    os.execute(cmd .. [[ -s stop]])
end

function _M.quit(apiok_home)
    local cmd = openresty_launch(apiok_home)
    os.execute(cmd .. [[ -s quit]])
end

function _M.test(apiok_home)
    local cmd = openresty_launch(apiok_home)
    os.execute(cmd .. [[ -t]])
end

function _M.reload(apiok_home)
    local cmd = openresty_launch(apiok_home)
    os.execute(cmd .. [[ -s reload]])
end

return _M
