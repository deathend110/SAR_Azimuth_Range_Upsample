function V4_Run_All()
% 依次执行V4测试、RT/RSFT主结果和机制实验。

experiment_dir = fileparts(mfilename("fullpath"));
repo_root = fileparts(experiment_dir);
addpath(repo_root, experiment_dir);

fprintf("=== V4实验套件：静态与单元检查 ===\n");
test_v4_core();

fprintf("\n=== V4实验套件：主结果 ===\n");
V4_MainEvaluation();

fprintf("\n=== V4实验套件：RSFT统一校准 ===\n");
V4_RSFTCalibration();

fprintf("\n=== V4实验套件：RSFT完整评价 ===\n");
V4_RSFTEvaluation();

fprintf("\n=== V4实验套件：机制实验 ===\n");
V4_Mechanism();

fprintf("\n=== V4实验套件：结果验收 ===\n");
V4_ValidateResults();

fprintf("\nV4实验套件全部完成。\n");
end
