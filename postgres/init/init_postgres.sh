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
    CREATE EXTENSION pgcrypto;
EOSQL

# Set timezone to UTC and create extension pgcrypto

psql -v ON_ERROR_STOP=1 -U "nerdz" "nerdz" <<-EOSQL
ALTER DATABASE nerdz SET timezone = 'UTC';
EOSQL

# Initialize the db
psql -v ON_ERROR_STOP=1 -U "nerdz" "nerdz" < $schema

# Be sure that nerdz is the real owner of the db nerdz
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "nerdz" <<-EOSQL
    ALTER DATABASE nerdz OWNER to nerdz;
EOSQL
