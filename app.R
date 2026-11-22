# Titra — Standalone GitHub-Ready Shiny Web Application
# Run locally:   shiny::runApp()
# From GitHub:   shiny::runGitHub("<user>/titra-shiny-web")
# GitHub Pages:  see .github/workflows/deploy-shinylive.yml (Shinylive / WebR static deploy)

library(shiny)
library(htmltools)
library(jsonlite)
library(base64enc)

options(shiny.maxRequestSize = 200 * 1024^2)

# Source pure-R Titra analytical & ingestion modules
for (.f in c("utils.R", "signal_utils.R", "analytics.R", "parser.R", "ingest.R", "report.R")) {
  source(file.path("R", .f), local = FALSE)
}

ui <- tagList(
  tags$head(
    tags$meta(charset = "utf-8"),
    tags$meta(name = "viewport", content = "width=device-width, initial-scale=1"),
    tags$meta(name = "theme-color", content = "#B81D33"),
    tags$title("Titra — DBS Programming Studio"),
    tags$link(rel = "icon", type = "image/svg+xml", href = "favicon.svg"),
    tags$link(rel = "stylesheet", href = "nr_dag.css"),
    tags$style(HTML(
      "html, body { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background: #FFFFFF; }
       #titra_host { width: 100vw; height: 100vh; }
       .nr-studio { height: 100vh !important; min-height: 0 !important; border-radius: 0 !important;
                    border-left: none !important; border-right: none !important; border-bottom: none !important;
                    box-shadow: none !important; }"
    ))
  ),
  tags$div(id = "titra_host"),
  tags$script(type = "module", src = "titra_shiny_bridge.js")
)

server <- function(input, output, session) {
  state_env <- new.env(parent = emptyenv())
  state_env$payload <- t_obj()
  state_env$selection <- titra_default_selection()
  state_env$norm <- NULL
  state_env$sources <- list()
  state_env$chunks <- list()
  state_env$input_state <- list(
    data_dir = "", files = list(), loaded = "", selected = "", report = NULL, modality = "lfp"
  )

  push_patch <- function(patch) {
    session$sendCustomMessage("titra_web_patch", patch)
  }

  # Send initial capabilities & empty state (auto-detects WebR / Shinylive)
  is_webr <- grepl("emscripten|wasm", paste(R.version$os, R.version$platform), ignore.case = TRUE)
  session$onFlushed(function() {
    push_patch(list(
      capabilities = list(wasm = is_webr, typst = !is_webr && nzchar(Sys.which("typst")), docx = !is_webr),
      selection = state_env$selection,
      input_state = state_env$input_state
    ))
  }, once = TRUE)

  process_input_request <- function(req) {
    if (is.null(req) || is.null(req$id)) return()
    t0 <- proc.time()[["elapsed"]]
    action <- t_str(req$action %||% "")
    st <- state_env$input_state
    st$id <- req$id
    st$action <- action
    st$error <- ""
    patch <- list()

    tryCatch({
      if (action == "clear") {
        state_env$norm <- NULL
        state_env$sources <- list()
        state_env$payload <- t_obj()
        state_env$selection <- titra_default_selection()
        st$report <- NULL
        st$selected <- ""
        st$loaded <- ""
        st$add_result <- NULL
        st$sources <- list()
        patch$selection <- state_env$selection
        patch$payload <- t_obj()
      } else if (action %in% c("upload", "upload_inspect", "upload_load")) {
        fname <- t_str(req$name %||% "upload.json")
        b64 <- t_str(req$b64 %||% "")
        if (!nzchar(b64)) stop("Upload the file again.")
        raw_bytes <- base64enc::base64decode(b64)
        txt <- rawToChar(raw_bytes)
        Encoding(txt) <- "UTF-8"
        raw_obj <- jsonlite::fromJSON(txt, simplifyVector = FALSE)
        sess <- titra_load_session(raw_obj, name = fname, size_bytes = length(raw_bytes),
                                   ftg_half_bw = t_num(state_env$selection$ftg_half_bw_hz, 4.0))
        st$report <- sess$report
        st$selected <- paste0("upload:", fname)
        st$add_result <- NULL
        if (isTRUE(sess$ok) && action %in% c("upload", "upload_load")) {
          state_env$norm <- sess$norm
          state_env$sources <- sess$sources
          state_env$selection <- sess$selection
          state_env$payload <- sess$payload
          st$loaded <- paste0("upload:", fname)
          st$sources <- t_list(sess$sources)
          patch$selection <- sess$selection
          patch$payload <- sess$payload
        }
      } else if (action == "add") {
        items <- list()
        for (f in req$files %||% list()) {
          rb <- base64enc::base64decode(t_str(f$b64 %||% ""))
          tx <- rawToChar(rb); Encoding(tx) <- "UTF-8"
          items[[length(items) + 1L]] <- list(name = t_str(f$name, "upload.json"), size = length(rb), obj = jsonlite::fromJSON(tx, simplifyVector = FALSE))
        }
        if (!length(items)) stop("Choose a JSON file to add.")
        if (isTRUE(req$replace) || is.null(state_env$norm)) {
          first <- items[[1]]
          sess <- titra_load_session(first$obj, name = first$name, size_bytes = first$size)
          if (!isTRUE(sess$ok)) {
            st$report <- sess$report
          } else {
            norm <- sess$norm; sources <- sess$sources
            for (it in items[-1L]) {
              f2 <- t_detect_format(it$obj)
              n2 <- if (f2 == "bravo") t_bravo_to_percept(it$obj, it$name) else it$obj
              mg <- t_merge_normalized(norm, n2, it$name)
              norm <- mg$norm
              sources[[length(sources) + 1L]] <- list(name = it$name, size = t_human_size(it$size), added = mg$summary)
            }
            parsed <- titra_parse_percept(norm, file_name = first$name)
            rep <- titra_inspect_json(norm, name = first$name, size_bytes = first$size)
            rep$sources <- t_list(sources)
            state_env$norm <- norm; state_env$sources <- sources
            state_env$selection <- titra_default_selection(parsed$payload)
            state_env$payload <- parsed$payload
            st$report <- rep; st$loaded <- paste0("upload:", first$name); st$selected <- st$loaded
            st$sources <- t_list(sources); st$add_result <- NULL
            patch$selection <- state_env$selection
            patch$payload <- state_env$payload
          }
        } else {
          norm <- state_env$norm; sources <- state_env$sources; msgs <- character(0)
          for (it in items) {
            f2 <- t_detect_format(it$obj)
            if (f2 == "unknown") stop(sprintf("%s is not a supported LFP JSON format.", it$name))
            n2 <- if (f2 == "bravo") t_bravo_to_percept(it$obj, it$name) else it$obj
            mg <- t_merge_normalized(norm, n2, it$name)
            norm <- mg$norm
            sources[[length(sources) + 1L]] <- list(name = it$name, size = t_human_size(it$size), added = mg$summary)
            msgs <- c(msgs, mg$summary)
          }
          parsed <- titra_parse_percept(norm, file_name = sources[[1]]$name)
          parsed$payload$metadata$merged <- TRUE
          rep <- titra_inspect_json(norm, name = paste(vapply(sources, `[[`, character(1), "name"), collapse = " + "))
          rep$sources <- t_list(sources)
          state_env$norm <- norm; state_env$sources <- sources
          state_env$selection <- titra_default_selection(parsed$payload)
          state_env$payload <- parsed$payload
          st$report <- rep; st$sources <- t_list(sources)
          st$add_result <- list(ok = TRUE, files = t_arr(vapply(items, `[[`, character(1), "name")),
                                message = paste("Added:", paste(msgs, collapse = "; ")), warnings = list())
          patch$selection <- state_env$selection
          patch$payload <- state_env$payload
        }
      }
    }, error = function(e) {
      st$error <<- conditionMessage(e)
      if (action == "add") {
        st$add_result <<- list(ok = FALSE, conflicts = t_arr(conditionMessage(e)),
                               message = paste("Could not merge file:", conditionMessage(e)))
      }
    })

    st$elapsed_s <- round(proc.time()[["elapsed"]] - t0, 2)
    state_env$input_state <- st
    patch$input_state <- st
    push_patch(patch)
  }

  observeEvent(input$titra_input_request, {
    process_input_request(input$titra_input_request)
  }, ignoreNULL = TRUE)

  observeEvent(input$titra_input_chunk, {
    ch <- input$titra_input_chunk
    if (is.null(ch) || is.null(ch$tx)) return()
    tx <- t_str(ch$tx)
    idx <- as.integer(ch$index) + 1L
    tot <- as.integer(ch$total)
    if (is.null(state_env$chunks[[tx]])) state_env$chunks[[tx]] <- character(tot)
    state_env$chunks[[tx]][idx] <- t_str(ch$data)
    if (all(nzchar(state_env$chunks[[tx]]))) {
      full_json <- paste(state_env$chunks[[tx]], collapse = "")
      state_env$chunks[[tx]] <- NULL
      req <- jsonlite::fromJSON(full_json, simplifyVector = FALSE)
      process_input_request(req)
    }
  }, ignoreNULL = TRUE)

  observeEvent(input$titra_report_request, {
    req <- input$titra_report_request
    if (is.null(req) || is.null(req$id)) return()
    res <- tryCatch(
      t_handle_report_request(state_env$payload, req),
      error = function(e) list(id = req$id, ok = FALSE, error = conditionMessage(e), elapsed_s = 0)
    )
    push_patch(list(report_result = res))
  }, ignoreNULL = TRUE)

  observeEvent(input$titra_selection, {
    state_env$selection <- input$titra_selection
  }, ignoreNULL = TRUE)
}

shinyApp(ui = ui, server = server)
