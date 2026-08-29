# Inbox Zero Home Assistant add-on — orchestrator image.
#
# The add-on does not bundle Inbox Zero. Instead it runs the official pre-built
# image (ghcr.io/elie222/inbox-zero) plus embedded Postgres/Redis on the host
# Docker daemon via the add-on's Docker API access. This image only carries the
# Docker CLI, the Compose plugin and the startup script.

FROM alpine:3.20

RUN apk add --no-cache \
        bash \
        docker-cli \
        docker-cli-compose \
        jq \
        openssl \
        util-linux \
    && rm -rf /var/cache/apk/*

COPY run.sh /app/run.sh
COPY compose.yaml /app/compose.yaml

RUN chmod +x /app/run.sh

CMD ["/app/run.sh"]
