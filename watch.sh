#!/bin/bash
# Rebuild the stack whenever ../webmail-server or ../webmail-client changes.
#
# Every Domain runs the same two images, webmail-server:local and
# webmail-client:local, so a change rebuilds the one image it touches and
# `docker compose up -d` then recreates every container that runs it. All
# Domains therefore stay on the same build. The databases are bind-mounted and
# survive. Open chat sockets reconnect on their own once the API is back.
#
# This is a rebuild, not hot module replacement: reload the browser tab after
# a client change. For HMR, use `npm run dev` in ../webmail-client (README.md).
#
# Usage:  ./watch.sh    (needs inotifywait: apt install inotify-tools)

set -euo pipefail
cd "$(dirname "$0")"

if ! command -v inotifywait >/dev/null; then
    echo "inotifywait is needed to watch for changes (apt install inotify-tools)" >&2
    exit 1
fi

# What each Dockerfile copies in. Anything else, such as tests or docs, does
# not change the image and is not watched.
SERVER=(../webmail-server/{go.mod,go.sum,Dockerfile,cmd,internal,schema})
CLIENT=(../webmail-client/{package.json,package-lock.json,tsconfig.json,vite.config.ts,index.html,Dockerfile,public,src})
# Changes arrive in bursts (an editor save, a git checkout), so wait until
# nothing has changed for this long before building.
QUIET=1

rebuild() {
    local service=$1 what=$2
    echo "── $(date +%T) $what changed, rebuilding"
    if docker compose build "$service" && docker compose up -d; then
        echo "── $(date +%T) $what is up"
    else
        echo "── $(date +%T) $what failed to build, still running the previous one" >&2
    fi
}

docker compose up -d --build
echo "── watching ../webmail-server and ../webmail-client, ctrl-c to stop"

inotifywait -m -q -r -e close_write,create,delete,move --format '%w%f' \
    --exclude '(_test\.go|~|\.swp|\.tmp)$' "${SERVER[@]}" "${CLIENT[@]}" |
while read -r path; do
    server=false client=false
    while :; do
        case $path in
            ../webmail-server/*) server=true ;;
            ../webmail-client/*) client=true ;;
        esac
        read -r -t "$QUIET" path || break
    done
    if $server; then rebuild api-103mail "server"; fi
    if $client; then rebuild web-103mail "client"; fi
done
