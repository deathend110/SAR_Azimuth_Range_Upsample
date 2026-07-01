# Stage 4 Revision Tracking v1

Manuscript: `sketch/brau_draft_v2.tex`

Source draft: `sketch/brau_draft_v1.tex`

Stage 3 decision: Major Revision

## Revision Matrix

| ID | Reviewer concern | Revision in v2 | Status |
|---|---|---|---|
| EIC-1 | Contribution framing is too broad and close to ordinary interpolation. | Reframed BRAU as pre-quantization frequency-domain range-azimuth zero-padding with fixed digital budget `Q=R\times A`; explicitly distinguishes it from post-reconstruction image interpolation. | Addressed |
| EIC-2/R1-1 | Processing chain and reproducibility details are underspecified. | Added compact pipeline order from raw echo to PSNR/SSIM, including threshold insertion, one-bit quantization, RC, frequency crop, RCMC, imaging, ROI, and normalization. | Addressed |
| R1-2 | Dataset protocol and GT definition are incomplete. | Added seed 2026, `A_s=0.6`, seven scene categories, 10 windows per dataset, 70 paired samples, and GT construction from unquantized raw echo through the same SAR chain. | Addressed |
| R1-3 | Statistical reporting lacks p-values. | Added Wilcoxon p-value summary in the main results text. | Addressed |
| R1-4 | `BestUni` definition differs across experiments. | Clarified that the main table selects best groups by mean PSNR, while the threshold robustness subsection uses per-sample maximum unidirectional reference. | Addressed |
| R2-1 | Literature gap should distinguish threshold/recovery work from allocation design. | Revised Introduction to state that prior work focuses on threshold design, recovery, or one-dimensional upsampling; this work studies two-dimensional allocation before quantization. | Addressed |
| R2-2/EIC-3 | Fig. 3 mechanism explanation is under-connected to metrics. | Added leakage metric definitions and linked Fig. 3, Table II, and final PSNR/SSIM gains through off-support and projected directional leakage. | Addressed |
| R3-1 | Fixed budget semantics are ambiguous. | Defined `Q` as a digital frequency-domain upsampling allocation/sample-count proxy, not ADC resolution, PRF, or bandwidth cost. | Addressed |
| DA-1 | Mechanism claim may overstate RCMC effect. | Reworded mechanism and conclusion to emphasize RC leakage evidence and state that RCMC rows retain the ordering after crop, without claiming additional RCMC improvement. | Addressed |

## Verification Targets

- Compile `brau_draft_v2.tex` twice with `pdflatex`.
- Check figure paths resolve.
- Check citation keys have matching bibliography entries.
- Check page count and major LaTeX warnings.
