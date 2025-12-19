FROM apiok-base:latest

WORKDIR /build

COPY Makefile /build/Makefile
COPY deps /build/deps
COPY scripts /build/scripts

RUN chmod +x /build/scripts/*.sh

RUN OPENRESTY_VERSION=1.21.4.1 OPENRESTY_PREFIX=/usr/local/openresty make build-openresty

COPY apiok /build/apiok
COPY bin /build/bin
COPY conf /build/conf
COPY resty /build/resty

RUN make deps && make install

WORKDIR /build

EXPOSE 80 443 8080

CMD ["/usr/local/openresty/nginx/sbin/nginx", "-p", "/usr/local/apiok", "-c", "/usr/local/apiok/conf/nginx.conf", "-g", "daemon off;"]
