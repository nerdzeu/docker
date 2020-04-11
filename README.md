nerdzeu/docker
==============

Setup the whole NERDZ platform in a single step.

## Usage

```sh
git clone --recursive https://github.com/nerdzeu/docker
cd docker

# Do you want certificate TLS enabled and certbot support?
./autosetup.sh -s 1 -e <email> <domain>
# e.g. ./autosetup.sh -s 1 -e my@ema.il nerdz.eu

# Do you want to develo locally without using HTTPS
./autosetup.sh -s 0 <domain>
#e.g ./autosetup.sh -s 0 local.nerdz.eu
```

The autosetup script does everything for you.

- It exposes a nginx docker container on the 80 (and when https is enabled, also on the 443) of your host.
- It configures any other services (camo, nerdzcrush, php website, api).
- It creates a nerdz.service file you can use to enable nerdz at boot.

## Database migration

If you're a nerdz owner (so in short this paragraph is for me), then first you have to dump the old database using:

```
pg_dump -U nerdz -d nerdz -f v1_dump.pgsql
```

Then, put the file `v1_dump.pgsql` here `postgres/init/migrate/v1_dump.pgsql`.

On the first startup, if this file is present, the postgres container will read it, apply any change required to migrate v1 to v2.
