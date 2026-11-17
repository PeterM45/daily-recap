---
name: daily-recap
description: Per-person numbers for a day, week or month of GitHub org activity and Linear ticket movement.
disable-model-invocation: true
---

Build a **recap** of a stretch of work: per person, what they did on GitHub (commits, pull requests, code reviews, PR comments) and in Linear (tickets created, commented on, moved, completed), across the GitHub org named in `config.env`. Every number comes from the scripts in `scripts/`. You run them and assemble their output; the counting is theirs.

The range is the argument, default today: one day (`2026-11-13`, `yesterday`, `last friday`), `FROM..TO`, `this week`, `last week`, `this month`, `last month` or `last N days`, always in the `TIMEZONE` from `config.env`. Pass it unchanged, quoted, to every script. If `config.env` is missing, the scripts say so: ask the user for their GitHub org and timezone and write it from `config.example.env`.

## Steps

1. **GitHub.** Start `scripts/github.sh "<range>"` and `scripts/prs.sh "<range>"` in the background: about a minute each for a day, several for a month. `github.sh` walks every branch of every org repo pushed since the range began, so commits that haven't reached `main` still count. `prs.sh` covers PRs opened and merged, reviews given on other people's PRs, and PR comments.

2. **Linear.** If `config.env` sets `LINEAR_API_KEY`, run `scripts/linear.sh "<range>"`: it fetches and tallies in seconds. Otherwise collect the issues through the Linear MCP: get the range start with `source scripts/day-bounds.sh "<range>" && echo $SINCE`, then dispatch one subagent with this brief, filling in `SINCE` and a JSONL path in your scratchpad:

   > Collect Linear issues into `<path>`. Call `list_issues` with `updatedAt: "<SINCE>"`, `includeArchived: true`, `limit: 250`, `fields: ["id"]`, following `cursor` until `hasNextPage` is false. For each id, call `get_issue` with `fields: ["id","title","assignee","createdBy","createdAt","completedAt","canceledAt","stateHistory"]` and `list_comments` with `issueId` (following `cursor`). Write each `get_issue` result to the file as one JSON line, verbatim, with one field added: `comments`, an array of `{"author": <author.name>, "createdAt": <createdAt>}` for every comment returned. Reply with only the path, the number of ids, and the file's line count.

   Done when the id count equals the line count. Then run `scripts/linear.sh --file <path> "<range>"`. The MCP route costs two calls per ticket, so past a few days tell the user it will be slow and that a `LINEAR_API_KEY` makes it instant.

3. **People.** Every script prints display names; the GitHub scripts map logins to names through `people.tsv` (format in `people.example.tsv`). A raw login or email in their output is someone new: add their row to `people.tsv` with their Linear display name, creating the file if needed, then rerun the GitHub scripts. Done when each person appears under one name across all outputs.

4. **Report.** Write the recap in chat:

   - a heading with the range
   - one summary table, a row per person from any output: commits, lines added and deleted, PRs opened, PRs merged, reviews given, PR comments, tickets created, ticket comments, tickets moved, tickets completed
   - per person beneath it: commits per repo, reviews by verdict, moves by target state, completed tickets as ID and title (for a range longer than a day, list them only for people with ten or fewer, otherwise give the count)
   - a PR reviews section from the `prs.sh` table: per PR, author and reviewers, review rounds, and the range's reviewer comments against the author's replies and fix commits. Tickets sitting In Review behind one of these PRs are being worked, not stalled
   - a cycle time section from the `prs.sh` table, next to the LinearB elite bands its header gives. Name how many of the merged PRs were reviewed: an unreviewed PR has no pickup or review stage, so a fast cycle time with few reviews means the review step is skipped, not quick. Treat a percentile over fewer than five PRs as an anecdote
   - one closing line: line counts leave out lockfiles and generated files; bot accounts are left out; ticket moves go to the person who made them, or, when an integration made them or the data came through the MCP, to the assignee (the creator when unassigned)

   Done when every number traces to a line of script output and every person in any output has a row.
