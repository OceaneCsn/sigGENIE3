**Gene Regulatory Network Inference with edges significance estimation**

---

The [GENIE3 package](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0012776) is a method mased on machine learning to infer regulatory links between genes and regulators.

GENIE3 takes as input a list of genes, that will be the nodes of the inferred network. Among those genes, some must be considered as potential regulators. 

GENIE3 can determine the influence if every regulators over each input genes, using their respective expression profiles, using ensemble trees regression.

For each target gene, the methods uses Random Forests to provide a ranking of all regulators based on their importance on the target expression. 

The idea is then to keep the strongest links to build the gene regulatory network. The way of choosing this minimal importance value needed to be included in the network is delicate, and no method was proposed in the original paper.

This code is a modified version of GENIE3, relying on the [rfPermute](https://rdrr.io/github/EricArcher/rfPermute/f/devel/rfPermtue%20ms/archer.Rmd) package to estimate pvalues for each regulattory link, instead of importance values that have to be arbitraily thresholded. 

It is a mix of the [C++ wrapper source code for GENIE3](https://github.com/aertslab/GENIE3/blob/master/R/GENIE3.R), and [the R implementation](https://github.com/vahuynh/GENIE3/blob/master/GENIE3_R/GENIE3.R), but with a call to rfPermute instead of randomForest during the regulatory links inference step. 

The pvalues, that can be corrected for multiple testing, are then returned instead of the importance values, and can be used as a more insightful cutoff for downstrean analysis.

**The code is still in developpement and was not intensively tested for now.**
