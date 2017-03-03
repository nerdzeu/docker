#!/usr/bin/env bash

#install docker-compose via pip

if [ $# -lt 1 ]; then
    echo "$0 <yourhost>"
    exit 1
fi

echo "[+] Installing docker-compose in a virtualenv..."
virtualenv nerdz_venv
source nerdz_venv/bin/activate
pip install docker-compose==1.7.0

echo "[+] Putting your hostname ($1) into nginx-reverse-proxy.custom"
cat nginx-reverse-proxy | sed "s/yourhost/$1/g" > nginx-reverse-proxy.custom

echo "[+] Creating nerdz.service.custom file"
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cat nerdz.service | sed "s#auto-replace-me#$DIR#g" > nerdz.service.custom

echo "[+] Moving custom service to systemd services path"
sudo cp nerdz.service.custom /lib/systemd/system/nerdz.service

echo "[+] Cofiguring PHP container"
DOCKER_GROUP=$(getent group docker | cut -d: -f3)
mkdir $DIR/php/env/
echo $DOCKER_GROUP > $DIR/php/env/DOCKER_GROUP

echo "[+] Enabling nerdz.service on boot"
sudo systemctl enable nerdz

echo "[+] Starting nerdz.service"
sudo systemctl start nerdz

echo "[+] Remember to move the ngnix-reverse-proxy.custom service file to your ngnix configuration folder"

