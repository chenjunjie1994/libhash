# Introduction

This project aims at intergrating popular hashing-based ANN search methods into one unified framework for more convenient performance comparison and further improvement.

We have now included the following methods:

* **LSH**: Locality Sensitive Hashing (SCG '04)
* **SH**: Spectral Hashing (NIPS '08)
* **ITQ**: Iterative Quantization (CVPR '11)
* **AGH**: Anchor Graph Hashing (ICML '11)
* **SpH**: Spherical Hashing (CVPR '12)

# Evaluation Results

We report the MeanAP (Mean Average Precision) scores for above methods on SIFT-1M and GIST-1M data sets. For each query, the ground-truth matches are defined as its top-100/1K/10K nearest neighbors in the Euclidean space.

## SIFT-1M

ANN Search of the top-100/1K/10K nearest neighbors:

| Method | 16-bit                | 32-bit                | 48-bit                | 64-bit                |
|--------|-----------------------|-----------------------|-----------------------|-----------------------|
| LSH    | .0063 / .0202 / .0957 | .0214 / .0493 / .1654 | .0371 / .0879 / .2277 | .0627 / .1136 / .2851 |
| SH     | .0147 / .0483 / .1536 | .0481 / .1012 / .2089 | .0807 / .1452 / .2528 | .1012 / .1634 / .2614 |
| ITQ    | .0089 / .0360 / .1626 | .0311 / .0899 / .2878 | .0579 / .1425 / .3701 | .0880 / .1931 / .4271 |
| AGH-1  | .0070 / .0350 / .1611 | .0224 / .0784 / .2497 | .0348 / .1043 / .2800 | .0468 / .1288 / .2981 |
| AGH-2  | .0035 / .0206 / .1151 | .0124 / .0482 / .1926 | .0208 / .0721 / .2257 | .0324 / .0915 / .2624 |
| SpH    | .0090 / .0345 / .1283 | .0325 / .0814 / .2170 | .0585 / .1356 / .2885 | .0859 / .1760 / .3410 |

## GIST-1M

To be added.
