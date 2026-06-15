#!/usr/bin/env Rscript
# Enrich publications.csv with DOIs + canonical metadata via Crossref.
# Output: scripts/publications-enriched.csv + scripts/crossref-cache/*.json

suppressPackageStartupMessages({
  library(stringr); library(readr); library(dplyr); library(tibble)
  library(purrr); library(httr2); library(jsonlite); library(stringdist)
})

PUB_CSV    <- "scripts/publications.csv"
OUT_CSV    <- "scripts/publications-enriched.csv"
CACHE_DIR  <- "scripts/crossref-cache"
MAILTO     <- "jrosenb8@utk.edu"   # polite pool; no key required
ACCEPT_SIM <- 0.85                 # title-similarity threshold

dir.create(CACHE_DIR, showWarnings = FALSE, recursive = TRUE)

pubs <- read_csv(PUB_CSV, show_col_types = FALSE)

# ---- Helpers ----
cache_key <- function(id) file.path(CACHE_DIR, paste0(id, ".json"))

clean_title_for_query <- function(t) {
  if (is.na(t)) return("")
  t |> str_replace_all("[\"'`]", "") |> str_squish()
}

first_surname_only <- function(authors_raw) {
  if (is.na(authors_raw)) return("")
  first <- str_split(authors_raw, ",")[[1]][1] |> str_trim()
  first |> str_remove_all("[\\^\\+\\\\']")
}

norm <- function(s) s |> str_to_lower() |>
  str_replace_all("[^a-z0-9]+", " ") |> str_squish()

title_sim <- function(a, b) {
  if (is.na(a) || is.na(b)) return(0)
  1 - stringdist(norm(a), norm(b), method = "jw", p = 0.1)
}

query_crossref <- function(entry) {
  f <- cache_key(entry$id)
  if (file.exists(f)) {
    return(tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL))
  }
  title <- clean_title_for_query(entry$title)
  if (nchar(title) < 10) return(NULL)
  author <- first_surname_only(entry$authors_raw)
  year <- suppressWarnings(as.integer(entry$year))

  req <- request("https://api.crossref.org/works") |>
    req_url_query(
      query.bibliographic = title,
      query.author        = if (nchar(author) > 0) author else NULL,
      rows                = 5,
      select              = "DOI,title,author,issued,container-title,volume,issue,page,URL,type,publisher",
      mailto              = MAILTO
    ) |>
    req_user_agent(sprintf("personal-homepage-enricher/1.0 (mailto:%s)", MAILTO)) |>
    req_retry(max_tries = 3, backoff = function(n) 2^n)

  if (!is.na(year)) {
    req <- req |> req_url_query(
      filter = sprintf("from-pub-date:%d,until-pub-date:%d", year - 1, year + 1),
      .multi = "comma"
    )
  }

  resp <- tryCatch(req |> req_perform(), error = function(e) NULL)
  if (is.null(resp) || resp_status(resp) != 200) return(NULL)

  body <- resp |> resp_body_string()
  writeLines(body, f)
  fromJSON(body, simplifyVector = FALSE)
}

flat_chr <- function(x) {
  if (is.null(x) || length(x) == 0) return(NA_character_)
  paste(as.character(unlist(x)), collapse = " ") |> str_squish()
}
flat_int <- function(x) {
  if (is.null(x) || length(x) == 0) return(NA_integer_)
  as.integer(unlist(x)[1])
}

cr_author_surnames <- function(it) {
  if (is.null(it$author) || !length(it$author)) return(character())
  sapply(it$author, function(a) flat_chr(a$family)) |>
    discard(is.na) |> str_to_lower() |> str_remove_all("[^a-z\\-]")
}

our_surnames <- function(authors_raw) {
  if (is.na(authors_raw)) return(character())
  chunks <- authors_raw |> str_replace_all("&", ",") |>
    str_split(",") |> unlist() |> str_trim()
  surnames <- chunks[str_detect(chunks, "^[A-Z][A-Za-z\\-\\s']{2,}$")]
  surnames |> str_to_lower() |> str_remove_all("[^a-z\\-]")
}

pick_best <- function(cr_json, entry) {
  items <- cr_json$message$items
  if (is.null(items) || !length(items)) return(NULL)
  ours <- our_surnames(entry$authors_raw)
  cand <- map_dfr(items, function(it) {
    crs <- cr_author_surnames(it)
    tibble(
      doi            = flat_chr(it$DOI),
      title          = flat_chr(it$title),
      container      = flat_chr(it[["container-title"]]),
      year_cr        = flat_int(it$issued$`date-parts`[[1]][1]),
      volume         = flat_chr(it$volume),
      issue          = flat_chr(it$issue),
      page           = flat_chr(it$page),
      url            = flat_chr(it$URL),
      type           = flat_chr(it$type),
      author_overlap = length(intersect(ours, crs)),
      author_n_cr    = length(crs)
    )
  })
  cand <- cand |> mutate(sim = map_dbl(title, ~ title_sim(.x, entry$title)))
  cand |> arrange(desc(sim)) |> slice(1)
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

needs_doi <- pubs |> filter(is.na(doi)) |> pull(id)
cat("Entries missing DOI:", length(needs_doi), "\n")

results <- list()
for (i in seq_len(nrow(pubs))) {
  row <- pubs[i, ]
  if (!is.na(row$doi)) {
    results[[row$id]] <- tibble(id = row$id, cr_doi = row$doi, cr_sim = NA_real_,
                                cr_title = NA_character_, cr_venue = NA_character_,
                                cr_year = NA_integer_, cr_volume = NA_character_,
                                cr_issue = NA_character_, cr_page = NA_character_,
                                cr_type = NA_character_, cr_author_overlap = NA_integer_,
                                cr_status = "had-doi")
    next
  }
  cj <- query_crossref(row)
  if (is.null(cj)) {
    results[[row$id]] <- tibble(id = row$id, cr_doi = NA_character_, cr_sim = NA_real_,
                                cr_title = NA_character_, cr_venue = NA_character_,
                                cr_year = NA_integer_, cr_volume = NA_character_,
                                cr_issue = NA_character_, cr_page = NA_character_,
                                cr_type = NA_character_, cr_author_overlap = NA_integer_,
                                cr_status = "no-response")
    next
  }
  best <- pick_best(cj, row)
  if (is.null(best) || is.na(best$doi)) {
    results[[row$id]] <- tibble(id = row$id, cr_doi = NA_character_, cr_sim = NA_real_,
                                cr_title = NA_character_, cr_venue = NA_character_,
                                cr_year = NA_integer_, cr_volume = NA_character_,
                                cr_issue = NA_character_, cr_page = NA_character_,
                                cr_type = NA_character_, cr_status = "no-candidates")
    next
  }
  # Combined acceptance rules:
  # (a) title_sim >= 0.85 AND at least one shared author surname
  # (b) title_sim >= 0.75 AND year matches AND 2+ shared author surnames
  entry_year <- suppressWarnings(as.integer(row$year))
  year_match <- !is.na(entry_year) && !is.na(best$year_cr) &&
                abs(entry_year - best$year_cr) <= 1
  status <- if (best$sim >= 0.85 && best$author_overlap >= 1) {
    "accepted"
  } else if (best$sim >= 0.75 && year_match && best$author_overlap >= 2) {
    "accepted-author"
  } else if (best$sim >= 0.85) {
    "title-only"     # high title sim but no author overlap — suspicious, reject
  } else {
    "low-sim"
  }
  accepted <- status %in% c("accepted", "accepted-author")
  results[[row$id]] <- tibble(
    id = row$id,
    cr_doi = if (accepted) best$doi else NA_character_,
    cr_sim = best$sim,
    cr_title  = best$title,
    cr_venue  = best$container,
    cr_year   = best$year_cr,
    cr_volume = best$volume,
    cr_issue  = best$issue,
    cr_page   = best$page,
    cr_type   = best$type,
    cr_author_overlap = best$author_overlap,
    cr_status = status
  )
  cat(sprintf("[%3d/%3d] %-55s %s (sim %.2f)\n",
              i, nrow(pubs), str_trunc(row$title, 55), status, best$sim))
  Sys.sleep(0.1)  # be polite
}

cr <- bind_rows(results)
enriched <- pubs |> left_join(cr, by = "id") |>
  mutate(
    doi = coalesce(doi, cr_doi),
    url = coalesce(url, if_else(!is.na(cr_doi), paste0("https://doi.org/", cr_doi), NA_character_))
  )

write_csv(enriched, OUT_CSV)

cat("\n---- Summary ----\n")
cr |> count(cr_status) |> print()
cat("\nTotal DOIs after enrichment:", sum(!is.na(enriched$doi)), "/", nrow(enriched), "\n")
cat("New DOIs added:", sum(is.na(pubs$doi) & !is.na(enriched$doi)), "\n")
cat("\nOutput: ", OUT_CSV, "\n")
