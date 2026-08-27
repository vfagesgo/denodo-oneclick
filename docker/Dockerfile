# denodo-oneclick — Docker install mode
#
# entrypoint.sh clones this repo and runs linux/install.sh inside the
# container. That script is written for (and tested on) Raspberry Pi OS,
# which is Debian-based and apt-driven, so the image is switched from
# Alpine to a Debian base to match: apt must exist, plus git (self-clone)
# and sudo + a non-root "denodo" user (linux/install.sh refuses to run as
# root and calls sudo throughout).
#
# Rollback: previous version used `alpine:3.20` with no extra packages/user.
# Revert with:
#   git log -- docker/Dockerfile   # find the prior commit
#   git checkout <commit> -- docker/Dockerfile

FROM debian:bookworm-slim

# Minimal bootstrap packages only. linux/install.sh installs everything else
# itself (postgres, java, nginx, etc.) — that's out of scope for the image.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      sudo \
      git \
      ca-certificates \
      curl \
    && rm -rf /var/lib/apt/lists/*

# linux/install.sh enforces "regular user + sudo" and is run via
# `sudo -H -u denodo` from entrypoint.sh, so that user must exist with
# passwordless sudo already set up.
RUN useradd -m -s /bin/bash denodo && \
    echo "denodo ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/denodo && \
    chmod 440 /etc/sudoers.d/denodo

# Non-secret build metadata only. Runtime config/secrets are passed via
# `docker run -e` / `--env-file` by install.sh, never baked into the image.
LABEL org.opencontainers.image.title="denodo-oneclick" \
      org.opencontainers.image.description="Denodo one-click Docker install (Debian base to match Raspberry Pi OS)"

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
