#' @title sigGENIE3
#'
#' @description \code{sigGENIE3} Infers a gene regulatory network (in the form of a pvalues-filled adjacency matrix) 
#' from expression data, using ensembles of regression trees.
#'
#' @param exprMatrix Expression matrix (genes x samples). Every row is a gene, every column is a sample.
#' The expression matrix can also be provided as one of the Bioconductor classes:
#' \itemize{
#' \item \code{ExpressionSet}: The matrix will be obtained through exprs(exprMatrix)
#' \item \code{RangedSummarizedExperiment}: The matrix will be obtained through assay(exprMatrix), 
#' wich will extract the first assay (usually the counts)
#' }
#' @param regulators Subset of genes used as candidate regulators. Must be either a 
#' vector of indices, e.g. \code{c(1,5,6,7)}, or a vector of gene names, e.g. 
#' \code{c("at_12377", "at_10912")}. The default value NULL means that all the genes are used as candidate regulators.
#' @param targets Subset of genes to which potential regulators will be calculated. Must be either 
#' a vector of indices, e.g. \code{c(1,5,6,7)}, or a vector of gene names, e.g. \code{c("at_12377", "at_10912")}. 
#' If NULL (default), regulators will be calculated for all genes in the input matrix.
#' @param K Number of candidate regulators randomly selected at each tree node (for the determination of the best split). 
#' Must be either "sqrt" for the square root of the total number of candidate regulators (default), 
#' "all" for the total number of candidate regulators, or a stricly positive integer.
#' @param nTrees Number of trees in an ensemble for each target gene. Default: 1000.
#' @param nCores Number of cores to use for parallel computing. Default: 1.
#' @param verbose If set to TRUE, a feedback on the progress of the calculations is given. Default: FALSE.
#' 
#' @param nShuffle Number of response permutations performed to estimate regulators null ditribution.
#' Default:1000.
#'
#' @return list containing two adjacency matrix of inferred network.
#' For pvalues, Element w_ij (row i, column j) gives the 
#' pvalue of the link from regulatory gene i to target gene j.
#' For pvalues, Element w_ij (row i, column j) gives the 
#' fdr adjusted pvalue of the link from regulatory gene i to target gene j.
#'
#' @examples
#' ## Generate fake expression matrix
#' exprMatrix <- matrix(sample(1:10, 100, replace=TRUE), nrow=20)
#' rownames(exprMatrix) <- paste("Gene", 1:20, sep="")
#' colnames(exprMatrix) <- paste("Sample", 1:5, sep="")
#'
#' ## Run sigGENIE3
#' set.seed(123) # For reproducibility of results
#' results <- sigGENIE3(exprMatrix, regulators=paste("Gene", 1:5, sep=""))
setGeneric("sigGENIE3", signature = "exprMatrix",
           function(exprMatrix,
                    regulators = NULL,
                    targets = NULL,
                    K = "sqrt",
                    nTrees = 1000,
                    nCores = 1,
                    verbose = FALSE,
                    nShuffle = 1000)
           {
             standardGeneric("sigGENIE3")
           })

#' @export
setMethod("sigGENIE3", "matrix",
          function(exprMatrix,
                   regulators = NULL,
                   targets = NULL,
                   K = "sqrt",
                   nTrees = 1000,
                   nCores = 1,
                   verbose = FALSE,
                   nShuffle = 1000)
          {
            .sigGENIE3(
              exprMatrix = exprMatrix,
              regulators = regulators,
              targets = targets,
              K = K,
              nTrees = nTrees,
              nCores = nCores,
              verbose = verbose,
              nShuffle = 1000
            )
          })

#' @export
setMethod("sigGENIE3", "SummarizedExperiment",
          function(exprMatrix,
                   regulators = NULL,
                   targets = NULL,
                   K = "sqrt",
                   nTrees = 1000,
                   nCores = 1,
                   verbose = FALSE,
                   nShuffle = 1000)
          {
            if (length(SummarizedExperiment::assays(exprMatrix)) > 1)
              warning("More than 1 assays are available. Only using the first one.")
            exprMatrix <- SummarizedExperiment::assay(exprMatrix)
            .sigGENIE3(
              exprMatrix = exprMatrix,
              regulators = regulators,
              targets = targets,
              K = K,
              nTrees = nTrees,
              nCores = nCores,
              verbose = verbose,
              nShuffle = 1000
            )
          })

#' @export
setMethod("sigGENIE3", "ExpressionSet",
          function(exprMatrix,
                   regulators = NULL,
                   targets = NULL,
                   K = "sqrt",
                   nTrees = 1000,
                   nCores = 1,
                   verbose = FALSE,
                   nShuffle = 1000)
          {
            exprMatrix <- Biobase::exprs(exprMatrix)
            .sigGENIE3(
              exprMatrix = exprMatrix,
              regulators = regulators,
              targets = targets,
              K = K,
              nTrees = nTrees,
              nCores = nCores,
              verbose = verbose,
              nShuffle = 1000
            )
          })

.sigGENIE3 <-
  function(exprMatrix,
           regulators,
           targets,
           K,
           nTrees,
           nCores,
           verbose,
           nShuffle)
  {
    .checkArguments(
      exprMatrix = exprMatrix,
      regulators = regulators,
      targets = targets,
      K = K,
      nTrees = nTrees,
      nCores = nCores,
      verbose = verbose,
      nShuffle = nShuffle
    )
    
    if (is.numeric(regulators))
      regulators <- rownames(exprMatrix)[regulators]
    
    ############################################################
    # transpose expression matrix to (samples x genes)
    exprMatrixT <- t(exprMatrix)
    rm(exprMatrix)
    num.samples <- nrow(exprMatrixT)
    allGeneNames <- colnames(exprMatrixT)
    
    # get names of input genes
    if (is.null(regulators))
    {
      regulatorNames <- allGeneNames
    } else
    {
      # input gene indices given as integers
      if (is.numeric(regulators))
      {
        regulatorNames <- allGeneNames[regulators]
        # input gene indices given as names
      } else
      {
        regulatorNames <- regulators
        # for security, abort if some input gene name is not in gene names
        missingGeneNames <- setdiff(regulatorNames, allGeneNames)
        if (length(missingGeneNames) != 0)
          stop(paste(
            "Regulator genes missing from the expression matrix:",
            paste(missingGeneNames, collapse =
                    ", ")
          ))
      }
    }
    regulatorNames <- sort(regulatorNames)
    rm(regulators)
    
    # get names of target genes
    if (is.null(targets))
    {
      targetNames <- allGeneNames
    } else
    {
      # input gene indices given as integers
      if (is.numeric(targets))
      {
        targetNames <- allGeneNames[targets]
        # input gene indices given as names
      } else
      {
        targetNames <- targets
        # for security, abort if some input gene name is not in gene names
        missingGeneNames <- setdiff(targetNames, allGeneNames)
        if (length(missingGeneNames) != 0)
          stop(paste(
            "Target genes missing from the expression matrix:",
            paste(missingGeneNames, collapse =
                    ", ")
          ))
      }
    }
    targetNames <- sort(targetNames)
    nGenes <- length(targetNames)
    rm(targets)

    if (verbose)
      message(paste(
        "\nK: ",
        K,
        "\nNumber of trees: ",
        nTrees,
        sep = ""
      ))

    # setup weight matrix
    fdrMatrix <-
      matrix(0.0,
             nrow = length(regulatorNames),
             ncol = length(targetNames))
    rownames(fdrMatrix) <- regulatorNames
    colnames(fdrMatrix) <- targetNames
    
    
    pvalMatrix <- fdrMatrix
    
    print(nCores)
    print(!foreach::getDoParRegistered())
    # compute importances for every target gene
    # random forests are not parallelized, but individual null distribution estimation
    # are
    if (verbose)
      message("Using 1 core.")
    for (targetName in targetNames)
    {
      if (verbose)
        message(paste(
          "Computing gene ",
          which(targetNames == targetName),
          "/",
          nGenes,
          ": ",
          targetName,
          sep = ""
        ))
      ####################################
      # remove target gene from input genes
      
      theseRegulatorNames <- setdiff(regulatorNames, targetName)
      numRegulators <- length(theseRegulatorNames)
      mtry <- .setMtry(K, numRegulators)
      
      x <- exprMatrixT[, theseRegulatorNames]
      y <- exprMatrixT[, targetName]
      
      #   ____________________________________________________________________________
      
      # Normalize output
      y <- y / sd(y)
      
      # By default, grow fully developed trees
      
      rf <-
        rfPermute::rfPermute(
          x,
          y,
          mtry = mtry,
          ntree = nTrees,
          replace = FALSE,
          nodesize = 1,
          nrep = nShuffle,
          num.cores = nCores
        )
      
      pvals <- rfPermute::rp.importance(rf)[,"IncNodePurity.pval"]
      pvals.names <- names(pvals)
      pvalMatrix[pvals.names, targetName] <- pvals

      fdr <- p.adjust(pvals, method = "fdr")
      fdrMatrix[pvals.names, targetName] <- fdr
    }
    return(list(p.values = pvalMatrix, fdr = fdrMatrix))
  }

# mtry <- setMtry(K, numRegulators)
.setMtry <- function(K, numRegulators)
{
  # set mtry
  if (class(K) == "numeric") {
    mtry <- K
  } else if (K == "sqrt") {
    mtry <- round(sqrt(numRegulators))
  } else {
    mtry <- numRegulators
  }
  
  return(mtry)
}


.checkArguments <-
  function(exprMatrix,
           regulators,
           targets,
           K,
           nTrees,
           nCores,
           verbose,
           nShuffle)
  {
    ############################################################
    # check input arguments
    if (!is.matrix(exprMatrix) && !is.array(exprMatrix)) {
      stop(
        "Parameter exprMatrix must be a two-dimensional matrix where each row corresponds to a 
        gene and each column corresponds to a condition/sample/cell."
      )
    }
    
    if (length(dim(exprMatrix)) != 2) {
      stop(
        "Parameter exprMatrix must be a two-dimensional matrix where each row corresponds to a 
        gene and each column corresponds to a condition/sample/cell."
      )
    }
    
    if (is.null(rownames(exprMatrix))) {
      stop("exprMatrix must contain the names of the genes as rownames.")
    }
    
    countGeneNames <- table(rownames(exprMatrix))
    nonUniqueGeneNames <- countGeneNames[countGeneNames > 1]
    if (length(nonUniqueGeneNames) > 0)
      stop("The following gene IDs (rownames) are not unique: ",
           paste(names(nonUniqueGeneNames), collapse = ", "))
    
    if (K != "sqrt" && K != "all" && !is.numeric(K)) {
      stop("Parameter K must be \"sqrt\", or \"all\", or a strictly positive integer.")
    }
    
    if (is.numeric(K) && K < 1) {
      stop("Parameter K must be \"sqrt\", or \"all\", or a strictly positive integer.")
    }
    
    if (!is.numeric(nTrees) || nTrees < 1) {
      stop("Parameter nTrees should be a stricly positive integer.")
    }
    
    if (!is.numeric(nShuffle) || nShuffle < 1) {
      stop("Parameter nShuffle should be a stricly positive integer.")
    }
    
    if (!is.null(regulators))
    {
      if (length(regulators) < 2)
        stop("Provide at least 2 potential regulators.")
      
      if (!is.vector(regulators)) {
        stop("Parameter 'regulators' must a vector (of indices or gene names).")
      }
      
      if (is.numeric(regulators)) {
        if (max(regulators) > nrow(exprMatrix))
          stop("At least one index in 'regulators' exceeds the number of genes.")
        if (min(regulators) <= 0)
          stop("The indexes in 'regulators' should be >=1.")
      }
      
      if (any(table(regulators) > 1))
        stop("Please, provide each regulator (name/ID) only once.")
      
      if (is.character(regulators)) {
        regulatorsInMatrix <- intersect(regulators, rownames(exprMatrix))
        if (length(regulatorsInMatrix) == 0)
          stop("The genes must contain at least one regulators")
        
        if (length(regulatorsInMatrix) < length(regulators))
          warning(
            "Only",
            length(regulatorsInMatrix),
            "out of",
            length(regulators),
            " candidate regulators (IDs/names) are in the expression matrix."
          )
      }
    }
    
    if (!is.null(targets))
    {
      if (!is.vector(targets)) {
        stop("Parameter 'targets' must a vector (of indices or gene names).")
      }
      
      if (is.numeric(targets)) {
        if (max(targets) > nrow(exprMatrix))
          stop("At least one index in 'targets' exceeds the number of genes.")
        if (min(targets) <= 0)
          stop("The indexes in 'targets' should be >=1.")
      }
      
      if (any(table(targets) > 1))
        stop("Please, provide each target (name/ID) only once.")
      
      if (is.character(targets)) {
        targetsInMatrix <- intersect(targets, rownames(exprMatrix))
        if (length(targetsInMatrix) == 0)
          stop("The genes must contain at least one targets.")
        
        
        if (length(targetsInMatrix) < length(targets))
          warning(
            "Only",
            length(targetsInMatrix),
            "out of",
            length(targets),
            "target genes (IDs/names) are in the expression matrix."
          )
      }
    }
    
    if (!is.numeric(nCores) || nCores < 1)
    {
      stop("Parameter nCores should be a stricly positive integer.")
    }
  }