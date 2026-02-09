# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a personal academic homepage built with Quarto. The site is configured to output both HTML (for the website) and PDF versions of pages. The HTML website is published to GitHub Pages from the `docs/` directory.

## Project Structure

- **Source files**: `.qmd` files in the root directory (index.qmd, about.qmd, vita.qmd, photography.qmd, other-presentations.qmd)
- **Configuration**: `_quarto.yml` - defines the website structure, navigation, and output formats
- **Output directory**: `docs/` - contains rendered HTML, PDF, and assets (configured for GitHub Pages)
- **Images**: `images/` directory for static assets
- **Styles**: `styles.css` for custom styling (currently minimal)

## Build Commands

### Render entire site
```bash
quarto render
```
This generates both HTML and PDF outputs for all pages to the `docs/` directory.

### Render single page
```bash
quarto render index.qmd        # Renders both HTML and PDF
quarto render index.qmd --to html  # HTML only
quarto render index.qmd --to pdf   # PDF only
```

### Preview site locally
```bash
quarto preview
```
Opens a local web server with live reload.

### Clean build artifacts
```bash
quarto clean
```
Removes the `.quarto/` cache directory (but not `docs/`).

## Output Formats

The site is configured in `_quarto.yml` to produce:
1. **HTML** - Website pages with Cosmo theme, TOC enabled, custom CSS
2. **PDF** - Uses XeLaTeX engine (note: `vita.qmd` is DOCX format only)

The `vita.qmd` file has `format: docx` in its front matter, overriding the global PDF format to produce a Word document instead.

## Key Configuration Details

- **Project type**: website
- **Output directory**: `docs/` (for GitHub Pages compatibility)
- **Theme**: cosmo (Bootstrap-based)
- **PDF engine**: xelatex
- The CNAME file is listed in `resources:` to ensure it's copied to `docs/` for custom domain

## Navigation Structure

The navbar (defined in `_quarto.yml`) includes:
- Home (index.qmd)
- About and Contact (about.qmd)
- Vita (vita.html - note: links to HTML, but source is vita.qmd which outputs DOCX)
- Research Group (external link)
- Newsletter/Blog (external link)
- Photography (photography.qmd)

## Git and Deployment

The site uses GitHub Pages, serving from the `docs/` directory on the `main` branch. After rendering, commit the updated `docs/` directory to deploy changes.

Files in `.gitignore`:
- R-specific files (.Rproj.user, .Rhistory, .RData, .Ruserdata)
- Quarto cache (/.quarto/)
- docs/CNAME (to prevent local overwrites)
- Quarto notebook temp files (**/*.quarto_ipynb)
