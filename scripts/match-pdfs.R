#!/usr/bin/env Rscript
# Match salvaged PDFs to parsed publications by author + year + venue heuristics.
# Output: scripts/pdf-matches.csv

suppressPackageStartupMessages({
  library(stringr); library(readr); library(dplyr)
  library(tibble);  library(purrr); library(tidyr); library(fs)
})

PUB_CSV  <- "scripts/publications.csv"
PDF_ROOT <- "pdf/salvaged"
OUT      <- "scripts/pdf-matches.csv"

pubs <- read_csv(PUB_CSV, show_col_types = FALSE)

pdfs <- dir_ls(PDF_ROOT, recurse = TRUE, glob = "*.pdf")
stopifnot(length(pdfs) > 0)

pdf_tbl <- tibble(
  pdf_path = as.character(pdfs),
  pdf_kind = basename(dirname(pdf_path)),   # publications / post-prints / pre-prints
  pdf_file = basename(pdf_path)
)

# ---- Tokenize a filename ----
tok_of <- function(fname) {
  s <- fname |>
    tools::file_path_sans_ext() |>
    str_to_lower() |>
    str_replace_all("[_\\.]+", "-") |>
    str_replace_all("[^a-z0-9-]", "-") |>
    str_replace_all("-+", "-") |>
    str_remove("^-|-$")
  str_split(s, "-")[[1]]
}

year_of <- function(tokens) {
  m <- tokens[str_detect(tokens, "^(19\\d{2}|20\\d{2})$")]
  if (length(m) == 0) NA_character_ else m[1]
}

# First-author surname from authors_raw: chunk before first comma
first_surname <- function(authors_raw) {
  if (is.na(authors_raw)) return(NA_character_)
  first <- str_split(authors_raw, ",")[[1]][1] |> str_trim()
  # handle "Rosenberg" or "Staudt Willet" or "Staudt-Willet" or "van Lissa"
  first |> str_to_lower() |>
    str_remove_all("[\\^\\+\\\\']") |>
    str_replace_all("\\s+", "-")
}

all_surnames <- function(authors_raw) {
  if (is.na(authors_raw)) return(character())
  # Split authors on commas and "&"
  chunks <- authors_raw |>
    str_replace_all("&", ",") |>
    str_split(",") |> unlist() |> str_trim()
  # Keep items that look like surnames (alpha, length >= 3, no initials pattern)
  surnames <- chunks[str_detect(chunks, "^[A-Z][A-Za-z\\-\\s]{2,}$")]
  # Drop single letters + "M" "J" etc. — already excluded by length 3 above
  surnames |> str_to_lower() |> str_replace_all("\\s+", "-")
}

# Words in a title, filtered: lowercase, 4+ chars, non-stopword
STOPWORDS <- c("with","from","that","this","their","they","these","those","into",
               "about","when","where","what","which","whose","have","been","were",
               "will","would","should","could","there","then","than","upon","also",
               "such","some","more","most","many","much","only","your","them",
               "between","among","through","across","toward","over","under",
               "after","before","during","within","without","beyond",
               "using","used","based","case","cases","study","studies",
               "paper","papers","review","reviews","note","notes",
               "research","researchers","researching",
               "education","educational","teaching","teachers","learning","learners",
               "article","articles","book","books","chapter","chapters",
               "introduction","introductory","conclusion","findings","results",
               "comparison","comparing","applying","exploring","investigation")

title_tokens <- function(title) {
  if (is.na(title)) return(character())
  ws <- title |> str_to_lower() |> str_replace_all("[^a-z0-9]+", " ") |>
    str_split(" ") |> unlist() |> keep(~ nchar(.x) >= 4)
  setdiff(ws, STOPWORDS)
}

# Known venue → token hints
venue_tokens <- function(venue) {
  if (is.na(venue)) return(character())
  v <- str_to_lower(venue)
  # Extract simple words + known abbreviations
  words <- str_split(v, "[^a-z]+")[[1]] |> keep(~ nchar(.x) >= 3)
  abbrevs <- c(
    "british journal of educational technology" = "bjet",
    "journal of research in science teaching"   = "jrst",
    "journal of research on technology in education" = "jrte",
    "journal of open source software"           = "joss",
    "journal of computers in mathematics and science teaching" = "jcmst",
    "techtrends" = "tt",
    "teaching and teacher education" = "tt",
    "educational studies" = "es",
    "learning analytics and knowledge" = "lak",
    "international conference of the learning sciences" = "icls",
    "educational data mining" = "edm",
    "aera open" = "aera-open",
    "journal of formative design in learning" = "jfdl",
    "the science teacher" = "tst"
  )
  hits <- character()
  for (nm in names(abbrevs)) if (str_detect(v, fixed(nm))) hits <- c(hits, abbrevs[[nm]])
  unique(c(words, hits))
}

score_match <- function(pdf_tokens, pdf_year, entry) {
  sc <- 0
  reasons <- character()

  # Year match (required — worth 3)
  if (!is.na(pdf_year) && !is.na(entry$year) && as.character(entry$year) == pdf_year) {
    sc <- sc + 3
    reasons <- c(reasons, "year")
  } else if (!is.na(pdf_year) && !is.na(entry$year)) {
    # within 1 year of publication — publishers sometimes lag
    if (abs(as.integer(entry$year) - as.integer(pdf_year)) == 1) {
      sc <- sc + 1
      reasons <- c(reasons, "year±1")
    }
  }

  # First-author surname match (worth 3)
  fsn <- first_surname(entry$authors_raw)
  if (!is.na(fsn) && fsn %in% pdf_tokens) {
    sc <- sc + 3
    reasons <- c(reasons, "first-author")
  }

  # Any co-author surname match (worth 1 per, capped at 2)
  coauth <- all_surnames(entry$authors_raw)
  coauth_hits <- intersect(coauth, pdf_tokens)
  coauth_hits <- setdiff(coauth_hits, fsn)
  if (length(coauth_hits)) {
    sc <- sc + min(2, length(coauth_hits))
    reasons <- c(reasons, paste0("coauth:", paste(coauth_hits, collapse = ",")))
  }

  # Venue hint match (worth 1)
  vts <- venue_tokens(entry$venue)
  venue_hits <- intersect(vts, pdf_tokens)
  if (length(venue_hits)) {
    sc <- sc + 1
    reasons <- c(reasons, paste0("venue:", paste(venue_hits, collapse = ",")))
  }

  # Title-keyword overlap (worth 2 per hit, capped at 6) — strongest discriminator
  # for ambiguous filenames
  tts <- title_tokens(entry$title)
  title_hits <- intersect(tts, pdf_tokens)
  if (length(title_hits)) {
    sc <- sc + min(6L, 2L * length(title_hits))
    reasons <- c(reasons, paste0("title:", paste(title_hits, collapse = ",")))
  }

  list(score = sc, reasons = paste(reasons, collapse = ";"))
}

normalize <- function(s) {
  s |> str_to_lower() |> str_replace_all("[^a-z0-9]+", " ") |> str_squish()
}

pdf_first_pages <- function(path, pages = 2) {
  out <- tryCatch(
    suppressWarnings(system2("pdftotext", c("-f", "1", "-l", pages, "-layout",
                                            shQuote(path), "-"),
                             stdout = TRUE, stderr = FALSE)),
    error = function(e) character()
  )
  paste(out, collapse = " ") |> normalize()
}

# Run matcher; also collect top 3 candidates for ambiguous/none review.
top_candidates <- list()

match_pdf_with_candidates <- function(row) {
  tokens <- tok_of(row$pdf_file)
  pyear  <- year_of(tokens)
  scored <- pubs |>
    mutate(.scored = map(seq_len(n()), function(i) score_match(tokens, pyear, pubs[i, ]))) |>
    mutate(score   = map_int(.scored, "score"),
           reasons = map_chr(.scored, "reasons")) |>
    select(-.scored) |>
    arrange(desc(score))

  need_text <- nrow(scored) >= 2 && (scored$score[1] - scored$score[2]) < 2 && scored$score[1] >= 4
  if (need_text) {
    ptext <- pdf_first_pages(row$pdf_path)
    if (nchar(ptext) > 100) {
      top_score <- scored$score[1]
      scored <- scored |>
        mutate(
          title_norm = normalize(title),
          contains_title = map2_lgl(title_norm, score, function(tn, s) {
            if (is.na(tn) || nchar(tn) < 12) return(FALSE)
            if (s < top_score - 2) return(FALSE)
            str_detect(ptext, fixed(tn))
          }),
          score = score + if_else(contains_title, 10L, 0L),
          reasons = if_else(contains_title, paste0(reasons, ";pdf-title"), reasons)
        ) |>
        select(-title_norm, -contains_title) |>
        arrange(desc(score))
    }
  }

  top    <- scored |> slice(1)
  second <- if (nrow(scored) >= 2) scored$score[2] else 0L
  conf <- case_when(
    top$score >= 6 & (top$score - second) >= 2 ~ "high",
    top$score >= 4 & (top$score - second) >= 2 ~ "medium",
    top$score >= 4                             ~ "ambiguous",
    TRUE                                       ~ "none"
  )

  if (conf %in% c("ambiguous", "none")) {
    cands <- scored |> slice(1:3) |> mutate(pdf_file = row$pdf_file, rank = row_number()) |>
      select(pdf_file, rank, id, title, year, venue, score, reasons)
    top_candidates[[length(top_candidates) + 1L]] <<- cands
  }

  tibble(
    pdf_path   = row$pdf_path, pdf_kind = row$pdf_kind, pdf_file = row$pdf_file,
    pdf_year   = pyear,
    match_id   = if (top$score >= 4) top$id    else NA_character_,
    match_title= if (top$score >= 4) top$title else NA_character_,
    match_year = if (top$score >= 4) top$year  else NA_integer_,
    score = top$score, runner_up = second, confidence = conf, reasons = top$reasons
  )
}

matches <- pdf_tbl |>
  mutate(row_id = row_number()) |>
  group_split(row_id) |>
  map_dfr(~ match_pdf_with_candidates(as.list(.x)))

write_csv(matches, OUT)
if (length(top_candidates)) {
  bind_rows(top_candidates) |> write_csv("scripts/pdf-matches-candidates.csv")
}

# ---- Diagnostics ----
cat("PDFs processed:", nrow(matches), "\n\n")
cat("Confidence distribution:\n")
matches |> count(confidence) |> print()
cat("\nAmbiguous / none (need eyeballs):\n")
matches |> filter(confidence %in% c("ambiguous", "none")) |>
  select(pdf_kind, pdf_file, match_title, score, runner_up, reasons) |>
  print(n = Inf, width = 200)
cat("\nHigh-confidence sample:\n")
matches |> filter(confidence == "high") |> slice_sample(n = 6) |>
  select(pdf_file, match_title, reasons) |> print(width = 200)

cat("\nOutput:", OUT, "\n")
