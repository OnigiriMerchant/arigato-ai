#!/bin/bash
# Runs after Claude edits or writes any file.
# Auto-formats Swift files via swiftformat and runs swiftlint for code-smell detection.

set -e

# Read hook input from stdin (Claude Code passes JSON)
INPUT=$(cat)

# Extract the file path that was just edited
FILE_PATH=$(echo "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]+"' | sed 's/"file_path"[[:space:]]*:[[:space:]]*"\(.*\)"/\1/')

# Only process .swift files
if [[ ! "$FILE_PATH" == *.swift ]]; then
    exit 0
fi

if [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

# Auto-format
if command -v swiftformat &>/dev/null; then
    swiftformat "$FILE_PATH" --quiet 2>/dev/null || true
fi

# Lint and surface issues to Claude (stderr is read by the agent)
if command -v swiftlint &>/dev/null; then
    LINT_OUTPUT=$(swiftlint --quiet --path "$FILE_PATH" 2>&1 | head -10)
    if [ -n "$LINT_OUTPUT" ]; then
        echo "🔍 swiftlint:" >&2
        echo "$LINT_OUTPUT" >&2
    fi
fi
