#!/usr/bin/env Rscript
# Download open-access PDFs (via Unpaywall best_oa_pdf) for entries
# that don't already have a salvaged PDF.
#
# Outputs:
#   pdf/oa/<safe-id>.pdf         one file per successfully fetched OA PDF
#   scripts/oa-fetch-log.csv     per-entry status (fetched | failed | landing-only | no-oa)
#   scripts/still-needed.csv     entries with no salvaged PDF AND no OA — manual retrieval list

suppressPackageStartupMessages({
  library(readr); library(dplyr); library(stringr); library(purrr)
  library(tibble); library(httr2); library(fs)
})

RIGHTS   <- "scripts/publications-rights.csv"
MATCHES  <- "scripts/pdf-matches.csv"
OA_DIR   <- "pdf/oa"
LOG_CSV  <- "scripts/oa-fetch-log.csv"
NEED_CSV <- "scripts/still-needed.csv"

dir_create(OA_DIR)

rights <- read_csv(RIGHTS, show_col_types = FALSE)
matches <- read_csv(MATCHES, show_col_types = FALSE) |>
  filter(!is.na(match_id), confidence %in% c("high", "medium"))

have_pdf_ids <- unique(matches$match_id)

safe_name <- function(id) str_replace_all(id, "[^A-Za-z0-9._-]", "-")

fetch_one <- function(row) {
  url <- row$best_oa_pdf %||% row$best_oa_url
  if (is.na(url) || !nzchar(url)) return(tibble(id = row$id, status = "no-oa", path = NA_character_, url = NA_character_))
  dest <- file.path(OA_DIR, paste0(safe_name(row$id), ".pdf"))
  if (file_exists(dest)) return(tibble(id = row$id, status = "cached", path = dest, url = url))

  resp <- tryCatch(
    request(url) |>
      req_user_agent("personal-homepage-oa/1.0 (mailto:jrosenb8@utk.edu)") |>
      req_timeout(30) |>
      req_retry(max_tries = 2) |>
      req_error(is_error = \(r) FALSE) |>
      req_perform(),
    error = function(e) NULL
  )
  if (is.null(resp) || resp_status(resp) != 200) {
    return(tibble(id = row$id, status = "failed", path = NA_character_, url = url))
  }
  ctype <- resp_header(resp, "content-type") %||% ""
  body <- resp_body_raw(resp)
  looks_pdf <- length(body) > 1000 && identical(as.raw(body[1:4]), charToRaw("%PDF"))
  if (!looks_pdf) {
    return(tibble(id = row$id, status = "landing-only", path = NA_character_, url = url))
  }
  writeBin(body, dest)
  tibble(id = row$id, status = "fetched", path = dest, url = url)
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a)) || !nzchar(a)) b else a

missing <- rights |> filter(!(id %in% have_pdf_ids))
cat("Entries missing a salvaged PDF:", nrow(missing), "\n")
oa_targets <- missing |> filter(isTRUE(is_oa) | (is_oa %in% TRUE), !is.na(best_oa_url))
cat("OA targets to fetch:", nrow(oa_targets), "\n\n")

log <- list()
for (i in seq_len(nrow(oa_targets))) {
  row <- oa_targets[i, ]
  res <- fetch_one(row)
  log[[i]] <- res
  cat(sprintf("[%2d/%2d] %-16s %s\n", i, nrow(oa_targets), res$status, str_trunc(row$title, 70)))
  Sys.sleep(0.3)
}
log_df <- bind_rows(log) |> left_join(rights |> select(id, title, venue, year, publisher), by = "id")
write_csv(log_df, LOG_CSV)

# Still-needed = missing a salvaged PDF AND we didn't fetch an OA copy successfully
fetched_ids <- log_df |> filter(status %in% c("fetched", "cached")) |> pull(id)
still_needed <- rights |>
  filter(!(id %in% have_pdf_ids), !(id %in% fetched_ids)) |>
  mutate(
    has_oa_url      = !is.na(best_oa_url),
    oa_fetch_status = log_df$status[match(id, log_df$id)]
  ) |>
  select(id, section, year, authors_raw, title, venue, publisher, doi,
         is_oa, has_oa_url, best_oa_url, oa_fetch_status,
         share_status, share_version, embargo_months, policy_pattern, policy_url)

write_csv(still_needed, NEED_CSV)

cat("\n---- Summary ----\n")
cat("Fetched OA PDFs:      ", sum(log_df$status == "fetched"), "\n")
cat("Cached (already had): ", sum(log_df$status == "cached"), "\n")
cat("Landing page only:    ", sum(log_df$status == "landing-only"), "\n")
cat("Fetch failed:         ", sum(log_df$status == "failed"), "\n")
cat("Still needed (manual):", nrow(still_needed), "\n")
cat("\nLog:          ", LOG_CSV, "\n")
cat("Still needed: ", NEED_CSV, "\n")
