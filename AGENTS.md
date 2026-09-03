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
- **`episodes/fetch_episodes.R`** is the fetch/refresh script (recovered from
  ad hoc console history and rebuilt as a reusable, merge-safe function — see
  "YouTube fetch script" section below). Source it and call
  `fetch_and_merge_episodes()` to pull new videos from the channel
  (`@TheForestersForecast-wb3jl`) and merge them into `episodes.yml`.

## YouTube fetch script (`episodes/fetch_episodes.R`)

- `fetch_and_merge_episodes()` — fetches every video from the channel's
  uploads playlist (paginated) via the YouTube Data API v3, then **merges**
  into `episodes/episodes.yml` by `youtube_id` (not title — YouTube titles
  get lightly copyedited after publishing, e.g. spacing/typo fixes, which
  would otherwise cause false "new episode" positives). Existing entries
  keep their curated `series`, `order`, `spotify_id`, and `description`;
  only `title`/`date` are refreshed from upstream. Brand-new videos are
  classified into `series`/`order` via `classify_episode()` based on title
  patterns (`"Episode N: ..."`, `"Grad Student Spotlight - Episode N: ..."`,
  `"A Band of Biometricians #N: ..."`); anything unrecognized (e.g. the
  channel's intro clip) defaults to `series: "The Forester's Forecast"`,
  `order: 0`. Returns the titles of genuinely new episodes and prints a
  reminder to add their `spotify_id`.
- `add_spotify_id(title, spotify_id)` — Spotify IDs aren't available via the
  YouTube API, so after a fetch, add each new episode's Spotify ID by hand
  (exact title match) once it's published on Spotify.
- **Setup required before use:** the API key is read from the
  `YOUTUBE_API_KEY` environment variable (set in `.Renviron`, which is
  gitignored and never committed) — never hardcode it in the script. See
  "Secret scanning" section below for why this matters here specifically.
- Usage: `source("episodes/fetch_episodes.R")` then
  `fetch_and_merge_episodes()`.

## Publishing (`episodes/update_and_publish.R`)

The site deploys to **two** places that both need updating, and the live
site is served from `gh-pages`, not `main`:
- `main` — the source branch (`.qmd` files, `episodes.yml`,
  `episodes/*.R`), plus a tracked-but-gitignored copy of the rendered
  `_site/` and `.quarto/_freeze/` (pre-existing state; `.gitignore` lists
  them but git keeps tracking already-tracked files regardless of ignore
  rules — this is intentional to leave alone, not a bug to fix).
- `gh-pages` — a separate branch containing *only* the rendered site,
  deployed via GitHub Pages to the custom domain
  (`www.theforestersforecast.com`, see `CNAME`). This is what
  `quarto publish gh-pages` manages, and is the actual live site.

**`episodes/update_and_publish.R`** wraps the whole cycle in one function,
`update_and_publish()`, run manually whenever new episodes are available:
1. `fetch_and_merge_episodes()` (see above).
2. If new episodes were found, pauses (in interactive sessions) so you can
   add `spotify_id`s via `add_spotify_id()` before publishing.
3. `quarto render` (full site).
4. Commits `episodes/episodes.yml` + `_site/` + `.quarto/_freeze/` to
   `main` (staged with `git add -f`, since those paths are technically
   gitignored-but-tracked — see git note below) and pushes to
   `origin/main`. Skipped if nothing changed.
5. Runs `quarto publish gh-pages --no-prompt --no-browser` to deploy the
   live site. **Deliberately does not pass `--no-render`** even though the
   site was just rendered in step 3 — `quarto publish`'s own render pass
   is what knows the destination site URL, which is required to generate
   `robots.txt`/`sitemap.xml`. Skipping that second render silently drops
   both files from the live site (found and fixed this exact bug once
   already).

Options: `update_and_publish(push = FALSE)` (commit to `main` locally only,
skip both the `main` push and the `gh-pages` publish),
`update_and_publish(publish_gh_pages = FALSE)` (push `main` but leave the
live site alone), `update_and_publish(commit_message = "...")` (override
the auto-generated `main` commit message).

**Git/Quarto quirks hit while building this:**
- Recent git's `advice.addIgnoredFile` refuses to (re-)stage paths under an
  ignored directory (`_site/`, `.quarto/_freeze/`) even when the specific
  file is already tracked, unless `-f` is passed — surfaces as a confusing
  exit-1 "paths are ignored" error even though the add actually succeeds
  for tracked files.
- `system2()` on Windows can mangle a multi-word string (e.g. a commit
  message) passed as a single `args` element into separate argv tokens;
  wrap such strings in `shQuote()` before passing to `system2()`.
- `quarto publish gh-pages` is git-based (unlike Quarto Pub/Netlify/etc.)
  and does **not** require `quarto publish accounts` setup — it just uses
  whatever git credentials/remote config already work for `origin`.

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

**Follow-up finding:** the same key was later found still sitting in
plaintext in the *local, gitignored* `.Rhistory` (never committed after the
above fix, but never scrubbed from disk either — the original ad hoc YouTube
fetch commands, including `api_key <- "AIzaSy..."`, lived there). It's been
redacted locally. This is the origin of `episodes/fetch_episodes.R` above —
reconstructed from those console commands, but rewritten to read the key
from `YOUTUBE_API_KEY` in `.Renviron` instead of hardcoding it, specifically
to prevent a repeat. Rotating the actual key in Google Cloud Console (not
just redacting the local copy) is still the responsible party's action item
if not already done; recommended key setup: restrict to YouTube Data API v3
only (API restriction), and use IP-address application restriction only if
running from a machine with a stable public IP, otherwise leave application
restriction as "None" and rely on the API restriction.

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

## Git identity and multi-account setup on this PC

This machine also has a separate work project using a different GitHub
account, so:
- Git identity for this repo is set **locally** (not `--global`):
  `user.name = "Micky Allen"`, `user.email = "micky10@vt.edu"`. Don't set
  these globally on this machine.
- The `origin` remote URL has the personal GitHub username embedded
  (`https://mickyallen10@github.com/mickyallen10/TheForestersForecast.git`)
  rather than a bare `https://github.com/...` URL. This was needed because
  Git Credential Manager was authenticating pushes as the other (work)
  GitHub account by default when the URL didn't disambiguate — embedding
  the username gets a separate stored credential. If pushes ever start
  failing with a 403 "Permission denied to <other-account>" again, this is
  the first thing to check/re-apply.

## Status

Home page embed feature is implemented and rendering cleanly.
`episodes/fetch_episodes.R` and `episodes/update_and_publish.R` both exist
and have been run successfully end-to-end, including a full fetch → render
→ commit `main` → publish `gh-pages` cycle. `episodes.yml` currently
includes a new episode ("A Band of Biometricians #2") and a
previously-untracked intro video, merged without disturbing existing
`spotify_id`s. Update this file as further work happens (e.g., if episode
data schema changes, if the embed styling is adjusted, if
`classify_episode()` needs new title patterns for a future series, or if
the publishing setup changes, e.g. a different deploy target than
`gh-pages`).
