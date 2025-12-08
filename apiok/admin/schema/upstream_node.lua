local constants = require "apiok.admin.dao.constants"
local common = require "apiok.admin.schema.common"

local _M = {}

local address = {
    type  = "string",
    anyOf = {
        {
            format = "ipv4"
        },
        {
            format = "ipv6"
        }
    }
}

local method_enum = {
    "",
    "GET",
    "POST",
    "HEADER",
    "OPTIONS"
}

local uri_pattern = "^\\/\\*?[0-9a-zA-Z-.=?_*/{}]+$"

local port = {
    type    = "number",
    minimum = 1,
    maximum = 65535,
}

local weight = {
    type    = "number",
    minimum = 1,
    maximum = 100,
}

local health = {
    type = "string",
    enum = { constants.UPSTREAM_NODE_DEFAULT_HEALTH, constants.UPSTREAM_NODE_DEFAULT_UNHEALTH }
}

local enabled = {
    type = "boolean",
}

local host = {
    type      = "string",
    maxLength = 150,
}

local method = {
    type = "string",
    enum = method_enum
}

local uri = {
    type      = "string",
    maxLength = 150,
    anyOf     = {
        {
            pattern = uri_pattern
        },
        {}
    }
}

local interval = {
    type    = "number",
    minimum = 0,
    maximum = 86400,
}

local timeout = {
    type    = "number",
    minimum = 0,
    maximum = 86400,
}

local http_statuses = {
    type = "array",
    items = {
        type = "number",
        minimum = 100,
        maximum = 599
    }
}

local successes = {
    type    = "number",
    minimum = 1,
    maximum = 254,
}

local failures = {
    type    = "number",
    minimum = 1,
    maximum = 254,
}

local tags = {
    type = "object",
    additionalProperties = {
        type = "string"
    }
}

_M.created = {
    type       = "object",
    properties = {
        name    = common.name,
        address = address,
        port    = {
            type    = "number",
            minimum = 1,
            maximum = 65535,
            default = constants.UPSTREAM_NODE_DEFAULT_PORT
        },
        weight  = {
            type    = "number",
            minimum = 1,
            maximum = 100,
            default = constants.UPSTREAM_NODE_DEFAULT_WEIGHT
        },
        health  = {
            type = "string",
            enum = { constants.UPSTREAM_NODE_DEFAULT_HEALTH, constants.UPSTREAM_NODE_DEFAULT_UNHEALTH }
        },
        check   = {
            type       = "object",
            properties = {
                enabled  = {
                    type    = "boolean",
                    default = constants.UPSTREAM_NODE_DEFAULT_ENABLED_FALSE,
                },
                tcp      = {
                    type    = "boolean",
                    default = constants.UPSTREAM_NODE_DEFAULT_ENABLED_TRUE,
                },
                method   = method,
                host     = host,
                uri      = uri,
                interval = {
                    type    = "number",
                    minimum = 0,
                    maximum = 86400,
                    default = constants.UPSTREAM_NODE_DEFAULT_INTERVAL
                },
                timeout  = {
                    type    = "number",
                    minimum = 0,
                    maximum = 86400,
                    default = constants.UPSTREAM_NODE_DEFAULT_TIMEOUT
                },
                healthy_http_statuses = http_statuses,
                healthy_successes = successes,
                unhealthy_http_statuses = http_statuses,
                unhealthy_http_failures = failures,
                unhealthy_tcp_failures = failures,
                unhealthy_timeouts = failures
            }
        },
        tags = tags
    },
    required   = { "name", "address", "port", "check" }
}

_M.updated = {
    type       = "object",
    properties = {
        upstream_node_key = common.param_key,
        name              = common.name,
        address           = address,
        port              = port,
        weight            = weight,
        health            = health,
        check             = {
            type       = "object",
            properties = {
                enabled  = enabled,
                tcp      = enabled,
                method   = method,
                host     = host,
                uri      = uri,
                interval = interval,
                timeout  = timeout,
                healthy_http_statuses = http_statuses,
                healthy_successes = successes,
                unhealthy_http_statuses = http_statuses,
                unhealthy_http_failures = failures,
                unhealthy_tcp_failures = failures,
                unhealthy_timeouts = failures
            }
        },
        tags = tags
    },
    required   = { "upstream_node_key" }
}

_M.upstream_node_data = {
    type       = "object",
    properties = {
        id      = common.id,
        name    = common.name,
        address = address,
        port    = port,
        weight  = weight,
        health  = health,
        check   = {
            type       = "object",
            properties = {
                enabled  = enabled,
                tcp      = enabled,
                method   = method,
                host     = host,
                uri      = uri,
                interval = interval,
                timeout  = timeout,
                healthy_http_statuses = http_statuses,
                healthy_successes = successes,
                unhealthy_http_statuses = http_statuses,
                unhealthy_http_failures = failures,
                unhealthy_tcp_failures = failures,
                unhealthy_timeouts = failures
            },
            required   = { "enabled", "interval", "timeout" }
        },
        tags = tags
    },
    required   = { "id", "name", "address", "port", "weight", "health", "check" }
}

_M.schema_ip = address

_M.schema_port = port

return _M