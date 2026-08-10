# SAR 复高斯噪声函数使用方法

## 1. 文档范围

本文提炼一个可复用的 SAR 复回波加性高斯白噪声函数，说明其功率定义、接口、调用方式和使用约束。

## 2. 统一噪声模型

设干净复回波为

$$
s\in\mathbb C^{N_r\times N_a},
$$

矩阵元素总数记为 `N`，信号平均功率定义为

$$
P_s=\frac{1}{N}\sum_{i=1}^{N}|s_i|^2.
$$

目标输入信噪比为 `SNR_dB` 时，目标复噪声功率为

$$
P_n=P_s10^{-\mathrm{SNR}_{dB}/10}.
$$

复高斯噪声由相互独立的实部与虚部构成：

$$
n_i^{(0)}=\sqrt{\frac{P_n}{2}}
\left(\xi_i^{(R)}+j\xi_i^{(I)}\right),
$$

$$
\xi_i^{(R)},\xi_i^{(I)}\overset{\mathrm{i.i.d.}}{\sim}\mathcal N(0,1).
$$

因而每个实分量的方差为 `Pn/2`，复噪声总功率为 `Pn`。噪声加在量化前：

$$
\widetilde{s}=s+n.
$$

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

### 基本调用

```matlab
rng(seed);
[noise, stats] = gaussian(signal, SNR_dB, false);
noisy_signal = signal + noise;
```

函数只生成噪声。若只需要带噪回波而不关心统计字段，也可以写成：

```matlab
noise = gaussian(signal, SNR_dB, false);
noisy_signal = signal + noise;
```

### 可重复调用

该函数内部使用全局 `randn`。需要复现结果时，应在调用前固定随机种子：

```matlab
seed = 2026;
rng(seed, "twister");
[noise, stats] = gaussian(signal, 5, false);
```

再次设置同一个 seed，并以相同顺序调用函数，可以得到相同噪声。若程序中还有其他随机操作，则应为每个任务设计独立 seed，或将函数改造成接收局部 `RandStream`。

### 结果核验

```matlab
assert(isequal(size(noise), size(signal)), ...
    "噪声与信号尺寸不一致。");
assert(abs(stats.NoiseMean) < 1e-6, ...
    "噪声均值未接近零。");

fprintf("目标 SNR: %.3f dB\n", stats.TargetSNRdB);
fprintf("实际 SNR: %.3f dB\n", stats.ActualSNRdB);
```

有限样本下目标 SNR 与实际 SNR 存在小偏差是正常的。如需严格匹配目标功率，可在减均值后增加一次功率归一化：

```matlab
Noise = Noise * sqrt(target_noise_power / ...
    mean(abs(Noise(:)) .^ 2));
```

## 4. 使用检查清单

1. 明确 SNR 是在复回波域定义，而不是在幅度图或强度图上定义。
2. 使用 `mean(abs(signal(:)).^2)` 计算复信号功率。
3. 复高斯实部和虚部各使用目标总功率的一半。
4. 记录目标 SNR 与有限样本实际 SNR。
5. 需要复现时，在调用前固定 seed，并避免无意改变随机数调用顺序。
6. 注意 `gaussian` 默认返回 double；若输入为 single，可在确认精度需求后显式转换。
7. 当前函数生成的是加性复高斯白噪声，不是乘性 speckle 噪声。
