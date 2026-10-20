FROM python:3.11-slim
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    fail2ban \
    iptables \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app ./app

COPY fail2ban/filter.d/http-flood.conf /etc/fail2ban/filter.d/http-flood.conf
COPY fail2ban/jail.d/ldap-api.conf /etc/fail2ban/jail.d/ldap-api.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8000

ENTRYPOINT ["/entrypoint.sh"]
