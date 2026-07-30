# V4 实验套件

该目录用于生成论文 V4 的 RT/RSFT 主结果、ENL/Entropy 指标和机制图。旧版
`Exp1`–`Exp5` 脚本及结果不会被覆盖。

## 运行入口

- `test_v4_core`：轻量单元测试，不读取外部 SAR 数据。
- `V4_MainEvaluation`：重跑 SplitRT 主实验并导出 Table III 指标。
- `V4_RSFTCalibration`：在统一70样本和搜索网格下校准主实验所需的9个距离倍率。
- `V4_RSFTEvaluation`：锁定每个距离倍率的RSFT参数并运行完整19组分配。
- `V4_RTFractionalPAllocationEvaluation`：按Table III(a)的固定
  SplitRT协议评价6组小数 $p$ 的平衡与单向分配。
- `V4_Mechanism`：重跑固定机制样本并导出统一频率画布和共享色条场景图。
- `V4_ValidateResults`：检查RT、RSFT和机制结果完整性，并回归对比旧 Exp1/Exp2。
- `V4_Run_All`：按测试、RT主实验、RSFT校准、RSFT评价和机制实验的顺序执行全部任务。

在仓库根目录启动 MATLAB 后执行：

```matlab
addpath("v4_experiments");
V4_Run_All;
```

结果写入 `V4_Experiments_Output`。RT 参数图继续复用既有文件：

- `assert/RT_SSIM_bestAs_curve.png`

小数 $p\in\{1.5,\sqrt{3},\sqrt{6},2.5,\sqrt{8},\sqrt{10}\}$ 的RT实验
固定使用 `As=0.6`，不执行阈值参数搜索。实验复用
Table III(a) 的70样本清单、ENL ROI、归一化和指标协议，并输出PSNR、SSIM、
Entropy和ENL。共评价18个分配组，输出1260行逐样本明细和6行配对检验：

```matlab
addpath("v4_experiments");
V4_RTFractionalPAllocationEvaluation;
```

结果写入：

- `V4_Experiments_Output/RTFractionalPAllocationEvaluation`

checkpoint按完整的 $p$ 标签集合写入 `Checkpoints/P_<标签集合>` 子目录。扩展
$p$ 列表时会保留旧配置的checkpoint，并为新配置使用独立目录。
当前协议使用 `centered_odd_v2` 后缀：当 `round(p*N_r)` 为奇数时，快时间轴
的中心样本严格对齐 $2R_0/C$，不会复用旧的半采样点偏移结果。小数组的RNG
编号按组名固定；历史组保持原编号，新增的
$\mathrm{R}\sqrt{6}\mathrm{A}\sqrt{6}$ 和
$\mathrm{R}\sqrt{10}\mathrm{A}\sqrt{10}$ 分别使用30和31。
与Table III(a)重合组的逐样本数值回归仅用于提示潜在漂移；参考文件缺失、
样本不匹配或数值超出参考容差时给出warning，不阻止本次有效结果写出。

RSFT 参数图由 `V4_RSFTCalibration` 根据统一校准结果重新生成：

- `V4_Experiments_Output/RSFTCalibration/V4_RSFT_ParameterMap.png`

Fig. 3 的逐场景 PSNR/SSIM 与图中标题使用同一数据源：

- `V4_Experiments_Output/Mechanism/V4_Scene_Metrics.csv`

RSFT 搜参和评价均支持 checkpoint。恢复时会核验样本数、预算、参数网格及
参数映射，配置不一致时拒绝静默复用旧结果。
