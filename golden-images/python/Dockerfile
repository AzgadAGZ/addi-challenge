FROM python:3.14-alpine AS builder
RUN apk add --no-cache build-base libffi-dev
RUN pip install --no-cache-dir uv

FROM python:3.14-alpine AS runtime
LABEL org.opencontainers.image.title="addi-python-base"
LABEL org.opencontainers.image.description="Hardened Python base image for Addi platform"
LABEL org.opencontainers.image.vendor="Addi Platform Engineering"
RUN addgroup -g 65532 -S nonroot && adduser -u 65532 -S nonroot -G nonroot
RUN apk add --no-cache libffi tini
COPY --from=builder /usr/local/bin/uv /usr/local/bin/uv
USER nonroot:nonroot
ENTRYPOINT ["tini", "--"]
