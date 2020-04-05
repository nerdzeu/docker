#!/usr/bin/env bash

usage() { echo "Usage: $0 [-s <ssl>] [-e <email>] domain" 1>&2; exit 1; }

# https://stackoverflow.com/a/51789677/2891324
function parse_yaml {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|,$s\]$s\$|]|" \
        -e ":1;s|^\($s\)\($w\)$s:$s\[$s\(.*\)$s,$s\(.*\)$s\]|\1\2: [\3]\n\1  - \4|;t1" \
        -e "s|^\($s\)\($w\)$s:$s\[$s\(.*\)$s\]|\1\2:\n\1  - \3|;p" $1 | \
   sed -ne "s|,$s}$s\$|}|" \
        -e ":1;s|^\($s\)-$s{$s\(.*\)$s,$s\($w\)$s:$s\(.*\)$s}|\1- {\2}\n\1  \3: \4|;t1" \
        -e    "s|^\($s\)-$s{$s\(.*\)$s}|\1-\n\1  \2|;p" | \
   sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)-$s[\"']\(.*\)[\"']$s\$|\1$fs$fs\2|p" \
        -e "s|^\($s\)-$s\(.*\)$s\$|\1$fs$fs\2|p" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p" | \
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]; idx[i]=0}}
      if(length($2)== 0){  vname[indent]= ++idx[indent] };
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) { vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, vname[indent], $3);
      }
   }'
}

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

getent group nerdz > /dev/null
if [[ $? -gt 0 ]]; then
    echo "[+] Creating the group nerdz with GID 7777."
    sudo groupadd -g 7777 nerdz
    echo "[+] Adding $USER to the nerdz group"
    sudo gpasswd -a $USER nerdz
fi

echo "[+] Ensure every volume on the host has the correct group and permission."
volumes_mapping=$(parse_yaml docker-compose.yml  |grep volume | cut -d= -f2)
for vol in ${volumes_mapping//\"}; do
    local_folder=$(echo $vol | cut -d: -f1)
    mkdir -p $local_folder
    sudo chown -R $USER:nerdz $local_folder
    sudo chmod -R 775 $local_folder
    sudo chmod g+s $local_folder
done


echo "[+] Creating a new virtualenv in ./venv"
if [ ! -d venv ]; then
    virtualenv -ppython3 venv
fi
source venv/bin/activate

echo "[+] Installing docker-compose in a virtualenv..."
pip install docker-compose==1.25.4

echo "[+] Configuring nginx to use $DOMAIN"

mv nginx/conf.d/nerdz.eu nginx/conf.d/$DOMAIN
mv nginx/conf.d/nerdz.eu.conf nginx/conf.d/$DOMAIN.conf

grep -rlZ "nerdz.eu" nginx/conf.d/$DOMAIN | xargs -0 -l sed -i -e "s/nerdz.eu/$DOMAIN/g"
sed -i -e "s/nerdz.eu/$DOMAIN/g" nginx/conf.d/$DOMAIN.conf

if (( $ENABLE_SSL )); then
    echo "[+] Certbot configuration..."
    bash init-letsencrypt.sh "$DOMAIN" "$EMAIL"
else
    # Remove all redirects if https is disabled
    begin_line=$(grep -n "HTTP->HTTPS" nginx/conf.d/$DOMAIN.conf  |cut -d: -f 1)
    end_line=$(wc -l nginx/conf.d/$DOMAIN.conf | awk '{ print $1 }')
    sed -i -e "$begin_line,$end_line s/^/#/" nginx/conf.d/$DOMAIN.conf
    # Remove all inclusion of ssl configuration
    sed -i -e "s!include conf.d/$DOMAIN/ssl_\(.*\).conf!#include conf.d/$DOMAIN/ssl_\1.conf!g" nginx/conf.d/$DOMAIN.conf
fi

# create one symlink per domain (with php code)
if [ "$DOMAIN" != "nerdz.eu" ]; then
    ln -s nerdz.eu php/websites/$DOMAIN
fi
for sub in www mobile static; do
    ln -s nerdz.eu php/websites/"$sub"."$DOMAIN"
done

echo "[+] Configuring nerdzcrush..."
cp nerdzcrush/mediacrush/MediaCrush/config.ini.sample nerdzcrush/mediacrush/MediaCrush/config.ini

if (( ! $ENABLE_SSL )); then
    sed -i -e "s/https/http/g" nerdzcrush/mediacrush/MediaCrush/config.ini
fi

sed -i -e "s/mediacru.sh/media.$DOMAIN/g" nerdzcrush/mediacrush/MediaCrush/config.ini
sed -i -e "s/redis-ip =.*$/redis-ip = redis/g" nerdzcrush/mediacrush/MediaCrush/config.ini

echo "[+] Configuring API..."

cp api/confSample.json api/runtime/config.json
sed -i -e "s/nerdz.eu/$DOMAIN/g" api/runtime/config.json
sed -i -e "s/127.0.0.1/postgres/g" api/runtime/config.json
sed -i -e 's#"NERDZPath".*#"NERDZPath"  : "/srv/http/nerdz.eu/",#g' api/runtime/config.json

echo "[+] Creating nerdz.service file in systemd/nerdz.service"
sed -i -e "s#auto-replace-me#$DIR#g" systemd/nerdz.service
echo
echo "Done."

echo "Start the containers with docker-compose up (-d to put it in background)"
echo "You can also use the systemd/nerdz.service file"
echo
