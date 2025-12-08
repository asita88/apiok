local _M = {}

_M.schema = {
    type       = "object",
    properties = {
        enabled = {
            type    = "boolean",
            default = true,
        },
        brokers = {
            type        = "array",
            items       = {
                type = "string",
            },
            minItems    = 1,
            description = "Kafka broker addresses, e.g., [\"127.0.0.1:9092\"]",
        },
        topic = {
            type        = "string",
            minLength   = 1,
            description = "Kafka topic name",
        },
        timeout = {
            type        = "number",
            minimum     = 1000,
            maximum     = 60000,
            default     = 5000,
            description = "Kafka connection timeout in milliseconds",
        },
        keepalive_timeout = {
            type        = "number",
            minimum     = 1000,
            maximum     = 600000,
            default     = 60000,
            description = "Kafka connection keepalive timeout in milliseconds",
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
    required   = { "brokers", "topic" }
}

return _M

