#!/usr/bin/env Rscript
# Check Unpaywall for open-access versions of every DOI we have.
# Output: scripts/publications-oa.csv + scripts/unpaywall-cache/*.json

suppressPackageStartupMessages({
  library(stringr); library(readr); library(dplyr); library(tibble)
  library(purrr); library(httr2); library(jsonlite)
})

IN_CSV    <- "scripts/publications-enriched.csv"
OUT_CSV   <- "scripts/publications-oa.csv"
CACHE_DIR <- "scripts/unpaywall-cache"
EMAIL     <- "jrosenb8@utk.edu"

dir.create(CACHE_DIR, showWarnings = FALSE, recursive = TRUE)
pubs <- read_csv(IN_CSV, show_col_types = FALSE)

safe_fname <- function(doi) {
  doi |> str_replace_all("[/]", "_") |> str_replace_all("[^A-Za-z0-9._-]", "-")
}

query_unpaywall <- function(doi) {
  f <- file.path(CACHE_DIR, paste0(safe_fname(doi), ".json"))
  if (file.exists(f)) {
    return(tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL))
  }
  req <- request(sprintf("https://api.unpaywall.org/v2/%s", doi)) |>
    req_url_query(email = EMAIL) |>
    req_user_agent(sprintf("personal-homepage-oa/1.0 (%s)", EMAIL)) |>
    req_retry(max_tries = 3, backoff = function(n) 2^n) |>
    req_error(is_error = \(resp) FALSE)  # 404 is a valid "DOI not in Unpaywall"

  resp <- tryCatch(req |> req_perform(), error = function(e) NULL)
  if (is.null(resp)) return(NULL)
  st <- resp_status(resp)
  if (st == 404) {
    writeLines("{}", f)  # cache the miss
    return(list())
  }
  if (st != 200) return(NULL)
  body <- resp |> resp_body_string()
  writeLines(body, f)
  fromJSON(body, simplifyVector = FALSE)
}

flat <- function(x) if (is.null(x) || length(x) == 0) NA_character_ else as.character(x[[1]])

extract_oa <- function(up) {
  if (is.null(up) || !length(up) || is.null(up$doi)) {
    return(tibble(oa_status = NA_character_, is_oa = NA, best_oa_url = NA_character_,
                  best_oa_pdf = NA_character_, oa_version = NA_character_,
                  oa_license = NA_character_, oa_host_type = NA_character_,
                  journal_is_oa = NA, publisher = NA_character_))
  }
  best <- up$best_oa_location
  tibble(
    oa_status     = flat(up$oa_status),
    is_oa         = isTRUE(up$is_oa),
    best_oa_url   = flat(best$url),
    best_oa_pdf   = flat(best$url_for_pdf),
    oa_version    = flat(best$version),
    oa_license    = flat(best$license),
    oa_host_type  = flat(best$host_type),
    journal_is_oa = isTRUE(up$journal_is_oa),
    publisher     = flat(up$publisher)
  )
}

has_doi <- pubs |> filter(!is.na(doi))
cat("DOIs to query:", nrow(has_doi), "\n\n")

results <- list()
for (i in seq_len(nrow(has_doi))) {
  row <- has_doi[i, ]
  up  <- query_unpaywall(row$doi)
  row_oa <- extract_oa(up) |> mutate(id = row$id, .before = 1)
  results[[row$id]] <- row_oa
  cat(sprintf("[%3d/%3d] %-20s %-15s %s\n",
              i, nrow(has_doi),
              row_oa$oa_status %||% "—",
              row_oa$oa_version %||% "",
              str_trunc(row$title, 55)))
  Sys.sleep(0.05)
}

`%||%` <- function(a, b) if (is.null(a) || is.na(a) || length(a) == 0) b else a

oa <- bind_rows(results)
merged <- pubs |> left_join(oa, by = "id")
write_csv(merged, OUT_CSV)

# ---- Summary ----
cat("\n---- Summary ----\n")
merged |> count(oa_status) |> arrange(desc(n)) |> print()

cat("\nBy OA version (archivable type):\n")
merged |> filter(is_oa) |> count(oa_version) |> print()

cat("\nBy section — how many have any OA version:\n")
merged |> group_by(section) |>
  summarise(n = n(),
            has_doi = sum(!is.na(doi)),
            is_oa   = sum(is_oa, na.rm = TRUE)) |>
  arrange(desc(n)) |> print()

cat("\nOutput:", OUT_CSV, "\n")
