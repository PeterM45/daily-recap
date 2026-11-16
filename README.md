# daily-recap

A Claude Code skill that reports what each person on your team did over a day, week or month, in numbers, from GitHub and Linear.

Type `/daily-recap` (or `/daily-recap yesterday`, `/daily-recap "last week"`) and you get:

- one table with a row per person: commits, lines added and deleted, PRs opened and merged, reviews given, PR comments, Linear tickets created, commented on, moved and completed
- per person: commits by repo, reviews by verdict, ticket moves by target state, completed tickets
- a PR reviews section: each PR under review in the range, its review rounds, and the reviewer's comments next to the author's replies and fix commits

Shell scripts do all the counting, so the numbers don't depend on the model doing arithmetic. Claude runs the scripts and writes up the report.

## What it counts

- **Commits** on every branch of every repo in the org pushed in the range, deduplicated by SHA, so work that hasn't merged still counts. Merge commits are counted separately. Commits on branches deleted since can't be seen.
- **Lines** exclude lockfiles and generated files (Drizzle snapshots, `convex/_generated`, `routeTree.gen.ts`, `.snap`). Edit `GENERATED` in `scripts/github.sh` to match your stack.
- **PRs**: opened and merged count for the PR author. Reviews only count on someone else's PR. Comments include inline review comments and the conversation thread.
- **Linear**: tickets created, comments, state changes and completions. A state change counts for whoever made it. Changes made by an integration (say, GitHub moving a ticket to Done on merge) count for the assignee.
- Bot accounts are excluded.

## Requirements

- [Claude Code](https://claude.com/claude-code)
- [`gh`](https://cli.github.com) logged in with `repo` and `read:org` scopes
- `jq`, `curl`, and GNU `date` (on macOS: `brew install coreutils jq`; the scripts use `gdate` when it exists)
- For Linear, either a personal API key in `config.env` (fast, recommended) or the [Linear MCP server](https://linear.app/docs/mcp) connected in Claude Code. Without a key, Claude makes two MCP calls per ticket, which is fine for a day and slow for a month, and moves count for the assignee because the MCP doesn't say who made them.

Tested on Linux.

## Install

```sh
git clone https://github.com/PeterM45/daily-recap ~/.claude/skills/daily-recap
cd ~/.claude/skills/daily-recap
cp config.example.env config.env      # set ORG, TIMEZONE and optionally LINEAR_API_KEY
cp people.example.tsv people.tsv      # optional, see below
```

For a single project instead of every project, clone into `.claude/skills/daily-recap` inside that repo. `config.env` and `people.tsv` are gitignored.

`people.tsv` maps GitHub logins to the names people use in Linear, so each person gets one row instead of two. Without it, GitHub activity shows under logins. When someone new shows up, Claude adds their row for you.

## Use

```
/daily-recap                       # today
/daily-recap yesterday
/daily-recap 2026-11-13
/daily-recap "last week"           # Monday to Sunday
/daily-recap "this month"
/daily-recap "last 30 days"
/daily-recap 2026-10-01..2026-10-15
```

Days are calendar days in `TIMEZONE`. The scripts also run on their own:

```sh
scripts/github.sh "last week"
scripts/prs.sh "last week"
scripts/linear.sh "last week"      # needs LINEAR_API_KEY
```

On a small org, the GitHub scripts take about a minute for a day and a few minutes for a month. GitHub's API allows 5,000 requests an hour, roughly one per commit plus a few per PR.
