# RSFT 实验

这个文档记录汇报为了双向上采样而加入RSFT论文的情况

# 1. RSFT复现
## 现有一维 RSFT 模型

设上采样后的 SAR 复回波为

$$
s_{\uparrow}(\tau,\eta)\in\mathbb{C},
$$

其中：

- $\tau$ 为距离快时间；
- $\eta$ 为方位慢时间。

现有距离向 RSFT 可写为

$$
u_{\mathrm{RSFT}}(\tau)
=A_u\exp\left[j\left(2\pi f_r\tau+\phi_0\right)\right],
$$

其中：

- $A_u$ 为阈值幅度；
- $f_r$ 为距离阈值频率；
- $\phi_0$ 为初始相位。

阈值幅度按照信号—阈值比 STR 设定：

$$
A_u
=\frac{\hat{\sigma}}{10^{\mathrm{STR}/20}},
$$

其中

$$
\hat{\sigma}
=\sqrt{\frac{2}{\pi}}\operatorname{mean}\left(|s_{\uparrow}|\right).
$$

在二维回波矩阵上，现有 RSFT 实际为

$$
U_{\mathrm{RSFT}}(m,n)
=A_u\exp\left[j\left(2\pi f_r\tau_m+\phi_0\right)\right],
$$

即同一条距离阈值向量沿全部方位脉冲重复。

# 2 RSFT加入双向上采样的结果
由于赵博老师的论文中，RSFT阈值是生成一条距离向的向量，方位向由相位控制。本质上是一维距离单频阈值，其形式为
$$u(\tau)=A\exp(j(2\pi f_0\tau+\phi))$$
阈值仅沿距离快时间方向变化；其所谓 2-D varying strategy 并非引入方位单频项，而是在不同慢时间脉冲之间改变距离单频阈值的初始相位
1D模式就是相位=0，2D模式就是相位在方位向上服从$U(0, 2\pi)$
**看论文文件**
我做了详细的1d 2d模式和两个可调参数A和$f_0$的搜索，用每个Q值每个组合的最优SSIM作为其参数，结果是这样的：
**看论文文件**
可以看出原版的RSFT是只对距离向上采样敏感的。和A的值无关，R的值越高，对应的1bit图效果越好

所以我想针对我们的双向上采样的特点，把RSFT扩展到2维。所以有了一下的2D RSFT：

# 3 2D-RSFT
## 1. 研究动机

当前 RSFT（Range Single-Frequency Threshold）在距离快时间方向生成单频复阈值，并沿方位方向重复。因此，RSFT 的谐波搬移和频谱容纳机制主要作用于距离频谱。

在固定总上采样预算

$$
Q_{\mathrm{up}}=R\times A
$$

下，R4A1 与 R2A2 虽然具有相同的总预算，但对现有 RSFT 而言，真正直接增强阈值频谱搬移能力的是距离倍率 $R$。因此，R4A1 实际上相当于使用比 R2A2 更大的距离频谱扩展空间，容易天然取得更高的成像指标。

为使阈值结构与双向距离—方位上采样相匹配，可以分别在距离方向和方位方向构造单频相位向量，并采用与 SplitRT 相同的“相位广播相加”方式生成二维阈值矩阵。该方案记为 **2D RSFT**。

## 2. 2D RSFT 的数学形式

分别构造距离向和方位向单频相位：

$$
\phi_r(\tau)=2\pi f_r\tau,
$$

$$
\phi_a(\eta)=2\pi f_a\eta,
$$

其中 $f_a$ 为方位慢时间方向的阈值频率。

将两个方向的相位广播相加，得到二维阈值：

$$
U_{\mathrm{2D\text{-}RSFT}}(\tau,\eta)
=A_u\exp\left\{
 j\left[
2\pi f_r\tau
+2\pi f_a\eta
+\phi_0
\right]
\right\}
$$

该式也可写为两个单位模复指数的乘积：

$$
U_{\mathrm{2D\text{-}RSFT}}(\tau,\eta)
=A_u
\exp(j2\pi f_r\tau)
\exp(j2\pi f_a\eta)
\exp(j\phi_0).
$$

离散形式为

$$
U[m,n]
=A_u\exp\left\{
j\left[
2\pi f_r\tau_m
+2\pi f_a\eta_n
+\phi_0
\right]
\right\}
$$

其中：

$$
\tau_m
=\frac{m-m_0}{F_{s,\uparrow}},
\qquad
F_{s,\uparrow}=R F_s,
$$

$$
\eta_n
=\frac{n-n_0}{\mathrm{PRF}_{\uparrow}},
\qquad
\mathrm{PRF}_{\uparrow}=A\,\mathrm{PRF}.
$$

这里 $m_0$ 和 $n_0$ 为距离向、方位向离散网格中心位置。

由于2D RSFT的公式内部有3个可调参数：$A$, $f_a$, $f_r$ ，而且在:
- $f_a=0$, $f_r\neq0$ 下，退化为赵博老师的距离向RSFT
- $f_a\neq0$, $f_r=0$ 下，退化为国离老师的方位向RSFT
- 都不为0时则将这个时间波动阈值扩展到二维空间.
整体思路是类似我构造Split RT的思路.就是加入的是二维相位
代码实现:
```
function [U, sigma_hat, threshold_amplitude] = buildRSFT2DThreshold( ...
		signal_up, S60, range_q, azimuth_q, ...
		STR_dB, fr_over_Br, fa_over_Ba, ...
		azimuth_bandwidth_Hz, initial_phase)

% 生成恒模二维单频阈值。
%
% 相位采用距离相位与方位相位相加，而不是两个复阈值直接相加：
% phi(m,n) = 2*pi*fr*tau_m + 2*pi*fa*eta_n + phi0
%
% 上采样后等效采样率：
% Fs_r_up = R * Fs
% PRF_up = A * PRF

arguments
	signal_up
	S60
	range_q (1, 1) double {mustBePositive}
	azimuth_q (1, 1) double {mustBePositive}
	STR_dB (1, 1) double
	fr_over_Br (1, 1) double {mustBeNonnegative}
	fa_over_Ba (1, 1) double {mustBeNonnegative}
	azimuth_bandwidth_Hz (1, 1) double {mustBePositive}
	initial_phase (1, 1) double = 0
end

[Nr_up, Na_up] = size(signal_up);
Fs_range_up = range_q * S60.Fs;
PRF_up = azimuth_q * S60.prf;

fast_time_rel = ((0:Nr_up - 1).' - floor(Nr_up / 2)) / Fs_range_up;
slow_time_rel = ((0:Na_up - 1) - floor(Na_up / 2)) / PRF_up;

fr_Hz = fr_over_Br * S60.B;
fa_Hz = fa_over_Ba * azimuth_bandwidth_Hz;

sigma_hat = sqrt(2 / pi) * mean(abs(signal_up(:)));
threshold_amplitude = sigma_hat / (10 ^ (STR_dB / 20));

phase_range = 2 * pi * fr_Hz * fast_time_rel;
phase_azimuth = 2 * pi * fa_Hz * slow_time_rel;

U = threshold_amplitude * exp(1i * (phase_range + phase_azimuth + initial_phase));

end
```
# 4 2D RSFT实验
##  4.1 参数定义

2D RSFT 至少包含三个核心参数：

$$
\mathrm{STR_db},
\qquad
\frac{f_r}{B_r},
\qquad
\frac{f_a}{B_a},
$$

其中：

- $B_r$ 为距离 LFM 信号带宽；
- $B_a$ 为有效方位多普勒带宽。

定义

$$
f_r=\alpha_r B_r,
\qquad
f_a=\alpha_a B_a,
$$

其中

$$
\alpha_r=\frac{f_r}{B_r},
\qquad
\alpha_a=\frac{f_a}{B_a}.
$$

必须满足离散采样约束：

$$
|f_r|<\frac{R F_s}{2},
$$

$$
|f_a|<\frac{A\,\mathrm{PRF}}{2}.
$$
我对三个可调参数做了完整的参数搜索, 上采样的Q值搜索范围`Q=1-10`
每个Q内有做了完整的q排列测试,比如Q=8,则有R1A8, R2A4, R4A2, R8A1.
$STR_dB = -10:4:10$
$\frac{f_r}{B_r} = 0:0.4:2.4$
$\frac{f_r}{B_r} = 0:0.4:2.4$

% 每轮围绕当前最优点细化；最多两轮，避免一次高密度三维全网格。
$STR_offsets = -2:1:2;$
$fine\_\frac{f_r}{B_r}\_offsets = -0.2:0.1:0.2;$
$fine\_\frac{f_a}{B_a}\_offsets = -0.2:0.1:0.2;$
这里的offsets的意思就是在第一轮粗搜索找到的最优参数为核心进行左右搜索

## 4.2 实验结果
最后的结果如下:

| GroupName | Best_STRdB | Best_FrOverBr | Best_FaOverBa |   PSNR_mean |    SSIM_mean |
| --------- | ---------: | ------------: | ------------: | ----------: | -----------: |
| R1A1      |          4 |           2.0 |           0.0 |     23.9541 |     0.688245 |
| R1A2      |          0 |           1.9 |           1.3 |     26.2935 |     0.797727 |
| R2A1      |          0 |           1.4 |           0.7 |     26.1939 |     0.792795 |
| R1A3      |         -2 |           2.0 |           1.4 |     27.9327 |     0.851550 |
| R3A1      |         -1 |           2.1 |           2.0 |     27.6118 |     0.843565 |
| **R1A4**  |     **-3** |       **0.0** |       **1.8** | **29.4150** | **0.890179** |
| **R2A2**  |     **-2** |       **0.6** |       **1.3** | **28.6958** | **0.874137** |
| **R4A1**  |     **-3** |       **2.0** |       **1.2** | **29.4294** | **0.889216** |
| **R1A5**  |     **-4** |       **1.2** |       **1.5** | **30.2844** | **0.905558** |
| **R5A1**  |     **-4** |       **1.5** |       **0.8** | **30.2706** | **0.906880** |
| **R1A6**  |     **-4** |       **1.2** |       **1.6** | **30.9650** | **0.919475** |
| **R2A3**  |     **-3** |       **2.0** |       **1.5** | **30.3742** | **0.910919** |
| **R3A2**  |     **-4** |       **0.8** |       **1.3** | **30.5266** | **0.910629** |
| **R6A1**  |     **-4** |       **1.8** |       **0.7** | **31.0641** | **0.921077** |
| **R1A7**  |     **-5** |       **0.2** |       **1.4** | **31.9399** | **0.932436** |
| **R7A1**  |     **-5** |       **1.6** |       **0.5** | **31.6894** | **0.929954** |
| **R1A8**  |     **-5** |       **1.8** |       **1.5** | **32.4656** | **0.940843** |
| **R2A4**  |     **-4** |       **2.0** |       **1.8** | **31.8710** | **0.934356** |
| **R4A2**  |     **-4** |       **2.0** |       **0.6** | **31.8274** | **0.933907** |
| **R8A1**  |     **-5** |       **1.8** |       **2.3** | **32.4735** | **0.940437** |
| **R1A9**  |     **-5** |       **1.6** |       **1.5** | **32.9947** | **0.947012** |
| **R3A3**  |     **-4** |       **0.8** |       **1.6** | **32.3228** | **0.940753** |
| **R9A1**  |     **-5** |       **1.6** |       **2.0** | **32.9179** | **0.946294** |
| **R1A10** |     **-5** |       **0.6** |       **1.6** | **33.3859** | **0.951786** |
| **R2A5**  |     **-4** |       **0.2** |       **1.4** | **32.5821** | **0.944086** |
| **R5A2**  |     **-4** |       **2.0** |       **2.0** | **32.3956** | **0.942488** |
| **R10A1** |     **-6** |       **1.6** |       **0.5** | **33.4636** | **0.951350** |

从表中可以直观看出：

1. 双向组的最优参数均满足：
$$f_r\neq0,\quad f_a\neq0$$
因此 2D RSFT 并没有退化为 Zhao 式纯距离 RSFT 或 Nie 式纯方位单频阈值。

2. 但是在相同预算：
$$Q=RA$$
下，单向组仍获得更高 PSNR/SSIM。

因此该结果支持如下现象：

> **二维阈值结构本身能够提升单比特 SAR 成像质量，但二维阈值频率结构并不必然导致二维上采样分配最优；在 2D RSFT 下，固定预算仍倾向集中于单一采样维度。**

我们加入 RSFT，是希望证明双向上采样在更强的确定性阈值下仍然成立。后续将 RSFT 扩展为同时含有距离频率和方位频率的 2D RSFT，并对每个 R×AR\times AR×A 配置独立进行了三参数搜索。结果表明，2D RSFT 的绝对性能确实高于原 RT，而且最优参数通常不会退化为纯距离或纯方位单频；但在固定预算内部，它仍然稳定偏好单向上采样配置。这说明二维变量依赖本身不足以支持 BARU，阈值频谱结构与采样分配之间存在更复杂的耦合。如果把结果保留在当前论文中，就必须把研究问题扩展为阈值与采样的联合设计，会削弱 BARU 主线。因此我倾向于删除 RSFT 实验，将论文限定在统一受控的 ZT、NCT 和 RT 设置下。