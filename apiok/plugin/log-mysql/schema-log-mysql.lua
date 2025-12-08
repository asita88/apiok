local _M = {}

_M.schema = {
    type       = "object",
    properties = {
        enabled = {
            type    = "boolean",
            default = true,
        },
        host = {
            type        = "string",
            minLength   = 1,
            default     = "127.0.0.1",
            description = "MySQL host",
        },
        port = {
            type        = "number",
            minimum     = 1,
            maximum     = 65535,
            default     = 3306,
            description = "MySQL port",
        },
        database = {
            type        = "string",
            minLength   = 1,
            description = "MySQL database name",
        },
        user = {
            type        = "string",
            minLength   = 1,
            description = "MySQL username",
        },
        password = {
            type        = "string",
            description = "MySQL password",
        },
        table_name = {
            type        = "string",
            minLength   = 1,
            default     = "apiok_access_log",
            description = "MySQL table name",
        },
        timeout = {
            type        = "number",
            minimum     = 1000,
            maximum     = 60000,
            default     = 5000,
            description = "MySQL connection timeout in milliseconds",
        },
        pool_size = {
            type        = "number",
            minimum     = 1,
            maximum     = 1000,
            default     = 100,
            description = "MySQL connection pool size",
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
        batch_size = {
            type        = "number",
            minimum     = 1,
            maximum     = 1000,
            default     = 100,
            description = "Batch insert size",
        },
        batch_timeout = {
            type        = "number",
            minimum     = 1000,
            maximum     = 60000,
            default     = 5000,
            description = "Batch insert timeout in milliseconds",
        },
    },
    required   = { "host", "database", "user", "table_name" }
}

return _M

