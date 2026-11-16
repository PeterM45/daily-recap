#!/usr/bin/env bash
# Usage: github.sh [DATE]
# Tallies every commit authored that day across all branches of all repos in $ORG,
# deduped by SHA. Prints per-person totals, then per-person-per-repo counts.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/day-bounds.sh" "${1:-}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A repo pushed before the day started cannot hold commits pushed during it.
gh api "orgs/$ORG/repos" --paginate \
  -q ".[] | select(.pushed_at >= \"$SINCE\") | .name" >"$TMP/repos"

while read -r repo; do
  gh api "repos/$ORG/$repo/branches" --paginate -q '.[].name' | while read -r branch; do
    gh api "repos/$ORG/$repo/commits?sha=$(jq -rn --arg b "$branch" '$b|@uri')&since=$SINCE&until=$UNTIL&per_page=100" \
      --paginate -q '.[].sha' | sed "s|^|$repo\t|"
  done
done <"$TMP/repos" | sort -u >"$TMP/shas"

# Merge commits count separately and carry no line stats: GitHub diffs them
# against the first parent, which would double-count the merged work.
# Lockfiles and generated files stay out of line counts; one Drizzle snapshot is ~6k lines.
GENERATED='(^|/)(pnpm-lock\.yaml|package-lock\.json|yarn\.lock|bun\.lockb?|[^/]*\.snap|routeTree\.gen\.ts)$|(^|/)(drizzle/meta|convex/_generated)/'
while IFS=$'\t' read -r repo sha; do
  gh api "repos/$ORG/$repo/commits/$sha" | jq -c --arg repo "$repo" --arg gen "$GENERATED" '
    (.files // [] | map(select(.filename | test($gen) | not))) as $f | {
      repo: $repo,
      who: (.author.login // .commit.author.email),
      merge: ((.parents | length) > 1),
      add: ($f | map(.additions) | add // 0), del: ($f | map(.deletions) | add // 0)
    }'
done <"$TMP/shas" >"$TMP/commits.jsonl"

echo "GitHub $ORG, $DAY ($TIMEZONE, $SINCE to $UNTIL)"
echo "Repos pushed: $(wc -l <"$TMP/repos")  Unique commits: $(wc -l <"$TMP/commits.jsonl")"
echo

NAMES='($people | split("\n") | map(select(length > 0) | split("\t")) | map({key: .[0], value: .[1]}) | from_entries) as $names
  | map(.who = ($names[.who] // .who))'

jq -sr --rawfile people "$PEOPLE" "$NAMES"' |
    (["person", "commits", "merges", "repos", "added", "deleted"] | @tsv),
    (group_by(.who) | sort_by(-length)[] | [
      .[0].who,
      (map(select(.merge | not)) | length),
      (map(select(.merge)) | length),
      (map(.repo) | unique | length),
      (map(select(.merge | not) | .add) | add // 0),
      (map(select(.merge | not) | .del) | add // 0)
    ] | @tsv)
' "$TMP/commits.jsonl" | column -t -s $'\t'
echo
jq -sr --rawfile people "$PEOPLE" "$NAMES"' |
    (["person", "repo", "commits"] | @tsv),
    (map(select(.merge | not)) | group_by([.who, .repo])[] | [.[0].who, .[0].repo, length] | @tsv)
' "$TMP/commits.jsonl" | column -t -s $'\t'
