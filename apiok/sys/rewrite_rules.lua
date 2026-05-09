local ngx = ngx
local string_upper = string.upper
local type = type
local pairs = pairs
local tostring = tostring
local pdk = require("apiok.pdk")

local _M = {}

function _M.decode_rewrite_rules(val)
	if val == nil then
		return nil
	end
	if type(val) == "table" then
		return val
	end
	if type(val) ~= "string" or val == "" then
		return nil
	end
	local t = pdk.json.decode(val)
	if type(t) == "table" then
		return t
	end
	if type(t) == "string" and t ~= "" then
		local t2 = pdk.json.decode(t)
		if type(t2) == "table" then
			return t2
		end
	end
	pdk.log.warn("[rewrite_rules] rewrite_rules is not a JSON object")
	return nil
end

local function sync_matched_from_ngx(ok_ctx)
	local m = ok_ctx.matched
	if not m then
		return
	end
	m.uri = ngx.var.uri
	m.method = ngx.req.get_method()
end

local function get_rewrite_rules(ok_ctx)
	local sr = ok_ctx.config and ok_ctx.config.service_router
	if not sr or not sr.router then
		return nil
	end
	local rr = sr.router.rewrite_rules
	local decoded = _M.decode_rewrite_rules(rr)
	if decoded ~= nil then
		sr.router.rewrite_rules = decoded
		return decoded
	end
	if type(rr) == "string" then
		sr.router.rewrite_rules = nil
	end
	return nil
end

local function apply_replace(rr, ok_ctx)
	local rep = rr.replace
	if not rep or type(rep) ~= "table" then
		return
	end
	local from = rep.from
	local to = rep.to
	if type(from) ~= "string" or from == "" then
		return
	end
	if type(to) ~= "string" then
		to = ""
	end
	local cur = ngx.var.uri
	local new_uri = pdk.string.replace(cur, from, to)
	if new_uri ~= cur then
		ngx.req.set_uri(new_uri, false)
	end
	sync_matched_from_ngx(ok_ctx)
end

local function apply_proxy_rewrite(rr, ok_ctx)
	local pr = rr["proxy-rewrite"]
	if not pr or type(pr) ~= "table" then
		return
	end

	if pr.regex_uri and type(pr.regex_uri) == "table" and pr.regex_uri[1] and pr.regex_uri[2] then
		local new_uri, err = ngx.re.gsub(ngx.var.uri, pr.regex_uri[1], pr.regex_uri[2], "jo")
		if err then
			pdk.log.error("[rewrite_rules] proxy-rewrite regex_uri: " .. tostring(err))
		else
			ngx.req.set_uri(new_uri, false)
		end
	elseif pr.uri and pr.uri ~= "" then
		ngx.req.set_uri(pr.uri, false)
	end

	if pr.host and pr.host ~= "" then
		ngx.req.set_header("Host", pr.host)
	end

	if pr.method and pr.method ~= "" then
		pdk.request.set_method(string_upper(tostring(pr.method)))
	end

	if pr.headers and pr.headers.set and type(pr.headers.set) == "table" then
		for k, v in pairs(pr.headers.set) do
			if k then
				ngx.req.set_header(k, tostring(v))
			end
		end
	end

	if pr.scheme == "http" or pr.scheme == "https" then
		ngx.req.set_header("X-Forwarded-Proto", pr.scheme)
	end

	sync_matched_from_ngx(ok_ctx)
end

local function apply_redirect(rr)
	local rd = rr["redirect"]
	if not rd or type(rd) ~= "table" then
		return
	end

	if rd.http_to_https == true then
		if ngx.var.scheme == "http" then
			local code = tonumber(rd.ret_code) or 302
			return ngx.redirect("https://" .. ngx.var.host .. ngx.var.request_uri, code)
		end
	end

	if rd.uri and rd.uri ~= "" then
		local code = tonumber(rd.ret_code) or 302
		return ngx.redirect(rd.uri, code)
	end
end

function _M.apply_http_access(ok_ctx)
	local rr = get_rewrite_rules(ok_ctx)
	if not rr or type(rr) ~= "table" then
		return
	end

	apply_replace(rr, ok_ctx)
	apply_proxy_rewrite(rr, ok_ctx)
	apply_redirect(rr)
end

return _M
