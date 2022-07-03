#!/usr/bin/env bash

schema=$(dirname $BASH_SOURCE[0])/create/schema.pgsql
v1dump=$(dirname $BASH_SOURCE[0])/migrate/v1_dump.pgsql
upgrade=$(dirname $BASH_SOURCE[0])/upgrade.pgsql

if [ ! -f "$schema" ] && [ ! -f "$v1dump" ] && [ ! -f "$upgrade" ]; then
    echo "Missing create/schema.pgsql and migrate/v1_dump.pgsql"
    echo "At least once is required."
    exit -1
fi

# create nerdz user and db
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE USER nerdz;
    CREATE DATABASE nerdz;
    GRANT ALL PRIVILEGES ON DATABASE nerdz TO nerdz;
    ALTER ROLE nerdz WITH PASSWORD 'nerdz';
    ALTER DATABASE nerdz OWNER to nerdz;
EOSQL


if [ -f "$upgrade" ]; then
    psql -v --username "$POSTGRES_USER" --dbname "nerdz" < "$upgrade"
    exit 0
fi
# If we have the v1_dump, we restore it and apply the migration script to convert it
# to nerdz v2
if [ -f "$v1dump" ]; then
    # Restore v1
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "nerdz" < "$v1dump"

    # Convert to v2
    db_patch=$(dirname $BASH_SOURCE[0])/migrate/patch.pgsql
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "nerdz" < "$db_patch"
elif [ -f "$v1dump" ]; then
    # Initialize the db, use superuser because we need to create extensions
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "nerdz" < "$schema"
fi

# Be sure that nerdz is the real owner of the db nerdz
# and timezone is UTC. Fix all the previleges
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "nerdz" <<-EOSQL
    ALTER DATABASE nerdz OWNER to nerdz;
    ALTER DATABASE nerdz SET timezone = 'UTC';
    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public to nerdz;
    GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public to nerdz;
    GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public to nerdz;
EOSQL
