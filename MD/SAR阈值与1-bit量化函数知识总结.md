# SAR 阈值与 1-bit 量化函数知识总结

## 1. 文档范围

本文整理本仓库中实际用于 **1-bit SAR 采集仿真**的阈值构造与量化实现。正文按算法去重，附录再列出重复实现所在文件。

这里的输入通常是上采样后的复回波

\[
S\in\mathbb{C}^{N_r^\uparrow\times N_a^\uparrow},
\]

其中行对应距离向（fast time），列对应方位向（slow time）。本文不把机制分析中的频谱支撑掩膜阈值当作 1-bit 采集阈值。

## 2. 统一的 1-bit 量化约定

仓库中的主要量化器均遵循

\[
y=\operatorname{sgn}_{+}\!\left(\Re(S+U)\right)
+j\operatorname{sgn}_{+}\!\left(\Im(S+U)\right),
\]

其中

\[
\operatorname{sgn}_{+}(x)=
\begin{cases}
-1,&x<0,\\
+1,&x\ge 0.
\end{cases}
\]

因此输出码字属于

\[
\{1+j,\ 1-j,\ -1+j,\ -1-j\}.
\]

需要特别注意：代码不是直接调用 MATLAB 的 `sign`，而是先初始化为 `+1`，再把严格小于零的位置改为 `-1`。所以输入恰好为零时输出 `+1`，不会产生零码字。

```matlab
re = ones(size(S), "like", real(S));
im = ones(size(S), "like", real(S));
re(real(S) + real(U) < 0) = -1;
im(imag(S) + imag(U) < 0) = -1;
S1 = complex(re, im);
```

仓库采用的是 **加阈值约定** `S + U`。如果其他论文写成 `S - \tau`，则其阈值变量与本仓库满足 `U=-\tau`，比较公式时必须先统一符号。

## 3. 公共幅度尺度

RT、SFT 和 RSFT 都先根据当前上采样复回波估计尺度

\[
\hat{\sigma}=\sqrt{\frac{2}{\pi}}\operatorname{mean}(|S|).
\]

RT/SplitRT 使用

\[
A_{\mathrm{RT}}=A_s\hat{\sigma},
\]

RSFT 使用信号阈值比 STR 控制幅度：

\[
A_u=\frac{\hat{\sigma}}{10^{\mathrm{STR}_{dB}/20}}.
\]

这里使用 `/20` 是因为 STR 用于幅度比，而不是功率比。`\hat{\sigma}` 必须由与阈值尺寸一致的上采样回波计算。

## 4. 阈值类型总览

| 类型 | 阈值结构 | 随机自由度 | 主要用途 |
|---|---|---:|---|
| ZT | `U=0` | 0 | 无阈值基线 |
| NCT | `U=A exp(j psi)` | 0 | 常数阈值对照 |
| 距离向 RT | 每个距离采样一个随机相位 | `Nr_up` | 距离上采样早期实验 |
| 方位向 RT | 每个方位采样一个随机相位 | `Na_up` | 方位上采样早期实验 |
| FullRT | 每个二维采样点独立随机相位 | `Nr_up*Na_up` | FullRT 与 SplitRT 对照 |
| SplitRT | 距离相位与方位相位相加 | `Nr_up+Na_up` | V5 当前论文主阈值 |
| SingleSFT | 快时间上的确定性线性相位 | 0 | 未调频率参数的探索脚本 |
| 一维 RSFT | 距离单频相位，沿方位复制 | 0 | V4/Exp5 的 range-only RSFT |
| 二维 RSFT | 距离与方位单频相位相加 | 0 | V4 二维 RSFT 补充实验 |

## 5. ZT：零阈值

### 定义

\[
U=0,
\qquad
y=\operatorname{sgn}_{+}(\Re S)+j\operatorname{sgn}_{+}(\Im S).
\]

### 精简实现

```matlab
function S1 = quantize_1bit_zero(S)
    re = ones(size(S), "like", real(S));
    im = ones(size(S), "like", real(S));
    re(real(S) < 0) = -1;
    im(imag(S) < 0) = -1;
    S1 = complex(re, im);
end
```

### 说明

- ZT 没有单独的阈值构造函数，阈值 `U=0` 隐含在量化器中。
- 用于 `ZT/NCT/RT` 对比实验和无阈值基线。
- 输入输出尺寸完全相同。

## 6. NCT：非减法常数阈值

### 定义

\[
U=Ae^{j\psi}.
\]

整个回波矩阵共享同一个复数阈值。仓库实验通常取 `psi=0`，此时 `U=A` 为实数阈值。

### 精简实现

```matlab
function S1 = quantize_1bit_nct(S, A, psi)
    u = A * exp(1i * psi);
    re = ones(size(S), "like", real(S));
    im = ones(size(S), "like", real(S));
    re(real(S) + real(u) < 0) = -1;
    im(imag(S) + imag(u) < 0) = -1;
    S1 = complex(re, im);
end
```

### 参数选择

仓库中有两种 NCT 幅度策略：

1. 从上采样回波幅度 `abs(S(:))` 的若干分位数中搜索 `A`。
2. 在阈值敏感性实验中使用 `A=As*sigma`，其中 `sigma` 为公共尺度估计。

NCT 的阈值构造与量化写在同一函数内，没有独立 `buildNCTThreshold`。

## 7. 一维随机 RT

### 距离向 RT

为每个距离采样生成一个相位，并沿所有方位脉冲广播：

\[
U_{n,m}=A_{\mathrm{RT}}e^{j\phi_r(n)},
\qquad \phi_r(n)\sim\mathcal U(0,2\pi).
\]

```matlab
phi = 2 * pi * rand(size(S, 1), 1);
U = A_rt * exp(1i * phi);  % Nr_up × 1，量化时沿列广播
```

### 方位向 RT

为每个方位采样生成一个相位，并沿所有距离单元广播：

\[
U_{n,m}=A_{\mathrm{RT}}e^{j\phi_a(m)},
\qquad \phi_a(m)\sim\mathcal U(0,2\pi).
\]

```matlab
phi = 2 * pi * rand(1, size(S, 2));
U = A_rt * exp(1i * phi);  % 1 × Na_up，量化时沿行广播
```

早期 `quantize_1bit_rt_random_phase` 把阈值生成和量化合并在一个函数中：距离上采样版本生成列向相位，方位上采样版本生成行向相位。

## 8. FullRT：二维全随机阈值

### 定义

\[
U_{n,m}=A_{\mathrm{RT}}e^{j\phi_{n,m}},
\qquad \phi_{n,m}\overset{\mathrm{i.i.d.}}{\sim}\mathcal U(0,2\pi).
\]

### 精简实现

```matlab
sigma = sqrt(2 / pi) * mean(abs(signal_up(:)));
A_rt = As * sigma;
phi = 2 * pi * rand(size(signal_up));
U = A_rt * exp(1i * phi);
```

FullRT 对每个二维采样点使用独立相位，随机自由度为 `Nr_up*Na_up`，主要用于和 SplitRT 比较。它不是当前 V5 论文的主阈值。

## 9. SplitRT：可分离二维随机阈值

### 定义

\[
\phi(n,m)=\phi_r(n)+\phi_a(m),
\]

\[
U_{n,m}=A_{\mathrm{RT}}
\exp\!\left[j\left(\phi_r(n)+\phi_a(m)\right)\right],
\]

其中

\[
\phi_r(n),\phi_a(m)\sim\mathcal U(0,2\pi).
\]

### 精简实现

```matlab
function U = buildSplitRTThreshold(signal_up, As)
    [Nr_up, Na_up] = size(signal_up);
    phi_r = 2 * pi * rand(Nr_up, 1);
    phi_a = 2 * pi * rand(1, Na_up);
    sigma = sqrt(2 / pi) * mean(abs(signal_up(:)));
    U = As * sigma * exp(1i * (phi_r + phi_a));
end
```

### 结构性质

- 相位自由度从 FullRT 的 `Nr_up*Na_up` 降为 `Nr_up+Na_up`。
- `phi_r + phi_a` 依靠 MATLAB 隐式扩展形成完整二维相位场。
- 等价地，阈值相位因子可以写成外积：

  \[
  e^{j(\phi_r+\phi_a)}=e^{j\phi_r}e^{j\phi_a}.
  \]

- 必须先将两个方向的**相位相加**再取复指数，不能把两个复阈值直接相加。
- SplitRT 是 V5 主实验、机制实验、阈值敏感性实验和噪声实验使用的阈值。

## 10. V5 分块 SplitRT 量化

V5 噪声实验不创建完整的阈值矩阵，而是保存距离、方位两个单位模相位向量，然后按列分块构造阈值。

```matlab
phase_range = exp(1i * 2 * pi * rand(stream, num_rows, 1));
phase_azimuth = exp(1i * 2 * pi * rand(stream, 1, num_cols));
amplitude = As * sqrt(2 / pi) * mean(abs(S(:)));

for first_col = 1:block_cols:num_cols
    columns = first_col:min(first_col + block_cols - 1, num_cols);
    threshold = amplitude * ...
        (phase_range * phase_azimuth(columns));
    % 对当前分块执行实虚部分离的 1-bit 量化
end
```

它与完整 SplitRT 数学等价，因为

\[
e^{j\phi_r}e^{j\phi_a}=e^{j(\phi_r+\phi_a)}.
\]

主要差异是工程实现：

- 使用局部 `RandStream`，不污染 MATLAB 全局 RNG 状态。
- 阈值分块生成，避免完整相位场和阈值矩阵常驻内存。
- 相同 seed 和相同随机数消费顺序下，可与完整 SplitRT 路径对齐。
- `block_cols` 只影响内存与速度，不应改变量化结果。

## 11. SingleSFT：实验性单频阈值

### 当前实现

```matlab
fast_time_rel = ((0:nrn_up - 1).' - floor(nrn_up / 2)) / Fs_up;
phi = 2 * pi * fast_time_rel;
U = A_rt * exp(1i * phi);
```

对应

\[
U_n=A_{\mathrm{RT}}e^{j2\pi t_n}.
\]

由于公式中没有显式频率参数 `f0_Hz`，量纲上相当于固定使用 `1 Hz`。该函数是把 RT 随机相位替换为单调快时间相位的探索性实现，不是完成参数调优的标准 SFT，也没有进入当前 V5 主实验。

## 12. 一维 RSFT

### 定义

一维 RSFT 只在距离快时间上变化：

\[
U_{n,m}=A_u\exp\!\left[j(2\pi f_0\tau_n+\phi_0)\right].
\]

同一距离阈值列向量复制到全部方位脉冲。

```matlab
fast_time_rel = ((0:Nr_up - 1).' - floor(Nr_up / 2)) / Fs_up;
phase = 2 * pi * f0_Hz * fast_time_rel + initial_phase;
U_column = threshold_amplitude * exp(1i * phase);
U = repmat(U_column, 1, size(signal_up, 2));
```

V4Core 中参数换算为

\[
f_0=\left(f_0/B_r\right)B_r,
\qquad F_s^\uparrow=R F_s.
\]

一维 RSFT 主要用于 V4 的统一校准与 RSFT 主实验，以及早期 `Exp5_RSFT_ParameterMap.m`。

## 13. 二维 RSFT

### 定义

\[
U_{n,m}=A_u\exp\!\left[j\left(
2\pi f_r\tau_n+2\pi f_a\eta_m+\phi_0
\right)\right].
\]

其中

\[
f_r=(f_r/B_r)B_r,
\qquad
f_a=(f_a/B_a)B_a,
\]

\[
\tau_n=\frac{n-\lfloor N_r^\uparrow/2\rfloor}{R F_s},
\qquad
\eta_m=\frac{m-\lfloor N_a^\uparrow/2\rfloor}{A\,\mathrm{PRF}}.
\]

### 精简实现

```matlab
fast_time_rel = ((0:Nr_up - 1).' - floor(Nr_up / 2)) ...
    / (range_q * S60.Fs);
slow_time_rel = ((0:Na_up - 1) - floor(Na_up / 2)) ...
    / (azimuth_q * S60.prf);

phase_range = 2 * pi * fr_Hz * fast_time_rel;
phase_azimuth = 2 * pi * fa_Hz * slow_time_rel;
U = threshold_amplitude * exp( ...
    1i * (phase_range + phase_azimuth + initial_phase));
```

二维 RSFT 同样是先把距离相位和方位相位相加，再取一次复指数。方位带宽按 `Ba`、`Bd`、`2*v/Da` 的优先级解析。部分辅助实验固定 `initial_phase=0`，完整搜索函数则保留该参数。

## 14. 通用阈值矩阵量化器

V4/V5 当前公共实现会先断言信号与阈值尺寸完全一致：

```matlab
function S1 = quantizeWithThreshold(S, U)
    assert(isequal(size(S), size(U)), "信号与阈值尺寸不一致。");
    re = ones(size(S), "like", real(S));
    im = ones(size(S), "like", real(S));
    re(real(S) + real(U) < 0) = -1;
    im(imag(S) + imag(U) < 0) = -1;
    S1 = complex(re, im);
end
```

早期 `quantize_1bit_with_U` 允许 `Nr×1` 或 `1×Na` 阈值通过隐式扩展参与运算；V4/V5 公共实现要求 `U` 已经是完整二维矩阵。这是接口约束差异，不是量化数学差异。

## 15. 随机数与可重复性

### 早期实现

- 阈值函数直接调用 `rand`，使用 MATLAB 全局 RNG。
- 可重复性依赖调用前执行的 `rng(seed)` 以及此前消耗过的随机数数量。
- 调整循环顺序或插入其他随机操作可能改变阈值 realization。

### V5 噪声快路径

- 每个量化任务使用 `RandStream('mt19937ar','Seed',seed)`。
- seed 由 `V5Core.rtSeed` 根据 SNR、分配组、样本和重复编号确定。
- 局部随机流将不同任务解耦，适合并行执行和 checkpoint 恢复。

## 16. 非 1-bit 采集阈值

`Exp2_Mechanism.m`、`Exp2_Mechanism_Supp.m` 和 V4/V5 机制代码中还有 `threshold_ratio` 或 `tau`，用于从参考频谱构造支撑掩膜：

\[
M(k_r,k_a)=\mathbf{1}\{|X_{\mathrm{ref}}(k_r,k_a)|
\ge \tau\max|X_{\mathrm{ref}}|\}.
\]

它服务于 off-support、range leakage 和 azimuth leakage 指标，不会加到复回波上，也不参与 1-bit 量化。因此它与 ZT、NCT、RT、SFT、RSFT 属于不同概念。

## 17. 实现来源索引

### 当前 V5 实现

| 文件 | 函数 | 作用 |
|---|---|---|
| `v5_experiments/V5Core.m` | `buildSplitRTThreshold` | 完整二维 SplitRT 阈值 |
| `v5_experiments/V5Core.m` | `quantizeWithThreshold` | 带尺寸断言的通用量化器 |
| `v5_experiments/V5Core.m` | `quantizeSplitRTBlocked` | 局部随机流、分块 SplitRT 量化 |

### V4/RSFT 研究实现

| 文件 | 函数 | 作用 |
|---|---|---|
| `v4_experiments/V4Core.m` | `buildSplitRTThreshold` | V4 SplitRT |
| `v4_experiments/V4Core.m` | `buildRSFTThreshold` | 一维距离 RSFT |
| `v4_experiments/V4Core.m` | `quantizeWithThreshold` | V4 通用量化器 |
| `v4_experiments/V4_RSFT2DAllocationSearch.m` | `buildRSFT2DThreshold` | 整数倍率二维 RSFT 搜索 |
| `v4_experiments/V4_RSFT2DFractionalPAllocationSearch.m` | `buildRSFT2DThreshold` | 小数倍率二维 RSFT 搜索 |
| `v4_experiments/V4_RSFT2DThresholdTransfer.m` | `buildRSFT2DThreshold` | 阈值迁移实验 |
| `v4_experiments/V4_RSFT2D_Q6DirectionalConstraintSearch.m` | `buildRSFT2DThreshold` | Q6 方向约束实验 |
| `v4_experiments/V4_RSFT2D_R1A1ZeroFrequencyCompare.m` | `buildRSFT2DThreshold` | 零频率对照实验 |
| `Exp5_RSFT_ParameterMap.m` | `build_rsft_threshold` | 早期一维 RSFT 参数图 |
| `Exp5_RSFT_ParameterMap.m` | `quantize_1bit_with_U` | RSFT 通用量化 |

### 主实验与机制实验中的 SplitRT 重复实现

以下函数数学结构相同，仅命名、输入是否已上采样以及局部注释略有区别：

- `Azimuth_Range_MixUpsample.m`
  - `Build_2D_SplitRT`
  - `Build_2D_RT`
  - `Range_Build_RT`
  - `Azimuth_Build_RT`
  - `quantize_1bit_with_U`
- `Compare_R2A2_FullRT_vs_SplitRT.m`
  - `Build_2D_RT`
  - `Build_2D_SplitRT`
  - `quantize_1bit_with_U`
- `Exp3A_SplitVsFull.m`
  - `Build_2D_RT`
  - `Build_2D_SplitRT`
  - `quantize_1bit_with_U`
- `Compare_RxAx_Groups_By_Q.m`
  - `Build_2D_SplitRT`
  - `quantize_1bit_with_U`
- `Exp1_MainResult.m`
  - `Build_2D_SplitRT`
  - `quantize_1bit_with_U`
- `Exp1_NonInteger.m`
  - `Build_2D_SplitRT`
  - `quantize_1bit_with_U`
- `Exp2_Mechanism.m`
  - `build_splitrt_threshold`
  - `quantize_1bit_with_U`
- `Exp2_Mechanism_Supp.m`
  - `build_splitrt_threshold`
  - `quantize_1bit_with_U`
- `Exp3B_ZT_NCT_RT.m`
  - `Build_2D_SplitRT`
  - `quantize_1bit_with_U`
  - `quantize_1bit_zero`
  - `quantize_1bit_nct`
- `Exp4A_ThresholdAs_SelectedQ.m`
  - `Build_2D_SplitRT_from_up`
  - `quantize_1bit_with_U`
  - `quantize_1bit_nct`
- `Exp4B_ThresholdAs_ByQ.m`
  - `Build_2D_SplitRT_from_up`
  - `quantize_1bit_with_U`
  - `quantize_1bit_nct`

### 早期单方向与噪声脚本

| 文件 | 函数 |
|---|---|
| `UpSample_range_ZT_NCT_RT.m` | `quantize_1bit_zero`、`quantize_1bit_nct`、`quantize_1bit_rt_random_phase` |
| `UpSample_azimuth_ZT_NCT_RT.m` | `quantize_1bit_zero`、`quantize_1bit_nct`、`quantize_1bit_rt_random_phase` |
| `t_RT_SFT.m` | `Range_Build_RT`、`Build_2D_SingleSFT`、`quantize_1bit_with_U` |
| `t_rangeup_noisy.m` | `Azimuth_Build_RT`、`Range_Build_RT`、`Build_2D_RT`、`Build_2D_SplitRT`、`quantize_1bit_with_U` |
| `t_baru_noisy.m` | `Azimuth_Build_RT`、`Range_Build_RT`、`Build_2D_SplitRT`、`quantize_1bit_with_U` |
| `t_azimuthup_noisy.m` | `Azimuth_Build_RT`、`quantize_1bit_with_U` |

## 18. 使用检查清单

1. 确认输入是复回波，而不是幅度图或强度图。
2. 确认距离为行、方位为列，阈值相位方向没有交换。
3. 确认阈值使用 `S+U` 还是 `S-U` 的符号约定。
4. 确认阈值与上采样回波尺寸一致，或广播方向符合设计。
5. 确认实部和虚部采用完全相同的判负规则。
6. 确认零值映射规则；本仓库将零映射为 `+1`。
7. 比较随机阈值时固定 seed，并记录全局 RNG 或局部流协议。
8. 二维阈值应将两个方向的相位相加后取复指数。
9. 比较不同上采样分配时，共享 GT、ROI、成像流程和归一化协议。
