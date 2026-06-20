# BRAU Research Packet

> ARS Stage 1 收尾材料；用于交接到 Stage 2 论文写作规划。
> 当前状态：实验结果已分析，尚未经过 Stage 2.5 integrity verification。
> 生成日期：2026-06-20

## 1. Material Passport

| 项目                  | 内容                                                                                                                                                              |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Artifact            | BRAU Research Packet                                                                                                                                            |
| Pipeline Stage      | Stage 1 RESEARCH -> Stage 2 WRITE handoff                                                                                                                       |
| Topic               | Bidirectional Range-Azimuth Upsampling for 1-bit SAR Imaging                                                                                                    |
| Data Access Level   | raw experiment outputs analyzed locally                                                                                                                         |
| Verification Status | ANALYZED, not integrity-verified                                                                                                                                |
| Primary Evidence    | `Exp1_MainResult_Output`, `Exp1_NonInteger_Output`, `Exp2_Mechanism_Output`, `Exp2_Mechanism_Supp_Output`, `Exp3A_SplitVsFull_Output`, `Exp3B_ZT_NCT_RT_Output` |
| Known Caveat        | 当前主结果为单 seed、70 个配对样本，不是原设计中的 5 seeds、350 个观测                                                                                                                   |

## 2. Final Research Question

在 1-bit SAR 成像中，当总上采样预算固定为 `Q = R x A` 时，将预算拆分到距离向和方位向两个维度，是否比将预算集中到单一维度更有效地改善重建质量？

## 3. Scope

### In Scope

- 1-bit SAR 成像中的距离向/方位向上采样预算拆分策略。
- 固定总预算 `Q` 下，双向拆分与单向集中上采样的重建质量对比。
- SplitRT、FullRT、ZT、NCT、RT 等阈值构造下的规律鲁棒性。
- 以 PSNR、SSIM、配对 Wilcoxon 检验和中间频谱泄漏指标作为证据。

### Out of Scope

- 不主张“双向拆分优于单向”是普遍信号处理规律。
- 不主张本文贡献是新的随机阈值理论。
- 不声称机制实验已经严格证明完整物理因果链。
- 不声称当前实验已经完成多 seed 统计稳健性验证。

## 4. Central Thesis

本文主张：在 1-bit SAR 成像中，固定总上采样预算下，将预算拆分到距离向和方位向两个维度，较单向集中上采样能更稳定地提升重建质量；该现象对非整数拆分和阈值构造方式具有鲁棒性。机制实验进一步提示，双向上采样的优势与更充分的二维频域冗余和较低的谱外泄漏有关，但当前机制证据应作为解释性支持，而不是完整理论证明。

## 5. Claim-Evidence Map

| Claim | Evidence | Strength | Paper Use |
|---|---|---:|---|
| C1: 双向拆分优于单向集中上采样 | Exp1 主结果：所有整数 `Q=4,6,8,9,10` 下最佳双向均优于最佳单向，Wilcoxon 显著 | Strong | 核心贡献 |
| C2: 优势不是整数因子组合巧合 | Exp1 非整数：`Q=3,4.5,5,7.5` 下非整数双向均优于等预算单向 | Strong | 佐证 |
| C3: 平衡分配不是必要条件 | `R2A3/R3A2`, `R2A4/R4A2`, `R2A5/R5A2` 等非均衡双向均进入高性能平台区 | Moderate to Strong | 佐证 |
| C4: 规律不依赖 SplitRT 内部实现 | Exp3A：SplitRT 与 FullRT 的 As 曲线基本贴合 | Strong | 鲁棒性 |
| C5: RT 不是创造双向优势的唯一原因 | Exp3B：ZT/NCT/RT 三类阈值下双向均优于最佳单向 | Strong | 鲁棒性 |
| C6: 双向优势可能来自更好的二维频谱泄漏抑制 | Exp2：主样本中 `R2A2` 在 RC/RCMC 后的 off-support、range leakage、azimuth leakage 均最低 | Moderate | 机制解释 |
| C7: 单向上采样只改善对应方向这一细机制 | Exp2 当前不充分；方向性分离不干净，补充样本中存在反例 | Weak | 不建议强写 |

## 6. Experiment Evidence Summary

### 6.1 Exp1 Main Result

输出目录：`Exp1_MainResult_Output`

核心设置：

- 数据：7 个 SAR 数据集，每个数据集 10 帧，共 70 个样本。
- 当前实际 seed：`seed = 2026`。
- 阈值：SplitRT，`As = 0.6`。
- 统计：最佳双向组 vs 最佳单向组，配对 Wilcoxon signed-rank test。

主增益表：

| Q | Best Bidir | Best Unidir | Delta PSNR | Delta SSIM | p PSNR | p SSIM |
|---:|---|---|---:|---:|---:|---:|
| 4 | R2A2 | R4A1 | 0.2856 | 0.0169 | 4.34e-10 | 3.56e-13 |
| 6 | R2A3 | R1A6 | 0.4170 | 0.0208 | 2.20e-11 | 3.56e-13 |
| 8 | R2A4 | R8A1 | 0.4576 | 0.0215 | 7.72e-13 | 3.56e-13 |
| 9 | R3A3 | R9A1 | 0.4685 | 0.0214 | 1.53e-11 | 3.56e-13 |
| 10 | R5A2 | R10A1 | 0.5072 | 0.0221 | 5.72e-13 | 3.56e-13 |

稳定性补充：

- 按 7 个数据集拆分后，各 `Q` 下最佳双向相对最佳单向均无负增益。
- 各 `Q` 的最小数据集级 PSNR 增益分别约为：`+0.2325`, `+0.3011`, `+0.2964`, `+0.3618`, `+0.4259 dB`。

可用图表：

| 图表 | 文件 | 用途 |
|---|---|---|
| 主结果 PSNR 曲线 | `Exp1_MainResult_Output/Exp1_MainResult_PSNR_curves.png` | 展示双向曲线整体高于单向 |
| 主结果 SSIM 曲线 | `Exp1_MainResult_Output/Exp1_MainResult_SSIM_curves.png` | 展示结构相似性提升 |
| 主结果汇总表 | `Exp1_MainResult_Output/Exp1_MainResult_Summary.csv` | 论文表格或补充材料 |
| 主结果增益表 | `Exp1_MainResult_Output/Exp1_MainResult_Gain.csv` | 核心统计证据 |

论文可写结论：

> Under the same total upsampling budget, bidirectional allocation consistently outperforms the best unidirectional allocation across all tested integer budgets.

论文避免写法：

> The result is validated over 350 observations or five random seeds.

当前实际不是 350 观测，不能这样写。

### 6.2 Exp1 Non-Integer Result

输出目录：`Exp1_NonInteger_Output`

主增益表：

| Q | Best Bidir | Best Unidir | Delta PSNR | Delta SSIM | p PSNR | p SSIM |
|---:|---|---|---:|---:|---:|---:|
| 3 | R1.5A2 | R3A1 | 0.2723 | 0.0146 | 1.22e-09 | 1.18e-12 |
| 4.5 | R1.5A3 | R4.5A1 | 0.3437 | 0.0172 | 1.63e-09 | 3.72e-13 |
| 5 | R2.5A2 | R5A1 | 0.3952 | 0.0196 | 4.00e-11 | 3.56e-13 |
| 7.5 | R2.5A3 | R1A7.5 | 0.4567 | 0.0221 | 4.23e-13 | 3.56e-13 |

可用图表：

| 图表           | 文件                                                     | 用途           |
| ------------ | ------------------------------------------------------ | ------------ |
| 非整数 PSNR 柱状图 | `Exp1_NonInteger_Output/Exp1_NonInteger_PSNR_bars.png` | 支撑“非整数有效”    |
| 非整数 SSIM 柱状图 | `Exp1_NonInteger_Output/Exp1_NonInteger_SSIM_bars.png` | 支撑“不是整数因子巧合” |
| 非整数增益表       | `Exp1_NonInteger_Output/Exp1_NonInteger_Gain.csv`      | 补充统计证据       |

论文可写结论：

> The advantage persists for non-integer upsampling factors, suggesting that it is not an artifact of integer factorization.

### 6.3 Exp2 Mechanism Result

输出目录：

- `Exp2_Mechanism_Output`
- `Exp2_Mechanism_Supp_Output`

主样本设置：

- `dataset = SAR_Dataset_city2_histeq`
- `file = rstart 301.mat`
- `c_start = 6500`
- `seed = 42`
- `As = 0.6`
- 对照：`R1A1_NoUp`, `R4A1`, `R1A4`, `R2A2`

主样本机制指标：

| Case | Node | Off-support | Range leakage | Azimuth leakage |
|---|---|---:|---:|---:|
| R1A1_NoUp | node1 residual | 0.817690 | 0.199773 | 0.038220 |
| R4A1 | node1 residual | 0.817692 | 0.199893 | 0.038220 |
| R1A4 | node1 residual | 0.817684 | 0.199774 | 0.038499 |
| R2A2 | node1 residual | 0.817687 | 0.199847 | 0.038413 |
| R1A1_NoUp | node2 RC | 0.926008 | 0.471044 | 0.101785 |
| R4A1 | node2 RC | 0.893954 | 0.368013 | 0.070476 |
| R1A4 | node2 RC | 0.901018 | 0.394427 | 0.072251 |
| R2A2 | node2 RC | 0.892857 | 0.363750 | 0.066680 |
| R1A1_NoUp | node3 RCMC | 0.926008 | 0.471044 | 0.101785 |
| R4A1 | node3 RCMC | 0.893954 | 0.368013 | 0.070476 |
| R1A4 | node3 RCMC | 0.901018 | 0.394427 | 0.072251 |
| R2A2 | node3 RCMC | 0.892857 | 0.363750 | 0.066680 |

机制解释强度：

- Node-1 residual：四组指标几乎重合，不能强声称双向优势在量化残差刚产生时已经显著拉开。
- Node-2 RC：`R2A2` 的 off-support、range leakage、azimuth leakage 均最低，可支持“RC 后双向方案表现出更低二维谱外泄漏”。
- Node-3 RCMC：指标与 Node-2 基本一致，说明当前 leakage 指标对 RCMC 增量作用不敏感。
- 多样本补充：多数 scene/tau 下 `R2A2` 最好，但 `filed` 场景部分 tau 下最佳单向略优，机制结论应降调。

多样本补充摘要：

| tau | R2A2 最优场景数 / 4 | Avg R2A2 off | Avg BestUni off | Avg Delta |
|---:|---:|---:|---:|---:|
| 0.15 | 4 | 0.408995 | 0.413779 | 0.004785 |
| 0.25 | 3 | 0.704181 | 0.705821 | 0.001640 |
| 0.35 | 3 | 0.868644 | 0.868598 | -0.000046 |
| 0.45 | 3 | 0.945249 | 0.944960 | -0.000288 |

可用图表：

| 图表 | 文件 | 用途 |
|---|---|---|
| 二维机制核心图 | `Exp2_Mechanism_Output/Exp2_2D_Mechanism_Figure.png` | 推荐正文机制图 |
| 二维机制核心图 PDF | `Exp2_Mechanism_Output/Exp2_2D_Mechanism_Figure.pdf` | 论文排版优先使用 |
| Node-1 残差频谱 | `Exp2_Mechanism_Output/Exp2_Node1_Residual_Spectra.png` | 补充说明量化残差 |
| Node-2 RC 频谱 | `Exp2_Mechanism_Output/Exp2_Node2_RC_Spectra.png` | 展示 RC 后差异 |
| 距离向 1D profile | `Exp2_Mechanism_Output/Exp2_Node1_Residual_Range_Profile.png` | 补充材料 |
| 方位向 1D profile | `Exp2_Mechanism_Output/Exp2_Node1_Residual_Azimuth_Profile.png` | 补充材料 |
| RC/RCMC/Final montage | `Exp2_Mechanism_Output/Exp2_Montage_RC_RCMC_Final.png` | 补充材料或备选图 |
| 多样本机制摘要图 | `Exp2_Mechanism_Supp_Output/Exp2_Supp_MultiSample_Summary.png` | 支撑机制趋势与局限 |

论文可写结论：

> Mechanism analysis suggests that bidirectional upsampling yields a cleaner two-dimensional spectral structure after range compression, as indicated by lower off-support and directional leakage ratios.

论文避免写法：

> The Node-1 quantization residual already proves that bidirectional upsampling pushes 1-bit quantization noise away from the valid support in both directions.

当前 Node-1 数据不支持这种强表述。

### 6.4 Exp3A SplitRT vs FullRT

输出目录：`Exp3A_SplitVsFull_Output`

结论摘要：

- `Q=4,6,9` 下，SplitRT 与 FullRT 的 PSNR/SSIM-As 曲线基本贴合。
- 最大绝对 PSNR 差约 `0.0851 dB`，平均绝对 PSNR 差约 `0.0132 ~ 0.0307 dB`。
- 最大绝对 SSIM 差约 `0.00258`，平均绝对 SSIM 差约 `0.00021 ~ 0.00066`。

差异摘要：

| Q | Max abs Delta PSNR | Mean abs Delta PSNR | Max abs Delta SSIM | Mean abs Delta SSIM |
|---:|---:|---:|---:|---:|
| 4 | 0.0835 | 0.0278 | 0.00258 | 0.00066 |
| 6 | 0.0851 | 0.0307 | 0.00127 | 0.00051 |
| 9 | 0.0457 | 0.0132 | 0.00053 | 0.00021 |

可用图表：

| 图表 | 文件 | 用途 |
|---|---|---|
| SplitRT vs FullRT PSNR 曲线 | `Exp3A_SplitVsFull_Output/Exp3A_SplitVsFull_PSNR_curves.png` | 展示内部阈值构造鲁棒性 |
| SplitRT vs FullRT SSIM 曲线 | `Exp3A_SplitVsFull_Output/Exp3A_SplitVsFull_SSIM_curves.png` | 补充结构相似性鲁棒性 |
| SplitRT vs FullRT 汇总表 | `Exp3A_SplitVsFull_Output/Exp3A_SplitVsFull_Summary.csv` | 补充材料 |

论文可写结论：

> SplitRT and FullRT produce nearly identical trends across the tested As range, indicating that the main observation is not tied to the internal implementation detail of RT construction.

### 6.5 Exp3B ZT/NCT/RT Robustness

输出目录：`Exp3B_ZT_NCT_RT_Output`

主增益表：

| Q | Threshold | Bidir | Best Unidir | Delta PSNR | p value |
|---:|---|---|---|---:|---:|
| 4 | ZT | Q4_R2A2 | Q4_R1A4 | 0.3612 | 7.09e-12 |
| 4 | NCT | Q4_R2A2 | Q4_R4A1 | 0.4308 | 3.56e-13 |
| 4 | RT | Q4_R2A2 | Q4_R1A4 | 0.2018 | 2.73e-07 |
| 6 | ZT | Q6_R2A3 | Q6_R1A6 | 0.4162 | 6.51e-13 |
| 6 | NCT | Q6_R2A3 | Q6_R6A1 | 0.4896 | 3.56e-13 |
| 6 | RT | Q6_R2A3 | Q6_R1A6 | 0.3306 | 1.95e-11 |
| 9 | ZT | Q9_R3A3 | Q9_R1A9 | 0.4318 | 2.13e-12 |
| 9 | NCT | Q9_R3A3 | Q9_R9A1 | 0.5341 | 3.56e-13 |
| 9 | RT | Q9_R3A3 | Q9_R9A1 | 0.3611 | 6.66e-11 |

可用图表：

| 图表 | 文件 | 用途 |
|---|---|---|
| ZT/NCT/RT 绝对性能柱状图 | `Exp3B_ZT_NCT_RT_Output/Exp3B_AbsoluteBars.png` | 展示不同阈值下绝对 PSNR |
| ZT/NCT/RT 增益柱状图 | `Exp3B_ZT_NCT_RT_Output/Exp3B_GainBars.png` | 推荐正文鲁棒性图 |
| ZT/NCT/RT 增益表 | `Exp3B_ZT_NCT_RT_Output/Exp3B_ZT_NCT_RT_Gains.csv` | 核心统计证据 |
| ZT/NCT/RT 汇总表 | `Exp3B_ZT_NCT_RT_Output/Exp3B_ZT_NCT_RT_Summary.csv` | 补充材料 |

论文可写结论：

> The bidirectional advantage remains significant under zero threshold, non-random constant threshold, and random threshold settings. RT improves absolute quality but does not create the bidirectional advantage from scratch.

## 7. Recommended Paper Figure/Table Package

4 页会议论文建议压缩成 3 个正文图表组：

| Priority | Type | Candidate | Reason |
|---:|---|---|---|
| P0 | Main figure | `Exp1_MainResult_Output/Exp1_MainResult_PSNR_curves.png` 或重绘为 PSNR+SSIM 双子图 | 最直接支撑核心 claim |
| P0 | Main table | `Exp1_MainResult_Output/Exp1_MainResult_Gain.csv` 精简表 | 显示最佳双向 vs 最佳单向及 p-value |
| P1 | Mechanism figure | `Exp2_Mechanism_Output/Exp2_2D_Mechanism_Figure.pdf` | 支撑二维频域解释 |
| P1 | Robustness figure | `Exp3B_ZT_NCT_RT_Output/Exp3B_GainBars.png` | 证明 ZT/NCT/RT 下规律稳定 |
| P2 | Supplementary | `Exp1_NonInteger_Output/Exp1_NonInteger_PSNR_bars.png` | 支撑非整数有效 |
| P2 | Supplementary | `Exp3A_SplitVsFull_Output/Exp3A_SplitVsFull_PSNR_curves.png` | 支撑 SplitRT≈FullRT |
| P2 | Supplementary | `Exp2_Mechanism_Supp_Output/Exp2_Supp_MultiSample_Summary.png` | 机制趋势与局限 |

如果正文只能放 3 张图，建议顺序：

1. Fig. 1: Main result across budgets, with PSNR/SSIM and best-bidirectional gain.
2. Fig. 2: 2D mechanism evidence after quantization/RC.
3. Fig. 3: Threshold robustness under ZT/NCT/RT.

非整数和 SplitRT vs FullRT 可合并进 supplementary 或正文小表。

## 8. Argument Blueprint

### Sub-Argument 1: Fixed-budget bidirectional allocation is empirically superior.

- Evidence: Exp1 中所有整数 `Q` 的最佳双向均显著优于最佳单向。
- Reasoning: 由于每个 `Q` 都是在相同总预算下比较，增益不能简单归因于更多总采样预算。
- Counter-argument: 可能只是某些数据集或某个 seed 的偶然现象。
- Response: 7 个数据集内无负增益；但仍承认当前是单 seed，需要未来多 seed 扩展。

### Sub-Argument 2: The advantage is not a factorization artifact.

- Evidence: 非整数实验中 `R1.5A2`, `R1.5A3`, `R2.5A2`, `R2.5A3` 均优于等预算单向。
- Reasoning: 若优势来自整数因子实现细节，非整数组合不应稳定复现。
- Counter-argument: 非整数插值可能引入额外平滑。
- Response: 论文中应强调这是佐证实验，不单独作为贡献；必要时把非整数结果放 supplementary。

### Sub-Argument 3: The finding is robust to threshold construction.

- Evidence: Exp3A 中 SplitRT≈FullRT；Exp3B 中 ZT/NCT/RT 下双向均显著优于最佳单向。
- Reasoning: 若双向优势由 RT 特定随机阈值构造导致，则 ZT/NCT 下不应保留。
- Counter-argument: NCT 搜索可能不公平。
- Response: 需要在方法中清楚写出 NCT 搜索规则，并说明所有方法共享同一评估流程。

### Sub-Argument 4: A plausible mechanism is reduced two-dimensional spectral leakage.

- Evidence: Exp2 主样本中 `R2A2` 在 RC/RCMC 后三项 leakage 指标最低。
- Reasoning: SAR 有效信息具有二维频域结构，双向上采样提供两个维度的频域冗余。
- Counter-argument: Node-1 residual 没有明显差异；补充样本中机制指标不是全胜。
- Response: 机制部分必须写成“suggests / indicates / is consistent with”，不能写成“proves”。

## 9. Language Control: What Can Be Claimed

### Strong Claims

- 在当前测试范围内，固定预算下最佳双向上采样稳定优于最佳单向上采样。
- 非整数上采样结果表明，该优势不是整数因子分配的偶然产物。
- ZT/NCT/RT 下双向优势均存在，说明 RT 不是创造该规律的必要条件。
- SplitRT 与 FullRT 曲线接近，说明主结论对 RT 内部构造细节不敏感。

### Qualified Claims

- 双向上采样可能通过更充分的二维频域冗余降低谱外泄漏。
- RC 后的频谱指标与最终图像质量优势一致。
- 平衡分配不是必要条件，但接近二维拆分的平台区更优。

### Claims to Avoid

- 已经完整证明 2D quantization noise shaping 的物理机制。
- 单向距离上采样只改善距离向、单向方位上采样只改善方位向。
- 结果已经经过 5 seeds 或 350 个观测验证。
- 本文提出的是新的阈值构造理论。
- 该规律可直接泛化到非 1-bit SAR 或普通图像超分辨。

## 10. Stage 2 Writing Inputs

### Recommended Title

Bidirectional Range-Azimuth Upsampling for 1-Bit SAR Imaging

### Candidate Abstract Skeleton

1-bit SAR imaging suffers from severe information loss caused by sign-only quantization. Existing threshold and oversampling strategies usually improve the quantization process along a single dimension. This paper studies a fixed-budget question: whether an upsampling budget should be concentrated in one dimension or split between range and azimuth. Experiments over seven SAR datasets show that bidirectional range-azimuth allocation consistently outperforms the best unidirectional allocation under the same total budget. The advantage persists for non-integer factors and remains significant under zero, constant, and random threshold settings. Mechanism analysis further suggests that bidirectional upsampling leads to cleaner two-dimensional spectral structure after range compression. These results support bidirectional allocation as a simple and robust design principle for 1-bit SAR upsampling.

### Suggested 4-Page Structure

| Section | Content | Evidence |
|---|---|---|
| I. Introduction | 1-bit SAR 信息损失；现有工作偏单方向阈值/上采样；本文提出固定预算拆分问题 | 问题定义 + 文献定位 |
| II. Method | BRAU 框架；`Q=R x A`；SplitRT；单向/双向对照定义 | 方法图或简洁公式 |
| III-A Main Results | 整数 Q 主结果；最佳双向 vs 最佳单向；统计检验 | Exp1 |
| III-B Mechanism Analysis | 频谱泄漏指标；Node-1 谨慎解释；RC 后 R2A2 更低泄漏 | Exp2 |
| III-C Robustness | 非整数、SplitRT/FullRT、ZT/NCT/RT | Exp1 NonInteger + Exp3 |
| IV. Conclusion | 总结主 claim；承认单 seed 和机制证据局限；未来多 seed/理论分析 | 全部 |

## 11. Integrity Risks Before Drafting

| Risk | Why It Matters | Required Handling |
|---|---|---|
| Sample count mismatch | 设计文档写 350，实际输出为 70 | 正文按 70 paired samples 写 |
| Mechanism overclaim | Node-1 不支持强机制证明 | 使用 suggest / indicate / consistent with |
| RCMC 指标不敏感 | Node-2 与 Node-3 数值几乎一致 | 不写 RCMC 进一步显著改善 |
| 多样本机制非全胜 | `filed` 场景部分 tau 下最佳单向略优 | 机制作为趋势证据，不作为硬定律 |
| 文献定位未核查 | Zhao 2019、Nie 2025 需准确引用 | Stage 2.5 前必须 DOI/Web 检索核查 |
| NCT 搜索公平性 | 审稿人可能质疑调参 | 方法中明确 NCT 搜索协议和共享评估条件 |

## 12. Next Pipeline Step

建议下一步进入 ARS Stage 2 WRITE / plan mode，先产出：

1. Paper Configuration Record。
2. 4 页会议论文 detailed outline。
3. Figure/Table placement plan。
4. Argument Blueprint 的论文版压缩表达。
5. Method section 的符号表和对照定义。

在 Stage 2 初稿完成后，必须进入 Stage 2.5 INTEGRITY，逐项核查：

- 数字是否全部可由 CSV 追溯。
- 图表 caption 是否与数据一致。
- 引用是否真实存在。
- claim 是否超出当前实验能支持的范围。
