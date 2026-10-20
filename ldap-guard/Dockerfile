FROM alpine:3.20

RUN apk add --no-cache iptables

COPY protect-ldaps.sh /protect-ldaps.sh
RUN chmod +x /protect-ldaps.sh

ENTRYPOINT ["/protect-ldaps.sh"]
