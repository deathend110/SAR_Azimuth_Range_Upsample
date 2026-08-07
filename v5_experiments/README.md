# V5 RT-only 实验套件

V5用于生成BRAU论文当前所需的SplitRT主结果、RT阈值敏感性、机制图和高斯
噪声实验。该套件不包含SFT、RSFT和当前论文未使用的小数倍率实验，也不会覆盖
`V4_Experiments_Output`。

## 入口

在仓库根目录启动MATLAB：

```matlab
addpath("v5_experiments");
test_v5_core;              % 不读取外部SAR数据的轻量测试
V5_MainEvaluation;         % 19组、70样本SplitRT主结果
V5_ThresholdSensitivity;   % R2A2/R2A3/R3A3的As曲线
V5_Mechanism;              % 机制频谱图、场景图和泄漏指标
V5_NoiseEvaluation;        % 双GT协议高斯噪声实验
V5_ValidateResults;        % 完整结果验收
```

`V5_Run_All`依次执行上述全部任务。完整实验耗时较长，尤其噪声实验包含29个
SNR点、70个样本、50次重复和3个分配组；应在明确授权后运行。

## 噪声协议

- SNR范围为`-2:0.5:12 dB`，另输出无高斯噪声clean baseline。
- 固定比较R4A1、R1A4和R2A2，SplitRT系数为`As=0.6`。
- 每个样本、重复和SNR只生成一次带噪回波，三种分配严格共享。
- 同一noisy 1-bit重建同时对clean GT和同噪声noisy GT计算PSNR/SSIM。
- 50次重复先在样本内平均，再对70个样本统计和执行配对检验。
- ENL沿用主实验协议：在field和port的20个clean GT上选择固定64×64均匀
  ROI，对归一化幅度平方得到的强度计算`mean(I)^2/var(I)`；所有SNR、重复和
  分配复用相同ROI。
- R50的CPU快路径跨SNR复用基础噪声和频域上采样，默认最多使用4个线程
  worker；并行池不可用时自动退回串行，不使用GPU。
- CPU快路径使用独立checkpoint，并按“样本-重复”单元增量保存；计算版本或
  实验签名不一致时拒绝静默恢复。

所有结果写入`V5_Experiments_Output`，CSV保留重复级、样本级和汇总级数据，
MAT与metadata记录完整配置和随机协议。
