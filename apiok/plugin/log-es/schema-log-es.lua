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
            description = "Elasticsearch host",
        },
        port = {
            type        = "number",
            minimum     = 1,
            maximum     = 65535,
            default     = 9200,
            description = "Elasticsearch port",
        },
        scheme = {
            type        = "string",
            enum        = { "http", "https" },
            default     = "http",
            description = "Elasticsearch scheme",
        },
        username = {
            type        = "string",
            description = "Elasticsearch username for basic auth",
        },
        password = {
            type        = "string",
            description = "Elasticsearch password for basic auth",
        },
        index_prefix = {
            type        = "string",
            minLength   = 1,
            default     = "apiok",
            description = "Elasticsearch index prefix",
        },
        index_type = {
            type        = "string",
            default     = "_doc",
            description = "Elasticsearch document type",
        },
        date_format = {
            type        = "string",
            default     = "%Y.%m.%d",
            description = "Date format for index name (e.g., %Y.%m.%d for daily indices)",
        },
        timeout = {
            type        = "number",
            minimum     = 1000,
            maximum     = 60000,
            default     = 5000,
            description = "Elasticsearch connection timeout in milliseconds",
        },
        batch_size = {
            type        = "number",
            minimum     = 1,
            maximum     = 10000,
            default     = 100,
            description = "Batch size for bulk API",
        },
        batch_timeout = {
            type        = "number",
            minimum     = 1000,
            maximum     = 60000,
            default     = 5000,
            description = "Batch flush timeout in milliseconds",
        },
        keepalive_timeout = {
            type        = "number",
            minimum     = 1000,
            maximum     = 600000,
            default     = 60000,
            description = "HTTP keepalive timeout in milliseconds",
        },
        keepalive_pool = {
            type        = "number",
            minimum     = 1,
            maximum     = 1000,
            default     = 10,
            description = "HTTP keepalive pool size",
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
    },
    required   = { "host", "port" }
}

return _M

