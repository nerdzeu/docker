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

After you only have to run docker-composer (it can take a long time if your internet connection is slow).

```sh
docker-compose up -d
```

If you don't want to run the container in detached mode, remove the `-d` (you'll see logs).

Otherwhise you can read the logs running `docker-composer logs`

When the installation is complete (see the logs of the docker_php container, when php-fpm started the setup is completed correctly).

Now you _MUST_ edit `docker/php/env/class/config/index.php` changing SITE_HOST to $yourhost-configured-on-nginx. (otherwise referrer control won't let you do anything).

Hint: set STATIC_DOMAIN to ''.

If you want (or need), you can change every other \_HOST contants.
