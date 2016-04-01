#!/usr/bin/env bash

#install docker-compose via pip

if [ $# -lt 1 ]; then
    echo "$0 <yourhost>"
    exit 1
fi

echo "[+] Installing docker-compose in a virtualenv..."
virtualenv nerdz_venv
source nerdz_venv/bin/activate
pip install docker-compose==1.6.2

#replace server_name in nginx-reverse-proxy with your server
echo "[+] Putting your hostname ($1) into nginx-reverse-proxy.custom"
cat nginx-reverse-proxy | sed "s/yourhost/$1/g" > nginx-reverse-proxy.custom
echo "[+] creating nerdz.service.custom file"
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cat nerdz.service | sed "s#auto-replace-me#$DIR#g" > nerdz.service.custom

echo "[+] Done."
echo 
echo "Now you have to follow the README. Thus configure the php backend, camo and nerdzcrush"

#automatically copy nginx-reverse-proxy.custom and certs to the right folders
#echo "next steps will require sudo as nginx folder is owned by root (somehow)"
#echo "copying your reverse proxy conf to /etc/nginx/sites-enabled/$1"
#sudo cp nginx-reverse-proxy.custom /etc/nginx/sites-enabled/$1
#echo "putting nerdz certs into nginx folders..."
#sudo mkdir -p /etc/nginx/ssl
#sudo cp nginx/conf/certs/nerdz.* /etc/nginx/ssl

echo "[+] Moving custom service to systemd services path"
sudo cp nerdz.service.custom /lib/systemd/system/nerdz.service

echo
echo "[+] Enabling nerdz.service"
sudo systemctl enable nerdz
echo
