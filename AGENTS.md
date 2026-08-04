# The Forester's Forecast — Project Memory

## What this is

A Quarto **website** project (not a data-analysis project) for *The
Forester's Forecast*, a podcast/interview series about forest biometrics
hosted by Micky G. Allen II. The site is built with Quarto (`_quarto.yml`,
`project: type: website`) using the `cosmo` theme plus a custom `_brand.yml`
and `styles.css`.

## Site structure

| File | Purpose |
|---|---|
| `index.qmd` | Home page — short description of the show and host. |
| `episodes.qmd` | Renders episode cards for the flagship series "The Forester's Forecast". |
| `grad-student-spotlight.qmd` | Renders episode cards for the "Grad Student Spotlight" series. |
| `band-of-biometricians.qmd` | Renders episode cards for the "A Band of Biometricians" series. |
| `about.qmd` | About page. |
| `_quarto.yml` | Site/navbar config, theme (`cosmo` + `brand`), `styles.css`. |
| `_brand.yml` | Brand colors/styling (see also `Foresters_Forecast_Brand_Colors.docx`). |

## Episode data pipeline

- **`episodes/episodes.yml`** is the single source of truth for all episode
  metadata across all three series. Each entry has: `title`, `series` (one
  of `"The Forester's Forecast"`, `"Grad Student Spotlight"`, `"A Band of
  Biometricians"`), `order` (position within its series), `date`,
  `youtube_id` (the YouTube video ID), `spotify_id` (Spotify episode ID),
  and `description`.
- **`episodes/render_episodes.R`** has shared helper functions
  (`load_episodes()`, `render_episode_card()`, `render_series()`) used by
  all three episode-listing `.qmd` pages to read `episodes.yml` and emit
  raw HTML/markdown episode cards (thumbnail, YouTube/Spotify links,
  description).
- Important formatting note baked into the render script: raw HTML lines
  must stay flush-left (no leading spaces) and each link wrapped in its own
  `<div>`, otherwise Pandoc misreads indented lines as code blocks.
- To refresh `episodes.yml` with new episodes, the intent (per a comment in
  the file) is to re-run a fetch script against the YouTube Data API v3
  (channel handle `@TheForestersForecast-wb3jl`) — no such fetch script
  currently exists in the repo; entries have so far been added manually.

## Home page "Latest Episodes" feature

`index.qmd` now has a "Latest Episodes" section (below the existing intro
paragraphs) that embeds the most recently *dated* episode from each of the
three series as a responsive YouTube player. This is powered by three new
helper functions added to `episodes/render_episodes.R`:

- `get_latest_episode(episodes, series_name)` — filters episodes to
  `series_name` and returns the one with the max `as.Date(date)` (NOT the
  max `order` — a couple of entries have `order` that doesn't perfectly
  track `date`, e.g. Episode 3 vs. 4 in "The Forester's Forecast", so date
  was chosen as the more reliable "latest" signal).
- `render_episode_embed(ep)` — renders a single episode as an H4 title,
  date, a `<div class="ratio ratio-16x9 mb-3"><iframe
  src="https://www.youtube.com/embed/<id>" ...></iframe></div>` responsive
  embed (Bootstrap ratio helper), and the description.
- `render_latest_series(episodes, series_name, show_heading = TRUE)` —
  looks up the latest episode via `get_latest_episode()` and renders it via
  `render_episode_embed()`, preceded by an H3 series-name heading.

`index.qmd` sources `episodes/render_episodes.R`, calls `load_episodes()`,
then calls `render_latest_series(episodes, series_name)` once per series
under a "## Latest Episodes" heading, each in its own
`#| results: asis` chunk.

Verified: `quarto render` (full site) completes without errors and
`_site/index.html` contains three `<iframe src="https://www.youtube.com/embed/...">`
embeds (one per series). Styling against `_brand.yml`/`styles.css` has not
yet been visually reviewed in a browser — that's a reasonable next step
after restarting RStudio (e.g. via `quarto preview`).

## Secret scanning / pre-commit hook

A leaked Google API key was previously committed in `.Rhistory` and pushed
to GitHub, triggering GitHub/Google secret-scanning warnings. It was
removed by amending the (single) commit on `main` that introduced it and
force-pushing; the key itself should have also been rotated in Google
Cloud Console (revoke/regenerate is the real fix — history rewriting alone
doesn't undo prior exposure).

To prevent recurrence, a pre-commit hook lives at **`.githooks/pre-commit`**
(tracked in the repo) that:
- Blocks staging/committing sensitive filenames (`.Rhistory`, `.Renviron`,
  `.env`, service-account JSON files) even if `git add -f` is used.
- Scans staged changes for secrets using **gitleaks** (installed via
  `winget install Gitleaks.Gitleaks`, currently v8.30.1) if it's found on
  `PATH` -- `gitleaks protect --staged --redact -v` -- which has a much
  broader/maintained rule set plus entropy-based detection than any hand-
  rolled regex could.
- Falls back to a small built-in regex scan (Google API keys, AWS access
  key IDs, GitHub/Slack tokens, private key blocks, generic
  `key/secret/token <- "..."` or `= "..."` assignments) if gitleaks isn't
  installed on a given machine, so the hook still does *something* useful
  everywhere.
- Exits non-zero and prints the offending pattern/line if anything matches,
  blocking the commit (bypassable per-commit via `git commit --no-verify`
  for confirmed false positives).

**Important:** `core.hooksPath` is a *local* git config, not something that
travels with the repo automatically. Every fresh clone (or this one, if
`core.hooksPath` ever gets reset) needs to run once:

```
git config core.hooksPath .githooks
```

`.gitignore` was also updated to cover `.Renviron`, `.env`, and `.env.*` in
addition to the pre-existing `.Rhistory` entry, as defense in depth.

**Note on `core.autocrlf`:** this repo has `core.autocrlf=true`, so files
on disk (including `.githooks/pre-commit` and `AGENTS.md` itself) have CRLF
line endings even though they're authored/stored as LF in git. Tools doing
exact-string-match edits against these files can fail confusingly with
"string not found" against seemingly-matching content -- rewriting the
whole file, or editing via a CRLF-aware method (e.g. `sed`), sidesteps it.

**Note on winget/PATH:** installing a tool via `winget install` updates the
user-level `PATH` in the registry immediately, but any *already-running*
shell/terminal process won't see the update until it's restarted -- this
can make a freshly-installed CLI tool appear as "not found" even though
the install succeeded and works fine in a new terminal/session.

## Status

Home page embed feature is implemented and rendering cleanly. Update this
file as further work happens (e.g., if a YouTube-API fetch script is
added, if episode data schema changes, or if the embed styling is
adjusted).
