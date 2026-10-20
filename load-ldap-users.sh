#!/bin/sh
set -eu

# Wait for the LDAP *service* to accept binds...
until docker exec openldap ldapwhoami -x -H ldap://localhost:389 -D "cn=admin,dc=example,dc=com" -w adminpassword >/dev/null 2>&1; do sleep 2; done

# ...then also wait for the actual database backend to be queryable. Right
# after container start, osixia/openldap can accept binds slightly before
# its backend/suffix is fully initialized, which can drop the connection
# mid-ldapadd and silently leave some entries missing.
until docker exec openldap ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=example,dc=com" -w adminpassword -b "dc=example,dc=com" -s base >/dev/null 2>&1; do sleep 2; done

docker cp ldap/users.ldif openldap:/tmp/users.ldif

# Retry a few times: -c (continuous) means one already-exists entry doesn't
# abort the whole batch, and retrying covers a connection drop mid-load.
attempt=1
max_attempts=5
until docker exec openldap ldapadd -c -x -H ldap://localhost:389 -D "cn=admin,dc=example,dc=com" -w adminpassword -f /tmp/users.ldif; do
  if [ "$attempt" -ge "$max_attempts" ]; then
    echo "ldapadd kept failing after $max_attempts attempts - continuing anyway (some entries may already exist)."
    break
  fi
  echo "ldapadd attempt $attempt failed, retrying in 2s..."
  attempt=$((attempt + 1))
  sleep 2
done

# Confirm the users we actually care about are present, rather than trusting
# ldapadd's exit code (which can be nonzero even on partial success).
missing=""
for u in alice bob; do
  if ! docker exec openldap ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=example,dc=com" -w adminpassword -b "ou=users,dc=example,dc=com" "(uid=$u)" 2>/dev/null | grep -q "^uid: $u$"; then
    missing="$missing $u"
  fi
done

if [ -n "$missing" ]; then
  echo "WARNING: these users are still missing from LDAP:$missing"
  echo "Re-run ./load-ldap-users.sh again, or check 'docker compose logs openldap'."
  exit 1
fi

echo "LDAP users loaded and verified: alice, bob."
