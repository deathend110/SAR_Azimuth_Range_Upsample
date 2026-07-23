# V4 实验套件

该目录用于生成论文 V4 的主结果、ENL/Entropy 指标和机制图。旧版
`Exp1`–`Exp5` 脚本及结果不会被覆盖。

## 运行入口

- `test_v4_core`：轻量单元测试，不读取外部 SAR 数据。
- `V4_MainEvaluation`：重跑 SplitRT 主实验并导出 Table III 指标。
- `V4_Mechanism`：重跑固定机制样本并导出统一频率画布和共享色条场景图。
- `V4_ValidateResults`：检查结果完整性并回归对比旧 Exp1/Exp2。
- `V4_Run_All`：按测试、主实验、机制实验的顺序执行全部任务。

在仓库根目录启动 MATLAB 后执行：

```matlab
addpath("v4_experiments");
V4_Run_All;
```

结果写入 `V4_Experiments_Output`。RT 与 RSFT 参数图仅复用以下既有文件，
本套件不会重新运行阈值扫描或阈值分配实验：

- `assert/RT_SSIM_bestAs_curve.png`
- `Exp5_RSFT_ParameterMap_Output/Exp5_RSFT_ParameterMap.png`
