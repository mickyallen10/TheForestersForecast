# Shared rendering logic for episode listing pages (episodes.qmd,
# grad-student-spotlight.qmd, band-of-biometricians.qmd).
#
# Note: HTML lines are kept flush-left (no leading spaces), and each link is
# wrapped in its own <div>. Indented lines or bare inline <a> tags inside a
# raw HTML block get misread by Pandoc (indented lines become code blocks;
# bare adjacent lines get merged into one paragraph).

load_episodes <- function(path = "episodes/episodes.yml") {
  if (!requireNamespace("yaml", quietly = TRUE)) install.packages("yaml")
  yaml::read_yaml(path)
}

render_episode_card <- function(ep) {
  cat("### ", ep$title, "\n\n", sep = "")
  cat("*", format(as.Date(ep$date), "%B %d, %Y"), "*\n\n", sep = "")

  if (!is.null(ep$youtube_id) && nzchar(ep$youtube_id)) {
    video_url <- sprintf("https://www.youtube.com/watch?v=%s", ep$youtube_id)
    thumb_url <- sprintf("https://img.youtube.com/vi/%s/hqdefault.jpg", ep$youtube_id)
    cat(sprintf(
      '<div class="d-flex align-items-center gap-3 mb-3">\n<a href="%s" target="_blank" rel="noopener" class="episode-thumb">\n<img src="%s" alt="%s">\n</a>\n<div class="d-flex flex-column gap-1">\n<div><a href="%s" target="_blank" rel="noopener">Watch on YouTube</a></div>\n',
      video_url, thumb_url, ep$title, video_url
    ))
    if (!is.null(ep$spotify_id) && nzchar(ep$spotify_id)) {
      spotify_url <- sprintf("https://open.spotify.com/episode/%s", ep$spotify_id)
      cat(sprintf('<div><a href="%s" target="_blank" rel="noopener">Listen on Spotify</a></div>\n', spotify_url))
    }
    cat('</div>\n</div>\n\n')
  }

  if (!is.null(ep$description) && nzchar(ep$description)) {
    cat(ep$description, "\n\n")
  }
  cat("---\n\n")
}

# Renders all episodes belonging to `series_name`, ordered by `order`.
# Set `show_heading = TRUE` to print an H2 with the series name (useful when
# a single page covers multiple series).
render_series <- function(episodes, series_name, show_heading = FALSE) {
  in_series <- Filter(function(e) e$series == series_name, episodes)
  if (length(in_series) == 0) return(invisible())

  in_series <- in_series[order(sapply(in_series, function(e) e$order))]

  if (show_heading) cat("## ", series_name, "\n\n", sep = "")

  for (ep in in_series) render_episode_card(ep)
}

# Returns the most recently dated episode entry belonging to `series_name`,
# or NULL if the series has no episodes.
get_latest_episode <- function(episodes, series_name) {
  in_series <- Filter(function(e) e$series == series_name, episodes)
  if (length(in_series) == 0) return(NULL)

  dates <- as.Date(sapply(in_series, function(e) e$date))
  in_series[[which.max(dates)]]
}

# Renders a single episode as an embedded (responsive) YouTube player, with
# title, date, and description -- used to showcase a "latest episode" card
# (e.g. on the home page) rather than the thumbnail/link layout used by
# render_episode_card().
render_episode_embed <- function(ep) {
  cat("#### ", ep$title, "\n\n", sep = "")
  cat("*", format(as.Date(ep$date), "%B %d, %Y"), "*\n\n", sep = "")

  if (!is.null(ep$youtube_id) && nzchar(ep$youtube_id)) {
    embed_url <- sprintf("https://www.youtube.com/embed/%s", ep$youtube_id)
    cat(sprintf(
      '<div class="ratio ratio-16x9 mb-3">\n<iframe src="%s" title="%s" allowfullscreen></iframe>\n</div>\n\n',
      embed_url, ep$title
    ))
  }

  if (!is.null(ep$description) && nzchar(ep$description)) {
    cat(ep$description, "\n\n")
  }
}

# Renders the latest episode of `series_name` as an embed, preceded by an H3
# series heading (set `show_heading = FALSE` to omit it).
render_latest_series <- function(episodes, series_name, show_heading = TRUE) {
  ep <- get_latest_episode(episodes, series_name)
  if (is.null(ep)) return(invisible())

  if (show_heading) cat("### ", series_name, "\n\n", sep = "")

  render_episode_embed(ep)
}
