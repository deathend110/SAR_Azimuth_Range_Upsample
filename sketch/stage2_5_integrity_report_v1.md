# Stage 2.5 Integrity Report v1

Paper: `sketch/brau_draft_v1.tex`

Mode: ARS Pipeline Stage 2.5, pre-review integrity check.

Verdict: **FAIL**

Reason: local experiment evidence is mostly consistent, but several reference entries contain incorrect bibliographic metadata. These must be corrected before Stage 3 review.

## Local Evidence Check

| Item | Verdict | Evidence |
|---|---|---|
| Figure paths | PASS | All four `\includegraphics` paths resolve to existing files. |
| Citation/reference matching | PASS | 8 cited keys and 8 `\bibitem` entries; no dangling or orphan citations. |
| Main Table I values | PASS | Values match `Exp1_MainResult_Output/Exp1_MainResult_Summary.csv` and gains match `Exp1_MainResult_Output/Exp1_MainResult_Gain.csv` after 4-decimal rounding. |
| Non-integer gains | PASS | Values match `Exp1_NonInteger_Output/Exp1_NonInteger_Gain.csv`: PSNR gains 0.2723, 0.3437, 0.3952, 0.4567; SSIM gain range 0.0146--0.0221. |
| Mechanism metrics | PASS | Table values match `Exp2_Mechanism_Output/Exp2_Mechanism_Metrics.csv` for `node2_rc` and `node3_rcmc`. |
| Threshold robustness gains | PASS WITH NOTE | Values match `Exp3B_ZT_NCT_RT_Output/Exp3B_ZT_NCT_RT_Gains.csv`. Note: `BestUniPSNR_Mean` is computed from per-sample maximum of range-only and azimuth-only PSNR, while the printed `BestUniGroup` is chosen by mean PSNR. The prose should avoid implying a single fixed unidirectional group was used for the gain vector. |
| SplitRT vs FullRT statement | PASS | `Exp3A_SplitVsFull_Output/Exp3A_SplitVsFull_Summary.csv` shows max mean difference of 0.0851 dB PSNR and 0.0026 SSIM across tested `Q` and `A_s`, supporting "nearly overlap". |

## Reference Audit

| Key | Verdict | Issue |
|---|---|---|
| `cumming2005sar` | VERIFIED | No correction required. |
| `curlander1991sar` | VERIFIED | No correction required. |
| `franceschetti1991signum` | VERIFIED | Add DOI if desired: `10.1049/ip-f-2.1991.0025`. |
| `zhao2019onebit` | FAIL | Draft lists `Y. Huang` and `Z. Bao`; verified metadata gives Bo Zhao, Lei Huang, Weimin Bao. DOI: `10.1109/TGRS.2019.2910284`. |
| `demir2018onebit` | FAIL | Draft lists vol. 12, no. 5, pp. 543--550. Verified metadata gives vol. 12, no. 12, pp. 1517--1526. DOI: `10.1049/iet-rsn.2018.5044`. |
| `zhao2021lowprecision` | FAIL | Draft lists pages 5005--5020 and issue 6. Verified metadata gives vol. 59, no. 4, pp. 3150--3160. DOI: `10.1109/TGRS.2020.3014300`. |
| `nie2025fixed` | FAIL | Draft author list is incorrect/incomplete. Verified metadata gives Guoli Nie, Bo Zhao, Qiuchen Liu, Lei Huang, Guisheng Liao, IEEE TGRS, vol. 63, pp. 1--15, 2025. DOI: `10.1109/TGRS.2024.3519757`. |
| `si2023dequantization` | FAIL | Draft author list is incorrect. Verified metadata gives Cuiqi Si, Bo Zhao, Lei Huang, Shiqi Liu, IEEE TGRS, vol. 61, pp. 1--16, 2023. DOI: `10.1109/TGRS.2023.3330530`. |

## Recommended Bibliography Corrections

```latex
\bibitem{zhao2019onebit}
B. Zhao, L. Huang, and W. Bao, ``One-bit SAR imaging based on single-frequency thresholds,'' \textit{IEEE Transactions on Geoscience and Remote Sensing}, vol. 57, no. 9, pp. 7017--7032, 2019, doi: 10.1109/TGRS.2019.2910284.

\bibitem{demir2018onebit}
M. Demir and E. Ercelebi, ``One-bit compressive sensing with time-varying thresholds in synthetic aperture radar imaging,'' \textit{IET Radar, Sonar \& Navigation}, vol. 12, no. 12, pp. 1517--1526, 2018, doi: 10.1049/iet-rsn.2018.5044.

\bibitem{zhao2021lowprecision}
B. Zhao, L. Huang, and B. Jin, ``Strategy for SAR imaging quality improvement with low-precision sampled data,'' \textit{IEEE Transactions on Geoscience and Remote Sensing}, vol. 59, no. 4, pp. 3150--3160, 2021, doi: 10.1109/TGRS.2020.3014300.

\bibitem{nie2025fixed}
G. Nie, B. Zhao, Q. Liu, L. Huang, and G. Liao, ``One-bit synthetic aperture radar imaging based on fixed-threshold with slow-time fluctuations,'' \textit{IEEE Transactions on Geoscience and Remote Sensing}, vol. 63, pp. 1--15, 2025, doi: 10.1109/TGRS.2024.3519757.

\bibitem{si2023dequantization}
C. Si, B. Zhao, L. Huang, and S. Liu, ``A convolutional de-quantization network for harmonics suppression in one-bit SAR imaging,'' \textit{IEEE Transactions on Geoscience and Remote Sensing}, vol. 61, pp. 1--16, 2023, doi: 10.1109/TGRS.2023.3330530.
```

## Source Audit Trail

- Cumming and Wong book: Google Books / Artech House metadata, ISBN `9781580530583`.
- Curlander and McDonough book: Wiley / library metadata, ISBN `9780471857709`.
- Franceschetti et al. signum-coded SAR: IET DOI `10.1049/ip-f-2.1991.0025`.
- Zhao et al. single-frequency thresholds: IEEE/ADS/Semantic Scholar metadata, DOI `10.1109/TGRS.2019.2910284`.
- Demir and Ercelebi time-varying thresholds: IET/Wiley metadata, DOI `10.1049/iet-rsn.2018.5044`.
- Zhao et al. low-precision sampled data: IEEE/dblp/cross-cited metadata, DOI `10.1109/TGRS.2020.3014300`.
- Nie et al. fixed-threshold slow-time fluctuations: dblp/Semantic Scholar/OpenReview metadata, DOI `10.1109/TGRS.2024.3519757`.
- Si et al. CDQOB-net: IEEE/Semantic Scholar/SZU author profile metadata, DOI `10.1109/TGRS.2023.3330530`.

## Next Gate

Fix the five failing bibliography entries, then re-run:

1. LaTeX compile check.
2. Citation/reference matching.
3. A focused re-check of corrected references.

