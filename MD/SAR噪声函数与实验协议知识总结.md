# SAR 噪声函数与实验协议知识总结

## 1. 文档范围

本文整理本仓库中实际用于 SAR 复回波噪声实验的两套实现：

1. 早期通用函数 `gaussian(signal,SNR_dB,verbose)`。
2. V5 噪声实验使用的 `V5Core.buildSharedNoiseBase(signal,seed)` 与线性缩放协议。

两者生成的都是加在 **1-bit 量化前复回波**上的复高斯白噪声。仓库没有单独实现乘性 speckle 噪声生成器。

## 2. 统一噪声模型

设干净复回波为

\[
s\in\mathbb C^{N_r\times N_a},
\]

总样本数为 `N`，信号平均功率定义为

\[
P_s=\frac{1}{N}\sum_{i=1}^{N}|s_i|^2.
\]

目标输入信噪比为 `SNR_dB` 时，目标复噪声功率为

\[
P_n=P_s10^{-\mathrm{SNR}_{dB}/10}.
\]

复高斯噪声由相互独立的实部与虚部构成：

\[
n_i^{(0)}=\sqrt{\frac{P_n}{2}}
\left(\xi_i^{(R)}+j\xi_i^{(I)}\right),
\]

\[
\xi_i^{(R)},\xi_i^{(I)}\overset{\mathrm{i.i.d.}}{\sim}\mathcal N(0,1).
\]

因而每个实分量的方差为 `Pn/2`，复噪声总功率为 `Pn`。噪声加在量化前：

\[
\widetilde{s}=s+n.
\]

## 3. `gaussian`：独立复高斯噪声函数

### 接口

```matlab
function [Noise, stats] = gaussian(signal, SNR_dB, verbose)
```

| 参数 | 含义 |
|---|---|
| `signal` | 用于估计功率的原始复回波 |
| `SNR_dB` | 目标输入 SNR，单位 dB |
| `verbose` | 是否打印统计信息，缺省为 `true` |
| `Noise` | 与 `signal` 同尺寸的复高斯噪声 |
| `stats` | 目标/实际 SNR、功率、标准差和均值 |

函数只返回噪声，不直接返回 `signal + Noise`。

### 精简实现

```matlab
signal_power = mean(abs(signal(:)) .^ 2);
target_noise_power = signal_power / (10 ^ (SNR_dB / 10));
scale_factor = sqrt(target_noise_power) / sqrt(2);

[rows, cols] = size(signal);
Noise = scale_factor * ...
    (randn(rows, cols) + 1j * randn(rows, cols));
Noise = Noise - mean(Noise, "all");
```

实际有限样本统计为

```matlab
actual_noise_power = mean(abs(Noise(:)) .^ 2);
actual_SNR_dB = 10 * log10(signal_power / actual_noise_power);
```

### 输出统计字段

- `TargetSNRdB`
- `ActualSNRdB`
- `SignalPower`
- `TargetNoisePower`
- `ActualNoisePower`
- `TargetNoiseStd`
- `ActualNoiseStd`
- `NoiseMean`

### 关键性质

1. 噪声实部和虚部独立，且使用相同方差。
2. 生成后减去有限样本复均值，使噪声样本均值接近机器精度零。
3. 减均值后没有再次把噪声精确归一化到目标功率。因此 `ActualSNRdB` 通常很接近、但不严格等于 `TargetSNRdB`。
4. 函数直接使用全局 `randn`，可重复性依赖外部 `rng(seed)` 和此前的随机数消费顺序。
5. 返回矩阵默认由 `randn` 决定为 double；函数没有主动转换为输入 `signal` 的数值类型。

### 调用方式

```matlab
rng(seed);
[noise, stats] = gaussian(signal60_input, SNR_dB, false);
noisy_signal = signal60_input + noise;
```

## 4. V5 共享基础噪声

### 接口

```matlab
function [base_noise, stats] = buildSharedNoiseBase(signal, seed)
```

该函数不直接生成某个目标 SNR 的最终噪声，而是生成一个可跨 SNR、跨分配组复用的基础 realization。

### 精简实现

```matlab
stream = RandStream('mt19937ar', 'Seed', seed);
[num_rows, num_cols] = size(signal);

base_noise = complex( ...
    randn(stream, num_rows, num_cols), ...
    randn(stream, num_rows, num_cols));
base_noise = base_noise - mean(base_noise, "all");

base_noise_power = mean(abs(base_noise(:)) .^ 2);
signal_power = mean(abs(signal(:)) .^ 2);
```

未缩放的 `base_noise` 实部和虚部方差各约为 1，因此复功率约为 2。

### SNR 缩放

V5 使用

```matlab
scales = sqrt(signal_power ./ ...
    (10 .^ (SNR_dB_list / 10))) / sqrt(2);
noise = scales(snr_idx) * base_noise;
```

若基础噪声的有限样本功率恰好为 2，则缩放后的功率正好等于目标 `Pn`。实际 SNR 使用基础噪声的实测功率审计：

\[
\mathrm{SNR}_{\mathrm{actual}}
=10\log_{10}\frac{P_s}{c^2P_{n,\mathrm{base}}},
\]

其中 `c` 是对应 SNR 的 `scale`。

V5 验收要求目标与实际 SNR 的最大偏差小于 `0.1 dB`。

## 5. V5 的共享噪声协议

### 样本与重复

每个 `(sample_id, repeat_idx)` 只生成一个 `base_noise`：

```matlab
[base_noise, noise_stats] = V5Core.buildSharedNoiseBase( ...
    clean_signal, V5Core.noiseSeed(cfg, sample_id, repeat_idx));
```

当前 V5 配置包含 70 个样本、29 个 SNR 点和 50 次重复。

### 跨 SNR 共享

同一个基础噪声只乘以不同的标量，得到所有目标 SNR 的噪声。这样不同 SNR 点对应同一空间 realization 的强弱变化，而不是完全不同的噪声图样。

### 跨分配组共享

R4A1、R1A4 和 R2A2 使用同一个原始网格基础噪声。对每个分配，分别用与干净信号相同的二维频域上采样算子处理噪声：

```matlab
noise_up = V5Core.twoDimUpsample( ...
    base_noise, azimuth_q, range_q);
signal_up = clean_up + scale * noise_up;
```

由于上采样是线性的，这与先在原始网格形成 `clean_signal + scale*base_noise`、再整体上采样等价。三种分配共享同一个底层噪声 realization，适合做配对比较。

### 局部随机流

`buildSharedNoiseBase` 使用局部 `RandStream`：

- 不修改 MATLAB 全局 RNG 状态。
- 不同样本和重复由 `V5Core.noiseSeed` 映射为确定性 seed。
- 并行顺序变化不会改变指定任务的基础噪声。
- checkpoint 恢复后仍可复现同一 realization。

### 数值类型

基础随机矩阵先以 double 生成并完成均值、功率统计。如果原始回波为 single，随后执行：

```matlab
if isa(signal, "single")
    base_noise = single(base_noise);
end
```

这样可降低后续二维上采样和 FFT 的内存占用。`BaseNoisePower` 记录的是转换为 single 之前的实测功率。

## 6. clean-GT 与 same-noise-GT

V5 对同一个 noisy 1-bit 重建同时使用两类参考图。

### clean-GT

由无噪声、未量化的复回波成像得到：

\[
I_{\mathrm{GT,clean}}=\mathcal I(s).
\]

noisy 1-bit 结果与它比较，衡量噪声和量化共同造成的总体退化。

### same-noise-GT

由加入同一噪声 realization、但未执行 1-bit 量化的复回波成像得到：

\[
I_{\mathrm{GT,noisy}}=\mathcal I(s+n).
\]

V5 利用成像快路径的线性部分先分别计算干净回波和基础噪声的复数 ROI：

```matlab
noisy_gt = normalize_image(abs( ...
    clean_complex_roi + scale * noise_complex_roi));
```

noisy 1-bit 结果与 same-noise-GT 比较时，更集中地衡量相同噪声条件下的量化与分配误差。

两种协议回答不同问题，不能混合汇总，也不能把 same-noise-GT 当成无噪声真值。

## 7. 随机种子映射

V5 将噪声 seed 和 RT seed 分开：

- `noiseSeed(cfg,sample_id,repeat_idx)` 决定基础高斯噪声。
- `rtSeed(cfg,snr_idx,group_idx,sample_id,repeat_idx)` 决定 SplitRT 阈值。

这种分离保证：

1. 同一样本和重复的噪声可跨分配共享。
2. 不同分配组可以拥有独立但可复现的随机阈值。
3. 修改并行 worker 数不应改变实验协议。
4. checkpoint 签名可以核验 seed 协议，避免静默复用不兼容结果。

## 8. `gaussian` 与 V5 协议对比

| 项目 | `gaussian` | V5 `buildSharedNoiseBase` |
|---|---|---|
| 随机源 | 全局 `randn` | 局部 `RandStream` |
| 输出 | 指定 SNR 的最终噪声 | 未缩放基础噪声 |
| 跨 SNR 共享 | 否，每次调用重新生成 | 是，同一基础 realization 线性缩放 |
| 跨分配共享 | 由调用者自行保证 | V5 流程显式保证 |
| 零均值 | 有 | 有 |
| 精确功率重归一化 | 无 | 无，但记录基础噪声实测功率并审计实际 SNR |
| 类型处理 | 通常为 double | 输入为 single 时转换为 single |
| 适用位置 | 早期单次演示与测试 | V5 多样本、多重复配对实验 |

## 9. Speckle 与 ENL 的边界

### 仓库没有显式 speckle 注入函数

本文两套噪声实现都是复回波域的加性高斯白噪声：

\[
\widetilde{s}=s+n.
\]

它们不是图像域的乘性 speckle 模型，例如

\[
I_{\mathrm{obs}}=I_{\mathrm{clean}}\cdot L.
\]

SAR speckle 来源于相干散射叠加，不能简单等同于普通加性白噪声。若未来增加 speckle 仿真，需要明确操作对象是复回波、幅度图还是强度图。

### ENL 是评价指标，不是噪声函数

仓库在归一化幅度平方形成的强度图上计算

\[
\mathrm{ENL}=\frac{\mu_I^2}{\operatorname{var}(I)}.
\]

ENL 使用 GT 选择的固定均匀 ROI，描述局部强度波动。它没有生成或注入噪声，也不能单独替代 PSNR、SSIM 和结构检查。

## 10. 实现来源索引

### 噪声函数

| 文件 | 函数 | 状态 |
|---|---|---|
| `gaussian.m` | `gaussian` | 早期通用复高斯噪声函数 |
| `v5_experiments/V5Core.m` | `buildSharedNoiseBase` | 当前 V5 基础噪声实现 |
| `v5_experiments/V5Core.m` | `noiseSeed` | 噪声 seed 映射 |
| `v5_experiments/V5Core.m` | `rtSeed` | 噪声实验中的 RT seed 映射 |

### 旧版调用位置

- `t_rangeup_noisy.m`
- `t_azimuthup_noisy.m`
- `t_baru_noisy.m`

这些脚本直接调用 `gaussian(signal60_input,SNR_dB)`，然后把返回噪声加到原始复回波。

### 当前 V5 调用链

1. `v5_experiments/V5_NoiseEvaluation.m`
   - `evaluateNoiseRepeat`
   - 为每个样本和重复创建共享基础噪声。
   - 计算全部 SNR 缩放系数和 actual SNR。
   - 构造 clean-GT 与 same-noise-GT 指标。
2. `v5_experiments/V5Core.m`
   - `buildSharedNoiseBase`
   - `twoDimUpsample`
   - `fastFocusComplexROI`
   - `buildNoiseFastImageFromUpsampled`
   - `quantizeSplitRTBlocked`

### 相关轻量测试

`v5_experiments/test_v5_core.m` 包含：

- `testGaussianSNRAndZeroMean`
- `testSharedNoiseIsDeterministic`
- `testLocalRandomStreamsAndBlockedQuantization`
- `testSeedMapping`

测试中的其他 `randn` 只用于构造随机测试矩阵，不属于仓库噪声算法。

## 11. 使用检查清单

1. 明确 SNR 是在 1-bit 量化前的复回波域定义。
2. 使用 `mean(abs(signal(:)).^2)` 计算复信号功率。
3. 复高斯实部和虚部各使用目标总功率的一半。
4. 记录目标 SNR 与有限样本实际 SNR。
5. 配对比较时让所有算法共享同一个基础噪声 realization。
6. 多 SNR 曲线应明确是共享基础噪声缩放还是每点独立噪声。
7. 长实验使用局部随机流和稳定 seed 映射，避免并行顺序影响结果。
8. 区分 clean-GT 与 same-noise-GT 的物理含义。
9. 不把加性高斯噪声、相干 speckle 和 ENL 混为同一概念。
10. 若输入为 single，检查类型转换发生在统计之前还是之后。
