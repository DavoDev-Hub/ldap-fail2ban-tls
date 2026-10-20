# LDAP + Keycloak + OAuth 2.0 / OIDC Lab

Complete Docker lab: OpenLDAP + phpLDAPadmin + Keycloak + PostgreSQL + FastAPI.

Architecture:
Browser/Swagger -> Keycloak :8081 -> OpenLDAP :389
Browser/Swagger -> Bearer token -> FastAPI :8000

## Start
```bash
docker compose up -d --build
./load-ldap-users.sh
```

## URLs
- phpLDAPadmin: http://localhost:8080
- Keycloak: http://localhost:8081
- FastAPI Swagger: http://localhost:8000/docs
- FastAPI health: http://localhost:8000/health
- Protected API: GET http://localhost:8000/api/profile

## Credentials
Keycloak admin: `admin` / `adminpassword`
LDAP admin DN: `cn=admin,dc=example,dc=com` / `adminpassword`
LDAP users: `alice` / `alice123`, `bob` / `bob123`

## OAuth/OIDC test
1. Start the stack and load LDAP users.
2. Open http://localhost:8000/docs.
3. Click **Authorize**.
4. Authenticate in Keycloak as `alice` / `alice123`.
5. Swagger receives an Authorization Code/PKCE token.
6. Call `GET /api/profile`.
7. FastAPI validates the JWT signature, issuer, and audience.

Keycloak realm: `cybersecurity`
OIDC client: `fastapi-api`

Keycloak federates users from:
`ldap://openldap:389`
with users under:
`ou=users,dc=example,dc=com`

## Reset everything
WARNING: deletes LDAP and Keycloak database data.
```bash
docker compose down -v
docker compose up -d --build
./load-ldap-users.sh
```
Or just run `./reset.sh`, which does all three steps for you.

## Troubleshooting: "We are sorry... Client not found."
This means the browser reached Keycloak for realm `cybersecurity` / client
`fastapi-api`, but that realm or client doesn't actually exist in Keycloak's
database yet.

**Root cause (almost always):** Keycloak's `start-dev --import-realm` only
imports `keycloak/import/cybersecurity-realm.json` the *first* time it boots
against an empty Postgres database. If you'd already run `docker compose up`
before (even once, even if it failed), the `keycloak_db` volume already
exists, so the import is silently skipped on later starts - the realm/client
you expect were never created.

**Fix:**
```bash
./reset.sh
```
This tears down the containers *and* volumes, rebuilds, and re-imports the
realm from scratch, then reloads the LDAP users.

**Verify the import actually happened:**
```bash
docker compose logs keycloak | grep -i realm
```
You should see a line confirming the `cybersecurity` realm was imported. You
can also check directly in the admin console at http://localhost:8081
(`admin` / `adminpassword`) under Realm settings, and confirm the
`fastapi-api` client exists under Clients in the `cybersecurity` realm.

## Getting a token with curl (no browser)
The Authorization Code flow (the Swagger **Authorize** button) needs a
browser - Keycloak returns an HTML login form, not something plain curl can
submit. For scripting/testing, the client has `directAccessGrantsEnabled:
true`, so you can use the Resource Owner Password grant instead:

```bash
curl -X POST http://localhost:8081/realms/cybersecurity/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=fastapi-api" \
  -d "username=alice" \
  -d "password=alice123" \
  -d "scope=openid"
```

This returns a JSON body with `access_token`. Use it against the API:

```bash
TOKEN=$(curl -s -X POST http://localhost:8081/realms/cybersecurity/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" -d "client_id=fastapi-api" \
  -d "username=alice" -d "password=alice123" -d "scope=openid" \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])")

curl http://localhost:8000/api/profile -H "Authorization: Bearer $TOKEN"
```

Password grants are enabled here only for local dev/testing convenience -
disable `directAccessGrantsEnabled` again (or don't use this in a real
environment) since it bypasses the browser-based login/consent screen.

You changed `keycloak/import/cybersecurity-realm.json`, so you must run
`./reset.sh` again for the updated client settings to actually import.

Other things to double check if the problem persists:
- You're opening http://localhost:8000/docs (not port 8081 directly) and
  clicking **Authorize** so the client_id is sent automatically.
- `docker compose ps` shows `keycloak` as healthy/running, not restarting.
- No other project on your machine left old volumes with the same names -
  run `docker volume ls | grep keycloak_db` to check for stale ones.

## Troubleshooting: "User returned from LDAP has null username" / login fails
If `docker compose logs keycloak` shows a `ModelException: User returned
from LDAP has null username!` when logging in or requesting a token, the
LDAP user federation provider is missing its attribute mappers. Hand-written
realm JSON (as opposed to one exported from a live, admin-console-configured
Keycloak) needs the `subComponents` under the LDAP provider explicitly -
without a `username` mapper telling Keycloak which LDAP attribute
(`uid`) maps to the Keycloak username, attribute lookups come back empty
even though the LDAP entry itself is found. This repo's realm file already
includes the required `username`, `first name`, `last name`, and `email`
mappers - if you're hitting this, run `./reset.sh` to make sure the current
file (with mappers) actually got imported, and check with:
```bash
docker exec keycloak cat /opt/keycloak/data/import/cybersecurity-realm.json \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['components']['org.keycloak.storage.UserStorageProvider'][0]['subComponents'])"
```
This should list four mappers, not an empty object.



## Cambio para el dashboard de favoritos
En `keycloak/import/cybersecurity-realm.json` se agregó `http://localhost:3000` a `webOrigins`
del cliente `fastapi-api`, para que el frontend pueda pedir el token (CORS).
Si ya habías levantado el stack, corre `./reset.sh` para que Keycloak re-importe el realm.
# ldap-fail2ban-tls
