FROM base/archlinux
MAINTAINER Paolo Galeone <nessuno@nerdz.eu>

RUN sed -i -e 's#https://mirrors\.kernel\.org#http://mirror.clibre.uqam.ca#g' /etc/pacman.d/mirrorlist && pacman -Sy php \
       php-pgsql \
       php-pear \
       php-gd \
       php-fpm \
       php-composer \
       php-apcu \
       wget \
       git \
       postgresql \
       postgresql-libs \
       base-devel \
       nginx \
       libunistring --noconfirm

# build nginx with perl module enabled

COPY nginx_builder .
RUN chmod +x nginx_builder
RUN ./nginx_builder

# get nerdz.eu, templates and test-db

RUN mkdir /home/nginx && cd /home/nginx && \
    git clone --recursive https://github.com/nerdzeu/nerdz.eu.git && \
    git clone https://github.com/nerdzeu/nerdz-test-db.git

# php fpm and php config
COPY php-fpm.conf /etc/php/
COPY php.ini /etc/php/
RUN echo "extension=apcu.so" >  /etc/php/conf.d/apcu.ini

# setting up nerdz

RUN cd /home/nginx/ && mkdir certs logs && cd nerdz.eu && composer install

COPY config.php /home/nginx/nerdz.eu/class/config/index.php

COPY certs /home/nginx/certs

RUN chown -R http:http /home/nginx

# begin postgres configuration

USER postgres
RUN initdb --locale en_US.UTF-8 -E UTF8 -D '/var/lib/postgres/data' && \
    pg_ctl -D /var/lib/postgres/data -l /dev/null start && sleep 4 && \
    psql -U postgres --command "CREATE USER test_db  WITH SUPERUSER PASSWORD 'db_test';" && \
    createdb -O test_db test_db && \
   ./home/nginx/nerdz-test-db/initdb.sh postgres test_db db_test

USER root
COPY nginx_conf/* /etc/nginx/

RUN echo "127.0.0.1 local.nerdz.eu static.local.nerdz.eu mobile.local.nerdz.eu" >> /etc/hosts

EXPOSE 80
EXPOSE 443
EXPOSE 5432

ENTRYPOINT /usr/bin/nginx -g 'pid /run/nginx.pid; error_log stderr;' && \
    su - postgres -c 'pg_ctl -D /var/lib/postgres/data -l /dev/null start' && \
    /usr/bin/php-fpm --pid /run/php-fpm/php-fpm.pid && /bin/bash
