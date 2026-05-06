#!/bin/bash
# Scans for accidentally committed secrets BEFORE git commit.
# Fires as a PreToolUse hook on Bash commands containing 'git commit'.
# Exit 2 blocks the commit with a message Claude reads.

set -e

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]+"' | sed 's/"command"[[:space:]]*:[[:space:]]*"\(.*\)"/\1/')

# Only check git commit operations
if [[ ! "$COMMAND" =~ git[[:space:]]+commit ]]; then
    exit 0
fi

# Check staged files for secret patterns
STAGED=$(git diff --cached --name-only 2>/dev/null)
if [ -z "$STAGED" ]; then
    exit 0
fi

PATTERNS=(
    'sk-ant-[a-zA-Z0-9_-]{20,}'      # Anthropic API key
    'sk-proj-[a-zA-Z0-9_-]{20,}'     # OpenAI project key
    'sk-[a-zA-Z0-9_-]{40,}'          # Generic OpenAI key
    'AIza[a-zA-Z0-9_-]{30,}'         # Google API key
    'ya29\.[a-zA-Z0-9_-]+'           # Google OAuth token
    'github_pat_[a-zA-Z0-9_]{20,}'   # GitHub PAT
    'leap_[a-zA-Z0-9]{20,}'          # LEAP API key (best guess pattern)
)

FOUND=""
for FILE in $STAGED; do
    if [ -f "$FILE" ]; then
        for PATTERN in "${PATTERNS[@]}"; do
            MATCH=$(grep -E "$PATTERN" "$FILE" 2>/dev/null | head -1 || true)
            if [ -n "$MATCH" ]; then
                FOUND="${FOUND}❌ Possible secret in $FILE: ${MATCH:0:30}...\n"
            fi
        done
    fi
done

if [ -n "$FOUND" ]; then
    echo "🚨 SECRET DETECTED — commit blocked" >&2
    echo -e "$FOUND" >&2
    echo "Move the secret to .env (gitignored) or to iOS Keychain." >&2
    exit 2
fi
