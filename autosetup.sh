#!/usr/bin/env bash

#install docker-compose via pip
virtualenv nerdz_venv
source nerdz_venv/bin/activate
pip install --upgrade docker-compose

#replace server_name in nginx-reverse-proxy with your server
cat nginx-reverse-proxy | sed "s/yourhost/$1/g" > nginx-reverse-proxy.custom
