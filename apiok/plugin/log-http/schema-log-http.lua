local _M = {}

_M.schema = {
    type       = "object",
    properties = {
        enabled = {
            type    = "boolean",
            default = true,
        },
        url = {
            type        = "string",
            minLength   = 1,
            description = "HTTP endpoint URL to send logs",
        },
        method = {
            type        = "string",
            enum        = { "POST", "PUT", "PATCH" },
            default     = "POST",
            description = "HTTP method to use",
        },
        timeout = {
            type        = "number",
            minimum     = 1000,
            maximum     = 60000,
            default     = 5000,
            description = "HTTP request timeout in milliseconds",
        },
        keepalive_timeout = {
            type        = "number",
            minimum     = 1000,
            maximum     = 600000,
            default     = 60000,
            description = "HTTP connection keepalive timeout in milliseconds",
        },
        keepalive_pool = {
            type        = "number",
            minimum     = 1,
            maximum     = 1000,
            default     = 10,
            description = "HTTP connection keepalive pool size",
        },
        headers = {
            type        = "object",
            description = "Custom HTTP headers to include in the request",
        },
        include_request_body = {
            type    = "boolean",
            default = false,
            description = "Include request body in log",
        },
        include_response_body = {
            type    = "boolean",
            default = false,
            description = "Include response body in log",
        },
        include_headers = {
            type        = "array",
            items       = {
                type = "string",
            },
            description = "Include specific request/response headers in log",
        },
        exclude_headers = {
            type        = "array",
            items       = {
                type = "string",
            },
            description = "Exclude specific headers from log (case-insensitive)",
        },
        log_format = {
            type = "string",
            enum = { "json", "text" },
            default = "json",
            description = "Log format: json or text",
        },
    },
    required   = { "url" }
}

return _M

