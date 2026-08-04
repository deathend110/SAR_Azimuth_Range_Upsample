function V5_Run_All()
% 依次执行V5轻量测试、论文RT实验、噪声实验和结果验收。
experiment_dir=fileparts(mfilename("fullpath")); repo_root=fileparts(experiment_dir);
addpath(repo_root,experiment_dir);
fprintf("=== V5实验套件：轻量单元测试 ===\n"); test_v5_core();
fprintf("\n=== V5实验套件：SplitRT主结果 ===\n"); V5_MainEvaluation();
fprintf("\n=== V5实验套件：RT阈值敏感性 ===\n"); V5_ThresholdSensitivity();
fprintf("\n=== V5实验套件：机制实验 ===\n"); V5_Mechanism();
fprintf("\n=== V5实验套件：高斯噪声实验 ===\n"); V5_NoiseEvaluation();
fprintf("\n=== V5实验套件：结果验收 ===\n"); V5_ValidateResults();
fprintf("\nV5 RT-only实验套件全部完成。\n");
end
