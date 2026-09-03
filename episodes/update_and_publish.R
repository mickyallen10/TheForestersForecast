# One-shot workflow to run whenever new episodes are available:
#   1. Fetch new videos from YouTube and merge them into episodes.yml
#      (existing spotify_id/description/order are preserved - see
#      fetch_episodes.R for details).
#   2. Pause so you can add spotify_id for any new episode(s) via
#      add_spotify_id(title, id) before publishing.
#   3. Render the Quarto site (quarto render).
#   4. Commit episodes.yml + the rendered _site/ + .quarto/_freeze changes,
#      and push to origin/main.
#
# Deliberately does NOT touch .Rhistory, .Renviron, .Rproj.user, .posit, or
# .quarto/idx|xref|project-cache - those are local session/cache state
# unrelated to episode content (some are gitignored; the pre-commit hook
# also blocks .Rhistory/.Renviron regardless).
#
# Usage:
#   source("episodes/update_and_publish.R")
#   update_and_publish()
#
# Options:
#   update_and_publish(push = FALSE)          # commit locally only, don't push
#   update_and_publish(commit_message = "...") # override the default message

run_git <- function(args, error_on_fail = TRUE) {
  result <- suppressWarnings(system2("git", args, stdout = TRUE, stderr = TRUE))
  status <- attr(result, "status")
  if (!is.null(status) && status != 0 && error_on_fail) {
    stop("git ", paste(args, collapse = " "), " failed:\n", paste(result, collapse = "\n"))
  }
  result
}

update_and_publish <- function(push = TRUE, commit_message = NULL) {
  source("episodes/fetch_episodes.R")

  message("== Step 1/4: fetching episodes from YouTube ==")
  new_titles <- fetch_and_merge_episodes()

  if (length(new_titles) > 0) {
    message(
      "\nNew episode(s) detected:\n",
      paste(" -", new_titles, collapse = "\n"),
      "\n\nIf any are published on Spotify, add their IDs now, e.g.:\n",
      '  add_spotify_id("', new_titles[1], '", "the-spotify-id")\n'
    )
    if (interactive()) {
      readline("Press <Enter> once you're ready to render and publish...")
    }
  } else {
    message("No new episodes found.")
  }

  message("\n== Step 2/4: rendering site ==")
  render_out <- suppressWarnings(system2("quarto", "render", stdout = TRUE, stderr = TRUE))
  cat(render_out, sep = "\n")
  render_status <- attr(render_out, "status")
  if (!is.null(render_status) && render_status != 0) {
    stop("quarto render failed - fix the error above before publishing.")
  }

  paths_to_stage <- c("episodes/episodes.yml", "_site", ".quarto/_freeze")
  message("\n== Step 3/4: checking for changes to commit ==")
  changed <- run_git(c("status", "--porcelain", "--", paths_to_stage))
  if (length(changed) == 0) {
    message("Nothing to commit - episodes.yml and the rendered site are already up to date.")
    return(invisible(NULL))
  }

  # -f: _site/ and .quarto/_freeze/ are (redundantly) listed in .gitignore
  # even though they're deliberately tracked; without -f, recent git refuses
  # to (re-)stage paths under an ignored directory and exits non-zero, even
  # for files already tracked.
  run_git(c("add", "-f", paths_to_stage))

  if (is.null(commit_message)) {
    commit_message <- if (length(new_titles) > 0) {
      sprintf("Add new episode(s): %s", paste(new_titles, collapse = "; "))
    } else {
      "Update rendered site"
    }
  }
  message("Committing: ", commit_message)
  run_git(c("commit", "-m", shQuote(commit_message)))

  message("\n== Step 4/4: ", if (push) "pushing to origin/main ==" else "skipping push (push = FALSE) ==")
  if (push) {
    push_out <- run_git(c("push", "origin", "main"))
    cat(push_out, sep = "\n")
  }

  message("\nDone.")
  invisible(new_titles)
}
