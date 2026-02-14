#!/bin/bash
set -euo pipefail

# Only run in remote (Claude Code on the web) environments
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Install build-essential for C compilation (gcc, make, etc.)
if ! command -v gcc &> /dev/null; then
  apt-get update -qq && apt-get install -y -qq build-essential > /dev/null 2>&1
fi
