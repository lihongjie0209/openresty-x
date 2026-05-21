local cjson = require("cjson.safe")

ngx.say(cjson.encode({
    status = "ok",
    service = "openresty-allinone"
}))


