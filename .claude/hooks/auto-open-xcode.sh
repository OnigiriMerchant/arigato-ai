#!/bin/bash
# SessionStart hook: ensure Xcode.app is running so the `xcode` MCP server
# (Apple's xcrun mcpbridge) can connect.
#
# Background: mcpbridge fatal-errors at startup if no Xcode process exists.
# This is by design — Apple's MCP server bridges to a running Xcode instance.
# Resolves V3 #50. Companion docs: CLAUDE.md "Xcode MCP server dependency".
#
# Tolerant of failure: never blocks Claude Code start. If Xcode is slow or
# fails to launch, mcpbridge fails for this session but Claude Code itself
# still works (XcodeBuildMCP is independent).

set -u

if pgrep -x Xcode >/dev/null 2>&1; then
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
XCODEPROJ="$(ls -d "$PROJECT_ROOT"/*.xcodeproj 2>/dev/null | head -1)"

if [ -z "$XCODEPROJ" ]; then
    exit 0
fi

open -a Xcode "$XCODEPROJ" >/dev/null 2>&1 &

for _ in $(seq 1 20); do
    if pgrep -x Xcode >/dev/null 2>&1; then
        sleep 2
        exit 0
    fi
    sleep 0.5
done

exit 0
