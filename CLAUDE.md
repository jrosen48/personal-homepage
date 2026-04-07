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

- **Source**: `.qmd` files in root — `index.qmd`, `about.qmd`, `vita.qmd`, `photography.qmd`, `other-presentations.qmd`
- **Config**: `_quarto.yml` — website structure, nav, and output formats
- **Output**: `docs/` — rendered HTML/PDF/assets (GitHub Pages root)
- **`vita.qmd`** has `format: docx` in its front matter, overriding the global PDF format to produce a Word document instead of PDF

## Deployment

GitHub Pages serves from `docs/` on `main`. After rendering, commit the updated `docs/` directory to deploy. The `CNAME` file is listed in `_quarto.yml` under `resources:` so it gets copied to `docs/` on each render.

The `docs/CNAME` is in `.gitignore` to prevent local overwrites of the custom domain setting.
