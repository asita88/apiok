use t::APIOK 'no_plan';

no_shuffle();
run_tests();

__DATA__

=== TEST 1: certificates created success (certificate name: test-nginx-certificate-created)
--- config
location /t {
    content_by_lua_block {
        local t = require("tools.request")

        local cert = t.read_file("t/certs/apiok.com.cer")
        local key =  t.read_file("t/certs/apiok.com.key")

        local code, message, body = t.test("/apiok/admin/certificates", ngx.HTTP_POST, {
            name = "test-nginx-certificate-created",
            snis = {
                "*.apiok.com"
            },
            cert = cert,
            key = key
        })

        ngx.status = code
        ngx.say(message)
    }
}
--- request
GET /t
--- response_body
OK
--- error_code chomp
200



=== TEST 2: certificates updated success (certificate name: test-nginx-certificate-created)
--- config
location /t {
    content_by_lua_block {
        local t = require("tools.request")

        local cert = t.read_file("t/certs/apiok.com.cer")
        local key =  t.read_file("t/certs/apiok.com.key")

        local code, message, body = t.test("/apiok/admin/certificates/test-nginx-certificate-created", ngx.HTTP_PUT, {
            name = "test-nginx-certificate-created",
            snis = {
                "*.apiok.com1"
            },
            cert = cert,
            key = key
        })

        ngx.status = code
        ngx.say(message)
    }
}
--- request
GET /t
--- response_body
OK
--- error_code chomp
200



=== TEST 3: certificates list success
--- config
location /t {
    content_by_lua_block {
        local t = require("tools.request").test

        local code, message, body = t("/apiok/admin/certificates", ngx.HTTP_GET)

        ngx.status = code
        ngx.say(message)
    }
}
--- request
GET /t
--- response_body
OK
--- error_code chomp
200



=== TEST 4: certificates detail success (certificate name: test-nginx-certificate-created)
--- config
location /t {
    content_by_lua_block {
        local t = require("tools.request").test

        local code, message, body = t("/apiok/admin/certificates/test-nginx-certificate-created", ngx.HTTP_GET)

        ngx.status = code
        ngx.say(message)
    }
}
--- request
GET /t
--- response_body
OK
--- error_code chomp
200



=== TEST 5: certificates deleted success (certificate name: test-nginx-certificate-created)
--- config
location /t {
    content_by_lua_block {
        local t = require("tools.request").test

        local code, message, body = t("/apiok/admin/certificates/test-nginx-certificate-created", ngx.HTTP_DELETE)

        ngx.status = code
        ngx.say(message)
    }
}
--- request
GET /t
--- response_body
OK
--- error_code chomp
200
