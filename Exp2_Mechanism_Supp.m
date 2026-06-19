clear; clc; close all;

%% =========================================================
%  实验二补充：多场景机制取证 + tau 敏感性分析
%  目标：在 4 个不同 SAR 场景上复现 Exp2 管道，
%  验证双向优势的跨场景一致性和 tau 稳定性
%% =========================================================

%% ==================== 参数区 ====================
S60 = load("FS60_params.mat");

As = 0.6;
tau_list = [0.15, 0.25, 0.35, 0.45];

data_root = "G:\MATLAB-G\SAR Full PSF";

sample_configs = struct( ...
    "scene_label", {"city2", "port", "suburb", "filed"}, ...
    "dataset_name", {"SAR_Dataset_city2_histeq", "SAR_Dataset_port", "SAR_Dataset_suburb", "SAR_Dataset_filed"}, ...
    "file_name", {"rstart 301.mat", "rstart 1.mat", "rstart 1.mat", "rstart 1.mat"}, ...
    "c_start", {6500, 0, 0, 0}, ...
    "seed", {42, 2026, 2027, 2028});

case_defs = struct( ...
    "case_name", {"R1A1_NoUp", "R4A1", "R1A4", "R2A2"}, ...
    "range_q",   {1, 4, 1, 2}, ...
    "azimuth_q", {1, 1, 4, 2}, ...
    "group_type",{ "no_upsample", "range_only", "azimuth_only", "bidir" });

output_dir = fullfile(pwd, "Exp2_Mechanism_Supp_Output");
if ~exist(output_dir, "dir")
    mkdir(output_dir);
end

fprintf("样本数: %d, tau值: %s\n", numel(sample_configs), mat2str(tau_list));

%% ==================== 自动检测 c_start ====================
for s = 1:numel(sample_configs)
    if sample_configs(s).c_start > 0
        continue;  % 已指定的（city2=6500）不覆盖
    end
    data_path = fullfile(data_root, sample_configs(s).dataset_name, sample_configs(s).file_name);
    raw_data = load(data_path);
    var_names = fieldnames(raw_data);
    raw = raw_data.(var_names{1});
    data_width = size(raw, 2);
    c_start = max(1, floor(data_width / 3));
    if c_start + S60.nrn > data_width
        c_start = data_width - S60.nrn;
    end
    sample_configs(s).c_start = c_start;
    fprintf("  %s: data_width=%d, auto c_start=%d\n", sample_configs(s).scene_label, data_width, c_start);
end
