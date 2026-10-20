#!/bin/sh
# Fully resets the lab: removes containers AND volumes, then rebuilds.
# Use this whenever you hit Keycloak's "Client not found" error - it almost
# always means the Postgres volume already existed, so Keycloak's
# `--import-realm` skipped importing keycloak/import/cybersecurity-realm.json
# on this run (it only auto-imports into an empty database).
set -eu

echo "Stopping stack and removing volumes (ldap, ldap config, keycloak db)..."
docker compose down -v

echo "Rebuilding and starting fresh..."
docker compose up -d --build

echo "Waiting for Keycloak to finish importing the realm..."
until docker compose logs keycloak 2>/dev/null | grep -qi "Imported realm cybersecurity\|Keycloak.*started"; do
  sleep 2
done

echo "Loading LDAP users..."
./load-ldap-users.sh

echo "Done. Verify the import with:"
echo "  docker compose logs keycloak | grep -i realm"
echo "Then open http://localhost:8000/docs and click Authorize."
