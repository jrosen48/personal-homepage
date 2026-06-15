#!/usr/bin/env Rscript
# Parse vita.qmd into a structured publications table.
# Output: scripts/publications.csv

suppressPackageStartupMessages({
  library(stringr)
  library(readr)
  library(dplyr)
  library(tibble)
  library(purrr)
})

VITA  <- "vita.qmd"
OUT   <- "scripts/publications.csv"

lines <- read_lines(VITA)

pub_start <- which(str_detect(lines, "^# Publications\\s*$"))
stopifnot(length(pub_start) == 1)
after_pub <- which(str_detect(lines, "^# "))
pub_end   <- after_pub[after_pub > pub_start][1] - 1
pub_lines <- lines[(pub_start + 1):pub_end]

header_idx <- which(str_detect(pub_lines, "^## "))

extract_section <- function(i) {
  start <- header_idx[i] + 1
  end   <- if (i < length(header_idx)) header_idx[i + 1] - 1 else length(pub_lines)
  raw_header <- pub_lines[header_idx[i]]
  section <- raw_header |>
    str_remove("^## ") |>
    str_remove("\\s*\\(\\d+\\)\\s*$") |>
    str_trim()
  body <- pub_lines[start:end]

  # Group consecutive non-blank lines into entry blocks.
  # Child bullets starting with "- " or "-   " are award/note annotations
  # and attach to the preceding entry.
  entries <- list()
  current <- character()
  flush <- function() {
    if (length(current)) {
      entries[[length(entries) + 1L]] <<- paste(current, collapse = " ")
      current <<- character()
    }
  }
  for (ln in body) {
    if (str_detect(ln, "^\\s*$")) {
      flush()
    } else if (str_detect(ln, "^-\\s+") && length(entries) > 0) {
      # append annotation to last entry
      note <- str_replace(ln, "^-\\s+", "")
      entries[[length(entries)]] <- paste(entries[[length(entries)]], note, sep = " | NOTE: ")
    } else {
      current <- c(current, ln)
    }
  }
  flush()

  if (!length(entries)) return(tibble())

  tibble(
    section = section,
    idx_in_section = seq_along(entries),
    citation_raw = unlist(entries)
  )
}

all_entries <- map_dfr(seq_along(header_idx), extract_section)

# ---- Field extraction heuristics ----

# Normalize: strip leading "+", "\^", "\+" mentee markers for authors.
# Keep the raw citation untouched; only build derived fields.

extract_year <- function(x) {
  # First 4-digit year (1990–2099) inside parens
  m <- str_match(x, "\\((?:[^)]*?)(19\\d{2}|20\\d{2})")
  m[, 2]
}

extract_year_paren <- function(x) {
  # Full first parenthetical that contains the year (e.g., "2024, March" or "advance online publication")
  m <- str_match(x, "\\(([^)]*?(19\\d{2}|20\\d{2})[^)]*?)\\)")
  m[, 2]
}

extract_authors <- function(x) {
  # Text before first "(" — the opening parenthetical should be the year-block
  auth <- str_extract(x, "^[^(]+")
  auth |> str_trim() |> str_remove("\\.$") |> str_trim()
}

extract_url <- function(x) {
  # Prefer first angle-bracket URL, then markdown link URL, then bare URL
  u <- str_match(x, "<(https?://[^>]+)>")[, 2]
  if (is.na(u)) u <- str_match(x, "\\]\\((https?://[^)\\s]+)")[, 2]
  if (is.na(u)) u <- str_match(x, "(https?://[^\\s)>]+)")[, 2]
  if (!is.na(u)) {
    # Strip common trailing junk: period, comma, ">", ")"
    u <- str_replace(u, "[\\.,\\)>]+$", "")
    # URL-decode the very common %3E (>) artifact at end
    u <- str_replace(u, "%3E$", "")
  }
  u
}

extract_doi <- function(url, citation) {
  # From URL first
  doi <- NA_character_
  if (!is.na(url)) {
    m <- str_match(url, "(?:doi\\.org/|dx\\.doi\\.org/)(10\\.[^\\s]+)")[, 2]
    if (!is.na(m)) doi <- m
  }
  if (is.na(doi)) {
    m <- str_match(citation, "(10\\.\\d{4,9}/[-._;()/:A-Za-z0-9]+)")[, 2]
    if (!is.na(m)) doi <- m
  }
  if (!is.na(doi)) doi <- str_replace(doi, "[\\.,\\)>]+$", "")
  doi
}

strip_authors_and_paren <- function(x) {
  # Strip authors + first parenthetical (year OR "in press" / "advance online publication" / etc.)
  # Trailing period after ")" is optional (some vita entries omit it).
  body <- str_replace(x, "\\s*\\|\\s*NOTE:.*$", "")
  str_replace(body, "^[^(]+\\([^)]*\\)\\.?\\s*", "")
}

# Title ends at first ". ", "? ", or "! " — track which boundary we hit so
# extract_venue can reuse it.
title_split <- function(x) {
  # Returns list(title = ..., after = ...) where `after` is text following title.
  after_paren <- strip_authors_and_paren(x)
  m <- str_match(after_paren, "^(.+?)([\\.\\?!])\\s+(.+)$")
  if (!is.na(m[1, 1])) {
    return(list(title = m[1, 2], punct = m[1, 3], after = m[1, 4]))
  }
  list(title = after_paren, punct = NA_character_, after = "")
}

extract_title <- function(x) {
  s <- title_split(x)
  t <- s$title |> str_trim() |> str_remove("\\.$") |> str_trim()
  if (!is.na(t) && str_detect(t, "^\\*.*\\*$")) {
    t <- str_sub(t, 2L, -2L)
  }
  # Preserve trailing ? or ! as part of the title (question-titles should keep
  # their punctuation)
  if (!is.na(s$punct) && s$punct %in% c("?", "!")) {
    t <- paste0(t, s$punct)
  }
  t
}

extract_venue <- function(x) {
  after_title <- title_split(x)$after
  # Prefer italicized run
  m <- str_match(after_title, "^\\s*\\*([^*]+)\\*")[, 2]
  if (is.na(m)) {
    # Conference pattern: "In *Proceedings of...*" — already handled by the italic
    # match above. Plain-text venue: up to first comma/period/paren.
    m <- str_match(after_title, "^([A-Z][^,.<(]*[A-Za-z)])")[, 2]
  }
  if (is.na(m)) {
    # "In Proceedings of..." with no italics
    m <- str_match(after_title, "^In\\s+([A-Z][^,.<(]*[A-Za-z)])")[, 2]
  }
  if (!is.na(m)) m <- str_trim(m) |> str_remove("[,\\.]$") |> str_trim()
  m
}

has_note <- function(x) str_detect(x, "\\|\\s*NOTE:")

extract_note <- function(x) {
  if (!has_note(x)) return(NA_character_)
  str_match(x, "\\|\\s*NOTE:\\s*(.*)$")[, 2]
}

pubs <- all_entries |>
  mutate(
    year          = extract_year(citation_raw),
    year_paren    = extract_year_paren(citation_raw),
    authors_raw   = extract_authors(citation_raw),
    url           = map_chr(citation_raw, extract_url),
    doi           = map2_chr(url, citation_raw, extract_doi),
    title         = map_chr(citation_raw, extract_title),
    venue         = map_chr(citation_raw, extract_venue),
    note          = map_chr(citation_raw, extract_note)
  ) |>
  mutate(
    id = sprintf("%s-%03d",
                 str_to_lower(str_replace_all(section, "[^A-Za-z0-9]+", "-")) |>
                   str_remove_all("-+$"),
                 idx_in_section),
    .before = 1
  )

dir.create("scripts", showWarnings = FALSE)
write_csv(pubs, OUT)

# ---- Diagnostics ----
cat("Total entries parsed:", nrow(pubs), "\n")
cat("\nBy section:\n")
pubs |> count(section) |> print(n = Inf)

miss <- pubs |>
  summarise(
    no_year  = sum(is.na(year)),
    no_url   = sum(is.na(url)),
    no_doi   = sum(is.na(doi)),
    no_title = sum(is.na(title) | title == ""),
    no_venue = sum(is.na(venue))
  )
cat("\nMissingness:\n"); print(miss)

cat("\nOutput written to:", OUT, "\n")
