# Local deployment

Four Domains on one machine, separated the way the federation design
describes: each is its own Server with its own database, its own API process
and its own hostname, and none can reach another's data.

| | 103mail.com | example.com | mail.acme.test | acme.test |
| --- | --- | --- | --- | --- |
| Browser | http://localhost:8001 | http://localhost:8002 | http://localhost:8003 | http://localhost:8004 |
| Federation hostname | `webmail.103mail.com` | `webmail.example.com` | `webmail.mail.acme.test` | `webmail.acme.test` |
| Test controls | `127.0.0.1:8081` | `127.0.0.1:8082` | `127.0.0.1:8083` | `127.0.0.1:8084` |
| Logins | `maurits@vdschee.nl` | `bob@example.com`, `carol@example.com` | `erin@mail.acme.test`, `carol@mail.acme.test` | `pete@acme.test`, `carol@acme.test` |
| Password | `password` | `password` | `password` | `password` |
| Data | a dump of your local `webmail` database | generated fixtures | generated fixtures | generated fixtures |

A fifth Domain, `peer.test`, is a scripted peer: an API and nginx with no
accounts anyone signs in to and no host ports. Envelopes signed with its key
can be sent as it to try forged, replayed and malformed traffic.

mail.acme.test is a Domain on a subdomain (RFC 4.1.1), and acme.test is its
parent, a separate Domain that shares nothing with it. Neither has a chat
proxy, because chat does not federate. acme.test's services are called
`*-parent`, because `*-acme` is mail.acme.test.

The end-to-end stories in `../webmail-e2e` run against a stack of their own
(`../webmail-e2e/stack`), built from the images this one builds, so the two can
run side by side.

Every account uses the password `password`, which is what `../webmail-legacy/syncdata.sh`
sets on a synced database.

## What runs

```
                    ┌─ web-103mail (nginx) ──── localhost:8001
                    │     bundle, /config.json, peer descriptor, TLS
  dom-103mail ──────┼─ api-103mail (Go) ─── data/103mail.com/webmail.db
                    └─ ws-103mail (ws2api, chat WebSockets)

                    ┌─ web-example (nginx) ──── localhost:8002
  dom-example ──────┼─ api-example (Go) ─── data/example.com/webmail.db
                    └─ ws-example (ws2api, chat WebSockets)

                    ┌─ web-acme (nginx) ─────── localhost:8003
  dom-acme ─────────┴─ api-acme (Go) ────── data/mail.acme.test/webmail.db

                    ┌─ web-parent (nginx) ───── localhost:8004
  dom-parent ───────┴─ api-parent (Go) ──── data/acme.test/webmail.db

  federation ─────── every web container, aliased to its real federation
                     hostname, plus every api container and every worker
```

Per Domain there is also a `worker-*` container. It drains that Domain's
federation outbox and sweeps the state that ages out with it. It is separate
from the API because delivery to a peer has a 72-hour retry budget and cannot
sit behind a user's compose (ADR 17).

Each Domain's database is an SQLite file in `data/{domain}/`, which its API and
worker both mount as `/data` (ADR 19). There is no database server: SQLite runs
in WAL mode with a busy timeout, so the two processes share the file safely.

`dom-*` are internal networks, so an API is reachable only from inside its own
Domain. The `federation` network is the only thing the two share: each web
container carries `webmail.{domain}` as a network alias, so `api-103mail`
resolves `webmail.example.com` in the cluster exactly as it would on the
internet. That is the path federated envelopes actually travel.

One hostname serves the client bundle, `/config.json`, the peer descriptor and
the REST API, so the bundle and the API share an origin and there is no
cross-origin handshake between them. That is required, not incidental: RFC 4.1
roots every protocol endpoint at `webmail.{domain}` and permits no other
hostname.

The browser on the host does not use those hostnames. Each web container also
serves its Domain over plain HTTP on port 8000, published as
`http://localhost:800N`. Browsers resolve `localhost` without `/etc/hosts` and
treat it as a secure context, so nothing has to be added to `/etc/hosts` and no
certificate has to be trusted. Only `/config.json` differs there: nginx points
its `apiBase` at the origin the browser used, which the client accepts for
loopback. Federation never takes this path; it stays on HTTPS between the
`webmail.{domain}` names on the `federation` network.

## Setup

Check out the sibling repositories next to this one:

    webmail/
      webmail-deploy/     this repository
      webmail-server/     the Go API, built as webmail-server:local
      webmail-client/     the React bundle in nginx, built as webmail-client:local

ws2api is built straight from its public GitHub repository. Then:

    docker compose up -d --build

and open http://localhost:8001 (103mail.com) or http://localhost:8002
(example.com). Nothing else is needed on the host: no `/etc/hosts` entries, no
trusted CA, and no local tools, because the `setup` service runs `setup.sh` in
a container before anything else starts.

`setup.sh` is idempotent. It generates a local CA and a certificate per
Federation hostname, an Ed25519 keypair and federation config per Domain, the
seed SQL, and one SQLite database per Domain. Re-running keeps what exists, so
pinned public keys do not move. The `setup` service runs as UID 1000 unless
`UID` and `GID` are exported, because everything it writes is bind-mounted.

`docker compose down` stops the stack. The databases are files and survive
that; `./setup.sh --reseed` (which needs `openssl`, `sqlite3` and `python3` on
the host) rebuilds them from the seed, discarding whatever the stack wrote.

To use images from a registry instead of building them, set
`WEBMAIL_SERVER_IMAGE`, `WEBMAIL_CLIENT_IMAGE`, `WEBMAIL_FAULTS_IMAGE` and
`WEBMAIL_MAILSINK_IMAGE`.

## Seed data

`seed/103mail.com.sqlite.sql` is a data-only dump of whatever `webmail` MySQL
database you have locally, so the 103mail Domain comes up with real threads,
calendars, chats and attachments. `mysql2sqlite.py` turns the dump into SQL
SQLite loads, and `lowercase.sql` then lowercases every stored address, since
the server compares them exactly (ADR 19). A row the schema refuses, such as a
subscription listed twice, is skipped. A statement that does not fit at all,
because the local database's schema has drifted, is skipped too, and `setup.sh`
lists what it skipped. `setup.sh` copies the attachment bytes out of
`../webmail-legacy/data/attachments` to go with it; they are copied rather than
bind-mounted, because the stack writes new attachments and should not write into
the directory the PHP backend reads.

`seed/example.com.sqlite.sql` is generated by `seed.sh` and holds two accounts, each
with a mailbox, inbox and alias, a mail thread, three meetings around today and
two direct chats. Two accounts because a live chat needs two people who can both
sign in, and chat is not federated. That is enough for every section of the client to show
something. Edit `seed.sh` and re-run `./setup.sh --reseed`, not the SQL.

If you have no local `webmail` database, `setup.sh` falls back to generating the
same fixtures for 103mail.com too.

## Chat

Chat is live over a WebSocket, not polled. Connections terminate in the `ws-*`
containers (ws2api) and never in the API, which is what keeps the API tier
stateless (ADR 13, ADR 18).

To see it, sign in as `bob@example.com` in one browser and `carol@example.com`
in another, both on http://localhost:8002, and open the chat they
share. A message typed in one appears in the other without a reload, and the
typing indicator shows in the header while the other is writing.

    docker compose logs -f api-example | grep chat

`/wsoverhttp/` is deliberately not proxied by nginx. It is authenticated only by
knowing a ClientId, which is safe for a proxy on the Domain's private network
and would not be on the internet.

The proxy exposes Prometheus metrics on its own port, reachable from inside the
Domain network:

    docker compose exec api-example wget -qO- http://ws:7001/

## Federation

It works. Composing from `bob@example.com` to `mevdschee@103mail.com` writes the
thread locally, returns to the browser immediately, and a worker carries the
signed envelope to the other Domain, which delivers it to the real mailbox. A
reply comes back onto the same thread on both sides. See ADR 17.

To watch it happen:

    sqlite3 data/example.com/webmail.db \
      "SELECT peer_domain, status, attempts, last_http_status FROM federation_outbox"
    docker compose logs -f worker-example

Each Domain's keypair is in `keys/`, generated by `setup.sh` and never checked
in. `domain/{domain}/federation.json` names the key file and is checked in,
because it holds no key material. The peer descriptor at
`/.well-known/webmail-federation` is rendered by the server from the key it
actually signs with, so the two cannot drift apart.

Each Domain advertises envelopes up to 36 MiB and attachments up to 25 MiB
(`maxEnvelopeBytes`, `maxAttachmentBytes`), and the API and nginx take request
bodies up to 48 MiB, so a file at the attachment limit fits on the wire in
base64. A file over the limit is refused when it is written, and one over a
peer's limit is bounced as `too_large` before it is sent (ADR 21).

To rotate a Domain's key, follow `../webmail-server/docs/runbooks/key-rotation.md`.

Only the Basic tier of the protocol is implemented. The Registrar extension and
everything built on it (shadow mailboxes, real-email addressing) is not, and
these Domains advertise `"registrar": false`.

`/config.json` is still a static file per Domain: it is client branding, and the
backend has no opinion about it.

## What is not here

**The certificates are not compliant.** RFC 9.2 requires a Web PKI certificate,
DV at minimum. These are signed by a local CA that only the Domains trust. A
peer implementing the RFC would refuse them, which is correct behaviour and not
a problem to work around locally.

**Email cannot leave.** Each API publishes outbound notifications to SNS as
in production, but `AWS_ENDPOINT_URL_SNS` points it at the `mailsink`
container, which captures them instead (`mailsink/`). No SES variables are set,
so the inbound webhook answers 503. The stack cannot mail a real person.

To read what every Domain has sent, newest last:

    curl http://127.0.0.1:8025/messages

`?after=N` lists only what came after message N. The sink keeps messages in
memory, so restarting it empties it.

**Test controls are on.** Each API serves the read-only controls of ADR 20 on
port 8081, reachable on the `federation` network at `control.webmail.{domain}`,
an alias of the Domain's API. They are published on the host as 8081 to 8084,
in the order of the table above:

    curl http://127.0.0.1:8082/control/envelopes
    curl http://127.0.0.1:8082/control/accounts
    curl http://127.0.0.1:8082/control/peers
    curl "http://127.0.0.1:8082/control/files?md5=..."
    curl "http://127.0.0.1:8082/control/threads?member=bob@example.com"

A production deployment must not set `WEBMAIL_CONTROL_ADDR`.

**Outages are staged from outside.** Every container carries a
`webmail.domain` label naming its Domain, which is how the end-to-end suite
takes a Domain down (`docker stop` on its containers) and brings it back. Each
worker's retry budget is `${RETRY_BUDGET_<DOMAIN>:-72h}`, for example
`RETRY_BUDGET_103MAIL_COM=2m docker compose up -d --no-deps --force-recreate
worker-103mail`, which a story uses to see a timeout in minutes. Anything
shorter than 72 hours is not conformant (RFC 6.4) and is for testing only. The
workers check every 10 seconds whether a peer they owe messages to is back
(`WEBMAIL_BACKFILL_PROBE`), where production uses 5 minutes, and drain their
outbox every second.

The faults, the federation config swap and the clock below exist for the
end-to-end stories, which now use their own copy of this stack. They are kept
here so a story's situation can be reproduced by hand.

**Faults can be staged.** Every Domain's nginx sends
`/api/v1/federation/inbound` through the `faults` container (`faults/`), which
passes it to that Domain's API unchanged unless a story arms a rule at
`http://127.0.0.1:8026/faults`: lose the answer to the next envelope, or
refuse with a given status and code. `DELETE /faults` clears every rule.

**A Domain's federation config can be swapped.** The api and worker of each
Domain mount `${FEDERATION_CONFIG_<DOMAIN>:-./domain/<domain>/federation.json}`.
A story writes a changed copy as `domain/<domain>/federation.e2e.json` (an
allowlist, a smaller attachment limit, a rotated key), recreates the two
containers with the variable set, and puts the original back afterwards.

**Time can be moved forward.** Every API and worker reads the time as the real
clock plus the offset in `clock/offset` (`WEBMAIL_CLOCK_FILE`), which
`setup.sh` creates as `0s`. The end-to-end suite moves it forward to let
retries, budgets and probes run out without waiting for them. All Domains
share it, so their timestamps stay comparable. It only ever moves forward; to
start over, rebuild the databases with `./setup.sh --reseed` and write `0s`.

## Checking it works

    curl http://localhost:8001/health
    curl http://localhost:8002/.well-known/webmail-federation

The same over the real hostname and TLS, the way a peer sees it:

    docker compose exec api-103mail curl --cacert /etc/webmail/certs/webmail-local-ca.crt \
      https://webmail.example.com/.well-known/webmail-federation

To sign in with an API call rather than the browser:

    curl -X POST http://localhost:8002/api/v1/auth/token \
      -H 'Content-Type: application/json' \
      -d '{"email":"bob@example.com","password":"password"}'

## Running the client against a bare server instead

For frontend work, `npm run dev` in `../webmail-client` is faster than a
rebuild. There is no backend on that origin to answer `/config.json`, so the
client falls back to a development config; point it at a locally running server:

    VITE_API_BASE=http://localhost:8080/api/v1 VITE_DOMAIN=103mail.com npm run dev

`http://localhost:5173` is already in the server's default
`WEBMAIL_ALLOWED_ORIGINS`.
