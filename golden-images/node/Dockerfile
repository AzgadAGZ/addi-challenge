FROM node:26-alpine AS runtime
LABEL org.opencontainers.image.title="addi-node-base"
LABEL org.opencontainers.image.description="Hardened Node.js base image for Addi platform"
LABEL org.opencontainers.image.vendor="Addi Platform Engineering"
RUN addgroup -g 65532 -S nonroot && adduser -u 65532 -S nonroot -G nonroot
RUN apk add --no-cache tini
USER nonroot:nonroot
ENTRYPOINT ["tini", "--"]
