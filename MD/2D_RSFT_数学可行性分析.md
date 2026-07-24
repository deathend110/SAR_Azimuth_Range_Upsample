# 2D RSFT 阈值的数学可行性分析

## 1. 研究动机

当前 RSFT（Range Single-Frequency Threshold）在距离快时间方向生成单频复阈值，并沿方位方向重复。因此，RSFT 的谐波搬移和频谱容纳机制主要作用于距离频谱。

在固定总上采样预算

\[
Q_{\mathrm{up}}=R\times A
\]

下，R4A1 与 R2A2 虽然具有相同的总预算，但对现有 RSFT 而言，真正直接增强阈值频谱搬移能力的是距离倍率 \(R\)。因此，R4A1 实际上相当于使用比 R2A2 更大的距离频谱扩展空间，容易天然取得更高的成像指标。

为使阈值结构与双向距离—方位上采样相匹配，可以分别在距离方向和方位方向构造单频相位向量，并采用与 SplitRT 相同的“相位广播相加”方式生成二维阈值矩阵。该方案记为 **2D RSFT**。

---

## 2. 现有一维 RSFT 模型

设上采样后的 SAR 复回波为

\[
s_{\uparrow}(\tau,\eta)\in\mathbb{C},
\]

其中：

- \(\tau\) 为距离快时间；
- \(\eta\) 为方位慢时间。

现有距离向 RSFT 可写为

\[
u_{\mathrm{RSFT}}(\tau)
=A_u\exp\left[j\left(2\pi f_r\tau+\phi_0\right)\right],
\]

其中：

- \(A_u\) 为阈值幅度；
- \(f_r\) 为距离阈值频率；
- \(\phi_0\) 为初始相位。

阈值幅度按照信号—阈值比 STR 设定：

\[
A_u
=\frac{\hat{\sigma}}{10^{\mathrm{STR}/20}},
\]

其中

\[
\hat{\sigma}
=\sqrt{\frac{2}{\pi}}\operatorname{mean}\left(|s_{\uparrow}|\right).
\]

在二维回波矩阵上，现有 RSFT 实际为

\[
U_{\mathrm{RSFT}}(m,n)
=A_u\exp\left[j\left(2\pi f_r\tau_m+\phi_0\right)\right],
\]

即同一条距离阈值向量沿全部方位脉冲重复。

---

## 3. 2D RSFT 的推荐数学形式

分别构造距离向和方位向单频相位：

\[
\phi_r(\tau)=2\pi f_r\tau,
\]

\[
\phi_a(\eta)=2\pi f_a\eta,
\]

其中 \(f_a\) 为方位慢时间方向的阈值频率。

将两个方向的相位广播相加，得到二维阈值：

\[
\boxed{
U_{\mathrm{2D\text{-}RSFT}}(\tau,\eta)
=A_u\exp\left\{
 j\left[
2\pi f_r\tau
+2\pi f_a\eta
+\phi_0
\right]
\right\}
}
\]

该式也可写为两个单位模复指数的乘积：

\[
U_{\mathrm{2D\text{-}RSFT}}(\tau,\eta)
=A_u
\exp(j2\pi f_r\tau)
\exp(j2\pi f_a\eta)
\exp(j\phi_0).
\]

离散形式为

\[
\boxed{
U[m,n]
=A_u\exp\left\{
j\left[
2\pi f_r\tau_m
+2\pi f_a\eta_n
+\phi_0
\right]
\right\}
}
\]

其中：

\[
\tau_m
=\frac{m-m_0}{F_{s,\uparrow}},
\qquad
F_{s,\uparrow}=R F_s,
\]

\[
\eta_n
=\frac{n-n_0}{\mathrm{PRF}_{\uparrow}},
\qquad
\mathrm{PRF}_{\uparrow}=A\,\mathrm{PRF}.
\]

这里 \(m_0\) 和 \(n_0\) 为距离向、方位向离散网格中心位置。

---

## 4. 与 SplitRT 的对应关系

SplitRT 的二维阈值结构为

\[
U_{\mathrm{SplitRT}}(m,n)
=A_s\hat{\sigma}
\exp\left[j\left(\phi_r(m)+\phi_a(n)\right)\right],
\]

其中 \(\phi_r\) 和 \(\phi_a\) 是分别沿距离和方位生成的随机相位向量。

2D RSFT 与 SplitRT 的形式完全一致，区别仅在于相位函数：

\[
\phi_r(m)=2\pi f_r\tau_m,
\qquad
\phi_a(n)=2\pi f_a\eta_n.
\]

因此，2D RSFT 可以看作将 SplitRT 的随机相位替换为距离—方位两个方向上的确定性线性相位。

---

## 5. 数学可行性推理

### 5.1 阈值模长保持恒定

由定义可得

\[
\left|U_{\mathrm{2D\text{-}RSFT}}(\tau,\eta)\right|
=A_u.
\]

因此，整个二维阈值矩阵的模长恒定，局部 STR 不随位置变化：

\[
\mathrm{STR}(\tau,\eta)
=20\log_{10}\frac{\hat{\sigma}}{A_u}
=\mathrm{STR}.
\]

这意味着现有 RSFT 的幅度标定公式仍然有效，不需要重新定义局部阈值幅度。

这是该构造成立的关键条件之一。

---

### 5.2 固定任一维后仍退化为一维单频阈值

固定某个方位采样点 \(\eta=\eta_n\)，有

\[
U(\tau,\eta_n)
=A_u\exp\left[j\left(2\pi f_r\tau+\phi_n\right)\right],
\]

其中

\[
\phi_n=2\pi f_a\eta_n+\phi_0.
\]

因此，对每一个方位脉冲而言，阈值仍是一条标准的距离向单频阈值，只是初始相位随方位变化。

同理，固定某个距离采样点 \(\tau=\tau_m\)，有

\[
U(\tau_m,\eta)
=A_u\exp\left[j\left(2\pi f_a\eta+\psi_m\right)\right],
\]

其中

\[
\psi_m=2\pi f_r\tau_m+\phi_0.
\]

因此，对每一个距离单元而言，阈值又是一条方位慢时间单频阈值。

这说明 2D RSFT 同时保留了距离向 RSFT 和方位向单频阈值的局部结构。

---

### 5.3 二维阈值对应二维频率平移

将阈值相位记为

\[
\psi(\tau,\eta)
=2\pi f_r\tau+2\pi f_a\eta+\phi_0.
\]

一比特量化后，按照单频阈值谐波展开的基本形式，量化信号中会出现

\[
m\phi(\tau,\eta)\pm n\psi(\tau,\eta)
\]

类型的互调项，其中 \(\phi(\tau,\eta)\) 为原 SAR 回波相位，\(m,n\) 为谐波阶数。

代入二维阈值相位后，由阈值引入的频移为

\[
\pm n\psi(\tau,\eta)
=\pm 2\pi n f_r\tau
\pm 2\pi n f_a\eta
\pm n\phi_0.
\]

因此，每个第 \(n\) 阶阈值谐波对应二维频率位移

\[
\boxed{
\Delta\boldsymbol{f}_n
=\pm n
\begin{bmatrix}
f_r\\
f_a
\end{bmatrix}
}
\]

即不再只沿距离频率轴移动，而是同时沿距离频率和方位多普勒频率移动。

从二维频谱角度看，单个阈值基频位于

\[
(f_r,f_a),
\]

其高阶项位于

\[
(\pm n f_r,\pm n f_a).
\]

因此，2D RSFT 具备将有害分量向二维频谱外部重新分配的数学可能性。

---

### 5.4 与 BRAU 双向频谱冗余相匹配

固定总预算下：

- R4A1 主要扩展距离频谱空间；
- R1A4 主要扩展方位频谱空间；
- R2A2 同时扩展距离和方位频谱空间。

对于现有 1D RSFT，阈值只沿距离方向产生确定性频移，因此 R4A1 能够提供更大的有效谐波容纳空间。

对于 2D RSFT，阈值谐波同时在两个频谱方向移动。此时：

- 只有距离扩展而没有方位扩展，可能导致方位向频移分量重新折叠进入主多普勒带；
- 只有方位扩展而没有距离扩展，可能导致距离向谐波重新折叠进入主距离带；
- 双向扩展可以同时为两个方向的频谱搬移提供冗余空间。

因此，2D RSFT 在机制上能够消除现有 RSFT 对距离倍率 \(R\) 的结构性偏向，并使阈值结构与 BRAU 的二维频谱冗余假设一致。

但需要强调：

> 该推理说明 2D RSFT 具有支持双向分配的机制基础，并不等价于数学上证明 R2A2 必然优于 R4A1。最终排序仍取决于 SAR 的距离带宽、方位多普勒带宽、匹配滤波增益、谐波阶数和频谱折叠位置。

---

### 5.5 与现有一比特量化操作兼容

一比特复量化仍按照实部和虚部分别进行：

\[
y(\tau,\eta)
=\operatorname{sign}\left(\Re\{s_{\uparrow}+U\}\right)
+j\operatorname{sign}\left(\Im\{s_{\uparrow}+U\}\right).
\]

由于 2D RSFT 输出仍是与回波矩阵同尺寸的复阈值矩阵，因此不需要修改现有量化器，只需替换阈值生成函数。

现有处理链仍可保持：

1. 距离—方位 FFT 零填充上采样；
2. 生成 2D RSFT；
3. 一比特量化；
4. 距离压缩；
5. 频域裁剪恢复原网格；
6. RCMC 和方位聚焦。

---

## 6. 不建议采用复数阈值直接相加

另一种表面上类似的构造为

\[
U_{\mathrm{sum}}(\tau,\eta)
=A_r\exp(j2\pi f_r\tau)
+A_a\exp(j2\pi f_a\eta).
\]

该式并不等价于相位相加。

其模长为

\[
|U_{\mathrm{sum}}|^2
=A_r^2+A_a^2
+2A_rA_a
\cos\left(2\pi f_r\tau-2\pi f_a\eta\right).
\]

当 \(A_r=A_a=A\) 时，

\[
0\le |U_{\mathrm{sum}}|\le 2A.
\]

这会导致：

1. 阈值幅度随位置变化；
2. 局部 STR 不再恒定；
3. 部分位置会出现近零阈值；
4. 现有 RSFT 的幅度线性分析不能直接复用；
5. 阈值频谱从一个二维频率点变为两个轴向频率点，量化后产生更复杂的组合谐波。

因此，主方案应采用

\[
\boxed{
\text{相位相加，再统一取复指数}
}
\]

而不是

\[
\boxed{
\text{两个复阈值直接相加}
}.
\]

复阈值直接相加可以作为额外的双音阈值消融实验，但不适合作为 2D RSFT 的默认定义。

---

## 7. 参数定义

2D RSFT 至少包含三个核心参数：

\[
\mathrm{STR},
\qquad
\frac{f_r}{B_r},
\qquad
\frac{f_a}{B_a},
\]

其中：

- \(B_r\) 为距离 LFM 信号带宽；
- \(B_a\) 为有效方位多普勒带宽。

定义

\[
f_r=\alpha_r B_r,
\qquad
f_a=\alpha_a B_a,
\]

其中

\[
\alpha_r=\frac{f_r}{B_r},
\qquad
\alpha_a=\frac{f_a}{B_a}.
\]

必须满足离散采样约束：

\[
|f_r|<\frac{R F_s}{2},
\]

\[
|f_a|<\frac{A\,\mathrm{PRF}}{2}.
\]

此外，需要分析高阶谐波

\[
nf_r,
\qquad
nf_a
\]

在有限采样率下的折叠位置，以避免主要有害分量重新进入有效距离带或主多普勒带。

---

## 8. 推荐实验协议

### 8.1 第一阶段：小规模可行性验证

先固定

\[
Q_{\mathrm{up}}=4,
\]

比较：

- R4A1；
- R2A2；
- R1A4。

测试三类阈值：

1. 现有 1D RSFT；
2. 相位相加的 2D RSFT；
3. 复阈值直接相加的双音阈值，仅作为消融。

建议记录：

\[
\min|U|,
\quad
\max|U|,
\quad
\operatorname{mean}|U|,
\quad
\operatorname{std}|U|.
\]

理论预期为：

- 1D RSFT：\(\operatorname{std}|U|\approx 0\)；
- 2D RSFT：\(\operatorname{std}|U|\approx 0\)；
- 复阈值直接相加：\(\operatorname{std}|U|>0\)，且可能出现接近零的阈值位置。

若 2D RSFT 能显著缩小 R4A1 与 R2A2 的差距，或使 R2A2 反超，则说明继续完整搜索具有价值。

---

### 8.2 第二阶段：公共参数固定预算实验

为了公平验证 BRAU，建议首先采用全组公共参数：

\[
(\mathrm{STR},\alpha_r,\alpha_a)
\]

对全部分配组保持一致。

该实验回答：

> 在完全相同的二维单频阈值下，固定总上采样预算应该如何在距离和方位之间分配？

这是最适合用于支撑 BRAU 主结论的实验协议。

---

### 8.3 第三阶段：联合参数优化实验

补充实验可以分别按照 \(R\) 和 \(A\) 标定频率：

\[
f_r=f_r(R),
\qquad
f_a=f_a(A).
\]

然后为每个 \((R,A)\) 组合构造对应阈值。

该实验回答：

> 当二维阈值参数与上采样配置联合设计时，每种分配能够达到怎样的性能上限？

但该结果不能再被解释为纯粹的固定预算公平比较，因为不同分配使用了不同的阈值参数。

---

## 9. 风险与理论边界

### 9.1 现有 RSFT 理论不能无修改地完整覆盖二维情形

现有 RSFT 的严格推导主要针对单一时间维度上的单频阈值。2D RSFT 虽然保持恒模、线性相位和单频切片结构，但完整的二维互调项、二维折叠区域和匹配滤波影响仍需重新推导。

因此，目前可以合理声称：

- 数学构造成立；
- 与现有量化和成像链兼容；
- 具备二维频移机制；
- 与 BRAU 的双向频谱冗余存在机制对应关系。

但不能在没有实验和更完整推导的情况下声称：

- 2D RSFT 必然优于 1D RSFT；
- 双向分配必然优于距离单向分配；
- 当前 RSFT 的全部线性恢复结论在二维情况下原样成立。

---

### 9.2 距离和方位并不物理对称

距离向由 LFM 带宽和快时间采样率决定，方位向由合成孔径、多普勒带宽和 PRF 决定。二者的：

- 有效带宽；
- 匹配滤波增益；
- 模糊周期；
- 高阶谐波失配程度；
- 频谱折叠规律

均可能不同。

因此，最佳参数通常不会满足

\[
\frac{f_r}{B_r}
=\frac{f_a}{B_a}.
\]

2D RSFT 应允许距离和方位频率独立设计。

---

## 10. 结论

### 10.1 数学可行性结论

采用

\[
\boxed{
U_{\mathrm{2D\text{-}RSFT}}(\tau,\eta)
=A_u\exp\left\{
 j\left[
2\pi f_r\tau
+2\pi f_a\eta
+\phi_0
\right]
\right\}
}
\]

构造二维 RSFT 在数学上是可行的。

其主要依据为：

1. 距离相位与方位相位可以通过广播相加形成二维线性相位；
2. 阈值模长恒定，现有 STR 幅度标定仍然有效；
3. 固定任一维后，阈值都退化为标准的一维单频阈值；
4. 阈值高阶分量在二维频谱中同时产生距离和方位频移；
5. 该二维频移机制与 BRAU 的双向频谱冗余具有直接对应关系；
6. 阈值矩阵可直接接入现有实部—虚部分离的一比特量化和后续成像链。

### 10.2 推荐实现结论

推荐采用：

\[
\boxed{
\text{距离相位向量}
+
\text{方位相位向量}
\rightarrow
\text{统一复指数}
}
\]

即

\[
U=A_u\exp[j(\phi_r+\phi_a+\phi_0)].
\]

不推荐采用：

\[
U=U_r+U_a,
\]

因为复阈值直接相加会破坏恒模结构和统一 STR 定义。

### 10.3 对论文实验的意义

2D RSFT 有望将现有 RSFT 的距离向结构性偏置转变为与双向上采样匹配的二维阈值结构，使 R4A1、R2A2 和 R1A4 的比较更接近真正的固定预算分配问题。

但其最终效果仍需通过公共参数下的固定预算实验验证。较严谨的论文表述应为：

> 2D RSFT provides a constant-modulus two-dimensional linear-phase threshold whose harmonics are shifted jointly in range and azimuth frequency. This construction is compatible with the existing one-bit quantization chain and provides a threshold geometry aligned with bidirectional spectral redundancy. Whether it restores a bidirectional allocation advantage remains an empirical question and must be evaluated under a common parameter setting.

---

## 11. 建议名称

推荐使用以下名称之一：

- **Two-Dimensional Range–Azimuth Single-Frequency Threshold（2D-RA-SFT）**；
- **Two-Dimensional RSFT（2D-RSFT）**；
- **Separable Two-Dimensional Single-Frequency Threshold（S2D-SFT）**。

从论文表达清晰度看，建议采用：

\[
\boxed{
\text{Two-Dimensional Range–Azimuth Single-Frequency Threshold}
}
\]

并在文中简称 **2D RSFT**。

