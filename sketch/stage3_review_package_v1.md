# Stage 3 Review Package v1

Manuscript: `Bidirectional Range-Azimuth Upsampling for 1-Bit SAR Imaging`

Input manuscript: `sketch/brau_draft_v1.tex`

Integrity gate: `sketch/stage2_5_integrity_report_v2.md` cleared Stage 2.5 with PASS WITH NOTE.

Decision: **Major Revision**

## Reviewer Configuration

| Reviewer | Identity | Focus |
|---|---|---|
| EIC | IEEE remote sensing / signal processing conference editor | Venue fit, novelty, contribution clarity, paper maturity |
| R1 Methodology | SAR imaging experiment and statistical evaluation reviewer | Experimental design, statistical comparison, reproducibility |
| R2 Domain | 1-bit SAR and low-precision radar imaging researcher | Literature positioning, SAR/quantization terminology, contribution |
| R3 Perspective | SAR system and implementation-oriented reviewer | Practical sampling implications, system cost, deployability |
| Devil's Advocate | Adversarial reviewer for central claim stress-test | Alternative explanations, hidden assumptions, overclaiming |

## EIC Review

Recommendation: **Major Revision**

Confidence: **4/5**

Summary: The manuscript has a clear and potentially useful contribution: under a fixed total upsampling budget, splitting the budget across range and azimuth gives better 1-bit SAR image quality than concentrating it in one dimension. The paper is concise, conference-shaped, and the main result is easy to understand. The corrected references and four-page structure make it close to a submit-ready draft. However, the current version still reads more like a strong experiment note than a fully defended conference paper. The novelty is plausible but not yet sharply separated from interpolation, oversampling, thresholding, and normalization effects. The EIC decision is therefore Major Revision, mainly because the central contribution needs clearer positioning and stronger claims-to-evidence alignment.

Strengths:
- The paper has a focused research question: fixed-budget range-azimuth allocation in 1-bit SAR.
- Table I is now interpretable because it reports absolute bidirectional/unidirectional metrics plus deltas.
- The paper uses multiple datasets and paired tests, which is stronger than a single-scene demonstration.

Weaknesses:
- **Contribution framing is still too broad.** The paper claims a design principle, but the current method section does not fully distinguish BRAU from ordinary two-dimensional interpolation before quantization.
- **Venue fit depends on reproducibility.** A reviewer will need enough detail to understand exactly where upsampling is inserted, how crop/normalization is handled, and how GT images are defined.
- **The mechanism figure is persuasive visually but under-explained.** Fig. 3 shows the four allocation regimes clearly, but the text needs to connect spectral extent, leakage metrics, and final image quality more tightly.

## Reviewer 1: Methodology Review

Recommendation: **Major Revision**

Confidence: **5/5**

Summary: The core comparison is reasonable: paired samples, fixed budget `Q=R x A`, PSNR/SSIM metrics, and Wilcoxon signed-rank tests. The main table values align with the experiment outputs. The key methodological weakness is reporting completeness. The paper says seven datasets and 10 frames per dataset, but does not give enough sampling, preprocessing, ROI, normalization, or reference-image details for independent replication. The threshold robustness experiment also uses a subtly different `BestUni` definition from the main experiment. That is not fatal, but it must be stated.

Major issues:
- **M1: Experimental protocol is under-specified.** Add dataset names or scene categories, frame selection rule, fixed seed, sample count, ROI/crop rule, and image normalization rule.
- **M2: Statistical reporting is incomplete.** The paper says all Wilcoxon tests are significant but does not report p-values or the tested paired vectors. Add p-value ranges or a compact note in Table I caption/text.
- **M3: Best unidirectional definition changes across experiments.** Main fixed-budget results select the best unidirectional group by mean PSNR. Exp3B computes `BestUniPSNR_Mean` using per-sample max over range-only and azimuth-only. Clarify this in the threshold subsection or adjust the computation/reporting to use one convention.
- **M4: Mechanism evidence is based on a representative case.** Table II is useful, but one scene/case is weaker than the multi-scene main result. Either say it is representative mechanism evidence, or add a sentence pointing to supplementary multi-sample consistency if you want a stronger mechanism claim.

Minor issues:
- Consider adding the exact `A_s=0.6` RT setting to the main experiment caption or method text.
- The method should state whether upsampling is performed before threshold generation and one-bit quantization.

## Reviewer 2: Domain Review

Recommendation: **Minor-to-Major Revision**

Confidence: **4/5**

Summary: The paper is well aligned with 1-bit SAR literature because it studies a design dimension that threshold-design papers do not emphasize. The introduction cites the right families of work: signum-coded SAR, single-frequency thresholds, time-varying thresholds, fixed-threshold slow-time fluctuations, and de-quantization networks. The remaining domain issue is positioning. The paper should explain why range-azimuth budget allocation is not just a preprocessing detail, but a sampling/quantization design variable that interacts with 2D SAR spectral support.

Major issues:
- **D1: Literature gap needs sharper wording.** The paper should say prior works focus on threshold construction and post-acquisition recovery, while this work changes the dimensional allocation before quantization under fixed budget.
- **D2: SAR processing chain should be more explicit.** The method mentions range compression, RCMC, and image formation, but does not name the processor assumptions or whether all groups use identical downstream parameters after crop/resize.
- **D3: Mechanism language risks overclaiming.** "Better matches the two-dimensional spectral structure" is plausible, but currently supported by one mechanism figure/table. Phrase it as mechanism evidence consistent with the metric gains unless additional theory is added.

Suggested additions:
- Add one sentence defining why unidirectional upsampling can leave directional leakage after 1-bit quantization.
- Add a short limitation/future-work sentence on theoretical modeling of 2D quantization noise shaping.

## Reviewer 3: Practical / System Perspective

Recommendation: **Minor Revision**

Confidence: **3/5**

Summary: From a system perspective, the idea is attractive because it does not require a new reconstruction network or a new SAR imaging processor. It changes allocation of the sampling/interpolation budget and may therefore be easy to test in existing processing pipelines. The practical question is what the "budget" means physically. If `Q=R x A` is a computational interpolation budget, the implication differs from actual ADC sampling, PRF, bandwidth, storage, or onboard processing cost. The paper should avoid implying immediate hardware savings unless the system interpretation is made explicit.

Major issue:
- **P1: Budget semantics are ambiguous.** Clarify whether the fixed budget is a digital upsampling/interpolation budget, an equivalent sample-count budget, or a proxy for hardware acquisition resources.

Minor issues:
- Non-integer factors are practically interesting, but the paper should state how they are implemented.
- Add a sentence on computational overhead: BRAU is simple, but 2D upsampling changes array sizes and processing cost.
- If page space allows, mention whether the approach applies to complex raw echoes, intensity-only processing, or the current simulated pipeline only.

## Devil's Advocate Review

### Strongest Counter-Argument

The strongest attack is that BRAU may not yet be proven as a SAR-specific mechanism. The observed gain could be caused by interpolation, crop/normalization, or metric bias rather than a deeper property of 1-bit SAR spectral structure. Under a fixed `Q`, distributing samples across two dimensions may simply produce a smoother image that PSNR/SSIM prefer, while single-direction upsampling produces anisotropic artifacts. That would still be useful, but weaker than the claimed design principle. The mechanism evidence partially addresses this, but Fig. 3 and Table II are not yet enough to rule out alternative explanations because the mechanism analysis is representative rather than comprehensive and because RC/RCMC metrics are identical in Table II.

### Issue List

Critical:
- None. The central result is supported by local experiment outputs and is not contradicted by the data shown.

Major:
- **DA1: Alternative explanation not ruled out.** The gain may be due to isotropic smoothing/interpolation rather than 1-bit SAR spectral leakage suppression.
- **DA2: Mechanism evidence is too narrow for the strength of the claim.** One representative spectral figure does not fully justify a general mechanism statement.
- **DA3: Statistical significance may be over-emphasized.** With 70 paired samples, small but consistent gains can be highly significant; practical significance should be discussed via effect size or gain magnitude.

Minor:
- **DA4: "Simple and effective design principle" is acceptable but should be grounded in tested conditions.** Avoid implying universality beyond the tested datasets, thresholds, and processing chain.

## Editorial Synthesis

### Reviewer Summary

| Reviewer | Recommendation | Confidence | Core concern |
|---|---:|---:|---|
| EIC | Major Revision | 4 | Contribution framing and conference readiness |
| R1 Methodology | Major Revision | 5 | Protocol detail, statistics, BestUni definition |
| R2 Domain | Minor-to-Major Revision | 4 | Domain positioning and mechanism wording |
| R3 Perspective | Minor Revision | 3 | Practical meaning of fixed budget |
| Devil's Advocate | No score | - | Alternative explanations and overclaim risk |

### Consensus

- [CONSENSUS-4] The core result is promising and worth developing into a submission.
- [CONSENSUS-4] The paper needs clearer methodological reporting before review-ready submission.
- [CONSENSUS-3] The mechanism discussion should be softened or supported with broader evidence.
- [CONSENSUS-3] The contribution should be positioned as fixed-budget allocation before one-bit quantization, not as a generic upsampling claim.

### Disagreements

- R3 views the paper as close to Minor Revision because the practical idea is straightforward. R1 and the EIC classify it as Major Revision because the experimental protocol and statistical reporting are not yet sufficient for independent review. Editorial resolution: **Major Revision**, because reproducibility and metric interpretation are core to this paper's credibility.

## Revision Roadmap

### Required Revisions

| ID | Revision item | Source | Priority | Effort |
|---|---|---|---|---|
| R1 | Add a compact experimental protocol paragraph: dataset names/categories, 7 x 10 sampling, seed, ROI/crop, normalization, GT/reference construction. | R1/EIC | P1 | 0.5 day |
| R2 | Clarify where upsampling occurs relative to threshold generation, one-bit quantization, RC, RCMC, and image formation. | R1/R2 | P1 | 0.5 day |
| R3 | Clarify `BestUni` definitions. Main experiment uses mean-best group; Exp3B uses per-sample max for the gain vector. | R1 | P1 | 0.5 day |
| R4 | Revise mechanism wording: either present Fig. 3/Table II as representative evidence or add broader mechanism statistics. | R1/R2/DA | P1 | 0.5-1 day |
| R5 | Add p-value reporting or a concise statistical note for Wilcoxon tests. | R1 | P1 | 0.25 day |
| R6 | Clarify what "fixed budget" means: digital upsampling/sample-count allocation proxy, not necessarily direct hardware budget. | R3 | P1 | 0.25 day |

### Suggested Revisions

| ID | Revision item | Source | Priority | Effort |
|---|---|---|---|---|
| S1 | Sharpen introduction gap: threshold design/post-processing vs dimensional allocation before quantization. | R2/EIC | P2 | 0.25 day |
| S2 | Add one sentence about practical computational overhead of bidirectional allocation. | R3 | P2 | 0.25 day |
| S3 | Add implementation note for non-integer upsampling factors. | R3 | P2 | 0.25 day |
| S4 | Keep claim language within tested conditions: datasets, thresholds, and processing chain. | DA | P2 | 0.25 day |

### Revision Checklist

- [ ] R1: Add compact experimental protocol details.
- [ ] R2: Clarify full processing order and identical downstream processing.
- [ ] R3: Clarify main-vs-threshold `BestUni` statistic.
- [ ] R4: Revise mechanism paragraph and caption to avoid overclaiming.
- [ ] R5: Add p-value/statistical reporting details.
- [ ] R6: Define the fixed-budget interpretation.
- [ ] S1-S4: Apply wording and positioning improvements.

## Next Pipeline Step

Stage 3 decision is **Major Revision**. The next ARS step is **Stage 4 REVISE**, using this roadmap as input.

