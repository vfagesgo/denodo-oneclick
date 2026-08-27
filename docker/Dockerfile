# denodo-oneclick — Docker install mode, hello-world placeholder
#
# This is a minimal stand-in for the real Denodo image. It only proves that
# install.sh can build and run a container with the expected configuration
# (parameters + license file). Replace the CMD below with the actual Denodo
# VDP install/startup once that work is scoped.
#
# Rollback: this file is additive (no prior Dockerfile existed). Tag builds
# so older images stay available, e.g.:
#   docker build -t denodo-oneclick:hello-world-v1 .

FROM alpine:3.20

# Non-secret build metadata only. Runtime config/secrets are passed via
# `docker run -e` / `--env-file` by install.sh, never baked into the image.
LABEL org.opencontainers.image.title="denodo-oneclick" \
      org.opencontainers.image.description="Hello-world placeholder for the Denodo one-click Docker install"

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
