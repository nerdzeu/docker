# nerdzeu/docker

# Usage
```sh
docker pull nerdzeu/docker
docker run nerdzeu/docker
```

# Develop

```sh
docker build -t <name> .
docker run -P -it -v /var/run/dbus:/var/run/dbus -v /run/systemd:/run/systemd -v /etc/systemd/system:/etc/systemd/system <container id>
```

# Reverse proxy

```sh
apt-get install nginx dnsmasq
```
Add in nginx.conf

```conf
resolver 127.0.0.1;
server {
listen 80;

server_name primary.nerdz.eu;
set $dn "local.nerdz.eu";
location / {
        proxy_pass http://$dn;
        }
}
```

Start dnsmasq and nginx. Edit `/etc/hosts` according to your container IP.
