#!/usr/bin/env bash
#
# Regenerate the publications dataset from vita.qmd and rebuild the page.
#
# Runs the full pipeline in dependency order:
#   parse-vita      vita.qmd            -> publications.csv
#   enrich-crossref + Crossref          -> publications-enriched.csv
#   check-unpaywall + Unpaywall         -> publications-oa.csv
#   match-pdfs      + pdf/salvaged/     -> pdf-matches.csv
#   apply-rights    + publisher policy  -> publications-rights.csv   (what the page reads)
#   fetch-oa-pdfs   downloads OA PDFs   -> pdf/oa/, still-needed.csv
#
# Crossref/Unpaywall responses are cached under scripts/, so re-runs only hit
# the network for DOIs that aren't cached yet (e.g. newly added publications).
#
# Usage:
#   bash scripts/update-publications.sh              # update dataset + render page
#   bash scripts/update-publications.sh --no-render  # update dataset only

set -euo pipefail

# Run from the repo root regardless of where the script was invoked, since the
# R scripts use paths relative to it (vita.qmd, scripts/*.csv, pdf/...).
cd "$(dirname "$0")/.."

stage() { printf '\n\033[1;34m>>> %s\033[0m\n' "$1"; Rscript "scripts/$1"; }

stage parse-vita.R
stage enrich-crossref.R
stage check-unpaywall.R
stage match-pdfs.R
stage apply-rights.R
stage fetch-oa-pdfs.R

if [[ "${1:-}" == "--no-render" ]]; then
  printf '\n\033[1;32mDataset updated.\033[0m (skipped render)\n'
  exit 0
fi

if command -v quarto >/dev/null 2>&1; then
  printf '\n\033[1;34m>>> quarto render publications.qmd\033[0m\n'
  quarto render publications.qmd
  printf '\n\033[1;32mDone — dataset and page updated.\033[0m\n'
else
  printf '\n\033[1;32mDataset updated.\033[0m quarto not on PATH; run: quarto render publications.qmd\n'
fi
