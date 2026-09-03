# Fetch new episodes from the YouTube Data API v3 and merge them into
# episodes/episodes.yml, WITHOUT clobbering fields that only exist there
# (spotify_id, and any hand-trimmed descriptions).
#
# Setup (one-time):
#   1. Create/rotate a YouTube Data API v3 key in Google Cloud Console.
#   2. Add it to .Renviron (NOT committed - see .gitignore) as:
#        YOUTUBE_API_KEY=your-key-here
#   3. Restart R (or run `readRenviron("~/.Renviron")`) so Sys.getenv() picks it up.
#
# Usage:
#   source("episodes/fetch_episodes.R")
#   new_titles <- fetch_and_merge_episodes()   # writes episodes/episodes.yml
#
# After running, new episodes will have series/order guessed from their title
# (see classify_episode()) and will be MISSING spotify_id - add those by hand
# with add_spotify_id(), same as before. Review classify_episode() output for
# any title pattern it doesn't recognize (order will be NA).

library(httr2)
library(purrr)
library(yaml)

CHANNEL_HANDLE <- "TheForestersForecast-wb3jl"
EPISODES_PATH <- "episodes/episodes.yml"

YAML_HEADER <- paste(
  "# Episode data for The Forester's Forecast, sourced from the YouTube channel",
  "# (youtube_id is the video ID; part after \"v=\" or after youtu.be/).",
  "# `series` groups episodes into one of three shows:",
  "#   - \"The Forester's Forecast\"",
  "#   - \"Grad Student Spotlight\"",
  "#   - \"A Band of Biometricians\"",
  "# `order` is the position within its series (used for sorting on the Episodes page).",
  "# `spotify_id` is the Spotify episode ID (from open.spotify.com/episode/<id>), when known.",
  "# To refresh this list from YouTube later, re-run episodes/fetch_episodes.R using the",
  "# YouTube Data API v3 (channel handle: @TheForestersForecast-wb3jl).",
  sep = "\n"
)

FIELD_ORDER <- c("title", "series", "order", "date", "youtube_id", "spotify_id", "description")

get_api_key <- function() {
  key <- Sys.getenv("YOUTUBE_API_KEY")
  if (!nzchar(key)) {
    stop(
      "YOUTUBE_API_KEY is not set. Add it to .Renviron and restart R ",
      "(see the header comment in this file)."
    )
  }
  key
}

# Classify a raw video title into series + order-within-series, mirroring the
# original ad hoc console logic. Returns list(series, order); order is NA if
# no pattern matched, which should be reviewed manually.
classify_episode <- function(title) {
  if (grepl("^Grad Student Spotlight", title)) {
    series <- "Grad Student Spotlight"
    num <- as.numeric(sub(".*Episode\\s*(\\d+).*", "\\1", title))
  } else if (grepl("^A Band of Biometricians", title)) {
    series <- "A Band of Biometricians"
    num <- as.numeric(sub(".*#(\\d+).*", "\\1", title))
  } else if (grepl("^Episode\\s*\\d+", title)) {
    series <- "The Forester's Forecast"
    num <- as.numeric(sub("^Episode\\s*(\\d+).*", "\\1", title))
  } else {
    # Fall back: treat as an unnumbered main-series episode (e.g. an intro),
    # matching the original convention of order 0 for the intro.
    series <- "The Forester's Forecast"
    num <- 0
  }
  list(series = series, order = as.integer(num))
}

# Keep only the first paragraph/line of a YouTube description, matching how
# existing entries in episodes.yml were trimmed.
trim_description <- function(desc) {
  if (is.null(desc) || !nzchar(desc)) return("")
  first_para <- strsplit(desc, "\n\n")[[1]][1]
  first_line <- strsplit(first_para, "\n")[[1]][1]
  trimws(first_line)
}

# Pull every video from the channel's uploads playlist via the YouTube Data API.
fetch_channel_videos <- function(api_key = get_api_key(), channel_handle = CHANNEL_HANDLE) {
  channel_resp <- request("https://www.googleapis.com/youtube/v3/channels") |>
    req_url_query(
      part = "contentDetails,snippet",
      forHandle = channel_handle,
      key = api_key
    ) |>
    req_perform()
  channel_data <- resp_body_json(channel_resp)
  uploads_playlist_id <- channel_data$items[[1]]$contentDetails$relatedPlaylists$uploads

  all_items <- list()
  page_token <- NULL
  repeat {
    playlist_resp <- request("https://www.googleapis.com/youtube/v3/playlistItems") |>
      req_url_query(
        part = "snippet,contentDetails",
        playlistId = uploads_playlist_id,
        maxResults = 50,
        pageToken = page_token,
        key = api_key
      ) |>
      req_perform()
    page_data <- resp_body_json(playlist_resp)
    all_items <- c(all_items, page_data$items)
    page_token <- page_data$nextPageToken
    if (is.null(page_token)) break
  }

  map(all_items, function(x) {
    sn <- x$snippet
    list(
      title = sn$title,
      date = substr(sn$publishedAt, 1, 10),
      youtube_id = sn$resourceId$videoId,
      description = trim_description(sn$description)
    )
  })
}

# Fetch from YouTube, merge with the existing episodes.yml (preserving
# spotify_id and existing descriptions for episodes already on file, keyed by
# youtube_id), classify any brand-new videos, and write the result back out.
# Returns the titles of newly-added episodes (character vector, possibly empty).
fetch_and_merge_episodes <- function(path = EPISODES_PATH) {
  existing <- if (file.exists(path)) yaml::read_yaml(path) else list()
  existing_by_id <- set_names(existing, map_chr(existing, "youtube_id"))

  fetched <- fetch_channel_videos()

  merged <- map(fetched, function(v) {
    prior <- existing_by_id[[v$youtube_id]]
    if (!is.null(prior)) {
      # Keep series/order/spotify_id/description as previously curated;
      # only refresh title/date in case of upstream edits.
      prior$title <- v$title
      prior$date <- v$date
      prior
    } else {
      cls <- classify_episode(v$title)
      list(
        title = v$title,
        series = cls$series,
        order = cls$order,
        date = v$date,
        youtube_id = v$youtube_id,
        spotify_id = NULL,
        description = v$description
      )
    }
  })

  # Diff by youtube_id (stable) rather than title (YouTube titles get
  # copyedited after publishing, which would otherwise look like a new video).
  new_ids <- setdiff(
    map_chr(merged, "youtube_id"),
    map_chr(existing, "youtube_id")
  )
  new_titles <- map_chr(merged[map_chr(merged, "youtube_id") %in% new_ids], "title")

  series_order <- c("The Forester's Forecast", "Grad Student Spotlight", "A Band of Biometricians")
  series_idx <- match(map_chr(merged, "series"), series_order)
  order_num <- map_dbl(merged, ~ if (is.null(.x$order) || is.na(.x$order)) Inf else .x$order)
  merged <- merged[order(series_idx, order_num)]

  merged <- lapply(merged, function(e) e[FIELD_ORDER[FIELD_ORDER %in% names(e)]])

  yaml_text <- as.yaml(merged)
  writeLines(paste0(YAML_HEADER, "\n\n", yaml_text), path, sep = "")

  if (length(new_titles) > 0) {
    message(
      "Added ", length(new_titles), " new episode(s): ",
      paste(new_titles, collapse = "; "),
      "\nReview series/order for these, and add spotify_id via add_spotify_id()."
    )
  } else {
    message("No new episodes found.")
  }

  invisible(new_titles)
}

# Set a single episode's Spotify ID by exact title match (Spotify IDs aren't
# available via the YouTube API, so these are added by hand after publishing).
add_spotify_id <- function(title, spotify_id, path = EPISODES_PATH) {
  episodes <- yaml::read_yaml(path)
  idx <- which(map_chr(episodes, "title") == title)
  if (length(idx) != 1) stop("Could not uniquely match title: ", title)
  episodes[[idx]]$spotify_id <- spotify_id
  episodes <- lapply(episodes, function(e) e[FIELD_ORDER[FIELD_ORDER %in% names(e)]])
  yaml_text <- as.yaml(episodes)
  writeLines(paste0(YAML_HEADER, "\n\n", yaml_text), path, sep = "")
  invisible(episodes)
}
