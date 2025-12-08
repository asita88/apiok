local _M = {}

_M.schema = {
    type       = "object",
    properties = {
        match_rules = {
            type       = "object",
            properties = {
                path = {
                    type = "string"
                },
                method = {
                    anyOf = {
                        {
                            type = "string",
                            enum = { "GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD", "TRACE" }
                        },
                        {
                            type = "array",
                            items = {
                                type = "string",
                                enum = { "GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD", "TRACE" }
                            }
                        }
                    }
                },
                headers = {
                    type = "object",
                    additionalProperties = {
                        type = "string"
                    }
                }
            }
        },
        tags = {
            type = "object",
            additionalProperties = {
                type = "string"
            }
        }
    },
    required   = { "tags" }
}

return _M

