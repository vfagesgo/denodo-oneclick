#!/bin/sh
## Hello-world placeholder entrypoint for the denodo-oneclick Docker image.
## Confirms the container received its configuration correctly; does not
## install or run Denodo VDP yet.

echo "Hello World from Denodo one-click installer!"
echo ""
echo "Configuration received by the container:"
echo "  DENODO_SUPPORT_CI      = ${DENODO_SUPPORT_CI:-<unset>}"
echo "  DENODO_SUPPORT_SECRET  = ${DENODO_SUPPORT_SECRET:+<set>}"
echo "  DENODO_LIC             = $( [ -f /denodo/license.lic ] && echo 'mounted at /denodo/license.lic' || echo '<missing>')"
echo "  DENODO_UPDATE          = ${DENODO_UPDATE:-<unset>}"
echo "  DENODO_PG_USER         = ${DENODO_PG_USER:-<unset>}"
echo "  DENODO_PG_PWD          = ${DENODO_PG_PWD:+<set>}"
echo "  DENODO_VDP_USER        = ${DENODO_VDP_USER:-<unset>}"
echo "  DENODO_VDP_PWD         = ${DENODO_VDP_PWD:+<set>}"
echo "  CLOUDFLARE_TUNNEL_KEY  = ${CLOUDFLARE_TUNNEL_KEY:+<set>}"
