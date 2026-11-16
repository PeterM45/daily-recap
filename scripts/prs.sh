#!/usr/bin/env bash
# Usage: prs.sh [DATE]
# Tallies that day's pull request activity across $ORG: PRs opened and merged
# (credited to the PR author), reviews submitted on someone else's PR, and comments
# (inline review comments plus conversation comments). Then lists every PR that got
# review activity that day, with its review rounds and the author's response.
# Bot accounts are left out.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/day-bounds.sh" "${1:-}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# TIMEZONE's UTC offset that day in seconds, so review rounds group by local date.
Z="$(TZ=$TIMEZONE date -d "$DAY 12:00" +%z)"
OFFSET=$(( ${Z:0:1}1 * (10#${Z:1:2} * 3600 + 10#${Z:3:2} * 60) ))

gh api -X GET search/issues --paginate -f q="org:$ORG is:pr updated:>=$SINCE" -f per_page=100 \
  -q '.items[] | "\(.repository_url | split("/") | last)\t\(.number)"' >"$TMP/prs"

# events.jsonl: one {type, who, at} per action. reviewed.jsonl: one row per PR that
# got a review or comment from someone other than its author that day.
while IFS=$'\t' read -r repo n; do
  base="repos/$ORG/$repo"
  gh api "$base/pulls/$n" >"$TMP/pr.json"
  gh api "$base/pulls/$n/reviews" --paginate | jq -s 'add // []' >"$TMP/reviews.json"
  { gh api "$base/pulls/$n/comments" --paginate; gh api "$base/issues/$n/comments" --paginate; } \
    | jq -s 'add // []' >"$TMP/comments.json"
  gh api "$base/pulls/$n/commits" --paginate | jq -s 'add // []' >"$TMP/commits.json"
  jq -nc --arg repo "$repo" --arg n "$n" --arg since "$SINCE" --arg until "$UNTIL" --argjson off "$OFFSET" \
    --slurpfile pr "$TMP/pr.json" --slurpfile reviews "$TMP/reviews.json" \
    --slurpfile comments "$TMP/comments.json" --slurpfile commits "$TMP/commits.json" '
    def today: . != null and . >= $since and . < $until;
    def human: .user.type != "Bot";
    $pr[0] as $p | $p.user.login as $author
    | ($reviews[0] | map(select(human and .user.login != $author and .submitted_at))) as $rv
    | ($comments[0] | map(select(human))) as $cm
    | ({type: "opened", who: $author, at: $p.created_at},
       (select($p.merged_at) | {type: "merged", who: $author, at: $p.merged_at}),
       ($rv[] | {type: ("review " + (.state | ascii_downcase)), who: .user.login, at: .submitted_at}),
       ($cm[] | {type: "comment", who: .user.login, at: .created_at})
       | {kind: "event"} + .),
      ([$rv[] | select(.submitted_at | today)] + [$cm[] | select((.created_at | today) and .user.login != $author)]
       | select(length > 0) | {
        kind: "reviewed",
        pr: "\($repo)#\($n)",
        title: $p.title[0:45],
        author: $author,
        reviewers: (map(.user.login) | unique),
        rounds: ($rv | map(select(.submitted_at < $until) | .submitted_at | fromdate + $off | todate[0:10]) | unique | length),
        reviewer_comments: ([$cm[] | select((.created_at | today) and .user.login != $author)] | length),
        author_replies: ([$cm[] | select((.created_at | today) and .user.login == $author)] | length),
        author_commits: ([$commits[0][] | select(.author.login == $author and (.commit.author.date | today))] | length),
        state: (if $p.merged_at then "merged" else $p.state end)
      })'
done <"$TMP/prs" >"$TMP/all.jsonl"

NAMES='($people | split("\n") | map(select(length > 0) | split("\t")) | map({key: .[0], value: .[1]}) | from_entries) as $names
  | def name: $names[.] // .;'

echo "Pull requests $ORG, $DAY ($TIMEZONE, $SINCE to $UNTIL)"
echo "PRs updated since day start: $(wc -l <"$TMP/prs")"
echo

jq -sr --rawfile people "$PEOPLE" --arg since "$SINCE" --arg until "$UNTIL" "$NAMES"'
  map(select(.kind == "event" and .at >= $since and .at < $until) | .who |= name)
  | (map(.type) | unique) as $types
  | (["person"] + $types | @tsv),
    (group_by(.who)[] | . as $mine | [.[0].who] + ($types | map(. as $t | [$mine[] | select(.type == $t)] | length)) | @tsv)
' "$TMP/all.jsonl" | column -t -s $'\t'
echo

echo "PR reviews (rounds = local days with a review, up to and including that day; other columns are that day only)"
jq -sr --rawfile people "$PEOPLE" "$NAMES"'
  (["pr", "title", "author", "reviewers", "rounds", "reviewer comments", "author replies", "author commits", "state"] | @tsv),
  (map(select(.kind == "reviewed")) | sort_by(-.reviewer_comments)[]
    | [.pr, .title, (.author | name), (.reviewers | map(name) | join(", ")), .rounds,
       .reviewer_comments, .author_replies, .author_commits, .state] | @tsv)
' "$TMP/all.jsonl" | column -t -s $'\t'
