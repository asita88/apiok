local _M = {}

_M.name = {
    type      = "string",
    minLength = 3,
    maxLength = 35,
    pattern   = "^\\*?[0-9a-zA-Z-_.]+$",
}

_M.items_object_name = {
    type       = "object",
    properties = {
        name = _M.name,
    },
    required   = { "name" }
}

_M.items_array_name = {
    type        = "array",
    uniqueItems = true,
    minItems    = 1,
    items       = _M.items_object_name
}

_M.items_array_name_or_null = {
    type        = "array",
    uniqueItems = true,
    items       = _M.items_object_name
}

_M.param_key = _M.name

return _M
