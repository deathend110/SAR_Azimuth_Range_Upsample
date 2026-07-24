# V4 实验套件

该目录用于生成论文 V4 的 RT/RSFT 主结果、ENL/Entropy 指标和机制图。旧版
`Exp1`–`Exp5` 脚本及结果不会被覆盖。

## 运行入口

- `test_v4_core`：轻量单元测试，不读取外部 SAR 数据。
- `V4_MainEvaluation`：重跑 SplitRT 主实验并导出 Table III 指标。
- `V4_RSFTCalibration`：在统一70样本和搜索网格下校准主实验所需的9个距离倍率。
- `V4_RSFTEvaluation`：锁定每个距离倍率的RSFT参数并运行完整19组分配。
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

RSFT 参数图由 `V4_RSFTCalibration` 根据统一校准结果重新生成：

- `V4_Experiments_Output/RSFTCalibration/V4_RSFT_ParameterMap.png`

Fig. 3 的逐场景 PSNR/SSIM 与图中标题使用同一数据源：

- `V4_Experiments_Output/Mechanism/V4_Scene_Metrics.csv`

RSFT 搜参和评价均支持 checkpoint。恢复时会核验样本数、预算、参数网格及
参数映射，配置不一致时拒绝静默复用旧结果。
