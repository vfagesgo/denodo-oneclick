#!/usr/bin/env bash
set -euo pipefail

# Resolve paths relative to this script so data files can be found no matter
# what the caller's working directory is.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


## Creating AISDK Agents
cp -a $SCRIPT_DIR/ai-sdk/chatbot_agent/custom/. \
      /opt/denodo/denodo-aisdk/api/agents/custom/
chown -R denodo:denodo /opt/denodo/denodo-aisdk/api/agents/custom/