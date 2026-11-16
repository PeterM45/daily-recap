#!/usr/bin/env bash
# Usage: source day-bounds.sh [DATE]
# DATE is anything GNU date reads (2026-11-13, yesterday, "last friday"); default today.
# Loads config.env (ORG, TIMEZONE) and sets DAY, SINCE and UNTIL (UTC ISO) for that
# calendar day in TIMEZONE, plus PEOPLE, the login-to-name map.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ ! -f "$ROOT/config.env" ]; then
  echo "Missing $ROOT/config.env: copy config.example.env and fill it in." >&2
  return 1 2>/dev/null || exit 1
fi
source "$ROOT/config.env"
PEOPLE="$ROOT/people.tsv"
[ -f "$PEOPLE" ] || PEOPLE=/dev/null

# macOS ships BSD date; GNU date from coreutils installs as gdate.
if command -v gdate >/dev/null; then date() { gdate "$@"; }; fi

DAY="$(TZ=$TIMEZONE date -d "${1:-today}" +%F)"
NEXT="$(date -d "$DAY + 1 day" +%F)"
SINCE="$(date -u -d "TZ=\"$TIMEZONE\" $DAY 00:00" +%FT%TZ)"
UNTIL="$(date -u -d "TZ=\"$TIMEZONE\" $NEXT 00:00" +%FT%TZ)"
export ORG TIMEZONE PEOPLE DAY SINCE UNTIL
