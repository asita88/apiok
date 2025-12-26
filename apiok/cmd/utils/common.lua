local script_path = debug.getinfo(1).source:sub(2)

local function trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function execute_cmd(cmd)
    local t = io.popen(cmd)
    local data = t:read("*all")
    t:close()
    return data
end

local apiok_home
if script_path:sub(1, 4) == '/usr' or script_path:sub(1, 4) == '/bin' or script_path:sub(1, 4) == '/opt' then
    apiok_home = "/usr/local/apiok"
    package.cpath = "/usr/local/apiok/deps/lib64/lua/5.1/?.so;"
            .. "/usr/local/apiok/deps/lib/lua/5.1/?.so;"
            .. package.cpath

    package.path = "/usr/local/apiok/deps/share/lua/5.1/apiok/lua/?.lua;"
            .. "/usr/local/apiok/deps/share/lua/5.1/?.lua;"
            .. "/usr/share/lua/5.1/apiok/lua/?.lua;"
            .. "/usr/local/share/lua/5.1/apiok/lua/?.lua;"
            .. package.path
else
    apiok_home = trim(execute_cmd("pwd"))
    package.cpath = apiok_home .. "/deps/lib64/lua/5.1/?.so;"
            .. package.cpath

    package.path = apiok_home .. "/apiok/?.lua;"
            .. apiok_home .. "/deps/share/lua/5.1/?.lua;"
            .. package.path
end

local openresty_bin = trim(execute_cmd("which openresty"))
if not openresty_bin then
    error("can not find the openresty.")
end

local openresty_launch = openresty_bin .. [[  -p ]] .. apiok_home .. [[ -c ]]
        .. apiok_home .. [[/conf/nginx.conf]]

return {
    apiok_home = apiok_home,
    openresty_launch = openresty_launch,
    trim = trim,
    execute_cmd = execute_cmd,
}