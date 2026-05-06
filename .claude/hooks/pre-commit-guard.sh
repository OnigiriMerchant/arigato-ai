#!/bin/bash
# Sanity checks before commit: build green, no force-unwraps in new code.
# Fires as a PreToolUse hook on Bash commands containing 'git commit'.

set -e

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]+"' | sed 's/"command"[[:space:]]*:[[:space:]]*"\(.*\)"/\1/')

if [[ ! "$COMMAND" =~ git[[:space:]]+commit ]]; then
    exit 0
fi

# Check staged Swift files for force-unwraps in production code (non-test files)
STAGED=$(git diff --cached --name-only --diff-filter=AM 2>/dev/null | grep -E '\.swift$' | grep -v 'Tests/' || true)

if [ -z "$STAGED" ]; then
    exit 0
fi

VIOLATIONS=""
for FILE in $STAGED; do
    if [ -f "$FILE" ]; then
        # Look for force-unwraps: variable! followed by . or ; or end-of-line, but not !=
        # This is a heuristic, not perfect, but catches the common cases.
        MATCHES=$(grep -nE '[a-zA-Z_)\]]\!(\.|[[:space:]]|$|;|,|\))' "$FILE" 2>/dev/null | grep -v '!=' | head -5 || true)
        if [ -n "$MATCHES" ]; then
            VIOLATIONS="${VIOLATIONS}⚠️  $FILE:\n$MATCHES\n"
        fi
    fi
done

if [ -n "$VIOLATIONS" ]; then
    echo "🛑 force-unwrap(s) detected in production code:" >&2
    echo -e "$VIOLATIONS" >&2
    echo "Use guard/if-let or invoke @code-reviewer to confirm before commit." >&2
    # Exit 1 = warn but don't block (Claude can override). Exit 2 would block.
    exit 1
fi
