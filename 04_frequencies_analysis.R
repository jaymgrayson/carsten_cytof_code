

Sys.time()

# Load packages
library(gdata)
library(ggplot2)
library(reshape2)
library(limma) # for strsplit2
library(RColorBrewer)
library(pheatmap)
library(gtools) # for logit
library(plyr) # for rbind.fill

##############################################################################
# Test arguments
##############################################################################


prefix='23_01_pca1_cl20_'
outdir='../carsten_cytof/PD1_project/CK_2016-06-23_01/050_frequencies_auto'
path_metadata='../carsten_cytof/PD1_project/CK_metadata/metadata_23_01.xlsx'
path_counts='../carsten_cytof/PD1_project/CK_2016-06-23_01/050_frequencies_auto/23_01_pca1_cl20_counts.xls'
path_fun_models='00_models.R'
path_fun_formulas='00_formulas_1dataset_3responses.R'
path_fun_plot_heatmaps='00_plot_heatmaps_for_sign_freqs.R'
FDR_cutoff='05'


prefix='01_23m6_29m4_'
outdir='../carsten_cytof/PD1_project/CK_2016-06-merged_23_29/01/08_frequencies_merged_2responses_both'
path_metadata=c('../carsten_cytof/PD1_project/CK_metadata/metadata_23_01.xlsx','../carsten_cytof/PD1_project/CK_metadata/metadata_29_01.xlsx')
path_counts=c('../carsten_cytof/PD1_project/CK_2016-06-23_01/050_frequencies/23_01_pca1_merging6_counts.xls','../carsten_cytof/PD1_project/CK_2016-06-29_01/050_frequencies/29_01_pca1_merging4_counts.xls')
path_fun_models='00_models.R'
path_fun_formulas='00_formulas_2dataset_2responses.R'
path_fun_plot_heatmaps='00_plot_heatmaps_for_sign_freqs.R'
FDR_cutoff='05'


##############################################################################
# Read in the arguments
##############################################################################

rm(list = ls())

args <- (commandArgs(trailingOnly = TRUE))
for (i in 1:length(args)) {
  eval(parse(text = args[[i]]))
}

cat(paste0(args, collapse = "\n"), fill = TRUE)


##############################################################################

if(!file.exists(outdir)) 
  dir.create(outdir, recursive = TRUE)


suffix <- paste0("_top", FDR_cutoff)
FDR_cutoff <- as.numeric(paste0("0.", FDR_cutoff))
FDR_cutoff


# ------------------------------------------------------------
# Load metadata
# ------------------------------------------------------------

md <- lapply(1:length(path_metadata), function(i){
  md <- read.xls(path_metadata[i], stringsAsFactors = FALSE)
  md
})

md <- plyr::rbind.fill(md)
rownames(md) <- md$shortname

### Factor arrangment
md$response <- factor(md$response, levels = c("NR", "R", "HD"))
md$response <- factor(md$response)
md$day <- factor(md$day, levels = c("base", "tx"))
md$day <- factor(md$day)
md$patient_id <- factor(md$patient_id)
md$data <- factor(md$data)
md$data_day <- interaction(md$data, md$day, lex.order = TRUE, drop = TRUE)

### Colors 
colors <- unique(md[, c("condition", "color")])
colors$condition <- factor(colors$condition)
## replace _ with \n
levels(colors$condition) <- gsub("_", "\n", levels(colors$condition ))

color_groups <- colors$color
names(color_groups) <- colors$condition

color_groupsb <- adjustcolor(color_groups, alpha = 0.3)
names(color_groupsb) <- colors$condition

color_samples <- md$color
names(color_samples) <- md$shortname

colors <- unique(md[, c("response", "color")])
color_response <- colors$color
names(color_response) <- colors$response


# ------------------------------------------------------------
# Load cluster frequencies
# ------------------------------------------------------------


freq <- lapply(1:length(path_counts), function(i){
  # i = 1
  freq <- read.table(path_counts[i], header = TRUE, sep = "\t", as.is = TRUE)
})

freq_out <- Reduce(function(...) merge(..., by = c("cluster", "label"), all=TRUE, sort = FALSE), freq)

## Drop the 'drop' cluster
freq_out <- freq_out[freq_out$label != "drop", , drop = FALSE]

if(!all(complete.cases(freq_out))){
  stop("There are some clusters that are not common in the merged data sets or have different cluster number!")
}


## keep only those samples that are also in the metadata file
freq_out <- freq_out[, c("cluster", "label", md$shortname)]

freq_out <- freq_out[order(freq_out$cluster), , drop = FALSE]

labels <- data.frame(cluster = freq_out$cluster, label = freq_out$label)
labels$label <- factor(labels$label, levels = unique(labels$label))
labels


# ---------------------------------------
# Keep only those samples that have enough cells
# Samples with 0 cells are eliminated from the analysis
# ---------------------------------------

min_cells <- 0

table_samp <- colSums(freq_out[md$shortname], na.rm = TRUE)
names(table_samp) <- md$shortname

keep_samps <- names(table_samp)[which(table_samp > min_cells)]

freq_out <- freq_out[, colnames(freq_out) %in% c("cluster", "label", keep_samps), drop = FALSE]

md <- md[md$shortname %in% keep_samps, , drop = FALSE]

## drop unused levels
md$response <- factor(md$response)
md$day <- factor(md$day)
md$patient_id <- factor(md$patient_id)


# ------------------------------------------------------------
# Normalize the frequencies using the arcsin-sqrt transformation + normalized to mean = 0 and sd = 1
# ------------------------------------------------------------


### arcsin-sqrt transformation
ass_freq_out <- freq_out
ass_freq_out[md$shortname] <- asin(sqrt((t(t(freq_out[md$shortname]) / colSums(freq_out[md$shortname])))))

expr_norm <- ass_freq_out[, c("cluster", "label", md[md$response != "HD", "shortname"])]
th <- 2.5

md$data_day <- factor(md$data_day)
data_days <- levels(md$data_day)

### Normalized to mean = 0 and sd = 1 per data and day
for(i in data_days){
  # i = "data23.base"
  expr_norm[, md[md$response != "HD" & md$data_day == i, "shortname"]] <- t(apply(expr_norm[, md[md$response != "HD" & md$data_day == i, "shortname"], drop = FALSE], 1, function(x){
    
    if(sum(!is.na(x)) == 0)
      return(x)
    
    if(sum(!is.na(x)) < 2)
      return(x-mean(x, na.rm = TRUE))
    
    sdx <- sd(x, na.rm = TRUE)
    if(sdx == 0)
      x <- (x-mean(x, na.rm = TRUE))
    else
      x <- (x-mean(x, na.rm = TRUE))/sdx
    
    x[x > th] <- th
    x[x < -th] <- -th
    
    return(x)}))
}


breaks = seq(from = -th, to = th, length.out = 101)
legend_breaks = seq(from = -round(th), to = round(th), by = 1)


# -----------------------------------------------------------------------------
# Plot a heatmap with clustered columns and all the rows
# -----------------------------------------------------------------------------


expr_heat <- expr_norm
rownames(expr_heat) <- expr_heat$label

expr <- expr_heat[, md[md$response != "HD", "shortname"]]

labels_row <- paste0(expr_heat$label)
labels_col <- colnames(expr)

annotation_col <- data.frame(response = factor(md[md$response != "HD", "response"]))
rownames(annotation_col) <- md[md$response != "HD", "shortname"]

annotation_colors <- list(response = color_response[levels(annotation_col$response)])

cluster_cols <- hclust(dist(t(expr)), method = "ward.D2")
cluster_rows <- hclust(dist(expr), method = "ward.D2")

# Using pheatmap
pheatmap(expr, cellwidth = 28, cellheight = 24, color = colorRampPalette(c("#87CEFA", "#56B4E9", "#0072B2", "#000000", "#D55E00", "#E69F00", "#FFD700"), space = "Lab")(100), breaks = breaks, legend_breaks = legend_breaks, cluster_cols = cluster_cols, cluster_rows = cluster_rows, labels_col = labels_col, labels_row = labels_row, fontsize_row = 14, fontsize_col = 14, fontsize = 12, annotation_col = annotation_col, annotation_colors = annotation_colors, annotation_legend = TRUE, filename = file.path(outdir, paste0(prefix, "frequencies_pheatmap_colclust", ".pdf")))




# ------------------------------------------------------------
# Test for frequency differences between groups
# ------------------------------------------------------------
## The model functions do not anlyse a cluster with NAs; 
## For merged data it means such cluster was not present in all the datasets
## For expression data clusters with no cells are skipped


### Load functions fitting models
source(path_fun_models)
### Load formulas that are fit in the models - this function may change the md object!!!
source(path_fun_formulas)

source(path_fun_plot_heatmaps)


levels(md$data)
levels(md$day)
levels(md$response)


models2fit <- c("glmer_binomial_interglht")


for(k in models2fit){
  # k = "glmer_logit_interglht"
  print(k)
  
  switch(k,
    
    glm_binomial_interglht = {
      # Fit a GLM binomial with interactions + test contrasts with multcomp pckg
      fit_out <- fit_glm_interglht(data = freq_out, md, family = "binomial", formula = formula_glm_binomial, K = K)
      
    }, 
    glm_quasibinomial_interglht = {
      # Fit a GLM quasibinomial with interactions + test contrasts with multcomp pckg
      fit_out <- fit_glm_interglht(data = freq_out, md, family = "quasibinomial", formula = formula_glm_binomial, K = K)
      
    },
    glmer_binomial_interglht = {
      # Fit a GLMM binomial with interactions + test contrasts with multcomp pckg
      fit_out <- fit_glmer_interglht(data = freq_out, md, family = "binomial", formula = formula_glmer_binomial, K = K)
      
    },
    lmer_logit_interglht = {
      
      logit_freq_out <- freq_out
      logit_freq_out[md$shortname] <- logit(t(t(freq_out[md$shortname]) / colSums(freq_out[md$shortname])))
      ## Be carefull about Inf and -Inf for prop = 0, 1
      fit_out <- fit_lmer_interglht(data = logit_freq_out, md, formula = formula_lmer, K = K)
      
    },
    lm_logit_interglht = {
      
      logit_freq_out <- freq_out
      logit_freq_out[md$shortname] <- logit(t(t(freq_out[md$shortname]) / colSums(freq_out[md$shortname])))
      ## Be carefull about Inf and -Inf for prop = 0, 1
      fit_out <- fit_lm_interglht(data = logit_freq_out, md, formula = formula_lm, K = K)
      
    },
    lmer_arcsinesqrt_interglht = {
      
      ass_freq_out <- freq_out
      ass_freq_out[md$shortname] <- asin(sqrt((t(t(freq_out[md$shortname]) / colSums(freq_out[md$shortname])))))
      
      fit_out <- fit_lmer_interglht(data = ass_freq_out, md, formula = formula_lmer, K = K)
      
    },
    lm_arcsinesqrt_interglht = {
      
      ass_freq_out <- freq_out
      ass_freq_out[md$shortname] <- asin(sqrt((t(t(freq_out[md$shortname]) / colSums(freq_out[md$shortname])))))
      
      fit_out <- fit_lm_interglht(data = ass_freq_out, md, formula = formula_lm, K = K)
      
    }
    
  )
  
  # ----------------------------------------
  # Extract p-values and coeffs
  # ----------------------------------------
  
  pvs <- data.frame(freq_out[, c("cluster", "label")], fit_out[["pvals"]])
  coeffs <- data.frame(freq_out[, c("cluster", "label")], fit_out[["coeffs"]])
  
  oo <- order(pvs[, pval_name1], decreasing = FALSE)
  pvs <- pvs[oo, , drop = FALSE]
  coeffs <- coeffs[oo, , drop = FALSE]
  
  ## save the results
  write.table(pvs, file=file.path(outdir, paste0(prefix, "frequencies_pvs_", k, suffix, ".xls")), row.names=FALSE, quote=FALSE, sep="\t")
  write.table(coeffs, file=file.path(outdir, paste0(prefix, "frequencies_coeffs_", k, suffix, ".xls")), row.names=FALSE, quote=FALSE, sep="\t")
  
  
  # ----------------------------------------
  # Plot a heatmap of significant cases - transform proportions with arcsin-sqrt so the dispersion is the same for low and high props.
  # ----------------------------------------
  
  ### add p-value info
  expr_all <- merge(pvs, expr_norm, by = c("cluster", "label"), all.x = TRUE, sort = FALSE)
  
  prefix2 <- paste0(k, "_")
  
  plot_heatmaps_for_sign_freqs(expr_all = expr_all, md = md, FDR_cutoff = FDR_cutoff, pval_name2 = pval_name2, adjpval_name2 = adjpval_name2, pval_name_list = pval_name_list, adjpval_name_list = adjpval_name_list, breaks = breaks, legend_breaks = legend_breaks, color_response = color_response, outdir = outdir, prefix = prefix, prefix2 = prefix2, suffix = suffix)
  
  
  
}











sessionInfo()




