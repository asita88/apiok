local _M = {}

_M.schema = {
    type = "object",
    properties = {
        enabled = {
            type = "boolean",
            default = true
        },
        uri_rewrite = {
            type = "object",
            properties = {
                type = {
                    type = "string",
                    enum = { "regex", "replace", "prefix", "suffix" }
                },
                value = {
                    oneOf = {
                        {
                            type = "object",
                            properties = {
                                pattern = {
                                    type = "string",
                                    minLength = 1
                                },
                                replacement = {
                                    type = "string"
                                },
                                flags = {
                                    type = "string"
                                }
                            },
                            required = { "pattern", "replacement" }
                        },
                        {
                            type = "object",
                            properties = {
                                from = {
                                    type = "string",
                                    minLength = 1
                                },
                                to = {
                                    type = "string"
                                }
                            },
                            required = { "from", "to" }
                        },
                        {
                            type = "object",
                            properties = {
                                remove = {
                                    type = "string"
                                },
                                add = {
                                    type = "string"
                                }
                            }
                        }
                    }
                }
            },
            required = { "type", "value" }
        },
        headers = {
            type = "object",
            additionalProperties = {
                oneOf = {
                    { type = "string" },
                    { type = "null" }
                }
            }
        },
        query_args = {
            type = "object",
            additionalProperties = {
                oneOf = {
                    { type = "string" },
                    { type = "number" },
                    { type = "null" }
                }
            }
        }
    },
    required = { "enabled" }
}

return _M

