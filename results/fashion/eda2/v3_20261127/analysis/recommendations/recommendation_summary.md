# Fashion-MNIST configuration comparison

## K-means codebook size

`k_comparison.csv` reports codebook distortion, occupancy, entropy and saved ARI, alongside transaction length, diversity and common Eclat counts for S0, S1, S3 and S6-B at each K. These transaction measures show how a shared codebook changes each encoding; they are not K-means fit metrics. Among K values with all three fits, the lowest mean distortion is K=256 (0.1769); the highest saved ARI is K=16 (0.8822). The two criteria can favor different K values.

The nondominated K candidates on mean distortion and saved ARI are 16, 64, 128, 256. This is a shortlist for review, not a universal optimum; the saved ARI sample provenance remains a limitation.

## Transaction representation

`representation_summary.csv` and `representation_comparison.csv` compare BoVW binary (S0), region-aware (S1), stripe-aware (S3), and neighbor-relation (S6-B) over matched K–seed inputs. The shortest mean transaction is S0; the highest unique-transaction ratio is S1; the most frequent 2-itemsets at the common scope is S1. These are separate tradeoff leaders: pattern count alone does not determine the preferred representation. The common mining scope is 3% minimum support with a maximum itemset length of two.

## Evidence limits

- The K comparison uses the configured five K values and three seeds; it does not establish a universal optimum.
- The common Eclat comparison is limited to 3% minimum support and itemsets of length at most two.
- A larger frequent-itemset count is not treated as a stand-alone quality objective.
- The results describe unsupervised structure and do not establish predictive classification value.
