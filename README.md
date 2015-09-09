nerdzeu/docker
==============

# Requirements

- Docker
- docker-compose
- nginx (on the host)

# Usage

 Clone the repo and its submodules

```sh
git clone --recursive https://github.com/nerdzeu/docker
```
Enter into the repo (docker) folder.

```sh
cd docker
```

On Debian you have the `/etc/nginx/sites-enabled/` folder where to put nginx-reverse-proxy.

```sh
cp nginx-reverse-proxy /etc/nginx/sites-enabled/<yourhost>
```

On other distros you should put the configuration file where nginx can found it.

You _must_ configure the file (the server_name directive of each server block. Do not touch anything else).

After you only have to run docker-composer (it can take a long time if your internet connection is slow).

```sh
docker-compose up -d
```

If you don't want to run the container in detached mode, remove the `-d` (you'll see logs).

Otherwhise you can read the locks running `docker-composer logs`

When the installation is complete (see the logs of the docker_php container, when php-fpm started the setup is completed correctly).

Now you _MUST_ edit `docker/php/env/class/config/index.php` changing SITE_HOST to <yourhost> (otherwise referrer control won't let you do anything).

If you want you want (or need), you can change every other _HOST contants.
