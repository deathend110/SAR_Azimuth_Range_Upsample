# BRAU V4 已用参考文献：选择思路、DOI 与网址

本文档对应 `sketch/brau_draft_v4.tex` 当前实际引用的 28 条文献。V4 的选择原则不是为了增加条目数量，而是围绕论文的论证链建立一个最小且完整的证据集合：

1. **SAR 成像与原始数据处理基础**：说明原始回波、距离压缩、RCMC、聚焦及星载数据量问题的工程背景。
2. **原始数据量化与 1-bit SAR 的技术脉络**：从块自适应量化、早期 signum/one-bit SAR，到 1-bit 相位量化与干涉处理，说明问题并非由本文首次提出。
3. **1-bit 测量与重建理论**：用压缩感知及 1-bit 采样理论解释符号量化造成的信息损失，以及阈值/冗余为何有意义。
4. **与 V4 方法直接相连的 SAR 工作**：优先保留 1-bit SAR 的阈值设计、低精度采样、去量化与稀疏重建研究。其中 Zhao (2019) 与 Nie (2025) 是本文 FFT 频域上采样及阈值设置的直接方法来源。
5. **评价指标与统计检验**：SSIM、Shannon entropy 和 ENL 的直接来源用于固定评价对象与计算定义，Wilcoxon 原始论文用于说明配对显著性检验。

所有含 DOI 的条目均提供 DOI 的规范解析网址 `https://doi.org/...`。书籍以及未注册 DOI 的早期文献明确标为“无 DOI”，并给出出版社页面或 Crossref 检索入口；不以猜测的 DOI 替代。

## 1. SAR 基础与原始数据量化背景

| # | 文献题名 | 在 V4 中的作用 | DOI | 网址 |
|---:|---|---|---|---|
| 1 | *Digital Processing of Synthetic Aperture Radar Data: Algorithms and Implementation* | SAR 数字处理、距离压缩和成像流程基础。 | 无 DOI（图书） | [Artech House 出版社页面](https://us.artechhouse.com/Digital-Processing-of-Synthetic-Aperture-Radar-Data-P1549.aspx) |
| 2 | *Synthetic Aperture Radar: Systems and Signal Processing* | SAR 系统、回波处理与成像基础。 | 无 DOI（图书） | [Wiley 出版社页面](https://www.wiley-vch.de/en/areas-interest/engineering/synthetic-aperture-radar-978-0-471-85770-9) |
| 3 | Block adaptive quantization of Magellan SAR data | 说明 SAR 原始数据量化和码率控制的早期工程需求。 | `10.1109/36.29557` | [DOI](https://doi.org/10.1109/36.29557) |
| 4 | Flexible dynamic block adaptive quantization for Sentinel-1 SAR missions | 用星载 Sentinel-1 场景补充灵活量化的工程背景。 | `10.1109/LGRS.2010.2047242` | [DOI](https://doi.org/10.1109/LGRS.2010.2047242) |
| 5 | Lossy predictive coding of SAR raw data | 补充 SAR 原始回波有损编码与数据压力的既有路径。 | `10.1109/TGRS.2003.811556` | [DOI](https://doi.org/10.1109/TGRS.2003.811556) |

## 2. 早期 1-bit SAR 与量化成像脉络

| # | 文献题名 | 在 V4 中的作用 | DOI | 网址 |
|---:|---|---|---|---|
| 6 | Processing of signum coded SAR signal: Theory and experiments | signum 编码 SAR 的早期理论与实验来源。 | `10.1049/ip-f-2.1991.0025` | [DOI](https://doi.org/10.1049/ip-f-2.1991.0025) |
| 7 | Time-domain convolution of one-bit coded radar signals | 早期 one-bit 雷达信号卷积处理。 | `10.1049/ip-f-2.1991.0057` | [DOI](https://doi.org/10.1049/ip-f-2.1991.0057) |
| 8 | Design and demonstration of a real time processor for one-bit coded SAR signals | 说明 1-bit SAR 的实时处理实现曾被研究。 | `10.1049/ip-rsn:19960406` | [DOI](https://doi.org/10.1049/ip-rsn:19960406) |
| 9 | Synthetic aperture radar interferometry using one bit coded raw and reference signals | 说明 one-bit 编码也被用于 SAR 干涉处理。 | `10.1109/36.628791` | [DOI](https://doi.org/10.1109/36.628791) |
| 10 | Synthetic aperture radar imaging by one bit coded signals | 1-bit SAR 成像的代表性早期工作。 | 未检索到 DOI | [Crossref 检索入口](https://search.crossref.org/?q=Synthetic%20aperture%20radar%20imaging%20by%20one%20bit%20coded%20signals) |
| 11 | Phase quantized SAR signal processing: Theory and experiments | 相位量化 SAR 的理论和实验补充。 | `10.1109/7.745692` | [DOI](https://doi.org/10.1109/7.745692) |

## 3. 1-bit 测量与压缩感知理论基础

| # | 文献题名 | 在 V4 中的作用 | DOI | 网址 |
|---:|---|---|---|---|
| 12 | An introduction to compressive sampling | 压缩感知的一般理论背景。 | `10.1109/MSP.2007.914731` | [DOI](https://doi.org/10.1109/MSP.2007.914731) |
| 13 | 1-bit compressive sensing | 1-bit 测量与符号量化重建的基础文献。 | `10.1109/CISS.2008.4558487` | [DOI](https://doi.org/10.1109/CISS.2008.4558487) |
| 14 | Trust, but verify: Fast and accurate signal recovery from 1-bit compressive measurements | 说明阈值辅助的 1-bit 测量能够改善恢复。 | `10.1109/TSP.2011.2162324` | [DOI](https://doi.org/10.1109/TSP.2011.2162324) |
| 15 | Robust 1-bit compressive sensing via binary stable embeddings of sparse vectors | 1-bit 嵌入与鲁棒恢复理论支撑。 | `10.1109/TIT.2012.2234823` | [DOI](https://doi.org/10.1109/TIT.2012.2234823) |

## 4. 直接相关的 1-bit / 低精度 SAR 方法

| # | 文献题名 | 在 V4 中的作用 | DOI | 网址 |
|---:|---|---|---|---|
| 16 | A MAP approach for 1-bit compressive sensing in synthetic aperture radar imaging | 1-bit SAR 的模型驱动重建代表。 | `10.1109/LGRS.2015.2390623` | [DOI](https://doi.org/10.1109/LGRS.2015.2390623) |
| 17 | Enhanced 1-bit radar imaging by exploiting two-level block sparsity | 用稀疏先验提升 1-bit 雷达成像的代表。 | `10.1109/TGRS.2018.2864795` | [DOI](https://doi.org/10.1109/TGRS.2018.2864795) |
| 18 | Sparse logistic regression-based one-bit SAR imaging | 近年的稀疏逻辑回归 1-bit SAR 重建方法。 | `10.1109/TGRS.2023.3322554` | [DOI](https://doi.org/10.1109/TGRS.2023.3322554) |
| 19 | One-bit compressive sensing with time-varying thresholds in synthetic aperture radar imaging | 时变阈值 1-bit SAR 方法。 | `10.1049/iet-rsn.2018.5044` | [DOI](https://doi.org/10.1049/iet-rsn.2018.5044) |
| 20 | One-bit SAR imaging based on single-frequency thresholds | 本文频域阈值及 FFT 频域上采样设置的直接来源之一。 | `10.1109/TGRS.2019.2910284` | [DOI](https://doi.org/10.1109/TGRS.2019.2910284) |
| 21 | Strategy for SAR imaging quality improvement with low-precision sampled data | 低精度 SAR 采样质量改善的直接相关工作。 | `10.1109/TGRS.2020.3014300` | [DOI](https://doi.org/10.1109/TGRS.2020.3014300) |
| 22 | Lightweight SAR: A two-bit strategy | 作为 1-bit 与更高位深 SAR 策略之间的对照背景。 | `10.3390/rs15020310` | [DOI](https://doi.org/10.3390/rs15020310) |
| 23 | A convolutional de-quantization network for harmonics suppression in one-bit SAR imaging | 近年的去量化网络及谐波抑制方法。 | `10.1109/TGRS.2023.3330530` | [DOI](https://doi.org/10.1109/TGRS.2023.3330530) |
| 24 | One-bit synthetic aperture radar imaging based on fixed-threshold with slow-time fluctuations | 本文 RT/RSFT 阈值设计和频域上采样流程的直接来源之一。 | `10.1109/TGRS.2024.3519757` | [DOI](https://doi.org/10.1109/TGRS.2024.3519757) |

## 5. 评价指标与统计检验

| # | 文献题名 | 在 V4 中的作用 | DOI | 网址 |
|---:|---|---|---|---|
| 25 | Image quality assessment: From error visibility to structural similarity | SSIM 的原始定义与本文结构相似性评价依据。 | `10.1109/TIP.2003.819861` | [DOI](https://doi.org/10.1109/TIP.2003.819861) |
| 26 | A Mathematical Theory of Communication | Shannon entropy 定义及本文归一化幅度直方图熵公式的来源。 | `10.1002/j.1538-7305.1948.tb01338.x` | [DOI](https://doi.org/10.1002/j.1538-7305.1948.tb01338.x)；[Wiley 页面](https://onlinelibrary.wiley.com/doi/abs/10.1002/j.1538-7305.1948.tb01338.x) |
| 27 | Synthetic aperture radar image despeckling via total generalised variation approach | 均匀强度区域上 ENL 定义及 \(\mu_I^2/\sigma_I^2\) 公式的直接依据。 | `10.1049/iet-ipr.2013.0701` | [DOI](https://doi.org/10.1049/iet-ipr.2013.0701)；[IET/Wiley 全文页](https://ietresearch.onlinelibrary.wiley.com/doi/full/10.1049/iet-ipr.2013.0701) |
| 28 | Individual Comparisons by Ranking Methods | 70 样本配对 Wilcoxon signed-rank test 的原始方法来源。 | `10.2307/3001968` | [DOI](https://doi.org/10.2307/3001968)；[JSTOR 页面](https://www.jstor.org/stable/3001968) |

## 使用边界

- 当前 V4 中，文献 [1]--[24] 服务于 Introduction、Method 以及实验章节中的问题背景、方法定位、量化失真解释和阈值参数设计；文献 [25]--[28] 用于 Evaluation Protocol 的指标与统计方法定义。
- 机制分析、阈值设计和主结果的核心证据来自本项目的 70 样本 V4 实验结果，而不是由外部文献代替实验结论。
- 早期文献虽然年代较早，但分别承担 SAR 基础、原始量化或 1-bit SAR 起源的“奠基性”角色，因此保留；近年文献用于呈现阈值、低精度采样、去量化和重建的最新技术脉络。
- 文献 [20] 与 [24] 是全文最直接的实现继承来源，并在 Method 和 Threshold Design 中分别标注其对应的频域上采样、RSFT 与 fluctuating-threshold 设置。它们不用于宣称本文结论已被既有工作证明，而用于说明本文在其既有频域/阈值框架内研究一个新的固定预算二维分配问题。
- Experiments and Results 中对既有文献的引用仅用于区分“已知的 1-bit 谐波失真与阈值影响”和“本文观察到的二维泄漏、最优参数及双向分配优势”；所有图表数值与 BRAU 结论仍由本文实验直接支撑。
