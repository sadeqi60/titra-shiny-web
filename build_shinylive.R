# Build a static browser-only Shinylive (WebR) version of Titra into ./site for GitHub Pages
# Requires: install.packages("shinylive")

if (!requireNamespace("shinylive", quietly = TRUE)) {
  stop("Install shinylive first: install.packages('shinylive')")
}
shinylive::export(appdir = ".", destdir = "site")
file.create(file.path("site", ".nojekyll"))
cat("Built browser-only Titra Shinylive app into ./site\n")
