# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal academic homepage for Joshua M. Rosenberg, Ph.D., built with Quarto. Outputs both HTML (website) and PDF from `.qmd` source files. Published to GitHub Pages from the `docs/` directory.

## Build Commands

```bash
quarto render                          # Render entire site (HTML + PDF)
quarto render index.qmd --to html     # Single page, HTML only
quarto render index.qmd --to pdf      # Single page, PDF only
quarto preview                         # Local server with live reload
quarto clean                           # Remove .quarto/ cache
```

## Key Architecture Notes

- **Source**: `.qmd` files in root — `index.qmd`, `research.qmd`, `publications.qmd`, `about.qmd`, `photography.qmd`, `vita.qmd`, `other-presentations.qmd`
- **Config**: `_quarto.yml` — website structure, nav, and output formats
- **Output**: `docs/` — rendered HTML/PDF/assets (GitHub Pages root)
- **Nav structure** (Oct 2026 simplification): Home | Research | Publications | Vita | About | Photography. Teaching and Contact live as sections on About; the research group, Substack, and other links are in the list on the homepage. Site copy is Josh's own sentences (old pages, vita Research Program section); do not add new prose without asking.
- **Redirects**: `about.qmd` carries `aliases: [/contact.html, /teaching.html]` and `photography.qmd` carries `aliases: [/writing-and-photography.html]` so URLs from the June 2026 structure still resolve
- **`vita.qmd`** and **`publications.qmd`** contain R code (the vita pulls live citation counts from Google Scholar via the `scholar` package), so a full render needs R

## Deployment

GitHub Pages serves from `docs/` on `main`. After rendering, commit the updated `docs/` directory to deploy. The `CNAME` file is listed in `_quarto.yml` under `resources:` so it gets copied to `docs/` on each render.

The `docs/CNAME` is in `.gitignore` to prevent local overwrites of the custom domain setting.
