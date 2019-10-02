#!/usr/local/bin/bash
# Remove acme-staging CA from Caddyfile, so Caddy gets production certs

sed -ri.bak '/acme-staging/d' /usr/local/www/Caddyfile
service caddy restart
