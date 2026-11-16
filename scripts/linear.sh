#!/usr/bin/env bash
# Usage: linear.sh ISSUES.jsonl [DATE]
# ISSUES.jsonl holds one Linear get_issue result per line, verbatim, with fields
# id, title, assignee, createdBy, createdAt, completedAt, canceledAt, stateHistory,
# plus comments: [{author, createdAt}], one entry per comment on the issue.
# Moves count every state change that started that day, credited to the assignee
# (the creator when unassigned): Linear's stateHistory does not record who made the change.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
FILE="$1"
source "$DIR/day-bounds.sh" "${2:-}"

PRELUDE='
  def today: . != null and . >= $since and . < $until;
  def who: .assignee // .createdBy;
  . as $all
  | [$all[] | . as $i | .stateHistory[1:][] | select(.startedAt | today)
      | {who: ($i | who), to: .state.name}] as $moves
  | ($moves | map(.to) | unique) as $states
  | [$all[] | (.comments // [])[] | select(.createdAt | today) | .author] as $commenters
'

echo "Linear, $DAY ($TIMEZONE, $SINCE to $UNTIL)"
echo "Issues updated since day start: $(wc -l <"$FILE")"
echo

jq -sr --arg since "$SINCE" --arg until "$UNTIL" "$PRELUDE"' |
  ([$all[] | select(.createdAt | today) | .createdBy] + [$all[] | who] + $commenters | unique) as $people
  | (["person", "created", "commented", "moved"] + ($states | map("to " + .)) + ["completed", "canceled"] | @tsv),
    ($people[] as $p | [
      $p,
      ([$all[] | select((.createdAt | today) and .createdBy == $p)] | length),
      ([$commenters[] | select(. == $p)] | length),
      ([$moves[] | select(.who == $p)] | length)
    ] + ($states | map(. as $s | [$moves[] | select(.who == $p and .to == $s)] | length)) + [
      ([$all[] | select(who == $p and (.completedAt | today))] | length),
      ([$all[] | select(who == $p and (.canceledAt | today))] | length)
    ] | select(.[1:] | add > 0) | @tsv)
' "$FILE" | column -t -s $'\t'
echo

{
  printf 'person\tresult\tissue\ttitle\n'
  jq -sr --arg since "$SINCE" --arg until "$UNTIL" "$PRELUDE"' |
    ($all[] | select(.completedAt | today) | [who, "completed", .id, .title] | @tsv),
    ($all[] | select(.canceledAt | today) | [who, "canceled", .id, .title] | @tsv)
  ' "$FILE" | sort
} | column -t -s $'\t'
