# # This script creates and saves the IMPACT Gene Info Data Frame within the package

library(cbioportalR)
library(tidyverse)
library(gnomeR)

set_cbioportal_db("msk")

# Functions --------------------------------------------------------------------

# function clean gene names
clean_genes <- function(impact_plat, name) {

  impact_plat %>%
    mutate(gene = str_replace_all(gene, "-", "."),
              platform = name) %>%
    filter(gene != "Tiling") %>%
    distinct()
}

# a function to get aliases from cbioportal API
get_alias <- function(hugo_symbol) {
  url_path = paste0("genes/", hugo_symbol, "/aliases")
  res <- cbioportalR::cbp_api(url_path)

  res <- res$content
  unlist(res)
}


# Get IMPACT genes -----------------------------------------------------------

api_341 <- get_gene_panel(panel_id = "IMPACT341") %>%
  transmute(gene = hugoGeneSymbol,
         entrez_id = entrezGeneId)

api_410 <- get_gene_panel(panel_id = "IMPACT410") %>%
  transmute(gene = hugoGeneSymbol,
         entrez_id = entrezGeneId)

api_468 <- get_gene_panel(panel_id = "IMPACT468") %>%
  transmute(gene = hugoGeneSymbol,
         entrez_id = entrezGeneId)

api_505 <- get_gene_panel(panel_id = "IMPACT505") %>%
  transmute(gene = hugoGeneSymbol,
            entrez_id = entrezGeneId)

l_api <- list("api_341" = api_341,
          "api_410" = api_410,
          "api_468" = api_468,
          "api_505" = api_505)

# create data frame of genes
impact_genes <- map2_df(l_api, names(l_api),
                        ~clean_genes(impact_plat = .x,
                                       name = .y))

impact_genes <- impact_genes %>%
  select(gene, entrez_id) %>%
  unique()


# Get Gene Entrez IDs  --------------------------------------------------------

# # API call to get a list of genes and entrez ids
all_genes <- get_genes()

all_genes <- all_genes %>%
  filter(type == "protein-coding") %>%
  janitor::clean_names() %>%
  rename("hugo_symbol" = hugo_gene_symbol)

# Get Aliases  --------------------------------------------------------

# get all aliases for impact genes
impact_alias <- impact_genes %>%
  select(gene) %>%
  dplyr::mutate(alias = purrr::map(gene,
                                   ~tryCatch(get_alias(.x),
                                             error = function(e) NA_character_)))
# unnested long version
impact_alias_table <- impact_alias %>%
  unnest(cols = c(alias),
         keep_empty = TRUE)

impact_alias_table %>%
  filter(gene == alias)


impact_alias_table <- impact_alias_table %>%
  filter(gene != alias)

impact_alias_table$gene[map_lgl(impact_alias_table$gene, ~.x %in%
                                  impact_alias_table$alias)] %>%
  unique()

impact_alias_table <- impact_alias_table %>%

  # I don't think these are aliases even though they came up. They usually only come up one way
  # I think they are separate genes although I am not sure
  filter(!(gene == "SOS1" & alias == "HGF")) %>%
  filter(!(gene == "HRAS" & alias == "KRAS")) %>%
  filter(!(gene == "TP53BP1" & alias == "TP53")) %>%
  filter(!(gene == "EZH2" & alias == "EZH1")) %>%

  # are MLL2 and MLL4 interchangeable?! - JJ email on 1/25/2021 says KMT2B = MLL4
  filter(!(gene == "KMT2D" & alias == "MLL4")) %>%
  filter(!(gene == "KMT2B" & alias == "MLL2")) %>%
  filter(!(gene == "ATRX" & alias == "RAD54L")) %>%
  distinct()

# check we've recoded all
impact_alias_table$gene[map_lgl(impact_alias_table$gene, ~.x %in% impact_alias_table$alias)] %>%
  unique()

impact_alias_table <- impact_alias_table %>%
  rename("hugo_symbol" = gene)

impact_alias_table <- impact_alias_table %>%
  left_join(., select(impact_genes, gene, entrez_id),
               by = c("hugo_symbol" = "gene")) %>%
  left_join(., select(all_genes, hugo_symbol, entrez_gene_id),
                       by = c("alias" = "hugo_symbol")) %>%
             rename(alias_entrez_id = entrez_gene_id)

impact_alias_table <- impact_alias_table %>%
  distinct()


usethis::use_data(impact_alias_table , overwrite = TRUE)
# save(impact_gene_info, file = here::here("impact_gene_info.RData"))

