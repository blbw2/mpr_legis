# Setup ----
library(httr2)
library(purrr)
library(tibble)
library(dplyr)

# Config ----
# Credentials in ~/.Renviron (usethis::edit_r_environ()), then restart R:
#   PISTE_CLIENT_ID=...
#   PISTE_CLIENT_SECRET=...
lf_env <- "prod"  # "sandbox" needs the credentials of a sandbox application

lf_urls <- list(
  prod    = list(oauth = "https://oauth.piste.gouv.fr/api/oauth/token",
                 api   = "https://api.piste.gouv.fr/dila/legifrance/lf-engine-app"),
  sandbox = list(oauth = "https://sandbox-oauth.piste.gouv.fr/api/oauth/token",
                 api   = "https://sandbox-api.piste.gouv.fr/dila/legifrance/lf-engine-app")
)[[lf_env]]

mpr_decree <- list(jorf_id = "JORFTEXT000041400291", num = "2020-26")

# User-facing functions ----
lf_token <- function() {
  tok <- oauth_flow_client_credentials(lf_client(), scope = "openid")
  message("Token OK, expires ", as.POSIXct(tok$expires_at))
  invisible(tok)
}

lf_ping <- function() {
  lf_request("list/ping") |> req_headers(Accept = "*/*") |> req_perform() |> resp_body_string()
}

lf_search_loda <- function(num, date, nature = "DECRET") {
  body <- list(
    recherche = list(
      champs = list(list(
        typeChamp = "NUM", operateur = "ET",
        criteres = list(list(typeRecherche = "EXACTE", valeur = num, operateur = "ET"))
      )),
      filtres = list(
        list(facette = "NATURE", valeurs = list(nature)),
        list(facette = "DATE_VERSION", singleDate = to_ms(date))
      ),
      pageNumber = 1, pageSize = 10, operateur = "ET",
      sort = "PERTINENCE", typePagination = "DEFAUT"
    ),
    fond = "LODA_DATE"
  )
  res <- lf_post("search", body)
  map(res$results, parse_search_hit) |> list_rbind()
}

lf_get_version <- function(text_id, date) {
  raw <- lf_post("consult/lawDecree", list(textId = text_id, date = to_ms(date)))
  list(
    date     = as.Date(date),
    raw      = raw,
    articles = map(collect_articles(raw), parse_article) |> list_rbind()
  )
}

# One row per article changed at each version start, with the amending act
lf_version_history <- function(text_id, from, to) {
  d   <- as.Date(from)
  out <- list()
  while (d <= as.Date(to)) {
    v     <- lf_get_version(text_id, d)
    start <- as.Date(v$raw$dateDebutVersion)
    end   <- as.Date(v$raw$dateFinVersion)
    out[[length(out) + 1]] <- v$articles |>
      filter(date_debut == start) |>
      mutate(version_start = start, version_end = end, .before = 1)
    if (is.na(end) || end <= d) break
    d <- end
  }
  list_rbind(out)
}

# Helpers ----
lf_client <- function() {
  id     <- Sys.getenv("PISTE_CLIENT_ID")
  secret <- Sys.getenv("PISTE_CLIENT_SECRET")
  if (id == "" || secret == "") stop("PISTE_CLIENT_ID / PISTE_CLIENT_SECRET not set (see Config).")
  oauth_client(id = id, secret = secret, token_url = lf_urls$oauth,
               auth = "body", name = "piste_legifrance")
}

# Token is cached in memory by httr2 and refreshed on expiry
lf_request <- function(path) {
  request(lf_urls$api) |>
    req_url_path_append(path) |>
    req_oauth_client_credentials(lf_client(), scope = "openid") |>
    req_headers(Accept = "application/json") |>
    req_throttle(rate = 5) |>
    req_retry(max_tries = 3)
}

lf_post <- function(path, body) {
  lf_request(path) |>
    req_body_json(body) |>
    req_perform() |>
    resp_body_json()
}

parse_search_hit <- function(hit) {
  t1 <- hit$titles[[1]] %||% list()
  tibble(
    id     = t1$id %||% NA_character_,
    cid    = t1$cid %||% NA_character_,
    title  = t1$title %||% NA_character_,
    nature = hit$nature %||% NA_character_,
    etat   = hit$etat %||% NA_character_
  )
}

collect_articles <- function(node) {
  c(node$articles %||% list(),
    list_flatten(map(node$sections %||% list(), collect_articles)))
}

parse_article <- function(a) {
  tibble(
    id         = a$id %||% NA_character_,
    cid        = a$cid %||% NA_character_,
    num        = a$num %||% NA_character_,
    etat       = a$etat %||% NA_character_,
    date_debut = from_ms(a$dateDebut),
    date_fin   = from_ms(a$dateFin),
    modificator      = a$modificatorTitle %||% NA_character_,
    modificator_cid  = a$modificatorCid %||% NA_character_,
    modificator_date = as.Date(a$modificatorDate %||% NA_character_),
    text       = html_to_text(a$content)
  )
}

check_version <- function(v, expect_cid) {
  stopifnot(
    "no articles returned" = nrow(v$articles) > 0,
    "wrong text returned"  = identical(v$raw$cid, expect_cid) || grepl(mpr_decree$num, v$raw$title %||% "")
  )
  out_of_window <- v$articles |> filter(!(date_debut <= v$date & v$date < date_fin))
  if (nrow(out_of_window) > 0) {
    print(out_of_window)
    stop("articles not in force at ", v$date)
  }
  message(v$date, ": ", nrow(v$articles), " articles, all in force at that date")
}

# Helpers of helpers ----
to_ms <- function(date) {
  as.numeric(as.POSIXct(paste(as.Date(date), "12:00:00"), tz = "Europe/Paris")) * 1000
}

from_ms <- function(x) {
  if (is.null(x)) return(as.Date(NA))
  as.Date(as.POSIXct(x / 1000, origin = "1970-01-01", tz = "Europe/Paris"))
}

html_to_text <- function(x) {
  if (is.null(x) || x == "") return(NA_character_)
  xml2::xml_text(xml2::read_html(paste0("<div>", x, "</div>")))
}

# 1. Auth + ping ----
lf_token()
lf_ping()

# 2. Resolve the consolidated id of the MPR decree ----
hits <- lf_search_loda(mpr_decree$num, Sys.Date())
hits
# search ids carry a version suffix, e.g. LEGITEXT000041403207_01-09-2026
legitext_id <- hits |> filter(cid == mpr_decree$jorf_id) |> pull(id) |> first() |> sub(pattern = "_.*", replacement = "")
stopifnot("decree not found by search" = !is.na(legitext_id))

# 3. Test: retrieve two dated versions of the decree ----
v_2020 <- lf_get_version(legitext_id, "2020-02-01")
v_2025 <- lf_get_version(legitext_id, "2025-01-01")

check_version(v_2020, mpr_decree$jorf_id)
check_version(v_2025, mpr_decree$jorf_id)

stopifnot("both dates return the same version" =
            !identical(v_2020$articles$id, v_2025$articles$id))

# Soft check (unverified prior): landlords ("bailleurs") only eligible from 2021
c(v_2020 = any(grepl("bailleur", v_2020$articles$text, ignore.case = TRUE)),
  v_2025 = any(grepl("bailleur", v_2025$articles$text, ignore.case = TRUE)))

# Eyeball against the web version:
# https://www.legifrance.gouv.fr/loda/id/JORFTEXT000041400291/2020-02-01/
v_2020$articles |> select(num, date_debut, date_fin, text)

dir.create("data/raw", recursive = TRUE, showWarnings = FALSE)
jsonlite::write_json(v_2020$raw, "data/raw/decret_2020-26_v2020-02-01.json", auto_unbox = TRUE)
jsonlite::write_json(v_2025$raw, "data/raw/decret_2020-26_v2025-01-01.json", auto_unbox = TRUE)

# 4. Amending acts, 2021-2023 (amounts arrêté = LEGITEXT000041403279) ----
# Spring 2022 bonus = Arrêté du 7 avril 2022 (JORFTEXT000045545997), from 2022-04-15
hist_arrete <- lf_version_history("LEGITEXT000041403279", "2021-07-01", "2023-01-31")
hist_arrete |> distinct(version_start, version_end, modificator, modificator_cid)
