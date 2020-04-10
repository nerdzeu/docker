#!/usr/bin/env bash

schema=$(dirname $BASH_SOURCE[0])/schema.sql
if [ ! -f "$schema" ]; then
    echo "Missing schema.sql"
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

# Initialize the db, use superuser because we need to create extensions
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "nerdz" < $schema

# Be sure that nerdz is the real owner of the db nerdz
# and timezone is UTC
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    ALTER DATABASE nerdz OWNER to nerdz;
    ALTER DATABASE nerdz SET timezone = 'UTC';
EOSQL
