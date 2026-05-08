local function trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function execute_cmd(cmd)
    local t = io.popen(cmd)
    local data = t:read("*all")
    t:close()
    return data
end

return {
    trim = trim,
    execute_cmd = execute_cmd,
}
