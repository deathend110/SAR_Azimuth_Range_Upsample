# Stage 2.5 Integrity Report v2

Paper: `sketch/brau_draft_v1.tex`

Mode: ARS Pipeline Stage 2.5, focused re-check after bibliography correction.

Verdict: **PASS WITH NOTE**

## Re-Check Summary

| Item | Verdict | Evidence |
|---|---|---|
| Failed bibliography entries from v1 | PASS | `zhao2019onebit`, `demir2018onebit`, `zhao2021lowprecision`, `nie2025fixed`, and `si2023dequantization` were corrected in `brau_draft_v1.tex`. |
| DOI coverage for one-bit SAR papers | PASS | DOI values are now included for `franceschetti1991signum`, `zhao2019onebit`, `demir2018onebit`, `zhao2021lowprecision`, `nie2025fixed`, and `si2023dequantization`. |
| Citation/reference matching | PASS | 8 cited keys and 8 `\bibitem` entries; no dangling citations and no orphan references. |
| LaTeX compile | PASS | `pdflatex` completed successfully after the bibliography corrections. |
| Local experimental evidence | PASS | v1 local checks remain valid: figures resolve, Table I matches Exp1 CSV files, non-integer gains match Exp1_NonInteger, mechanism metrics match Exp2, and threshold gains match Exp3B. |

## Remaining Note Before Review

The threshold robustness paragraph uses gains from `Exp3B_ZT_NCT_RT_Gains.csv`. In that experiment, `BestUniPSNR_Mean` is computed from the per-sample maximum of range-only and azimuth-only PSNR, while `BestUniGroup` is chosen by mean PSNR for reporting. The current prose says "best unidirectional group" broadly; this is acceptable for a draft, but the Stage 3 reviewer should check whether this needs a one-sentence clarification.

## Pipeline Gate

Stage 2.5 is cleared for Stage 3 review.

