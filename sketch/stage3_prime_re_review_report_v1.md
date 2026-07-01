# Stage 3' Verification Review Report v1

Manuscript: `sketch/brau_draft_v2.tex`

Prior review package: `sketch/stage3_review_package_v1.md`

Revision tracker: `sketch/stage4_revision_tracking_v1.md`

Mode: ARS `academic-paper-reviewer` re-review

## Decision

**Minor Revision**

The Stage 3 major-revision content issues are substantially resolved. The revised draft now distinguishes BRAU from ordinary post-reconstruction interpolation, reports the main experimental protocol, defines the processing chain, clarifies `BestUni`, reports Wilcoxon significance, and links Fig. 3/Table III to spectral leakage metrics. Remaining issues are submission-readiness and formatting checks rather than core technical blockers.

## Revision Response Checklist

### Priority 1 — Required Revisions

| # | Original review item | Author's claim / revision | Status | Revision location | Verified? | Quality assessment |
|---|---|---|---|---|---|---|
| R1 | Add compact experimental protocol: datasets, 7 x 10 sampling, seed, ROI/crop, normalization, GT construction. | Added seed 2026, SplitRT `A_s=0.6`, seven scene categories, 10 windows per dataset, 70 paired samples, GT from unquantized raw echo through RC/RCMC/imaging/ROI/normalization. | FULLY_ADDRESSED | Method, Evaluation Protocol | Yes | The reproducibility gap is materially reduced. |
| R2 | Clarify where upsampling occurs relative to threshold generation, one-bit quantization, RC, RCMC, and image formation. | Added FFT zero-padding before threshold generation and one-bit quantization; added pipeline table from raw echo to PSNR/SSIM. | FULLY_ADDRESSED | Method, Fixed-Budget Range-Azimuth Upsampling; Table I | Yes | The revised method now separates BRAU from image-domain interpolation. |
| R3 | Clarify main-vs-threshold `BestUni` statistic. | Main results select best groups by mean PSNR; robustness experiment uses per-sample maximum unidirectional reference. | FULLY_ADDRESSED | Method, Evaluation Protocol; Robustness subsection | Yes | The statistical convention is explicit enough for reviewers. |
| R4 | Revise mechanism wording and connect Fig. 3/Table III to metrics without overclaiming. | Added spectral energy, support mask, off-support, range leakage, and azimuth leakage formulas; states RCMC rows retain ordering after crop. | FULLY_ADDRESSED | Mechanism Analysis Through Spectral Leakage | Yes | The mechanism evidence is now tied to defined metrics and avoids claiming extra RCMC improvement. |
| R5 | Add p-value reporting for Wilcoxon tests. | Added compact p-value statement: `p_PSNR <= 4.34e-10`, `p_SSIM = 3.56e-13` for listed budgets. | FULLY_ADDRESSED | Main Fixed-Budget Results | Yes | Enough for conference paper text; exact per-Q p-values remain in experiment output. |
| R6 | Define fixed-budget meaning. | Defines `Q` as digital frequency-domain upsampling allocation/sample-count proxy, not ADC, PRF, or bandwidth. | FULLY_ADDRESSED | Method, Fixed-Budget Range-Azimuth Upsampling; Conclusion | Yes | Resolves the practical/system ambiguity. |

### Priority 2 — Suggested Revisions

| # | Original review item | Status | Notes |
|---|---|---|---|
| S1 | Sharpen literature gap: threshold design/post-processing vs dimensional allocation before quantization. | FULLY_ADDRESSED | Introduction now frames prior work around threshold/recovery/one-dimensional processing and positions BRAU as pre-quantization allocation. |
| S2 | Add computational/practical overhead note. | PARTIALLY_ADDRESSED | The draft states BRAU changes the frequency-domain grid and does not alter the SAR processor. It does not quantify overhead, which is acceptable for this conference-length version. |
| S3 | Add implementation note for non-integer factors. | FULLY_ADDRESSED | Non-integer subsection states same frequency-domain resampling and crop procedure. |
| S4 | Keep claim language within tested conditions. | FULLY_ADDRESSED | Claims are now tied to tested budgets, datasets, thresholds, and the stated processing chain. |

## New Issues Found During Re-Review

| # | Type | Location | Description | Severity |
|---|---|---|---|---|
| NEW-1 | Formatting/readiness | Title block | Author names, affiliations, email fields, and funding footnote remain template placeholders. | Minor before submission |
| NEW-2 | Formatting/readiness | Whole PDF | Current `pdflatex` output is 5 pages. If ICICSP requires strict 4 pages, compression is still needed. | Minor-to-major depending on venue rule |
| NEW-3 | Formatting/readiness | Fig. 3 | Fig. 3 is fixed with `\refstepcounter{figure}` rather than a standard IEEE `figure` float, by layout choice. It achieves the requested placement but should be checked visually in the final PDF. | Minor |

## Decision Rationale

The first-round Major Revision was driven by contribution framing, reproducibility, statistical reporting, mechanism explanation, and budget semantics. All six required revision items are now verified as fully addressed in `brau_draft_v2.tex`. The paper has moved from an experiment-note style draft to a more review-ready conference manuscript.

The remaining concerns are not about the central BRAU claim. They are final submission preparation issues: placeholder metadata, page limit, and visual validation of the manually placed Fig. 3. Therefore the appropriate re-review decision is **Minor Revision**, followed by ARS Stage 4.5 final integrity after these small items are resolved or explicitly accepted.

## Recommended Next ARS Step

Proceed to **Stage 4.5 FINAL INTEGRITY** after handling submission metadata and deciding whether the target ICICSP page limit requires compression.

