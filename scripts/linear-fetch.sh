#!/usr/bin/env bash
# Usage: linear-fetch.sh [RANGE]
# Prints one JSON line per Linear issue with activity since the range began, in the
# format linear.sh reads, using LINEAR_API_KEY from config.env. Each stateHistory
# entry carries the actor who made that change, taken from the issue's history.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/day-bounds.sh" "${1:-}"
: "${LINEAR_API_KEY:?LINEAR_API_KEY is not set in config.env}"

QUERY='query($since: DateTimeOrDuration!, $until: DateTimeOrDuration!, $after: String) {
  issues(first: 25, after: $after, includeArchived: true,
         filter: {updatedAt: {gte: $since}, createdAt: {lt: $until}}) {
    pageInfo { hasNextPage endCursor }
    nodes {
      identifier title createdAt completedAt canceledAt
      assignee { name } creator { name }
      comments(first: 100, filter: {createdAt: {gte: $since, lt: $until}}) {
        pageInfo { hasNextPage } nodes { createdAt user { name } }
      }
      stateHistory(first: 100) { pageInfo { hasNextPage } nodes { startedAt state { name } } }
      history(first: 100) {
        pageInfo { hasNextPage } nodes { createdAt updatedAt actor { name } toState { name } }
      }
    }
  }
}'

# Linear folds one person's changes made close together into a single history entry
# spanning createdAt..updatedAt, so a state change's actor is whoever owns the entry
# whose window covers it. Changes made by integrations have no actor.
SHAPE='.data.issues.nodes[] | . as $i
  | [.history.nodes[] | select(.toState and .actor)] as $h
  | {
      id: .identifier, title, createdAt, completedAt, canceledAt,
      assignee: .assignee.name, createdBy: .creator.name,
      stateHistory: [.stateHistory.nodes | sort_by(.startedAt)[] | .startedAt as $t | {
        state, startedAt,
        actor: ([$h[] | select(.createdAt[0:19] <= $t[0:19] and $t[0:19] <= .updatedAt[0:19]) | .actor.name] | first)
      }],
      comments: [.comments.nodes[] | {author: .user.name, createdAt}],
      truncated: (.comments.pageInfo.hasNextPage or .stateHistory.pageInfo.hasNextPage or .history.pageInfo.hasNextPage)
    }'

after=null
while :; do
  page="$(jq -n --arg q "$QUERY" --arg since "$SINCE" --arg until "$UNTIL" --argjson after "$after" \
      '{query: $q, variables: {since: $since, until: $until, after: $after}}' \
    | curl -sS https://api.linear.app/graphql \
        -H "Content-Type: application/json" -H "Authorization: $LINEAR_API_KEY" -d @-)"
  if jq -e '.errors' <<<"$page" >/dev/null; then
    jq -c '.errors' <<<"$page" >&2
    exit 1
  fi
  jq -c "$SHAPE" <<<"$page" | tee >(jq -r 'select(.truncated) | "warning: \(.id) has over 100 history or comment entries; oldest are missing" ' >&2)
  [ "$(jq -r '.data.issues.pageInfo.hasNextPage' <<<"$page")" = true ] || break
  after="$(jq '.data.issues.pageInfo.endCursor' <<<"$page")"
done
