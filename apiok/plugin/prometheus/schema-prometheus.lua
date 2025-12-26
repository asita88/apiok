local _M = {}

_M.schema = {
    type       = "object",
    properties = {
        enabled = {
            type    = "boolean",
            default = true,
        },
    },
}

return _M

