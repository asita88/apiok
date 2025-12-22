local type         = type
local ipairs       = ipairs
local str_sub      = string.sub
local str_gsub     = string.gsub
local str_len      = string.len
local str_upper    = string.upper
local tab_insert   = table.insert
local ngx_re_gsub  = ngx.re.gsub
local ngx_re_match = ngx.re.match
local ngx_re_find  = ngx.re.find


local ok, new_tab = pcall(require, "table.new")
if not ok then
    new_tab = function(narr, nrec)
        return {}
    end
end


local _METHODS = new_tab(0, 7)
_METHODS['GET'] = true
_METHODS['POST'] = true
_METHODS['PUT'] = true
_METHODS['DELETE'] = true
_METHODS['PATCH'] = true
_METHODS['HEAD'] = true
_METHODS['OPTIONS'] = true


local _M = { _VERSION = '0.1.0' }


local mt = { __index = _M }


-- 注册路由规则
-- @param self 路由对象实例
-- @param path 路由路径，格式为 "host:path" 或纯路径，支持通配符 * 和变量 {name}
-- @param method HTTP 方法，可以是字符串（如 "GET"）或表（如 {"GET", "POST"}），支持逗号分隔的字符串
-- @param handler 路由处理函数
-- @param priority 路由优先级，数字越小优先级越高，默认为 1
local function push_router(self, path, method, handler, priority)
    -- 验证路径参数
    if type(path) ~= "string" then
        error("invalid argument path", 2)
    end

    -- 设置优先级，默认为 1
    if priority and type(priority) ~= "number" then
        error("missing argument priority", 2)
    else
        priority = 1
    end

    -- 验证处理函数
    if not handler or type(handler) == "nil" then
        error("missing argument handler", 2)
    end

    -- 验证方法参数
    if not method then
        error("missing argument method", 2)
    end

    -- 解析方法参数，支持字符串和表两种格式
    local method_type = type(method)
    if method_type ~= "string" and method_type ~= "table" then
        error("missing argument method", 2)
    end

    -- 将方法字符串或表转换为统一的方法表
    local method_table = {}
    if method_type == "string" then
        -- 支持逗号分隔的字符串，如 "GET,POST"
        str_gsub(method, "[^,]+", function(method_str)
            if #method_str > 0 then
                tab_insert(method_table, str_upper(method_str))
            end
        end)
    elseif method_type == "table" then
        -- 支持方法数组，如 {"GET", "POST"}
        for i = 1, #method do
            if #method[i] > 0 then
                tab_insert(method_table, str_upper(method[i]))
            end
        end
    end

    -- 验证方法表不为空
    local method_table_len = #method_table
    if method_table_len == 0 then
        error("missing argument method", 2)
    end

    -- 验证所有方法都是有效的 HTTP 方法
    for i = 1, method_table_len do
        if not _METHODS[method_table[i]] then
            error("method invalid", 2)
        end
    end

    -- 为每个方法初始化路由缓存表
    for i = 1, method_table_len do
        if not self.cached_data[method_table[i]] then
            self.cached_data[method_table[i]] = new_tab(10, 0)
        end
    end

    -- 将路径转换为正则表达式
    local variables = new_tab(1, 0)
    
    local regexp = path
    
    -- 如果路径包含冒号，说明是 "host:path" 格式，需要分别处理 host 和 path 部分
    local colon_pos = string.find(regexp, ":", 1, true)
    if colon_pos then
        local host_part = str_sub(regexp, 1, colon_pos - 1)
        local path_part = str_sub(regexp, colon_pos + 1)
        
        -- 转义 host 部分中的正则特殊字符（如点号、加号等）
        host_part = ngx_re_gsub(host_part, "([%.%+%*%?%^%$%(%)%[%]%{%}%|%\\])", "\\%1", "jo")
        
        regexp = host_part .. ":" .. path_part
    end
    
    -- 处理路径变量，将 {name} 转换为命名捕获组 (?P<name>[^/]++)
    regexp = ngx_re_gsub(regexp, "(\\{[a-zA-Z0-9-_]+\\})", function(m)
        local name = str_sub(m[1], 2, str_len(m[1]) - 1)
        tab_insert(variables, name)
        return '(?P<' .. name .. '>[^/]++)'
    end, "i")

    -- 处理通配符 *，转换为匹配任意字符（字母、数字、下划线、连字符、斜杠、点号）
    local wildcard_from = ngx_re_find(regexp, "\\*", "jo")
    if wildcard_from then
        regexp = ngx_re_gsub(regexp, "\\*", "([a-zA-Z0-9-_\\/\\.]*)", "jo")
    end

    -- 为每个方法注册路由规则
    for i = 1, method_table_len do
        tab_insert(self.cached_data[method_table[i]], {
            path = path,
            regexp = "^" .. regexp .. "$",
            handler = handler,
            priority = priority,
            variables = variables,
        })
    end
end


function _M.post(self, path, handler)
    push_router(self, path, "POST", handler)
end


function _M.delete(self, path, handler)
    push_router(self, path, "DELETE", handler)
end


function _M.put(self, path, handler)
    push_router(self, path, "PUT", handler)
end


function _M.get(self, path, handler)
    push_router(self, path, "GET", handler)
end


function _M.patch(self, path, handler)
    push_router(self, path, "PATCH", handler)
end


function _M.head(self, path, handler)
    push_router(self, path, "HEAD", handler)
end


function _M.options(self, path, handler)
    push_router(self, path, "OPTIONS", handler)
end


function _M.any(self, method, path, handler)
    push_router(self, path, method, handler)
end


function _M.dispatch(self, path, method, ...)
    if not method or type(path) ~= "string" then
        return nil, "missing argument method"
    end


    method = str_upper(method)
    if not _METHODS[method] then
        return nil, "method invalid"
    end


    local params = new_tab(0, 1)
    local handler
    local current_router


    local routers = self.cached_data[method] or new_tab(1, 0)
    for i = 1, #routers do
        local router = routers[i]
        local matched = ngx_re_match(path, router.regexp, "jo")
        if matched then
            router.matched = matched
            if not current_router or router.priority > current_router.priority then
                current_router = router
                handler = router.handler
            end
        end
    end


    if current_router and #current_router.variables > 0 then
        local router_matched = current_router.matched
        for _, variable in ipairs(current_router.variables) do
            params[variable] = router_matched[variable]
        end
    end


    if handler and type(handler) == "function" then
        handler(params, ...)
        return true
    end


    return nil, "not matched"
end


function _M.new(routers)
    if not routers then
        routers = new_tab(0, 0)
    end


    local router_len = #routers
    local self = setmetatable({
        cached_data = new_tab(0, router_len)
    }, mt)


    for i = 1, router_len do
        local router = routers[i]
        push_router(self, router.path, router.method, router.handler, router.priority)
    end


    return self
end


return _M

