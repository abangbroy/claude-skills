# Postmortem template

Blameless: describe what the system and process allowed, not who erred. Write
it within two working days, while the details are fresh. Keep it to a page.

```markdown
# Incident YYYY-MM-DD: <short, plain title>

- **Severity:** <money lost / data exposed / feature down / degraded>
- **Duration:** <start> to <end> (<N> min); detected by <alert | user | engineer> after <N> min
- **Impact:** <who, how many, what they saw; money and data affected, with numbers>

## Timeline (UTC)
- HH:MM  <what happened / what was seen>
- HH:MM  <what was done, by whom, with what result>

## Root cause
<One paragraph: the chain of events that made this possible. Ask "why" until
the answer is a missing safeguard, not a person.>

## What went well / what didn't
- Detection: <how fast, what would have been faster>
- Response: <what helped, what slowed us down>
- Luck: <anything that limited the damage by chance, not design>

## Durable changes
| Change | Type (test / alert / guard / hook / rule / runbook) | Owner | Due | PR |
| --- | --- | --- | --- | --- |
| <regression test for X> | test | | | |
| <alert when Y exceeds Z> | alert | | | |

## Follow-ups that are NOT done
<Be honest about what was deferred and the risk of leaving it.>
```

A postmortem with no row in "Durable changes" is a story, not a fix.
