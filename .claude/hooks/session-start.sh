#!/bin/bash
set -e

PROJECT_NAME=$(basename "$(pwd)")
BRANCH=$(git branch --show-current 2>/dev/null || echo "no-git")
LAST_COMMIT=$(git log -1 --oneline 2>/dev/null || echo "no commits")
UNCOMMITTED=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
SWIFT_VERSION=$(swift --version 2>/dev/null | head -1 | grep -oE 'Swift version [0-9.]+' | head -1)
XCODE_VERSION=$(xcodebuild -version 2>/dev/null | head -1)

if [ "$UNCOMMITTED" -gt 0 ]; then
    STATUS_LINE="⚠️  $UNCOMMITTED uncommitted change(s)"
else
    STATUS_LINE="✅ working tree clean"
fi

{
    echo "📱 $PROJECT_NAME | branch: $BRANCH"
    echo "🔧 $XCODE_VERSION | $SWIFT_VERSION"
    echo "📝 last commit: $LAST_COMMIT"
    echo "$STATUS_LINE"
} >&2

cat << JSON
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Project: $PROJECT_NAME | Branch: $BRANCH | Last commit: $LAST_COMMIT | $STATUS_LINE"
  }
}
JSON
