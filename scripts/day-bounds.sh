#!/usr/bin/env bash
# Usage: source day-bounds.sh [RANGE]
# RANGE is one day (2026-11-13, yesterday, "last friday": anything GNU date reads),
# FROM..TO with each end a day, or one of "this week", "last week" (Monday to Sunday),
# "this month", "last month", "last N days". Default today.
# Loads config.env and sets FROM and TO (inclusive local dates), LABEL, SINCE and
# UNTIL (UTC ISO bounds in TIMEZONE), plus PEOPLE, the login-to-name map.
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

day() { TZ=$TIMEZONE date -d "$1" +%F; }
# shift DATE N: DATE moved N days, counted from noon so DST changes can't skip a day.
shift_days() { TZ=$TIMEZONE date -d "@$(( $(TZ=$TIMEZONE date -d "$1 12:00" +%s) + $2 * 86400 ))" +%F; }

TODAY="$(day today)"
MONDAY="$(shift_days "$TODAY" $(( 1 - $(TZ=$TIMEZONE date +%u) )))"
MONTH_START="${TODAY:0:8}01"
RANGE="${1:-today}"
case "$RANGE" in
  *..*) FROM="$(day "${RANGE%%..*}")"; TO="$(day "${RANGE##*..}")" ;;
  "this week") FROM="$MONDAY"; TO="$TODAY" ;;
  "last week") FROM="$(shift_days "$MONDAY" -7)"; TO="$(shift_days "$MONDAY" -1)" ;;
  "this month") FROM="$MONTH_START"; TO="$TODAY" ;;
  "last month") TO="$(shift_days "$MONTH_START" -1)"; FROM="${TO:0:8}01" ;;
  "last "[0-9]*" days") N="${RANGE//[!0-9]/}"; FROM="$(shift_days "$TODAY" $(( 1 - N )))"; TO="$TODAY" ;;
  *) FROM="$(day "$RANGE")"; TO="$FROM" ;;
esac
if [[ "$FROM" > "$TO" ]]; then
  echo "Range starts after it ends: $FROM to $TO" >&2
  return 1 2>/dev/null || exit 1
fi

LABEL="$FROM"
[ "$FROM" = "$TO" ] || LABEL="$FROM to $TO"
SINCE="$(date -u -d "TZ=\"$TIMEZONE\" $FROM 00:00" +%FT%TZ)"
UNTIL="$(date -u -d "TZ=\"$TIMEZONE\" $(shift_days "$TO" 1) 00:00" +%FT%TZ)"
export ORG TIMEZONE PEOPLE FROM TO LABEL SINCE UNTIL
