nerdzeu/docker
==============

# Requirements

- Docker
- virtualenv
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

## nginx configuration

Now, execute

```sh
. autosetup.sh <yourhost>
```

`autosetup.sh` will
* automagically create a virtualenv and install docker-compose from the cheese shop (PyPI)
* create `nginx-reverse-proxy.custom`, which is an ad-hoc modified nginx-reverse-proxy with `<yourhost>` as `server_name`.

Please take your time to carefully review each modification using `git diff` (it works on submodules too, just `cd` into them).
In `nginx-reverse-proxy.custom`, you should not touch anything but the `server_name` if you find the script did not work.

On Debian you have the `/etc/nginx/sites-enabled/` folder where to put nginx-reverse-proxy.

```sh
cp nginx-reverse-proxy.custom /etc/nginx/sites-enabled/<yourhost>
```

On other distros you should put the configuration file where nginx can found it.

### Enable SSL on nginx

To enable SSL, you have to perform the following step:

```sh
# if you're using a different folder, you may want
# to update the ssl_certificate_* paths
#vim /etc/nginx/sites-enabled/<yourhost>
mkdir /etc/nginx/ssl
cp nginx/conf/certs/nerdz.* /etc/nginx/ssl/
```
In case you don't want SSL, or you already have your own SSL certificates, modify
every `ssl_certificate` directive with the path to your own SSL certs.

### Apply your modifications to nginx

Now, you can restart your nginx istance. On debian, just run `service nginx restart`. On other platforms, consult your system' man page.

## docker configuration

After you only have to run docker-composer (it can take a long time if your internet connection is slow).

Since we're using virtual env, you first have to

```sh
cd nerdz_venv
source bin/activate
```

Than you can run docker-compose

```sh
docker-compose up -d
```

If you don't want to run the container in detached mode, remove the `-d` (you'll see logs).

Otherwhise you can read the logs running `docker-compose logs`

When the installation is complete (see the logs of the docker_php container, when php-fpm started the setup is completed correctly), stop it with `ctrl-c` or `docker-compose stop`.  
You are now ready for a new round of configuration.

## camo configuration

[Camo](https://github.com/atmos/camo) is a nice proxy to serve HTTP images on HTTPS.  
It can be configured by environment variables, and they're read from `camo/env` file.
An example follows.
```sh
#put these in a file called `env` inside the camo submodule. 
export PORT=8081
export CAMO_KEY=<camokey>
```

## Nerdz site configuration

Now you _MUST_ edit `docker/php/env/nerdz.eu/class/config/index.php`:

* change `SITE_HOST` to `$yourhost-configured-on-nginx`   
  (otherwise referrer control won't let you do anything).
* change `CAMO_KEY` to `$camokey-configured-in-camo`

If you want (or need), you can change every other \_HOST contants. Please note that, if you did not set up a DNS entry for `STATIC_DOMAIN`, you may want to set it to `''`. If you did it, instead, you may want to set it as `'//static.<yourhost>'`: it will avoid some headaches later.

## Start docker again

Run `docker-compose` again.

```sh
docker-compose up -d
```

Now, your system should be up and running. Enjoy your shiny Nerdz installation!

# Troubleshooting

* _Everything went kaboom!_  
Please get out of Iran and try again.

* _CSS and stuff is not loaded!_  
Did you try to setup STATIC_DOMAIN to `''` or `'//static.<yourhost>'`?

* _My problem is not listed here!_  
Please, open an issue in the project issue tracker: we'll be more than happy to help you. In case you did find a solution and want to make it available to others, please modify the README and open a PR.


