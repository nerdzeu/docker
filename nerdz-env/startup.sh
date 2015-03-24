#!/usr/bin/env bash

export GOPATH=/srv/http/go
export PATH=$PATH:$GOPATH/bin

if [ ! -d /srv/http/nerdz.eu ]; then
    mkdir -p /srv/http/go
    cd /srv/http
    git clone --recursive https://github.com/nerdzeu/nerdz.eu.git
    git clone https://github.com/nerdzeu/nerdz-test-db.git
    go get -u github.com/nerdzeu/nerdz-api

    cd nerdz.eu
    composer install
fi

chown -R http:http /srv/http
/usr/bin/php-fpm -F
