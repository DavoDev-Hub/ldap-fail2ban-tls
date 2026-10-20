import logging
import os
import time
from logging.handlers import RotatingFileHandler

import httpx
from typing import Annotated
from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.security import OAuth2AuthorizationCodeBearer
from jose import jwt, JWTError
from starlette.middleware.base import BaseHTTPMiddleware

KC_INTERNAL=os.getenv("KEYCLOAK_INTERNAL","http://keycloak:8080")
KC_PUBLIC=os.getenv("KEYCLOAK_PUBLIC","http://localhost:8081")
REALM=os.getenv("KEYCLOAK_REALM","cybersecurity")
CLIENT_ID=os.getenv("KEYCLOAK_CLIENT_ID","fastapi-api")
ISSUER=f"{KC_PUBLIC}/realms/{REALM}"
JWKS_URL=f"{KC_INTERNAL}/realms/{REALM}/protocol/openid-connect/certs"

oauth2_scheme=OAuth2AuthorizationCodeBearer(
    authorizationUrl=f"{ISSUER}/protocol/openid-connect/auth",
    tokenUrl=f"{ISSUER}/protocol/openid-connect/token",
    scopes={"openid":"OpenID Connect identity"},
)
app=FastAPI(title="LDAP + OAuth 2.0 / OIDC API",version="2.0.0")

# --- Log de acceso para Fail2Ban --------------------------------------------
# uvicorn manda su access log a stdout (igual que nginx), así que montamos
# un log propio a un archivo real para que Fail2Ban lo pueda vigilar.
LOG_DIR = "/var/log/ldap-api"
os.makedirs(LOG_DIR, exist_ok=True)

access_logger = logging.getLogger("access")
access_logger.setLevel(logging.INFO)
_handler = RotatingFileHandler(f"{LOG_DIR}/access.log", maxBytes=5_000_000, backupCount=2)
_handler.setFormatter(logging.Formatter("%(message)s"))
access_logger.addHandler(_handler)


class AccessLogMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        response = await call_next(request)
        ip = request.headers.get("x-forwarded-for", request.client.host if request.client else "-")
        ts = time.strftime("%d/%b/%Y:%H:%M:%S %z")
        access_logger.info(
            '%s - - [%s] "%s %s HTTP/1.1" %s',
            ip, ts, request.method, request.url.path, response.status_code,
        )
        return response


app.add_middleware(AccessLogMiddleware)

@app.get("/health")
def health(): return {"status":"ok"}

async def current_user(token: Annotated[str,Depends(oauth2_scheme)]):
    try:
        async with httpx.AsyncClient() as c:
            r=await c.get(JWKS_URL,timeout=5); r.raise_for_status()
            jwks=r.json()
        header=jwt.get_unverified_header(token)
        key=next((k for k in jwks["keys"] if k.get("kid")==header.get("kid")),None)
        if not key: raise HTTPException(401,"Signing key not found")
        return jwt.decode(token,key,algorithms=["RS256"],audience=CLIENT_ID,issuer=ISSUER)
    except (JWTError,httpx.HTTPError,StopIteration) as e:
        raise HTTPException(401,f"Invalid access token: {e}",headers={"WWW-Authenticate":"Bearer"})

@app.get("/api/profile")
async def profile(user: Annotated[dict,Depends(current_user)]):
    return {"message":"OAuth 2.0 access token accepted","subject":user.get("sub"),
            "username":user.get("preferred_username"),"email":user.get("email"),"issuer":user.get("iss")}
