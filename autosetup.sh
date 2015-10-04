#!/usr/bin/env bash

#install docker-compose via pip

echo "installing docker-compose in a virtualenv..."
virtualenv nerdz_venv
source nerdz_venv/bin/activate
pip install docker-compose

#replace server_name in nginx-reverse-proxy with your server
echo "putting your hostname ($1) into nginx-reverse-proxy"
cat nginx-reverse-proxy | sed "s/yourhost/$1/g" > nginx-reverse-proxy.custom

#automatically copy nginx-reverse-proxy.custom and certs to the right folders
echo "next steps will require sudo as nginx folder is owned by root (somehow)"
echo "copying your reverse proxy conf to /etc/nginx/sites-enabled/$1"
sudo cp nginx-reverse-proxy.custom /etc/nginx/sites-enabled/$1
echo "putting nerdz certs into nginx folders..."
sudo mkdir -p /etc/nginx/ssl
sudo cp nginx/conf/certs/nerdz.* /etc/nginx/ssl
