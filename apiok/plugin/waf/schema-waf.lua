local _M = {}

_M.schema = {
    type = "object",
    properties = {
        enabled = {
            type = "boolean",
            default = true
        },
        ip_whitelist = {
            type = "object",
            properties = {
                enabled = {
                    type = "boolean",
                    default = true
                },
                ip_list = {
                    type = "array",
                    items = {
                        type = "string"
                    },
                    description = "IP whitelist, supports wildcard (e.g., 192.168.1.*)"
                }
            },
            required = { "enabled", "ip_list" }
        },
        ip_blacklist = {
            type = "object",
            properties = {
                enabled = {
                    type = "boolean",
                    default = true
                },
                ip_list = {
                    type = "array",
                    items = {
                        type = "string"
                    },
                    description = "IP blacklist, supports wildcard (e.g., 192.168.1.*)"
                }
            },
            required = { "enabled", "ip_list" }
        },
        rules = {
            type = "object",
            properties = {
                rule_list = {
                    type = "array",
                    items = {
                        type = "object",
                        properties = {
                            name = {
                                type = "string",
                                description = "Rule group name for logging"
                            },
                            conditions = {
                                type = "array",
                                items = {
                                    type = "object",
                                    properties = {
                                        patterns = {
                                            type = "array",
                                            items = {
                                                type = "string"
                                            },
                                            description = "Patterns to match (regex or exact match for method)"
                                        },
                                        match_type = {
                                            type = "string",
                                            enum = { "uri", "args", "header", "body", "all", "method", "request_size" },
                                            default = "all",
                                            description = "Where to match: uri, args, header (includes User-Agent), body, all, method, or request_size"
                                        },
                                        operator = {
                                            type = "string",
                                            enum = { "match", "not_match" },
                                            default = "match",
                                            description = "Operator: match or not_match"
                                        }
                                    },
                                    required = { "patterns", "match_type" }
                                }
                            },
                            action = {
                                type = "string",
                                enum = { "block", "log" },
                                default = "block"
                            }
                        },
                        required = { "conditions", "action" }
                    }
                }
            }
        }
    },
    required = { "enabled" }
}

return _M
