#!/bin/sh
# Remove acme-staging CA from Caddyfile, so Caddy gets production certs

sed -ri.bak 's/acme_ca/#acme_ca/' /usr/local/www/Caddyfile
service caddy reload
