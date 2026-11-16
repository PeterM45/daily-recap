#!/usr/bin/env bash
# Usage: linear.sh [RANGE]                 fetch with LINEAR_API_KEY, then tally
#        linear.sh --file ISSUES.jsonl [RANGE]   tally issues collected another way
# ISSUES.jsonl holds one Linear get_issue result per line, verbatim, with fields
# id, title, assignee, createdBy, createdAt, completedAt, canceledAt, stateHistory,
# plus comments: [{author, createdAt}], one entry per comment on the issue.
# Moves count every state change in the range, credited to the actor who made it when
# a stateHistory entry names one (linear-fetch.sh adds them), else to the assignee,
# else the creator.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
if [ "${1:-}" = --file ]; then
  FILE="$2"
  shift 2
else
  FILE="$TMP/issues.jsonl"
  "$DIR/linear-fetch.sh" "${1:-}" >"$FILE"
fi
source "$DIR/day-bounds.sh" "${1:-}"

PRELUDE='
  def in_range: . != null and . >= $since and . < $until;
  def who: .assignee // .createdBy;
  . as $all
  | [$all[] | . as $i | .stateHistory[1:][] | select(.startedAt | in_range)
      | {who: (.actor // ($i | who)), to: .state.name}] as $moves
  | ($moves | map(.to) | unique) as $states
  | [$all[] | (.comments // [])[] | select(.createdAt | in_range) | .author] as $commenters
'

echo "Linear, $LABEL ($TIMEZONE, $SINCE to $UNTIL)"
echo "Issues with activity since the range began: $(wc -l <"$FILE")"
echo

jq -sr --arg since "$SINCE" --arg until "$UNTIL" "$PRELUDE"' |
  ([$all[] | select(.createdAt | in_range) | .createdBy] + [$all[] | who] + $commenters | unique) as $people
  | (["person", "created", "commented", "moved"] + ($states | map("to " + .)) + ["completed", "canceled"] | @tsv),
    ($people[] as $p | [
      $p,
      ([$all[] | select((.createdAt | in_range) and .createdBy == $p)] | length),
      ([$commenters[] | select(. == $p)] | length),
      ([$moves[] | select(.who == $p)] | length)
    ] + ($states | map(. as $s | [$moves[] | select(.who == $p and .to == $s)] | length)) + [
      ([$all[] | select(who == $p and (.completedAt | in_range))] | length),
      ([$all[] | select(who == $p and (.canceledAt | in_range))] | length)
    ] | select(.[1:] | add > 0) | @tsv)
' "$FILE" | column -t -s $'\t'
echo

{
  printf 'person\tresult\tissue\ttitle\n'
  jq -sr --arg since "$SINCE" --arg until "$UNTIL" "$PRELUDE"' |
    ($all[] | select(.completedAt | in_range) | [who, "completed", .id, .title] | @tsv),
    ($all[] | select(.canceledAt | in_range) | [who, "canceled", .id, .title] | @tsv)
  ' "$FILE" | sort
} | column -t -s $'\t'
