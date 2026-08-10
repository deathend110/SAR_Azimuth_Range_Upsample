# SAR 阈值与 1-bit 量化函数知识总结

## 1. 文档范围

本文整理可直接复用的 **1-bit SAR 复回波阈值构造与量化函数**，重点说明数学定义、输入输出、参数含义和调用方法。

这里的输入通常是上采样后的复回波

$$
S\in\mathbb{C}^{N_r^\uparrow\times N_a^\uparrow},
$$

其中行对应距离向（fast time），列对应方位向（slow time）。本文所说的阈值均指加到复回波上的采集阈值。

## 2. 统一的 1-bit 量化约定

本文中的量化器统一遵循

$$
y=\operatorname{sgn}_{+}\!\left(\Re(S+U)\right)
+j\operatorname{sgn}_{+}\!\left(\Im(S+U)\right),
$$

其中

$$
\operatorname{sgn}_{+}(x)=
\begin{cases}
-1,&x<0,\\
+1,&x\ge 0.
\end{cases}
$$

因此输出码字属于

$$
\{1+j,\ 1-j,\ -1+j,\ -1-j\}.
$$

需要特别注意：代码不是直接调用 MATLAB 的 `sign`，而是先初始化为 `+1`，再把严格小于零的位置改为 `-1`。所以输入恰好为零时输出 `+1`，不会产生零码字。

```matlab
re = ones(size(S), "like", real(S));
im = ones(size(S), "like", real(S));
re(real(S) + real(U) < 0) = -1;
im(imag(S) + imag(U) < 0) = -1;
S1 = complex(re, im);
```

函数采用 **加阈值约定** `S + U`。如果其他实现写成 $S-\tau$，则两者的阈值变量满足 $U=-\tau$，复用时必须先统一符号。

## 3. 公共幅度尺度

RT、SFT 和 RSFT 都先根据当前上采样复回波估计尺度

$$
\hat{\sigma}=\sqrt{\frac{2}{\pi}}\operatorname{mean}(|S|).
$$

RT/SplitRT 使用

$$
A_{\mathrm{RT}}=A_s\hat{\sigma},
$$

RSFT 使用信号阈值比 STR 控制幅度：

$$
A_u=\frac{\hat{\sigma}}{10^{\mathrm{STR}_{dB}/20}}.
$$

这里使用 `/20` 是因为 STR 用于幅度比，而不是功率比。$\hat{\sigma}$ 必须由与阈值尺寸一致的上采样回波计算。

## 4. 阈值类型总览

| 类型 | 阈值结构 | 随机自由度 | 结构特点 |
|---|---|---:|---|
| ZT | `U=0` | 0 | 不引入额外阈值 |
| NCT | `U=A exp(j psi)` | 0 | 全矩阵共享一个复常数 |
| 距离向 RT | 每个距离采样一个随机相位 | `Nr_up` | 沿方位方向保持不变 |
| 方位向 RT | 每个方位采样一个随机相位 | `Na_up` | 沿距离方向保持不变 |
| FullRT | 每个二维采样点独立随机相位 | `Nr_up*Na_up` | 二维逐点独立随机 |
| SplitRT | 距离相位与方位相位相加 | `Nr_up+Na_up` | 可分离二维随机相位 |
| SingleSFT | 快时间上的确定性线性相位 | 0 | 单方向线性相位 |
| 一维 RSFT | 距离单频相位，沿方位复制 | 0 | 单方向可调频率 |
| 二维 RSFT | 距离与方位单频相位相加 | 0 | 两方向频率可独立设置 |

## 5. ZT：零阈值

### 定义

$$
U=0,
\qquad
y=\operatorname{sgn}_{+}(\Re S)+j\operatorname{sgn}_{+}(\Im S).
$$

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
- 可作为不施加阈值时的基础量化器。
- 输入输出尺寸完全相同。

## 6. NCT：非减法常数阈值

### 定义

$$
U=Ae^{j\psi}.
$$

整个回波矩阵共享同一个复数阈值。取 `psi=0` 时，`U=A` 为纯实阈值；非零 `psi` 会同时改变实部和虚部判决边界。

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

### 使用方法

`A` 控制阈值幅度，`psi` 控制复平面方向。若希望阈值随输入幅度尺度变化，可使用 `A=As*sigma`；若已有绝对幅度标定，也可以直接传入固定 `A`。该函数把常数阈值构造和量化合并在一起。

## 7. 一维随机 RT

### 距离向 RT

为每个距离采样生成一个相位，并沿所有方位脉冲广播：

$$
U_{n,m}=A_{\mathrm{RT}}e^{j\phi_r(n)},
\qquad \phi_r(n)\sim\mathcal U(0,2\pi).
$$

```matlab
phi = 2 * pi * rand(size(S, 1), 1);
U = A_rt * exp(1i * phi);  % Nr_up × 1，量化时沿列广播
```

### 方位向 RT

为每个方位采样生成一个相位，并沿所有距离单元广播：

$$
U_{n,m}=A_{\mathrm{RT}}e^{j\phi_a(m)},
\qquad \phi_a(m)\sim\mathcal U(0,2\pi).
$$

```matlab
phi = 2 * pi * rand(1, size(S, 2));
U = A_rt * exp(1i * phi);  % 1 × Na_up，量化时沿行广播
```

也可以把阈值生成和量化合并在一个函数中：距离向版本生成列相位向量，方位向版本生成行相位向量。

## 8. FullRT：二维全随机阈值

### 定义

$$
U_{n,m}=A_{\mathrm{RT}}e^{j\phi_{n,m}},
\qquad \phi_{n,m}\overset{\mathrm{i.i.d.}}{\sim}\mathcal U(0,2\pi).
$$

### 精简实现

```matlab
sigma = sqrt(2 / pi) * mean(abs(signal_up(:)));
A_rt = As * sigma;
phi = 2 * pi * rand(size(signal_up));
U = A_rt * exp(1i * phi);
```

FullRT 对每个二维采样点使用独立相位，随机自由度为 `Nr_up*Na_up`。其阈值矩阵与输入回波尺寸完全相同。

## 9. SplitRT：可分离二维随机阈值

### 定义

$$
\phi(n,m)=\phi_r(n)+\phi_a(m),
$$

$$
U_{n,m}=A_{\mathrm{RT}}
\exp\!\left[j\left(\phi_r(n)+\phi_a(m)\right)\right],
$$

其中

$$
\phi_r(n),\phi_a(m)\sim\mathcal U(0,2\pi).
$$

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
- 等价地，阈值相位因子可以写成外积。

$$
e^{j(\phi_r+\phi_a)}=e^{j\phi_r}e^{j\phi_a}.
$$

- 必须先将两个方向的**相位相加**再取复指数，不能把两个复阈值直接相加。

## 10. SingleSFT：固定线性相位阈值

### 函数实现

```matlab
fast_time_rel = ((0:nrn_up - 1).' - floor(nrn_up / 2)) / Fs_up;
phi = 2 * pi * fast_time_rel;
U = A_rt * exp(1i * phi);
```

对应

$$
U_n=A_{\mathrm{RT}}e^{j2\pi t_n}.
$$

由于该接口没有显式频率参数 `f0_Hz`，量纲上相当于固定使用 `1 Hz`。如需通用单频阈值，应使用下一节的一维 RSFT 形式，把频率作为显式输入。

## 11. 一维 RSFT

### 定义

一维 RSFT 只在距离快时间上变化：

$$
U_{n,m}=A_u\exp\!\left[j(2\pi f_0\tau_n+\phi_0)\right].
$$

同一距离阈值列向量复制到全部方位脉冲。

```matlab
fast_time_rel = ((0:Nr_up - 1).' - floor(Nr_up / 2)) / Fs_up;
phase = 2 * pi * f0_Hz * fast_time_rel + initial_phase;
U_column = threshold_amplitude * exp(1i * phase);
U = repmat(U_column, 1, size(signal_up, 2));
```

归一化频率参数可按下式换算：

$$
f_0=\left(f_0/B_r\right)B_r,
\qquad F_s^\uparrow=R F_s.
$$

调用前应保证 `fast_time_rel` 是列向量，最终阈值通过 `repmat` 扩展为与 `signal_up` 完全相同的尺寸。

## 12. 二维 RSFT

### 定义

$$
U_{n,m}=A_u\exp\!\left[j\left(
2\pi f_r\tau_n+2\pi f_a\eta_m+\phi_0
\right)\right].
$$

其中

$$
f_r=(f_r/B_r)B_r,
\qquad
f_a=(f_a/B_a)B_a,
$$

$$
\tau_n=\frac{n-\lfloor N_r^\uparrow/2\rfloor}{R F_s},
\qquad
\eta_m=\frac{m-\lfloor N_a^\uparrow/2\rfloor}{A\,\mathrm{PRF}}.
$$

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

二维 RSFT 同样是先把距离相位和方位相位相加，再取一次复指数。调用者需要提供距离带宽 `B_r`、方位带宽 `B_a`、距离采样率 `F_s` 和方位脉冲重复频率 `PRF`。若不需要整体相位偏移，可令 `initial_phase=0`。

## 13. 通用阈值矩阵量化器

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

### 输入输出

- `S`：待量化复回波，二维数值矩阵。
- `U`：复阈值矩阵，尺寸必须与 `S` 完全一致。
- `S1`：与 `S` 同尺寸的复数 1-bit 码字矩阵。

如果希望使用 `Nr×1` 或 `1×Na` 的方向阈值，应先通过隐式扩展构造完整矩阵，或者使用支持广播且带明确尺寸检查的量化器。

## 14. 最小调用流程

以下示例以 SplitRT 为例，展示完整的工具调用顺序：

```matlab
% 1. 输入必须是二维复回波
assert(~isreal(signal_up), "输入应为复回波。");

% 2. 固定随机种子，保证随机阈值可复现
rng(2026, "twister");

% 3. 构造与输入同尺寸的阈值场
U = buildSplitRTThreshold(signal_up, As);
assert(isequal(size(signal_up), size(U)), ...
    "信号与阈值尺寸不一致。");

% 4. 实部、虚部分别执行二值判决
channel_1bit = quantizeWithThreshold(signal_up, U);
```

若不希望修改 MATLAB 全局随机状态，可将阈值构造函数中的 `rand` 改为接收局部 `RandStream`，并使用 `rand(stream,...)`。

## 15. 使用检查清单

1. 确认输入是复回波，而不是幅度图或强度图。
2. 确认距离为行、方位为列，阈值相位方向没有交换。
3. 确认阈值使用 `S+U` 还是 `S-U` 的符号约定。
4. 确认阈值与上采样回波尺寸一致，或广播方向符合设计。
5. 确认实部和虚部采用完全相同的判负规则。
6. 确认零值映射规则；本文函数将零映射为 `+1`。
7. 比较随机阈值时固定 seed，并记录全局 RNG 或局部流协议。
8. 二维阈值应将两个方向的相位相加后取复指数。
9. 使用线性相位阈值时，检查时间轴、采样率和频率单位是否一致。
