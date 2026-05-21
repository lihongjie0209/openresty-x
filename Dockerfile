FROM docker.m.daocloud.io/openresty/openresty:bullseye-fat

LABEL org.opencontainers.image.title="openresty-allinone"
LABEL org.opencontainers.image.description="OpenResty all-in-one image with common Lua plugins and hot reload support"

ENV DEBIAN_FRONTEND=noninteractive
ENV LUAROCKS_VERSION=3.11.1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    inotify-tools \
    liblua5.1-0-dev \
    libpcre3-dev \
    libssl-dev \
    lua5.1 \
    zlib1g-dev \
    && curl -fsSL "https://luarocks.org/releases/luarocks-${LUAROCKS_VERSION}.tar.gz" -o /tmp/luarocks.tar.gz \
    && tar -xzf /tmp/luarocks.tar.gz -C /tmp \
    && cd "/tmp/luarocks-${LUAROCKS_VERSION}" \
    && ./configure --with-lua=/usr --lua-version=5.1 \
    && make \
    && make install \
    && rm -rf /tmp/luarocks.tar.gz "/tmp/luarocks-${LUAROCKS_VERSION}" \
    && rm -rf /var/lib/apt/lists/*

RUN luarocks install lua-resty-http \
    && luarocks install lua-resty-cookie \
    && luarocks install lua-resty-jwt \
    && luarocks install lua-resty-kafka \
    && luarocks install pgmoon \
    && git clone --depth 1 https://github.com/bigplum/lua-resty-mongol.git /tmp/lua-resty-mongol \
    && make -C /tmp/lua-resty-mongol PREFIX=/usr/local/openresty install \
    && rm -rf /tmp/lua-resty-mongol \
    && luarocks install lua-resty-openssl \
    && luarocks install lua-resty-string \
    && opm get \
    bungle/lua-resty-session \
    bungle/lua-resty-template \
    firesnow/lua-resty-checkups \
    knyar/nginx-lua-prometheus \
    zmartzone/lua-resty-openidc \
    && printf '%s\n' \
    'local modules = {' \
    '    "resty.core",' \
    '    "resty.dns.resolver",' \
    '    "resty.http",' \
    '    "resty.cookie",' \
    '    "resty.jwt",' \
    '    "resty.kafka.producer",' \
    '    "pgmoon",' \
    '    "resty.limit.req",' \
    '    "resty.limit.conn",' \
    '    "resty.limit.count",' \
    '    "resty.mongol",' \
    '    "resty.redis",' \
    '    "resty.mysql",' \
    '    "resty.openssl",' \
    '    "resty.hmac",' \
    '    "resty.openssl.hmac",' \
    '    "resty.openidc",' \
    '    "resty.session",' \
    '    "resty.string",' \
    '    "resty.template",' \
    '    "resty.websocket.server",' \
    '    "resty.checkups",' \
    '    "resty.upload",' \
    '    "prometheus",' \
    '}' \
    'for _, module_name in ipairs(modules) do' \
    '    assert(require(module_name), "failed to load " .. module_name)' \
    'end' \
    'print("plugins ok")' \
    > /tmp/verify-plugins.lua \
    && /usr/bin/resty /tmp/verify-plugins.lua \
    && rm -f /tmp/verify-plugins.lua

RUN mkdir -p /etc/openresty/conf.d /etc/openresty/lua /var/log/openresty

COPY docker/openresty-entrypoint.sh /usr/local/bin/openresty-entrypoint.sh
COPY nginx/nginx.conf /etc/openresty/nginx.conf
COPY nginx/conf.d/default.conf /etc/openresty/conf.d/default.conf
COPY lua/health.lua /etc/openresty/lua/health.lua

RUN sed -i 's/\r$//' /usr/local/bin/openresty-entrypoint.sh \
    && chmod +x /usr/local/bin/openresty-entrypoint.sh

EXPOSE 80 443

ENTRYPOINT ["/usr/local/bin/openresty-entrypoint.sh"]
