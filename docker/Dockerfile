FROM apiok-base:latest

WORKDIR /build

COPY Makefile /build/Makefile
COPY deps /build/deps
COPY scripts /build/scripts
COPY apiok /build/apiok
COPY bin /build/bin
COPY conf /build/conf
COPY resty /build/resty

RUN chmod +x /build/scripts/*.sh
RUN make OPENRESTY_VERSION=1.25.3.2 OPENRESTY_PREFIX=/opt/apiok/openresty build
RUN make deps && make install

RUN rm -rf /build/*
WORKDIR /opt/apiok

EXPOSE 80 443 8080

CMD ["/opt/apiok/openresty/nginx/sbin/nginx", "-p", "/opt/apiok/apiok", "-c", "/opt/apiok/apiok/conf/nginx.conf", "-g", "daemon off;"]
