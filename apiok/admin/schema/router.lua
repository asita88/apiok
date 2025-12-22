local pdk    = require("apiok.pdk")
local common = require "apiok.admin.schema.common"

local _M = {}

local paths = {
    type        = "array",
    minItems    = 1,
    uniqueItems = true,
    items       = {
        type    = "string",
        --pattern = "^\\/\\*?[0-9a-zA-Z-.=?_*/{}]+$"
        minLength = 1,
        maxLength = 2000
    }
}

local headers = {
    type = "object"
}

local methods = {
    type        = "array",
    minItems    = 1,
    uniqueItems = true,
    items       = {
        type = "string",
        enum = pdk.const.ALL_METHODS_ALL
    }
}

local enabled = {
    type = "boolean",
}

local client_max_body_size = {
    type = "number",
    minimum = 0,
    description = "Maximum request body size in bytes. 0 means unlimited. Can be specified with units like 'k' (kilobytes), 'm' (megabytes), 'g' (gigabytes)."
}

local chunked_transfer_encoding = {
    type = "boolean",
    description = "Enable or disable chunked transfer encoding. true = enable chunked encoding, false = disable chunked encoding (use Content-Length instead), nil = use default behavior."
}

local proxy_buffering = {
    type = "boolean",
    description = "Enable or disable proxy buffering. true = enable buffering (default), false = disable buffering (streaming mode)."
}

local proxy_cache_config = {
    type = "object",
    properties = {
        enabled = {
            type = "boolean",
            description = "Enable proxy cache. true = enable cache, false = disable cache."
        },
        cache_key = {
            type = "string",
            description = "Cache key template. Default: $scheme$proxy_host$request_uri. Can use variables like $host, $uri, $args, etc."
        },
        cache_valid = {
            type = "string",
            description = "Cache validity time. Format: 'time [status_code ...]'. Example: '200 302 10m', '404 1m', 'any 5m'"
        },
        cache_bypass = {
            type = "array",
            items = {
                type = "string"
            },
            description = "Conditions to bypass cache. Array of variable expressions. Example: ['$http_pragma', '$http_authorization']"
        },
        no_cache = {
            type = "array",
            items = {
                type = "string"
            },
            description = "Conditions to not cache. Array of variable expressions. Example: ['$http_pragma', '$http_authorization']"
        }
    },
    description = "Proxy cache configuration. If enabled=true, cache will be used. Other fields are optional."
}

local proxy_set_header_config = {
    type = "object",
    additionalProperties = {
        type = "string"
    },
    description = "Additional proxy headers to set. Key-value pairs where key is header name and value is header value. Can use Nginx variables like $host, $remote_addr, etc. Example: {'X-Custom-Header': 'value', 'X-Forwarded-Proto': '$scheme'}"
}

_M.created = {
    type       = "object",
    properties = {
        name     = common.name,
        methods  = {
            type        = "array",
            minItems    = 1,
            uniqueItems = true,
            items       = {
                type = "string",
                enum = pdk.const.ALL_METHODS_ALL
            },
            default     = { pdk.const.METHODS_ALL }
        },
        paths    = paths,
        headers  = headers,
        service  = common.items_object_name,
        plugins  = common.items_array_name_or_null,
        upstream = common.items_object_name,
        enabled  = {
            type    = "boolean",
            default = true
        },
        client_max_body_size = client_max_body_size,
        chunked_transfer_encoding = chunked_transfer_encoding,
        proxy_buffering = proxy_buffering,
        proxy_cache = proxy_cache_config,
        proxy_set_header = proxy_set_header_config
    },
    required   = { "name", "paths", "service" }
}

_M.updated = {
    type       = "object",
    properties = {
        router_key = common.param_key,
        methods    = methods,
        paths      = paths,
        headers    = headers,
        service    = common.items_object_id_or_name,
        plugins    = common.items_array_id_or_name_or_null,
        upstream   = common.items_object_id_or_name_or_null,
        enabled    = enabled,
        client_max_body_size = client_max_body_size,
        chunked_transfer_encoding = chunked_transfer_encoding,
        proxy_buffering = proxy_buffering,
        proxy_cache = proxy_cache_config,
        proxy_set_header = proxy_set_header_config
    },
    required   = { "router_key" }
}

_M.detail = {
    type       = "object",
    properties = {
        router_key = common.param_key
    },
    required   = { "router_key" }
}

_M.deleted = {
    type       = "object",
    properties = {
        router_key = common.param_key
    },
    required   = { "router_key" }
}

_M.router_data = {
    type       = "object",
    properties = {
        name     = common.name,
        methods  = methods,
        paths    = paths,
        headers  = headers,
        service  = common.items_object_name,
        plugins  = common.items_array_name_or_null,
        upstream = {
            type = "object"
        },
        enabled  = enabled,
        client_max_body_size = client_max_body_size,
        chunked_transfer_encoding = chunked_transfer_encoding,
        proxy_buffering = proxy_buffering,
        proxy_cache = proxy_cache_config,
        proxy_set_header = proxy_set_header_config
    },
    required   = { "name", "methods", "paths", "headers", "service", "upstream", "enabled" }
}

return _M
