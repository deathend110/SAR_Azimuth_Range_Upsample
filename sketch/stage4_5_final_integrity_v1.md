# 学术完整性验证报告 — Stage 4.5 最终检查 v1

论文：`sketch/brau_draft_v2.tex`

验证模式：**最终验证（Mode 2 — 修订后的全面独立检查）**

验证时间：2026-07-01

## 结论

**PASS** — 零问题。Stage 4.5 通过，可进入 Stage 5 定稿。

## 验证汇总

| 类别              | 总数       | 通过   | 问题数         |
| --------------- | -------- | ---- | ----------- |
| 参考文献存在性         | 8        | 8    | 0           |
| 书目准确性           | 8        | 8    | 0           |
| 鬼影引用（孤本引用/悬空引用） | --       | --   | 0 孤本 / 0 悬空 |
| 引文上下文准确性        | 8（100%）  | 8    | 0           |
| 统计数据准确性         | 全部数值     | 全部通过 | 0           |
| 内部一致性           | --       | 通过   | 0           |
| 原创性检查（D1）       | 4 段（57%） | 4    | 0           |
| 主张验证（E）         | 12（100%） | 12   | 0           |

## Phase A：参考文献验证

### A1/A2：参考文献存在性与书目准确性

| #   | 键                         | 结论    | 确认来源                                                                                                       |
| --- | ------------------------- | ----- | ---------------------------------------------------------------------------------------------------------- |
| 1   | `cumming2005sar`          | ✓ 已验证 | Artech House ISBN 9781580530583；UBC SAR 实验室页面确认作者 Cumming & Wong，2005 年                                    |
| 2   | `curlander1991sar`        | ✓ 已验证 | Wiley ISBN 9780471857709；Google Books 确认作者 Curlander & McDonough，1991 年 11 月                               |
| 3   | `franceschetti1991signum` | ✓ 已验证 | IET Digital Library DOI 10.1049/ip-f-2.1991.0025，卷 138 期 3 第 192–198 页，作者 Franceschetti/Pascazio/Schirinzi |
| 4   | `zhao2019onebit`          | ✓ 已验证 | IEEE Xplore DOI 10.1109/TGRS.2019.2910284，卷 57 期 9 第 7017–7032 页，作者 Zhao/Huang/Bao                         |
| 5   | `demir2018onebit`         | ✓ 已验证 | IET/Wiley DOI 10.1049/iet-rsn.2018.5044，卷 12 期 12 第 1517–1526 页，作者 Demir/Ercelebi                          |
| 6   | `zhao2021lowprecision`    | ✓ 已验证 | IEEE Xplore DOI 10.1109/TGRS.2020.3014300，卷 59 期 4 第 3150–3160 页，作者 Zhao/Huang/Jin                         |
| 7   | `nie2025fixed`            | ✓ 已验证 | IEEE Xplore DOI 10.1109/TGRS.2024.3519757，卷 63 第 1–15 页，作者 Nie/Zhao/Liu/Huang/Liao                         |
| 8   | `si2023dequantization`    | ✓ 已验证 | IEEE Xplore DOI 10.1109/TGRS.2023.3330530，卷 61 第 1–16 页，作者 Si/Zhao/Huang/Liu                               |

### A3：鬼影引用检查

- 引用键与 `\bibitem` 条目：8 对 8 — 无悬空引用，无孤本参考文献 ✓
- 每次引用在正文中均出现至少一次 ✓

## Phase B：引文上下文验证（100%）

所有 8 条引用经评估其上下文准确性：

| 引用                                                  | 正文主张                             | 与源文献的一致性                              |
| --------------------------------------------------- | -------------------------------- | ------------------------------------- |
| cumming2005sar, curlander1991sar                    | SAR 形成高分辨率图像；传统 SAR 使用高分辨率 ADC   | 标准 SAR 教材——主张精确 ✓                     |
| franceschetti1991signum                             | 早期 signum 编码 SAR 研究表明可从仅符号数据形成图像 | 论文标题"signum coded SAR signal"——主张精确 ✓ |
| zhao2019onebit                                      | 单频阈值抑制谐波干扰                       | 论文提出 SFT 以抑制谐波——主张精确 ✓                |
| demir2018onebit, zhao2021lowprecision, nie2025fixed | 时变和固定阈值策略                        | 所有三篇论文均研究阈值策略——主张精确 ✓                 |
| si2023dequantization                                | 基于学习的反量化方法抑制谐波                   | CDQOB-net 是一种基于学习的反量化网络——主张精确 ✓       |

**结论：无失真或错误表述。**

## Phase C：数据验证

### C1：统计数据交叉引用 — 所有数值与 CSV 导出文件匹配

| 表格/段 | 检查项 | 结论 |
|--------|-------|---------|
| 表 I（主结果） | Q=4,6,8,9,10 的 PSNR/SSIM 值与 Δ 值 | ✓ 与 `Exp1_MainResult_Summary.csv` 和 `_Gain.csv` 完全匹配，4 位小数取整一致 |
| 非整数部分 | Q=3,4.5,5,7.5 的 ΔPSNR | ✓ 与 `Exp1_NonInteger_Gain.csv` 匹配 |
| 表 II（机制） | 4 种分配下 RC/RCMC 的 off-support/range-leakage/azimuth-leakage | ✓ 与 `Exp2_Mechanism_Metrics.csv` 匹配 |
| 阈值实验 | ZT/NCT/RT 下 Q=4,6,9 的 ΔPSNR | ✓ 与 `Exp3B_ZT_NCT_RT_Gains.csv` 匹配 |
| SplitRT vs FullRT 陈述 | "几乎重叠"，最大均值差 0.0851 dB PSNR | ✓ 与 `Exp3A_SplitVsFull_Summary.csv` 匹配 |
| Wilcoxon p 值 | p_PSNR ≤ 4.34×10⁻¹⁰, p_SSIM = 3.56×10⁻¹³ | ✓ 与增益 CSV 匹配（使用最保守的 p 值上限） |

### C2：内部一致性

- 种子 2026、A_s=0.6、7 个场景、每数据集 10 个窗口、70 个配对样本：正文与实验协议一致 ✓
- 阈值实验的 BestUni 定义已正确限定（每样本最大值） ✓
- 所有数值在正文与表格之间一致 ✓

### C3：图表标题保真度

图/表格式评估：
- 图 1-2（PSNR/SSIM 曲线）：标题声称内容与 CSV 数据一致 ✓
- 图 3（频谱）：由 `\refstepcounter{figure}` 放置，手动但功能正确；标题准确描述频谱行为 ✓
- 表 I（主增益）：标题声明"best groups are selected by mean PSNR"，与实验协议一致 ✓
- 表 II（机制指标）：标题声明"Lower values indicate cleaner spectral concentration"，与已确认数据一致 ✓

## Phase D：原创性验证

### D1：段落级原创性检查（已检查 4/7 段 = 57%）

| 段落位置 | 句子样例 | 结果 |
|----------|-------------|--------|
| 引言第 3 段 | "Most existing work focuses on how to construct thresholds... In contrast, this paper studies a less explored design question..." | **原创** — 未找到相关匹配 |
| 方法 §2.1 | "The proposed bidirectional range-azimuth upsampling (BRAU) strategy does not change the SAR imaging processor itself" | **原创** — 关键技术区别 |
| 机制 §3.3 | "Using a reference spectrum X_ref, the support mask is defined by M(k_r,k_a)=1..." | **原创** — 具体技术公式 |
| 结论第 2 段 | "After range compression, the bidirectional group produces lower off-support spectral energy..." | **原创** — 具体机制主张 |

### D2：自我剽窃检查

- 前提：用户未提供作者姓名以进行自我剽窃检查
- **外部查重说明**：本报告使用 WebSearch 进行启发式比较，并非专业剽窃检测软件（如 Turnitin/iThenticate）。建议在正式投稿前使用专业工具进行全面查重。

## Phase E：主张验证（100%，12/12 条主张）

| # | 主张 | 位置 | 验证依据 | 结论 |
|---|-------|----------|--------------|--------|
| 1 | "PSNR improvement ranges from 0.2856 dB to 0.5072 dB" | 第 3.1 节 | `Exp1_MainResult_Gain.csv` | ✓ 已验证 |
| 2 | "SSIM improvement ranges from 0.0169 to 0.0221" | 第 3.1 节 | `Exp1_MainResult_Gain.csv` | ✓ 已验证 |
| 3 | "p_PSNR ≤ 4.34×10⁻¹⁰, p_SSIM = 3.56×10⁻¹³" | 第 3.1 节 | `Exp1_MainResult_Gain.csv` | ✓ 已验证 |
| 4 | "非整数 PSNR gains 0.2723, 0.3437, 0.3952, 0.4567 dB" | 第 3.2 节 | `Exp1_NonInteger_Gain.csv` | ✓ 已验证 |
| 5 | "SSIM gain range 0.0146 to 0.0221" | 第 3.2 节 | `Exp1_NonInteger_Gain.csv` | ✓ 已验证 |
| 6 | "R2A2 achieves the lowest off-support ratio, range leakage, and azimuth leakage" | 第 3.3 节 | `Exp2_Mechanism_Metrics.csv` | ✓ 已验证 |
| 7 | ZT gains: 0.3612, 0.4162, 0.4318 dB | 第 3.4 节 | `Exp3B_ZT_NCT_RT_Gains.csv` | ✓ 已验证 |
| 8 | NCT gains: 0.4308, 0.4896, 0.5341 dB | 第 3.4 节 | `Exp3B_ZT_NCT_RT_Gains.csv` | ✓ 已验证 |
| 9 | RT gains: 0.2018, 0.3306, 0.3611 dB | 第 3.4 节 | `Exp3B_ZT_NCT_RT_Gains.csv` | ✓ 已验证 |
| 10 | "SplitRT and FullRT nearly overlap" | 第 3.4 节 | `Exp3A_SplitVsFull_Summary.csv` | ✓ 已验证 |
| 11 | "seven SAR datasets", "70 paired test samples" | 第 2.3 节 | 与实验协议一致 | ✓ 已验证 |
| 12 | "seed 2026, A_s=0.6, SplitRT" | 第 2.3 节 | 与实验协议一致 | ✓ 已验证 |

**结论：无 MAJOR_DISTORTION，无 UNVERIFIABLE 主张。**

## 7 项 AI 研究失败模式检查

| 模式 | 状态 | 理由 |
|------|--------|----------|
| **模式 1**：实现错误通过 AI 自检 | **CLEAR** | 实验输出（CSV 文件）与论文表格精确匹配，数值分布自然（非"过于整齐"的伪迹）。每项结果均有对应的 CSV 导出文件。 |
| **模式 2**：幻觉引用 | **CLEAR** | 所有 8 条参考文献均已通过 WebSearch 验证，包含完整的 DOIs 和可核实的书目元数据。 |
| **模式 3**：幻觉实验结果 | **CLEAR** | 每个声称的数字均直接追溯到本地 CSV 导出文件，精确度达 4 位小数。 |
| **模式 4**：捷径依赖 | **CLEAR** | 论文在 3 种阈值设置（ZT/NCT/RT）、非整数因子和 7 个数据集中证实了双向优势——远超单一场景/单一设置的演示。 |
| **模式 5**：将实现错误重构为新颖见解 | **CLEAR** | 机制分析（频谱泄漏指标）在已处理数据中提供了 BRAU 工作原理的可验证证据；增益并非来自意外行为。 |
| **模式 6**：方法论编造 | **CLEAR** | 方法部分描述的处理流水线与实验输出一致；参数（种子、A_s、预算）与数据文件匹配。 |
| **模式 7**：早期流水线阶段的框架锁定 | **CLEAR** | 论文的研究问题（预算分配）从一开始就得到了很好的限定；方法允许双向和单向比较，没有隐性偏见。 |

**阻塞条件：无 SUSPECTED 或 INSUFFICIENT EVIDENCE 模式 — 流水线继续运行。**

## 与 Stage 2.5 的对比

| 项目 | Stage 2.5 结论 | Stage 4.5 结论 | 结果 |
|------|----------------|----------------|--------|
| `zhao2019onebit` 书目错误 | FAIL → 已修正 | ✓ 已验证 | 已解决 |
| `demir2018onebit` 书目错误 | FAIL → 已修正 | ✓ 已验证 | 已解决 |
| `zhao2021lowprecision` 书目错误 | FAIL → 已修正 | ✓ 已验证 | 已解决 |
| `nie2025fixed` 书目错误 | FAIL → 已修正 | ✓ 已验证 | 已解决 |
| `si2023dequantization` 书目错误 | FAIL → 已修正 | ✓ 已验证 | 已解决 |
| 实验数值 | 通过（附注） | ✓ 已验证（从头开始） | 一致 |
| BestUni 定义说明 | 说明中的说明 | ✓ 已正确限定在阈值部分 | 改进 |

## 问题列表

**零问题。** PASS，已清除进入 Stage 5。

## 工具限制声明

> 本验证报告的原创性检查（Phase D）使用 WebSearch 进行启发式比较，并非专业剽窃检测软件（如 Turnitin/iThenticate）。覆盖范围仅限于可公开搜索的文献，采样率为 57%，存在漏检风险。这些结果作为初步筛查；建议在正式投稿前使用专业查重工具进行完整查重。

## 验证审计追踪

| 参考/检查 | 搜索词/方法 | 结果 |
|-----------|-------------|--------|
| cumming2005sar | "Digital Processing of Synthetic Aperture Radar Data" Cumming Wong Artech House | 出版商页面 + UBC 实验室页面确认 |
| curlander1991sar | "Synthetic Aperture Radar Systems and Signal Processing" Curlander McDonough Wiley | Wiley + Google Books 确认 |
| franceschetti1991signum | DOI 10.1049/ip-f-2.1991.0025 | IET Digital Library 确认，卷/期/页匹配 |
| zhao2019onebit | DOI 10.1109/TGRS.2019.2910284 | IEEE Xplore 确认，所有元数据匹配 |
| demir2018onebit | DOI 10.1049/iet-rsn.2018.5044 | IET/Wiley 确认，卷/期/作者匹配 |
| zhao2021lowprecision | DOI 10.1109/TGRS.2020.3014300 | IEEE Xplore 确认，修正后的卷/页匹配 |
| nie2025fixed | DOI 10.1109/TGRS.2024.3519757 | IEEE 确认：Nie/Zhao/Liu/Huang/Liao，卷 63 第 1-15 页 |
| si2023dequantization | DOI 10.1109/TGRS.2023.3330530 | IEEE 确认：Si/Zhao/Huang/Liu，卷 61 第 1-16 页 |
| 表 I 数值 | 与 Exp1_MainResult_Summary.csv 和 Gain.csv 比较 | 所有 5 个预算逐值匹配 |
| 非整数数值 | 与 Exp1_NonInteger_Gain.csv 比较 | 4 个预算均匹配 |
| 机制数值 | 与 Exp2_Mechanism_Metrics.csv 比较 | 8 行指标值匹配 |
| 阈值数值 | 与 Exp3B_ZT_NCT_RT_Gains.csv 比较 | 9 个增益值匹配 |
| 原创性 | WebSearch "bidirectional range-azimuth upsampling" + "fixed-budget" | 无相关现有技术 |
| 跨引用检查 | 引文 ↔ \bibitem 匹配 | 8/8 双向匹配 |

## 流水线门控

Stage 4.5 结论：**PASS（零问题）**

下一阶段：**Stage 5 FINALIZE** — 格式转换（默认 MD，DOCX/Pandoc，LaTeX/PDF）。
