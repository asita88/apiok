local _M = {}

_M.schema = {
    type       = "object",
    properties = {
        enabled = {
            type    = "boolean",
            default = true,
        },
        ip_whitelist = {
            type        = "array",
            items       = {
                type = "string",
            },
            description = "IP whitelist, requests from these IPs will bypass all checks",
        },
        ip_blacklist = {
            type        = "array",
            items       = {
                type = "string",
            },
            description = "IP blacklist, requests from these IPs will be blocked",
        },
        sql_injection = {
            type       = "object",
            properties = {
                enabled = {
                    type    = "boolean",
                    default = true,
                },
                action  = {
                    type = "string",
                    enum = { "block", "log" },
                    default = "block",
                },
            },
            default = {
                enabled = true,
                action  = "block",
            },
        },
        xss = {
            type       = "object",
            properties = {
                enabled = {
                    type    = "boolean",
                    default = true,
                },
                action  = {
                    type = "string",
                    enum = { "block", "log" },
                    default = "block",
                },
            },
            default = {
                enabled = true,
                action  = "block",
            },
        },
        path_traversal = {
            type       = "object",
            properties = {
                enabled = {
                    type    = "boolean",
                    default = true,
                },
                action  = {
                    type = "string",
                    enum = { "block", "log" },
                    default = "block",
                },
            },
            default = {
                enabled = true,
                action  = "block",
            },
        },
        allowed_methods = {
            type        = "array",
            items       = {
                type = "string",
                enum = { "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS" },
            },
            description = "Allowed HTTP methods, empty means all methods are allowed",
        },
        blocked_user_agents = {
            type        = "array",
            items       = {
                type = "string",
            },
            description = "Blocked User-Agent patterns (supports wildcard)",
        },
        max_request_size = {
            type        = "number",
            minimum     = 0,
            description = "Maximum request body size in bytes, 0 means unlimited",
            default     = 0,
        },
        sensitive_data_leak = {
            type       = "object",
            properties = {
                enabled = {
                    type    = "boolean",
                    default = true,
                },
                action  = {
                    type = "string",
                    enum = { "block", "log" },
                    default = "block",
                },
            },
            default = {
                enabled = true,
                action  = "block",
            },
        },
    },
}

return _M

