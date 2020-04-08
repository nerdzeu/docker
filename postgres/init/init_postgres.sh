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
EOSQL

# Set timezone to UTC and create extension pgcrypto

psql "nerdz" "nerdz" <<-EOSQL
ALTER DATABASE nerdz SET timezone = 'UTC';
CREATE EXTENSION pgcrypto;
EOSQL

# Initialize the db
psql -U "nerdz" "nerdz" < $schema
