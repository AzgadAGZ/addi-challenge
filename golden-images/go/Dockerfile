FROM golang:1.26-bookworm AS builder
# Build stage - discarded in final image

FROM gcr.io/distroless/base-debian12:nonroot AS runtime
LABEL org.opencontainers.image.title="addi-go-base"
LABEL org.opencontainers.image.description="Hardened Go base image for Addi platform"
LABEL org.opencontainers.image.vendor="Addi Platform Engineering"
# security.cve-exceptions label is injected at build time by CI
# via --label security.cve-exceptions='[{"id":"CVE-...","pkg":"...","sev":"HIGH","status":"wont-fix"}]'
EXPOSE 8080
USER nonroot:nonroot
