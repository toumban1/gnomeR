# Main Binary Matrix Function ------------------

#' Enables creation of a binary matrix from a mutation file with
#' a predefined list of samples (rows are samples and columns are genes)
#' @param samples a character vector specifying which samples should be included in the resulting data frame.
#' Default is NULL is which case all samples with an alteration in the mutation, cna or fusions file will be used. If you specify
#' a vector of samples that contain samples not in any of the passed genomic data frames, 0's (or NAs when appropriate if specifying a panel) will be
#' returned for every column of that patient row.
#' @param mutation A data frame of mutations in the format of a maf file.
#' @param mut_type The mutation type to be used. Options are "omit_germline", "somatic_only", "germline_only" or "all". Note "all" will
#' keep all mutations regardless of status (not recommended). Default is omit_germline which includes all somatic mutations, as well as any unknown mutation types (most of which are usually somatic)
#' @param snp_only Boolean to rather the genetics events to be kept only to be SNPs (insertions and deletions will be removed).
#' Default is FALSE.
#' @param include_silent Boolean to keep or remove all silent mutations. TRUE keeps, FALSE removes. Default is FALSE.
#' @param fusion A data frame of fusions. If not NULL the outcome will be added to the matrix with columns ending in ".fus".
#' Default is NULL.
#' @param cna A data frame of copy number alterations. If inputed the outcome will be added to the matrix with columns ending in ".del" and ".amp".
#' Default is NULL.
#' @param specify_panel a character vector of length 1 with panel id (see gnomeR::gene_panels for available panels), "impact", or "no", or a
#' data frame of `sample_id`-`panel_id` pairs specifying panels for which to insert NAs indicating that gene was not tested.
#' If a single panel id is passed, all genes that are not in that panel (see gnomeR::gene_panels) will be set to NA in results.
#' If `"impact"` passed, impact panel version will be inferred based on each sample_id and NA's annotated accordingly for each sample
#' If specific panel IDs passed, genes not tested in that panel will be should be considered. Default When TRUE NAs will fill the cells for genes
#' Default is "no" which returns data as is with no NA annotation.
#' If you wish to specify different panels for each sample, pass a data frame (with all samples included) with columns: `sample_id`, and `panel_id`. Each sample will be
#' annotated with NAs according to that specific panel.
#' @param rm_empty boolean specifying if alteration columns with no events founds should be removed. Default is FALSE
#' @param recode_aliases boolean specifying if automated gene name alias matching should be done. Default is TRUE. When TRUE
#' the function will check for genes that may have more than 1 name in your data using the aliases im gnomeR::impact_gene_info alias column
#' @param ... Further arguments passed to the oncokb() function such a token
#' @return a data frame with sample_id and alteration binary columns with values of 0/1
#' @export
#' @examples
#' mut.only <- create_gene_binary(mutation = gnomeR::mutations)
#'
#' samples <- gnomeR::mutations$sampleId
#'
#' bin.mut <- create_gene_binary(
#'   samples = samples, mutation = gnomeR::mutations,
#'   mut_type = "omit_germline", snp_only = FALSE,
#'   include_silent = FALSE
#' )
#'
#' @import dplyr
#' @import dtplyr
#' @import stringr

create_gene_binary <- function(samples=NULL,

                          mutation = NULL,
                          mut_type = c("omit_germline", "somatic_only", "germline_only", "all"),
                          snp_only = FALSE,
                          include_silent = FALSE,

                          fusion = NULL,

                          cna = NULL,

                          specify_panel = "no",
                          rm_empty = FALSE,
                          recode_aliases = TRUE,
                          ...){

  genie_gene_info <- gnomeR::genie_gene_info
  impact_gene_info <- gnomeR::impact_gene_info
  pathways <- gnomeR::pathways
  gene_panels <- gnomeR::gene_panels

  # Check Arguments ------------------------------------------------------------

  if(is.null(mutation) && is.null(fusion) && is.null(cna)) {
    cli::cli_abort("You must provided at least one of the three following arguments: {.code mutation}, {.code fusion} or {.code cna}.")
  }

  # Check that mutation, fusion, cna is data.frame
  is_df <- purrr::map(
    list(mutation = mutation, fusion = fusion, cna = cna),
    ~dplyr::case_when(
      !is.null(.x) ~ "data.frame" %in% class(.x))
    ) %>%
    purrr::compact()

  not_df <- names(is_df[which(is_df == FALSE)])

  if(length(not_df) > 0) {
    cli::cli_abort("{.code {not_df}} must be a data.frame")
  }


  # if samples not passed we will infer it from data frames
  switch(is.null(samples),
         cli::cli_alert_info("{.code samples} argument is {.code NULL}. We will infer your cohort inclusion and resulting data frame will include all samples with at least one alteration in {.field mutation}, {.field fusion} or {.field cna} data frames"))

  # * mut_type-----
  mut_type <- match.arg(mut_type)

  # * Specify_panel must be a known character or data frame with specified column-----

  # make tibbles into data.frames - idk if this is needed, could change switch to ifelse I think a alternative
  if("tbl" %in% class(specify_panel)) {
    specify_panel <- as.data.frame(specify_panel)
  }

  specify_panel <-
    switch(class(specify_panel),
         "character" = {

           choices_arg = c("no", "impact", "IMPACT", gene_panels$gene_panel)
           match.arg(specify_panel, choices = choices_arg)
         },

         "data.frame" = {

           specify_panel %>%
             purrr::when(
               length(setdiff(c(specify_panel$gene_panel), gene_panels$gene_panel)) > 0 ~
                           cli::cli_abort("Panels not known: {.val {setdiff(c(specify_panel$gene_panel), gene_panels$gene_panel)}}. See {.code  gnomeR::gene_panels} for known panels, or skip annotation with {.code specify_panel = 'no'} or indicating {.code 'no'} for those samples in {.field panel_id} column of sample_id-panel_id pair data frame"),
                         TRUE ~ .)},

           cli::cli_abort("{.code specify_panel} must be a character vector of length 1 or a data frame.")
         )


  # * Mutation  checks  --------

  # standardize columns names
  mutation <- switch(!is.null(mutation),
                     sanitize_mutation_input(mutation = mutation))

  # * Fusion checks  ----------
  fusion <- switch(!is.null(fusion),
                   sanitize_fusion_input(fusion))

  # * CNA checks  ------------
  cna <- switch(!is.null(cna), {
    sanitize_cna_input(cna)

  })


  #  Make Final Sample List ----------------------------------------------------


  # If user doesn't pass a vector, use samples in files as final sample list
    samples_final <- samples %||%
      c(mutation$sample_id,
        fusion$sample_id,
        cna$sample_id) %>%
      as.character() %>%
      unique()

    # Binary matrix for each data type ----------------------------------------------
    mutation_binary_df <- switch(!is.null(mutation),
                              .mutations_gene_binary(mutation = mutation,
                                                       samples = samples_final,
                                                       mut_type = mut_type,
                                                       snp_only = snp_only,
                                                       include_silent = include_silent,
                                                       specify_panel = specify_panel,
                                                       recode_aliases = recode_aliases))


  # fusions
  fusion_binary_df <-  switch(!is.null(fusion),
                           .fusions_gene_binary(fusion = fusion,
                                                  samples = samples_final,
                                                  specify_panel = specify_panel,
                                                  recode_aliases = recode_aliases))


  # cna
  cna_binary_df <- switch(!is.null(cna),
                       .cna_gene_binary(cna = cna,
                                          samples = samples_final,
                                          specify_panel = specify_panel,
                                          recode_aliases = recode_aliases))

  # put them all together
  all_binary <- bind_cols(list(mutation_binary_df,
                               fusion_binary_df,
                               cna_binary_df))

  # Platform-specific NA Annotation ------

  # we've already checked the arg is valid
  # If character, make into data frame sample-panel pair to input in function
  if(is.character(specify_panel)) {

    sample_panel_pair <- switch(specify_panel,
      "impact" = specify_impact_panels(all_binary),
      "no" = {
        rownames(all_binary) %>%
          as.data.frame() %>%
          stats::setNames("sample_id") %>%
          mutate(panel_id = "no")
      },

      rownames(all_binary) %>%
        as.data.frame() %>%
        stats::setNames("sample_id") %>%
        mutate(panel_id = specify_panel)
    )
    # create data frame of sample IDs

  }

  all_binary <- annotate_any_panel(sample_panel_pair, all_binary)

  # Remove Empty Columns ------
  not_all_na <- which(
      apply(all_binary, 2,
                     function(x){
                       length(unique(x[!is.na(x)]))
                       }) > 1)

  if(rm_empty) {
    all_binary <- all_binary[, which(not_all_na > 1)]
  }

  # Warnings and Attributes --------

  # return omitted zero  samples as warning/attribute

  # samples_omitted <- setdiff(samples, samples_final)
  #
  # if(sum(samples_omitted) > 0) {
  #   attr(all_binary, "omitted") <- samples_omitted
  #
  #   cli::cli_warn("i" = "{length(samples_omitted)} samples were omitted due to  not have any mutations found in the mutation file.
  #                 To view these samples see {.code attr(<your_df>, 'omitted')}")
  # }

  return(all_binary)
}


# Mutations Binary Matrix -----------------------------------------------------

#' Make Binary Matrix From Mutation data frame
#'
#' @inheritParams create_gene_binary
#'
#' @return a data frame
#' @export
#'
.mutations_gene_binary <- function(mutation,
                                     samples,
                                     mut_type,
                                     snp_only,
                                     include_silent,
                                     specify_panel,
                                     recode_aliases = recode_aliases){

  if(recode_aliases) {
    mutation <- recode_alias(mutation)
  }

  # apply filters --------------
 mutation <- mutation %>%
   purrr::when(
     snp_only ~ filter(., .data$variant_type == "SNP"),
     ~.
   ) %>%
   purrr::when(
     !include_silent ~ filter(., .data$variant_classification != "Silent"),
     ~.
   ) %>%
   purrr::when(
     mut_type == "all" ~ .,
     mut_type == "omit_germline" ~ {
       filter(., .data$mutation_status != "GERMLINE" |
         .data$mutation_status != "germline" | is.na(.data$mutation_status))

       blank_muts <- mutation %>%
         filter(is.na(.data$mutation_status) | .$mutation_status == "") %>%
         nrow()

       if ((blank_muts > 0)) {
         cli::cli_warn("{(blank_muts)} mutations marked as blank were retained in the resulting binary matrix.")
       }
       return(.)
     },
     mut_type == "somatic_only" ~ filter(., .data$mutation_status == "SOMATIC" |
       .data$mutation_status == "somatic"),
     mut_type == "germline_only" ~ filter(., .data$mutation_status == "GERMLINE" |
       .data$mutation_status == "germline"),
     TRUE ~ .
   )





  # create empty data.frame to hold results -----
  mut <- as.data.frame(matrix(0L, nrow=length(samples),
                              ncol=length(unique(mutation$hugo_symbol))))

  colnames(mut) <- unique(mutation$hugo_symbol)
  rownames(mut) <- samples

  # populate matrix
  for(i in samples){
    genes <- mutation$hugo_symbol[mutation$sample_id %in% i]
    if(length(genes) != 0) {
      mut[match(i, rownames(mut)), match(unique(as.character(genes)), colnames(mut))] <- 1
      }
  }

  return(mut)
}



# Fusions Binary Matrix -----------------------------------------------------

#' Make Binary Matrix From Fusion data frame
#'
#' @inheritParams create_gene_binary
#'
#' @return a data frame
#'
.fusions_gene_binary <- function(fusion,
                                 samples,
                                 specify_panel,
                                 recode_aliases){

  # CHECK HERE----
  if("site_1_hugo_symbol" %in% colnames(fusion)) {
    fusion <- rename(fusion, "hugo_symbol" = "site_1_hugo_symbol")
  }


  fusion <- fusion %>%
    filter(.data$sample_id %in% samples)

  if(recode_aliases) {
    fusion <- recode_alias(fusion)
  }

  # create empty data frame -----
  fusions_out <- as.data.frame(matrix(0L, nrow=length(samples),
                              ncol=length(unique(fusion$hugo_symbol))))


  colnames(fusions_out) <- unique(fusion$hugo_symbol)
  rownames(fusions_out) <- samples

  # populate matrix
  for(i in samples){
    genes <- fusion$hugo_symbol[fusion$sample_id %in% i]
    if(length(genes) != 0)
      fusions_out[match(i,rownames(fusions_out)),
                 match(unique(as.character(genes)),colnames(fusions_out))] <- 1

  }

  # add .fus suffix on columns
  if(ncol(fusions_out) > 0) {
    colnames(fusions_out) <- paste0(colnames(fusions_out),".fus")
  }
  return(fusions_out)
}


# CNA Binary Matrix -----------------------------------------------------

#' Make Binary Matrix From CNA data frame
#'
#' @inheritParams create_gene_binary
#'
#' @return a data frame
#'
.cna_gene_binary <- function(cna,
                               samples,
                               specify_panel,
                               recode_aliases){


  if(recode_aliases) {
    cna <- recode_alias(cna)
  }


  # * deletions ----------
  cna_filt <- cna %>%
    filter(.data$alteration == "deletion")

  # create empty data.frame to hold results -
  cna_del <- as.data.frame(matrix(0L, nrow=length(samples),
                                  ncol=length(unique(cna_filt$hugo_symbol))))

  colnames(cna_del) <- unique(cna_filt$hugo_symbol)
  rownames(cna_del) <- unique(samples)

  if(nrow(cna_filt) > 0) {

    # populate matrix
    for(i in samples){
      genes <- cna_filt$hugo_symbol[cna_filt$sample_id %in% i]
      if(length(genes) != 0) {
        cna_del[match(i, rownames(cna_del)), match(unique(as.character(genes)), colnames(cna_del))] <- 1
      }
    }

    n # filter those in final samples list
    cna_del <- cna_del[rownames(cna_del) %in% samples,]
    names(cna_del) <- paste0(names(cna_del), ".Del")

  }
  # * amplifications ----------

  cna_filt <- cna %>%
    filter(.data$alteration == "amplification")

  # create empty data.frame to hold results
  cna_amp <- as.data.frame(matrix(0L, nrow=length(samples),
                                  ncol=length(unique(cna_filt$hugo_symbol))))

  colnames(cna_amp) <- unique(cna_filt$hugo_symbol)
  rownames(cna_amp) <- samples

  if(nrow(cna_filt) > 0) {

    # populate matrix
    for(i in samples){
      genes <- cna_filt$hugo_symbol[cna_filt$sample_id %in% i]
      if(length(genes) != 0) {
        cna_amp[match(i, rownames(cna_amp)), match(unique(as.character(genes)), colnames(cna_amp))] <- 1
      }
    }

    # filter those in final samples list
    cna_amp <- cna_amp[rownames(cna_amp) %in% samples,]
    names(cna_amp) <- paste0(names(cna_amp), ".Amp")
  }


  # * join deletions and amplifications -----
  cna_res <- bind_cols(cna_amp, cna_del)

  return(cna_res)
}




# WIDE CNA Binary Matrix -----------------------------------------------------

#' #' Make Binary Matrix From CNA data frame
#' #'
#' #' @inheritParams create_gene_binary
#' #'
#' #' @return a data frame
#' #'
#' .cna_gene_binary_wide <- function(cna,
#'                                   samples,
#'                                   cna_binary,
#'                                   cna_relax,
#'                                   specify_panel,
#'                                   recode_aliases){
#'
#'
#'   if(recode_aliases) {
#'     cna <- recode_alias(cna)
#'   }
#'
#'   # If more than 1 row per gene, combine rows
#'   dups <- cna$hugo_symbol[duplicated(cna$hugo_symbol)]
#'
#'   if(length(dups) > 0){
#'     for(i in dups){
#'       temp <- cna[which(cna$hugo_symbol == i),] # grep(i, cna$hugo_symbol,fixed = TRUE)
#'       temp2 <- as.character(unlist(apply(temp, 2, function(x){
#'         if(all(is.na(x)))
#'           out <- NA
#'         else if(anyNA(x))
#'           out <- x[!is.na(x)]
#'         else if(length(unique(x)) > 1)
#'           out <- x[which(x != 0)]
#'         else
#'           out <- x[1]
#'         return(out)
#'       })))
#'       temp2[-1] <- as.numeric(temp2[-1])
#'       cna <- rbind(cna[-which(cna$hugo_symbol == i),],
#'                    temp2)
#'     }
#'   }
#'
#'   rownames(cna) <- cna$hugo_symbol
#'   cna <- cna[,-1]
#'
#'   # flip
#'   cna <- as.data.frame(t(cna))
#'
#'   # fix names
#'   rownames(cna) <- gsub("\\.","-",rownames(cna))
#'
#'   # filter those in final samples list
#'   cna <- cna[rownames(cna) %in% samples,]
#'
#'   # If cna binary
#'   samples_temp <- rownames(cna)
#'
#'   if(cna_binary){
#'     temp <- do.call("cbind",apply(cna,2,function(x){
#'       if(cna_relax){
#'         yA <- ifelse(as.numeric(x)>=0.9,1,0)
#'         yD <- ifelse(as.numeric(x)<=-0.9,1,0)
#'       }
#'       if(!cna_relax){
#'         yA <- ifelse(as.numeric(x)==2,1,0)
#'         yD <- ifelse(as.numeric(x)<=-0.9,1,0) #==-2
#'       }
#'       out <- as.data.frame(cbind(yA,yD))
#'       colnames(out) <- c("Amp","Del")
#'       return(out)
#'     }))
#'
#'     cna <- temp[,apply(temp,2,function(x){sum(x,na.rm=T) > 0})]
#'     rownames(cna) <- samples_temp
#'
#'     # add missing
#'     if(length(which(is.na(match(samples,rownames(cna))))) > 0){
#'       missing <- samples[which(is.na(match(samples,rownames(cna))))]
#'       add <- as.data.frame(matrix(0L,nrow = length(missing),ncol = ncol(cna)))
#'       rownames(add )  <- missing
#'       colnames(add) <- colnames(cna)
#'       cna <- as.data.frame(rbind(cna,add))
#'     }
#'     cna <- cna[match(samples,rownames(cna)),]
#'     cna[is.na(cna)] <- 0
#'   }
#'
#'   if(!cna_binary){
#'
#'     # add missing
#'     if(length(which(is.na(match(samples,rownames(cna))))) > 0){
#'       missing <- samples[which(is.na(match(samples,rownames(cna))))]
#'       add <- as.data.frame(matrix(0L,nrow = length(missing),ncol = ncol(cna)))
#'       rownames(add )  <- missing
#'       colnames(add) <- colnames(cna)
#'       cna <- as.data.frame(rbind(cna,add))
#'       cna <- cna[match(samples,rownames(cna)),]
#'     }
#'     cna <- cna[match(samples,rownames(cna)),]
#'
#'     cna <- cna %>%
#'       mutate_all(~ as.numeric(gsub(" ","",as.character(.)))) %>%
#'       mutate_all(
#'         ~ case_when(
#'           . == 0 ~ "NEUTRAL",
#'           . %in% c(-1.5,-1) ~ "LOH",
#'           . == 1 ~ "GAIN",
#'           . == 2 ~ "AMPLIFICATION",
#'           . == -2 ~ "DELETION",
#'         )
#'       ) %>%
#'       mutate_all(
#'         ~factor(.,
#'                 levels = c("NEUTRAL","DELETION","LOH","GAIN","AMPLIFICATION")[
#'                   which(c("NEUTRAL","DELETION","LOH","GAIN","AMPLIFICATION") %in% .)
#'                 ])
#'       )
#'
#'
#'     # add cna annotation
#'     if(ncol(cna) > 0) {
#'       colnames(cna) <- paste0(colnames(cna),".cna")
#'     }
#'
#'     rownames(cna) <- samples
#'     cna[is.na(cna)] <- "NEUTRAL"
#'   }
#'
#'   return(cna)
#' }
#'
#' #create_gene_binary(mutation = gnomeR::mutations, specify_panel = "no")
#'
