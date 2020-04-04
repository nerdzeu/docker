#!/usr/bin/env bash

usage() { echo "Usage: $0 [-s <ssl>] [-e <email>] domain" 1>&2; exit 1; }

ENABLE_SSL=0
EMAIL=""

while getopts ":s:e:" o; do
    case "${o}" in
        s)
            ENABLE_SSL=${OPTARG}
            ;;
        e)
            EMAIL=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ $# -lt 1 ]; then
    usage
fi

DOMAIN=$1
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "*** variables ***"
echo
echo "Doamin: $DOMAIN"
echo "Enable ssl: $(( ENABLE_SSL == 1 ))"
echo "Email $EMAIL"
echo "Cwd: $DIR"
echo

echo "[+] Creating a new virtualenv in ./venv"
if [ ! -d venv ]; then
    virtualenv -ppython3 venv
fi
source venv/bin/activate

echo "[+] Installing docker-compose in a virtualenv..."
pip install docker-compose==1.25.4

echo "[+] Putting your hostname ($DOMAIN) where needed..."

grep -rlZ "nerdz.eu" nginx/ | xargs -0 -l sed -i -e "s/nerdz.eu/$DOMAIN/g"

if (( $ENABLE_SSL )); then
    echo "[+] Certbot configuration..."
    bash init-letsencrypt.sh "$DOMAIN" "$EMAIL"
else
    # Remove all redirects if https is disabled
    begin_line=$(grep -n "HTTP->HTTPS" nginx/conf.d/nerdz.eu.conf  |cut -d: -f 1)
    end_line=$(wc -l nginx/conf.d/nerdz.eu.conf | awk '{ print $1 }')
    echo "start $begin_line "
    echo "end $end_line "
    sed -i -e "$begin_line,$end_line s/^/#/" nginx/conf.d/nerdz.eu.conf
fi

echo "[+] Creating nerdz.service file in systemd/nerdz.service"
sed -i -e "s#auto-replace-me#$DIR#g" systemd/nerdz.service
echo
echo "Done."
