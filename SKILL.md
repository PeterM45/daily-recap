---
name: daily-recap
description: Per-person numbers for one day of GitHub org activity and Linear ticket movement.
disable-model-invocation: true
---

Build a **recap** of one day's work: per person, what they did on GitHub (commits, pull requests, code reviews, PR comments) and in Linear (tickets created, commented on, moved, completed), across the GitHub org named in `config.env`. Every number comes from the scripts in `scripts/`. You fetch, run them, and assemble their output; the counting is theirs.

The day is the argument (`2026-11-13`, `yesterday`, `last friday`), default today, always a calendar day in the `TIMEZONE` from `config.env`. Pass it unchanged to every script. If `config.env` is missing, the scripts say so: ask the user for their GitHub org and timezone and write it from `config.example.env`.

## Steps

1. **GitHub.** Start `scripts/github.sh <day>` and `scripts/prs.sh <day>` in the background, about a minute each. `github.sh` walks every branch of every org repo pushed since the day began, so commits that haven't reached `main` still count. `prs.sh` covers PRs opened and merged, reviews given on other people's PRs, and PR comments.

2. **Linear.** While they run, get the day's start with `source scripts/day-bounds.sh <day> && echo $SINCE`, then dispatch one subagent with this brief, filling in `SINCE` and a JSONL path in your scratchpad:

   > Collect Linear issues into `<path>`. Call `list_issues` with `updatedAt: "<SINCE>"`, `includeArchived: true`, `limit: 250`, `fields: ["id"]`, following `cursor` until `hasNextPage` is false. For each id, call `get_issue` with `fields: ["id","title","assignee","createdBy","createdAt","completedAt","canceledAt","stateHistory"]` and `list_comments` with `issueId` (following `cursor`). Write each `get_issue` result to the file as one JSON line, verbatim, with one field added: `comments`, an array of `{"author": <author.name>, "createdAt": <createdAt>}` for every comment returned. Reply with only the path, the number of ids, and the file's line count.

   A comment bumps its issue's `updatedAt`, so this list catches every ticket commented on that day.

   Done when the id count equals the line count.

3. **Tally.** Run `scripts/linear.sh <path> <day>`.

4. **People.** Every script prints display names; the GitHub scripts map logins to names through `people.tsv` (format in `people.example.tsv`). A raw login or email in their output is someone new: add their row to `people.tsv` with their Linear display name, creating the file if needed, then rerun the GitHub scripts. Done when each person appears under one name across all outputs.

5. **Report.** Write the recap in chat:

   - a heading with the day
   - one summary table, a row per person from any output: commits, lines added and deleted, PRs opened, PRs merged, reviews given, PR comments, tickets created, ticket comments, tickets moved, tickets completed
   - per person beneath it: commits per repo, reviews by verdict, moves by target state, completed tickets as ID and title
   - a PR reviews section from the `prs.sh` table: per PR, author and reviewers, review rounds, and that day's reviewer comments against the author's replies and fix commits. Tickets sitting In Review behind one of these PRs are being worked, not stalled
   - one closing line: Linear doesn't record who moved a ticket, so moves go to the assignee (the creator when unassigned); line counts leave out lockfiles and generated files; bot accounts are left out

   Done when every number traces to a line of script output and every person in any output has a row.
