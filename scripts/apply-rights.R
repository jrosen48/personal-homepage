#!/usr/bin/env Rscript
# Apply publisher self-archiving policies to publications-oa.csv.
# Output: scripts/publications-rights.csv

suppressPackageStartupMessages({
  library(stringr); library(readr); library(dplyr); library(tibble); library(purrr)
})

source("scripts/publisher-policies.R")  # exposes PUBLISHER_POLICIES

pubs <- read_csv("scripts/publications-oa.csv", show_col_types = FALSE)

# Default for unknown publishers (Option 2: optimistic AM-posting, no embargo).
DEFAULT_POLICY <- tibble(
  match_pattern   = NA_character_,
  share           = "yes-default",
  version         = "AM",
  embargo_months  = 0,
  policy_url      = NA_character_,
  note            = "Author's accepted manuscript posted per standard green-OA self-archiving norms (publisher policy not verified individually).",
  verified_on     = NA_character_
)

# Look up policy by matching publisher string (Crossref) or venue (vita).
match_policy <- function(publisher, venue) {
  candidates <- PUBLISHER_POLICIES
  target <- paste(c(publisher, venue), collapse = " ") |> str_to_lower()
  if (is.na(target) || !nzchar(target)) return(DEFAULT_POLICY)
  hit <- candidates |> filter(map_lgl(match_pattern,
                                      ~ str_detect(target, regex(.x, ignore_case = TRUE))))
  if (nrow(hit) == 0) return(DEFAULT_POLICY)
  # First match wins (ordered roughly by specificity in the lookup file)
  hit |> slice(1)
}

today_year <- as.integer(format(Sys.Date(), "%Y"))

rights <- pubs |>
  mutate(
    .policy = map2(publisher, venue, match_policy),
    share_status    = map_chr(.policy, ~ .x$share),
    share_version   = map_chr(.policy, ~ .x$version),
    embargo_months  = map_int(.policy, ~ as.integer(.x$embargo_months)),
    policy_url      = map_chr(.policy, ~ .x$policy_url),
    policy_note     = map_chr(.policy, ~ .x$note),
    policy_verified = map_chr(.policy, ~ .x$verified_on),
    policy_pattern  = map_chr(.policy, ~ .x$match_pattern %||% "(default)")
  ) |>
  select(-.policy)

# Embargo math — any publication whose (year + embargo/12) <= this year is free now.
rights <- rights |>
  mutate(
    pub_year     = suppressWarnings(as.integer(year)),
    embargo_clear= pub_year + ceiling(embargo_months / 12) <= today_year,
    # Final per-entry decision
    can_share_now = case_when(
      is_oa                                        ~ TRUE,   # Unpaywall OA → just use it
      share_status == "no"                         ~ FALSE,
      share_status %in% c("yes", "yes-default") & (is.na(pub_year) | embargo_clear) ~ TRUE,
      TRUE                                         ~ FALSE   # embargo still active
    ),
    # Which version should end up on the site
    site_version = case_when(
      is_oa & !is.na(oa_version)        ~ oa_version,       # use Unpaywall-reported version
      can_share_now & share_version == "VoR" ~ "publishedVersion",
      can_share_now & share_version == "AM"  ~ "acceptedVersion",
      can_share_now & share_version == "SM"  ~ "submittedVersion",
      TRUE                                ~ NA_character_
    ),
    # Text to display under each entry
    attribution = case_when(
      is_oa & !is.na(oa_license)         ~ sprintf("Open access (%s). %s", oa_license, policy_note %||% ""),
      is_oa                              ~ "Open access via the publisher.",
      can_share_now                      ~ policy_note,
      !is.na(pub_year) & !embargo_clear  ~ sprintf("Under embargo until ~%d per %s self-archiving policy.",
                                                   pub_year + ceiling(embargo_months / 12),
                                                   coalesce(publisher, "publisher")),
      TRUE                               ~ "Rights status not determined; available on request."
    )
  )

`%||%` <- function(a, b) if (is.null(a) || is.na(a) || !nzchar(a)) b else a

write_csv(rights, "scripts/publications-rights.csv")

cat("---- Rights summary ----\n")
cat("Total entries:", nrow(rights), "\n\n")

cat("can_share_now (final verdict per entry):\n")
rights |> count(can_share_now) |> print()

cat("\nshare_status (rule that applied):\n")
rights |> count(share_status) |> print()

cat("\nsite_version distribution:\n")
rights |> count(site_version) |> print()

cat("\nUnder active embargo:\n")
embargoed <- rights |> filter(!can_share_now, share_status %in% c("yes","yes-default"), !embargo_clear, !is.na(pub_year))
cat("  ", nrow(embargoed), "entries\n")
embargoed |> select(year, publisher, title) |>
  mutate(title = str_trunc(title, 55)) |> print(n = 10)

cat("\nPublishers matched by rule:\n")
rights |> filter(!is.na(publisher)) |>
  count(publisher, policy_pattern, sort = TRUE) |> print(n = 20)

cat("\nOutput: scripts/publications-rights.csv\n")
