#' @title Join barcodes with additional variables
#'
#' @description Each member of the \code{joinWith()}-family takes a data.frame as
#' input that contains at least the variables \emph{barcodes} and \emph{sample}.
#' (Easily obtained with the \code{spata::coords()}-family.) It joins them over
#'  the \emph{barcodes}-variable with a specified aspect.
#'
#' @param object A valid spata-object.
#' @inherit check_coords_df params
#' @inherit check_features params
#' @inherit check_gene_sets params
#' @inherit check_genes params
#' @inherit check_smooth params
#' @inherit check_method params
#' @inherit verbose params
#' @param variables A named list. Names must contain one of \emph{features, genes}
#' or \emph{gene_sets}. The input of \code{coords_df} will be joined with
#' the respective elements of each slot by calling the appropriate
#' \code{joinWith*()}-function.
#'
#' @return The input data.frame of \code{coords_df} joined with all the
#' specified variable-elements (by the key-variable \emph{barcodes}).
#'
#' @export

joinWithFeatures <- function(object,
                             coords_df,
                             features,
                             smooth = FALSE,
                             smooth_span = 0.02,
                             verbose = TRUE){

  # 1. Control --------------------------------------------------------------

  # lazy check

  check_object(object)
  check_coords_df(coords_df)
  check_smooth(df = coords_df, smooth = smooth, smooth_span = smooth_span)


  # adjusting check
  features <- check_features(object, features = features)

  # -----

  # 2. Join data ------------------------------------------------------------

  fdata <-
    featureData(object, of_sample = base::unique(coords_df$sample)) %>%
    dplyr::select(dplyr::all_of(x = c("barcodes", features)))

  joined_df <-
    dplyr::left_join(x = coords_df, y = fdata, by = "barcodes")

  # -----

  # 3. Smooth if specified -------------------------------------------------

  if(base::isTRUE(smooth)){

    joined_df <-
      purrr::imap_dfr(.x = joined_df,
                      .f = hlpr_smooth,
                      coords_df = joined_df,
                      verbose = verbose,
                      smooth_span = smooth_span,
                      aspect = "feature",
                      subset = features)

  }

  # -----

  base::return(joined_df)

}


#' @rdname joinWithFeatures
#' @export
joinWithGenes <- function(object,
                          coords_df,
                          genes,
                          average_genes = FALSE,
                          smooth = FALSE,
                          smooth_span = 0.02,
                          normalize = TRUE,
                          verbose = TRUE){

  # 1. Control --------------------------------------------------------------

  # lazy check

  check_object(object)
  check_coords_df(coords_df)
  check_smooth(df = coords_df, smooth = smooth, smooth_span = smooth_span)

  # adjusting check
  rna_assay <- exprMtr(object, of_sample = base::unique(coords_df$sample))
  genes <- check_genes(object, genes = genes, rna_assay = rna_assay)

  # -----

  # 2. Extract expression values and join with coords_df ---------------------

  barcodes <- coords_df$barcodes

  # compute mean if necessary
  if(base::length(genes) > 1 && average_genes){

    rna_assay <- base::colMeans(rna_assay[genes, barcodes])
    col_names <- "mean_genes"

  } else if(base::length(genes) > 1){

    rna_assay <- t(rna_assay[genes, barcodes])
    col_names <- genes

  } else if(base::length(genes) == 1){

    rna_assay <- rna_assay[genes, barcodes]

    if(base::isTRUE(average_genes)){
      col_names <- "mean_genes"
    } else {
      col_names <- genes
    }


  }

  # convert results to data frame with appropriate column names
  gene_vls <-
    base::as.data.frame(rna_assay, row.names = NULL) %>%
    magrittr::set_colnames(value = col_names) %>%
    dplyr::mutate(
      barcodes = coords_df$barcodes
    )


  # join both
  joined_df <-
    dplyr::left_join(x = coords_df, y = gene_vls, by = "barcodes")

  # -----

  # 3. Smooth and normalize if specified ------------------------------------

  if(base::isTRUE(smooth)){

    joined_df <-
      purrr::imap_dfr(.x = joined_df,
                      .f = hlpr_smooth,
                      coords_df = joined_df,
                      verbose = verbose,
                      smooth_span = smooth_span,
                      aspect = "gene",
                      subset = col_names)


  }

  if(base::isTRUE(normalize)){

    joined_df <-
      purrr::imap_dfr(.x = joined_df,
                      .f = hlpr_normalize_imap,
                      aspect = "Gene",
                      verbose = verbose,
                      subset = col_names
      )

  }

  # -----

  base::return(joined_df)

}


#' @rdname joinWithFeatures
#' @export
joinWithGeneSets <- function(object,
                             coords_df,
                             gene_sets,
                             method_gs = "mean",
                             smooth = FALSE,
                             smooth_span = 0.02,
                             normalize = TRUE,
                             verbose = TRUE){

  # 1. Control --------------------------------------------------------------

  # lazy check

  check_object(object)
  check_coords_df(coords_df)
  check_smooth(df = coords_df, smooth = smooth, smooth_span = smooth_span)
  check_method(method_gs = method_gs)


  # adjusting check
  gene_sets <- check_gene_sets(object, gene_sets = gene_sets)

  # -----

  # 2. Extract gene set data and join with coords_df ------------------------

  rna_assay <- exprMtr(object = object, of_sample = base::unique(coords_df$sample))
  gene_set_df <- object@used_genesets
  joined_df <- coords_df

  for(i in base::seq_along(gene_sets)){

    # get gene names of specified gene sets
    genes <-
      gene_set_df %>%
      dplyr::filter(ont %in% gene_sets[i]) %>%
      dplyr::filter(gene %in% base::rownames(rna_assay)) %>%
      dplyr::pull(gene)

    # apply specified method to handle gene sets
    if(method_gs == "mean"){

      geneset_vls <-
        base::colMeans(rna_assay[genes, ]) %>%
        base::as.data.frame() %>%
        magrittr::set_colnames(value = gene_sets[i]) %>%
        tibble::rownames_to_column(var = "barcodes")

      if(verbose){

        base::message(stringr::str_c(
          "Calculating expression score for gene set ",
          "(",i, "/", base::length(gene_sets), ")", "  '",
          gene_sets[i],
          "' according to method: '",
          method_gs,
          "'.",
          sep = ""))

      }


    } else if(method_gs %in% c("gsva", "ssgsea", "zscore", "plage")) {

      if(verbose){

        base::message(stringr::str_c(
          "Calculating expression score for gene set ",
          "(",i, "/", base::length(gene_sets), ")", "  '",
          gene_sets[i],
          "' according to method: '",
          method_gs,
          "'. This might take a few moments.",
          sep = ""))

      }

      geneset_vls <-
        GSVA::gsva(expr = rna_assay[genes,],
                   gset.idx.list = gene_set_df,
                   mx.diff = 1,
                   parallel.sz = 2,
                   method = method_gs,
                   verbose = FALSE) %>%
        t() %>%
        as.data.frame() %>%
        magrittr::set_colnames(value = gene_sets[i]) %>%
        tibble::rownames_to_column(var = "barcodes")

    } else {

      stop("Please enter valid method to handle gene sets.")

    }

    # gradually add gene_set columns to joined_df
    joined_df <-
      dplyr::left_join(x = joined_df, y = geneset_vls, by = "barcodes")

  }

  # -----


  # 3. Smooth and normalize if specified ------------------------------------

  if(base::isTRUE(smooth)){

    joined_df <-
      purrr::imap_dfr(.x = joined_df,
                      .f = hlpr_smooth,
                      coords_df = joined_df,
                      verbose = verbose,
                      smooth_span = smooth_span,
                      aspect = "gene set",
                      subset = gene_sets)

  }

  if(base::isTRUE(normalize)){

    joined_df <-
      purrr::imap_dfr(.x = joined_df,
                      .f = hlpr_normalize_imap,
                      aspect = "Gene set",
                      verbose = verbose,
                      subset = gene_sets)

  }

  # -----

  base::return(joined_df)

}

#' @rdname joinWithFeatures
#' @export
joinWithVariables <- function(object,
                              coords_df,
                              variables,
                              method_gs = "mean",
                              average_genes = FALSE,
                              smooth = FALSE,
                              smooth_span = 0.02,
                              normalize = TRUE,
                              verbose = TRUE){

  stopifnot(base::is.list(variables))
  stopifnot(base::any(c("features", "genes", "gene_sets") %in% base::names(variables)))

  if("features" %in% base::names(variables)){

    coords_df <-
      joinWithFeatures(object = object,
                       features = variables$features,
                       coords_df = coords_df,
                       smooth = smooth,
                       smooth_span = smooth_span,
                       verbose = verbose)

  }

  if("genes" %in% base::names(variables)){

    coords_df <-
      joinWithGenes(object = object,
                    coords_df = coords_df,
                    genes = variables$genes,
                    average_genes = average_genes,
                    smooth = smooth,
                    smooth_span = smooth_span,
                    normalize = normalize,
                    verbose = verbose)

  }

  if("gene_sets" %in% base::names(variables)){

    coords_df <-
      joinWithGeneSets(object = object,
                       coords_df = coords_df,
                       gene_sets = variables$gene_sets,
                       method_gs = method_gs,
                       smooth = smooth,
                       smooth_span = smooth_span,
                       normalize = normalize,
                       verbose = verbose)
  }

  base::return(coords_df)

}

