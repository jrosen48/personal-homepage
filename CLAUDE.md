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

- **Source**: `.qmd` files in root — `index.qmd`, `research.qmd`, `teaching.qmd`, `publications.qmd`, `writing-and-photography.qmd`, `about.qmd`, `contact.qmd`, `vita.qmd`, `other-presentations.qmd`
- **Config**: `_quarto.yml` — website structure, nav, and output formats
- **Output**: `docs/` — rendered HTML/PDF/assets (GitHub Pages root)
- **Nav structure** (per 2026 site refresh): Home | Research | Teaching | Publications | Writing & Photography | About | Contact. The CV lives behind a button on About (`vita.html` / `vita.pdf`); the research group and Substack are linked contextually, not from the navbar.
- **`writing-and-photography.qmd`** carries `aliases: [/photography.html]` so the old Photography URL redirects
- **`vita.qmd`** and **`publications.qmd`** contain R code (the vita pulls live citation counts from Google Scholar via the `scholar` package), so a full render needs R

## Deployment

GitHub Pages serves from `docs/` on `main`. After rendering, commit the updated `docs/` directory to deploy. The `CNAME` file is listed in `_quarto.yml` under `resources:` so it gets copied to `docs/` on each render.

The `docs/CNAME` is in `.gitignore` to prevent local overwrites of the custom domain setting.
