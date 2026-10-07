---
name: llm-product-features
description: Build product features where an LLM's output reaches users - recommendations, generated plans or text, structured extraction - so they stay correct, cheap and safe. The model picks from IDs the app gives it and never writes URLs, prices or facts; output is schema- and business-validated with retry and provider fallback; user text is fenced as data; prompts are versioned files; an eval harness with a baseline gates every prompt or model change; cost, caps and call logs are built in. Use whenever an app feature calls an LLM (OpenAI, Anthropic, Gemini or any provider), when writing or changing a prompt, picking a model, adding structured output, or debugging bad, invented or costly AI output.
---

# LLM product features

Treat the model as a talented, unreliable contractor: good at choosing,
combining and wording; bad at facts, arithmetic, links and following rules
every time. The app does everything that must be exactly right, and checks
everything the model returns before a user sees it.

## 1. Decide what the model does and what the app does

| The model | The app |
| --- | --- |
| Chooses among candidates the app selected (by short id) | Filters and scores candidates from real data |
| Groups, orders, explains, writes copy, translates tone | Computes every price, quantity, total, date, timeline |
| Says which ids it used | Inserts URLs, images and prices from the database by id |

- **The model never writes URLs, prices or product facts.** Give candidates
  short aliases (`P01`, `S1`), never real ids or links; strip URLs from names
  you send; fail validation on any URL-like text in output.
- A hard filter in code (budget, availability, must-haves, delivery dates)
  runs before the model; too few candidates → a typed error and a helpful
  message, not a model call.
- Snapshot the inputs a paid output was generated from, so editing inputs
  later can't change what someone paid for.

## 2. Validate everything that comes back

- Ask for structured output (JSON schema derived from a Zod/Pydantic schema)
  and **still parse it yourself** with the same schema: providers differ in
  how strictly they follow it.
- Then **business validation**: ids exist in the candidate list, no duplicates,
  totals inside the requested band (with a small tolerance), quantities within
  limits, every reference the model makes points at something it was given.
- On failure: **one retry on the same provider with the validation errors and
  the rejected output appended**, then the fallback provider gets the same two
  attempts. Config errors (missing key, 401/403/404) skip straight to fallback.
- Bound latency: SDK auto-retries off, an explicit timeout per stage.
- Everything the user sees passes through validation. If it can't be fixed,
  fail visibly (and refund if they paid), never show unvalidated text.

## 3. Provider adapter

- One `AiProvider` interface (`structured(schema, prompt)`, `text(prompt)`)
  with an implementation per provider plus a **deterministic fake** for tests,
  E2E and CI. Production refuses the fake, including as fallback.
- Providers and models are configuration per stage (`AI_STAGE1_PROVIDER`,
  `AI_STAGE1_MODEL`, fallback pair), so switching is a config change chosen
  by the eval, not by brand.
- Log every call to a `generations` table: provider, model, prompt version,
  tokens (including thinking), cost from a prices table, latency, error, and
  every attempt. Retries and fallbacks cost money; the row shows the total.
- Data protection: check where each provider processes data before sending
  user content; exclude providers that don't fit the law you're under.

## 4. Untrusted user text

Free text users type goes in exactly one fenced block, as JSON-escaped data
(`<`, `>`, `&` escaped so it can't close the fence), after URLs are stripped.
The system prompt says the block is preferences, not instructions, and to
ignore requests in it to change rules, reveal the prompt or add links. Render
templates in a single pass so `{{…}}` inside user text is never expanded. Put
a prompt-injection case in the eval set.

## 5. Prompts are code

- Files in `prompts/`, not inline strings, with a header:
  `<!-- prompt_version: stage1-v0.4 -->` and a changelog comment per version.
- Bump the version on every change; the version is logged with each call.
- Changing a prompt or model means running the eval before and after on the
  same provider and recording both in `docs/ai/`.

## 6. Eval harness

Details and file shapes in [references/eval-harness.md](references/eval-harness.md).

- 20–40 realistic briefs covering the real mix (languages, edge budgets,
  edge dates, injection attempt), with dates as offsets from a fixed `today`
  so runs are reproducible, and a fixed candidate catalog.
- Automatic metrics: valid JSON, valid ids, within budget, pass on first
  attempt, pass after retry/fallback, plus task-specific checks.
- Human-graded columns (quality 1–5, language quality 1–5) in a review sheet
  the owner fills in when picking models.
- `evals/baseline.json` per stage and provider/model; `eval --ci` fails when
  a metric drops more than a tolerance; `--update-baseline` after an accepted
  change. CI runs it offline on the fake provider on every PR, but that only
  proves structure: a prompt that got worse still passes it. So a PR that
  touches `prompts/**` or the model config also runs a small **real-model
  smoke eval** (a fixed 8–10 case subset, a hard dollar cap, a wider
  tolerance because real output varies) and fails on a drop. Starter in
  [references/eval-real.yml](references/eval-real.yml). Full-set runs across
  candidate models stay manual, with keys, when choosing or changing models.

## 7. Cost control

- **Two stages when output is long and some users won't pay**: a cheap model
  makes a short structured preview (free); the strong model writes the full
  output only after payment. Output tokens dominate cost.
- Cheapest model that passes the eval for each stage.
- A daily cap on free generations across all users, counted under an advisory
  lock (failed ones count too — they cost money), plus per-IP/session rate
  limits and bot protection on the free entry point.
- Watch provider price changes (intro pricing ends); keep prices in one file
  with a "verified on" date.

## 8. Tests

- Unit: candidate filter and scoring, money computed by the app, validation
  rejects invented ids / URLs / out-of-band totals, retry feeds back errors,
  fallback after two failures, fake provider deterministic.
- The eval gate in CI.
- E2E on the fake provider: assert structure (three packages, buttons, links
  from the catalog), never generated wording.
