local ngx = ngx
local pdk = require("apiok.pdk")
local stringx = require("apiok.pdk.string")

local plugin_common = require("apiok.plugin.plugin_common")

local plugin_name = "waf"

local _M = {}

local SQL_INJECTION_PATTERNS = {
    "(%s|^)(union|select|insert|update|delete|drop|create|alter|exec|execute|script)(%s|$)",
    "(%s|^)(or|and)(%s|%+|=|'|\")",
    "(%s|^)(1=1|1=2|'1'='1'|'1'='2')",
    "(%s|^)(%+|-|\\*|/|%%)",
    "(%s|^)(--|#|/\\*|\\*/)",
    "(%s|^)(char|nchar|varchar|nvarchar|int|bigint|smallint|tinyint|float|real|double|decimal|numeric|money|smallmoney|bit|datetime|smalldatetime|timestamp|uniqueidentifier|text|ntext|image|xml|sql_variant|table|cursor|hierarchyid|geography|geometry)(%s|%()",
    "(%s|^)(xp_|sp_|sys\\.|information_schema|mysql\\.|pg_|pg_catalog)",
    "(%s|^)(load_file|into\\s+outfile|into\\s+dumpfile|load\\s+data)",
    "(%s|^)(benchmark|sleep|waitfor|delay)",
    "(%s|^)(%?|%:|%%)",
}

local XSS_PATTERNS = {
    "<script[^>]*>.*?</script>",
    "<iframe[^>]*>.*?</iframe>",
    "<object[^>]*>.*?</object>",
    "<embed[^>]*>.*?</embed>",
    "<link[^>]*>.*?</link>",
    "<style[^>]*>.*?</style>",
    "javascript:",
    "onerror\\s*=",
    "onload\\s*=",
    "onclick\\s*=",
    "onmouseover\\s*=",
    "onfocus\\s*=",
    "onblur\\s*=",
    "onchange\\s*=",
    "onsubmit\\s*=",
    "eval\\s*\\(",
    "expression\\s*\\(",
    "vbscript:",
    "data:text/html",
    "data:image/svg",
}

local PATH_TRAVERSAL_PATTERNS = {
    "\\.\\./",
    "\\.\\.\\\\",
    "%2e%2e%2f",
    "%2e%2e%5c",
    "\.\./",
    "\.\.\\",
    "/\\.\\./",
    "\\\\\\.\\.\\\\",
}

local SENSITIVE_DATA_PATTERNS = {
    "(?i)(password|pwd|passwd)\\s*[:=]\\s*['\"]?[^'\"\\s]{6,}",
    "(?i)(api[_-]?key|apikey)\\s*[:=]\\s*['\"]?[^'\"\\s]{10,}",
    "(?i)(secret|secret[_-]?key)\\s*[:=]\\s*['\"]?[^'\"\\s]{10,}",
    "(?i)(token|access[_-]?token)\\s*[:=]\\s*['\"]?[^'\"\\s]{10,}",
    "(?i)(credit[_-]?card|card[_-]?number|cc[_-]?number)\\s*[:=]\\s*['\"]?[0-9]{13,19}",
    "(?i)(ssn|social[_-]?security[_-]?number)\\s*[:=]\\s*['\"]?[0-9]{3}-?[0-9]{2}-?[0-9]{4}",
    "(?i)(private[_-]?key|rsa[_-]?key)\\s*[:=]\\s*['\"]?-----BEGIN",
}

function _M.schema_config(config)
    local plugin_schema_err = plugin_common.plugin_config_schema(plugin_name, config)
    if plugin_schema_err then
        return plugin_schema_err
    end
    return nil
end

local function match_pattern(text, patterns)
    if not text or type(text) ~= "string" then
        return false
    end
    
    text = string.lower(text)
    
    for _, pattern in ipairs(patterns) do
        if string.find(text, pattern) then
            return true
        end
    end
    
    return false
end

local function check_ip_list(ip, list)
    if not list or #list == 0 then
        return false
    end
    
    for _, item in ipairs(list) do
        if ip == item then
            return true
        end
        if string.find(item, "*") then
            local pattern = "^" .. string.gsub(string.gsub(item, "%.", "%%."), "%*", ".*") .. "$"
            if string.match(ip, pattern) then
                return true
            end
        end
    end
    
    return false
end

local function check_user_agent(user_agent, blocked_list)
    if not user_agent or not blocked_list or #blocked_list == 0 then
        return false
    end
    
    user_agent = string.lower(user_agent)
    
    for _, pattern in ipairs(blocked_list) do
        local regex_pattern = "^" .. string.gsub(string.gsub(pattern, "%.", "%%."), "%*", ".*") .. "$"
        if string.match(user_agent, regex_pattern) then
            return true
        end
    end
    
    return false
end

local function check_request_data(ok_ctx, plugin_config)
    local matched = ok_ctx.matched
    
    local check_data = {}
    
    if matched.uri then
        table.insert(check_data, matched.uri)
    end
    
    if matched.args then
        for k, v in pairs(matched.args) do
            table.insert(check_data, k)
            if type(v) == "string" then
                table.insert(check_data, v)
            end
        end
    end
    
    if matched.header then
        for k, v in pairs(matched.header) do
            if type(v) == "string" then
                table.insert(check_data, v)
            end
        end
    end
    
    if matched.body and type(matched.body) == "string" then
        table.insert(check_data, matched.body)
    end
    
    local all_data = table.concat(check_data, " ")
    
    if plugin_config.sql_injection and plugin_config.sql_injection.enabled then
        if match_pattern(all_data, SQL_INJECTION_PATTERNS) then
            pdk.log.warn("[waf] SQL injection detected: " .. ngx.var.remote_addr)
            if plugin_config.sql_injection.action == "block" then
                return true, "SQL injection detected"
            end
        end
    end
    
    if plugin_config.xss and plugin_config.xss.enabled then
        if match_pattern(all_data, XSS_PATTERNS) then
            pdk.log.warn("[waf] XSS attack detected: " .. ngx.var.remote_addr)
            if plugin_config.xss.action == "block" then
                return true, "XSS attack detected"
            end
        end
    end
    
    if plugin_config.path_traversal and plugin_config.path_traversal.enabled then
        if match_pattern(all_data, PATH_TRAVERSAL_PATTERNS) then
            pdk.log.warn("[waf] Path traversal detected: " .. ngx.var.remote_addr)
            if plugin_config.path_traversal.action == "block" then
                return true, "Path traversal detected"
            end
        end
    end
    
    if plugin_config.sensitive_data_leak and plugin_config.sensitive_data_leak.enabled then
        if match_pattern(all_data, SENSITIVE_DATA_PATTERNS) then
            pdk.log.warn("[waf] Sensitive data leak detected: " .. ngx.var.remote_addr)
            if plugin_config.sensitive_data_leak.action == "block" then
                return true, "Sensitive data leak detected"
            end
        end
    end
    
    return false, nil
end

function _M.http_access(ok_ctx, plugin_config)
    if not plugin_config.enabled then
        return
    end
    
    local remote_addr = ngx.var.remote_addr
    
    if plugin_config.ip_whitelist and check_ip_list(remote_addr, plugin_config.ip_whitelist) then
        return
    end
    
    if plugin_config.ip_blacklist and check_ip_list(remote_addr, plugin_config.ip_blacklist) then
        pdk.log.warn("[waf] IP blocked: " .. remote_addr)
        pdk.response.exit(403, { message = "Access denied" })
    end
    
    local matched = ok_ctx.matched
    
    if plugin_config.allowed_methods and #plugin_config.allowed_methods > 0 then
        local method = ngx.req.get_method()
        local allowed = false
        for _, m in ipairs(plugin_config.allowed_methods) do
            if method == m then
                allowed = true
                break
            end
        end
        if not allowed then
            pdk.log.warn("[waf] Method not allowed: " .. method .. " from " .. remote_addr)
            pdk.response.exit(405, { message = "Method not allowed" })
        end
    end
    
    if plugin_config.blocked_user_agents then
        local user_agent = matched.header and matched.header["User-Agent"] or ngx.var.http_user_agent
        if check_user_agent(user_agent, plugin_config.blocked_user_agents) then
            pdk.log.warn("[waf] User-Agent blocked: " .. (user_agent or "") .. " from " .. remote_addr)
            pdk.response.exit(403, { message = "Access denied" })
        end
    end
    
    if plugin_config.max_request_size and plugin_config.max_request_size > 0 then
        local content_length = tonumber(ngx.var.content_length) or 0
        if content_length > plugin_config.max_request_size then
            pdk.log.warn("[waf] Request too large: " .. content_length .. " bytes from " .. remote_addr)
            pdk.response.exit(413, { message = "Request entity too large" })
        end
    end
    
    local blocked, reason = check_request_data(ok_ctx, plugin_config)
    if blocked then
        pdk.response.exit(403, { message = reason })
    end
end

return _M

