#!/usr/bin/env bash

if [ $# -lt 1 ]; then
    echo "$0 <YOUR_HOST>"
    exit 1
fi

if [ -z ${VIRTUAL_ENV+x} ]; then
    deactivate
fi

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "[+] Creating a new virtualenv in ./venv"
if [ ! -d venv ]; then
    virtualenv -ppython3.7 venv
fi
source venv/bin/activate

echo "[+] Installing docker-compose in a virtualenv..."
pip install docker-compose==1.25.4

echo "[+] Putting your hostname ($1) where needed..."

grep -rlZ "nerdz.eu" nginx/ | xargs -0 -l sed -i -e "s/nerdz.eu/$1/g"
sed -i -e "s/nerdz.eu/$1/g" init-letsencrypt.sh

echo "[+] Certbot configuration..."
./init-letsencrypt.sh

echo "[+] Creating nerdz.service file in systemd/nerdz.service"
sed -i -e "s#auto-replace-me#$DIR#g" systemd/nerdz.service
echo
echo "Done."
