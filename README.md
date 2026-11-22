# Titra — Standalone Shiny Web App (GitHub-Ready)

A self-contained, GitHub-ready **R Shiny** web application implementing the complete **Titra** DBS Programming & Electrophysiology Studio — zero Python required, zero external C/DSP dependencies.

## Features
- **Clean First Appearance**: Animated Titra DBS-lead emblem above **Welcome to Titra**, with a single local **LFP Input Object** dropzone and live 4-stage progress bar.
- **Adaptive Input Engine**: Auto-detects and verifies Medtronic Percept PC/RC JSON session reports and amplitude-titration exports; dynamically enables only the objects supported by the loaded file; supports multi-file session merging and chunked uploads for large clinical JSON files.
- **17 Built-In Presets + Custom DAG Builder**: Core Beta & FTG Pipeline, Directional Survey, Game Theory, Extreme-Value Tail Risk, Option Pricing, and Complete Graph Signal Processing DAG — plus `+ Insert Object`, right-click branching, 4-sided port wiring, Auto-Layout, Full-Stage Focus, and the compact `FTG Δf` controller.
- **Multi-Format Reports & Instant Clear**: Word (`.docx`), printable HTML/PDF, pure-vector SVG, PNG, ZIP bundle, and a title-bar **`✕ Clear`** button with warning tooltip for instant reset between cases.
- **Locked Titra Favicon**: Displays Titra's DBS-lead emblem in the browser tab at all times.

## 1. Run Locally

```r
install.packages(c("shiny", "htmltools", "jsonlite", "base64enc"))
shiny::runApp()
```

## 2. Upload to GitHub & Publish Free on GitHub Pages (Shinylive / WebR)

1. Push this folder to a new GitHub repository (e.g., `titra-shiny-web`).
2. On GitHub go to **Settings → Pages → Build and deployment → Source: GitHub Actions**.
3. The included workflow `.github/workflows/deploy-shinylive.yml` automatically exports and publishes a browser-only WebAssembly (WebR / Shinylive) version of the app where uploaded clinical JSON files never leave the visitor's computer.

## 3. Other Hosting Options

- **Run straight from GitHub in R**: `shiny::runGitHub("<your-user>/titra-shiny-web")`
- **shinyapps.io / Posit Connect Cloud**: Connect your GitHub repository directly (`app.R` is at the repo root).
- **Docker**: `docker build -t titra-shiny . && docker run -p 3838:3838 titra-shiny`
