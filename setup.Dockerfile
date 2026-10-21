# What setup.sh needs: openssl for the certificates and keys, sqlite3 for the
# databases, GNU date for the meeting times in seed.sh, and python3 for
# mysql2sqlite.py when there is a MySQL dump to convert.
FROM alpine:3.20
RUN apk add --no-cache bash coreutils openssl sqlite python3
