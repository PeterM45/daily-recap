# daily-recap

A Claude Code skill that reports what each person on your team did in one day, in numbers, from GitHub and Linear.

Type `/daily-recap` (or `/daily-recap yesterday`) and you get:

- one table with a row per person: commits, lines added and deleted, PRs opened and merged, reviews given, PR comments, Linear tickets created, commented on, moved and completed
- per person: commits by repo, reviews by verdict, ticket moves by target state, completed tickets
- a PR reviews section: each PR under review that day, its review rounds, and the reviewer's comments next to the author's replies and fix commits

Shell scripts do all the counting, so the numbers don't depend on the model doing arithmetic. Claude fetches the Linear data, runs the scripts and writes up the report.

## What it counts

- **Commits** on every branch of every repo in the org pushed that day, deduplicated by SHA, so work that hasn't merged still counts. Merge commits are counted separately.
- **Lines** exclude lockfiles and generated files (Drizzle snapshots, `convex/_generated`, `routeTree.gen.ts`, `.snap`). Edit `GENERATED` in `scripts/github.sh` to match your stack.
- **PRs**: opened and merged count for the PR author. Reviews only count on someone else's PR. Comments include inline review comments and the conversation thread.
- **Linear**: tickets created, comments, state changes and completions in that day.
- Bot accounts are excluded.

One limit: Linear's state history doesn't record who moved a ticket, so a move counts for the ticket's assignee, or its creator when unassigned.

## Requirements

- [Claude Code](https://claude.com/claude-code)
- The [Linear MCP server](https://linear.app/docs/mcp) connected in Claude Code
- [`gh`](https://cli.github.com) logged in with `repo` and `read:org` scopes
- `jq`, and GNU `date` (on macOS: `brew install coreutils jq`; the scripts use `gdate` when it exists)

Tested on Linux.

## Install

```sh
git clone https://github.com/PeterM45/daily-recap ~/.claude/skills/daily-recap
cd ~/.claude/skills/daily-recap
cp config.example.env config.env      # set ORG and TIMEZONE
cp people.example.tsv people.tsv      # optional, see below
```

For a single project instead of every project, clone into `.claude/skills/daily-recap` inside that repo.

`people.tsv` maps GitHub logins to the names people use in Linear, so each person gets one row instead of two. Without it, GitHub activity shows under logins. When someone new shows up, Claude adds their row for you.

## Use

```
/daily-recap                 # today
/daily-recap yesterday
/daily-recap "last friday"
/daily-recap 2026-11-13
```

A day is a calendar day in `TIMEZONE`. The GitHub scripts take about a minute each on a small org; you can run them on their own:

```sh
scripts/github.sh yesterday
scripts/prs.sh yesterday
```
