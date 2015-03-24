#!/bin/bash

wget http://nginx.org/download/nginx-1.6.2.tar.gz

tar xf nginx-1.6.2.tar.gz
cd nginx-1.6.2
./configure --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/run/nginx.pid \
    --lock-path=/run/nginx.lock \
    --http-client-body-temp-path=/var/lib/nginx/client-body \
    --http-proxy-temp-path=/var/lib/nginx/proxy \
    --http-fastcgi-temp-path=/var/lib/nginx/fastcgi \
    --http-uwsgi-temp-path=/var/lib/nginx/uwsgi \
    --http-scgi-temp-path=/var/lib/nginx/scgi \
    --user=http \
    --group=http \
    --with-http_ssl_module \
    --with-http_perl_module \
    --with-http_spdy_module \
    --with-ipv6 \
    --with-cc-opt='-O2 -g -pipe -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector --param=ssp-buffer-size=4 -m64 -mtune=generic' \
    --with-ld-opt='-Wl,-E'

make && make install
cd ..
rm -rf nginx-1.6.2*
