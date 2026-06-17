clear; clc; close all;

%% =========================================================
%  实验一（续）：非整数上采样佐证实验
%  验证非整数倍 R×A 拆分下，双向仍优于单向
%  说明：核心claim不依赖整数分配的巧合
%  4组非整数Q × 每组3方案(双向+2单向) + NoUpsample基线 = 13个评测方案
%% =========================================================

%% ==================== 参数区 ====================
S60 = load("FS60_params.mat");

% 固定随机种子（与Exp1_MainResult一致，保证可复现）
seed = 2026;
rng(seed);

% Split RT 阈值强度
As = 0.6;

% 数据根目录
data_root = "G:\MATLAB-G\SAR Full PSF";

% 7个数据集文件夹名（与Exp1_MainResult完全一致）
dataset_names = { ...
    "SAR_Dataset_Bangkok_1", ...
    "SAR_Dataset_city1_histeq", ...
    "SAR_Dataset_city2_histeq", ...
    "SAR_Dataset_SAR_figure", ...
    "SAR_Dataset_filed", ...
    "SAR_Dataset_port", ...
    "SAR_Dataset_suburb"
};
num_datasets = numel(dataset_names);

% 每个数据集内分层抽样数量
num_samples_per_dataset = 10;
total_samples = num_datasets * num_samples_per_dataset;

% 输出目录
output_dir = fullfile(pwd, "Exp1_NonInteger_Output");
if ~exist(output_dir, "dir")
    mkdir(output_dir);
end

%% ==================== 非整数组合定义 ====================
% 每组Q下包含：1个非整数双向 + 2个单向上采样对照
% NoUpsample(R1A1)作为通用基线，对所有Q相同
group_defs = build_noninteger_group_definitions();
num_groups = numel(group_defs);

fprintf("=== 共定义 %d 个非整数评测组合 ===\n", num_groups);
for g_idx = 1:num_groups
    fprintf("  [%02d] %s (Q=%.2f, R=%.2f, A=%.2f, type=%s, set=%d)\n", ...
        g_idx, group_defs(g_idx).group_name, group_defs(g_idx).Q, ...
        group_defs(g_idx).Range_q, group_defs(g_idx).Azimuth_q, ...
        group_defs(g_idx).group_type, group_defs(g_idx).set_id);
end

%% ==================== 数据集选择：种子取固定位置 ====================
fprintf("\n=== 数据集选择 ===\n");
selected_mats = struct("dataset", {}, "folder", {}, "filename", {}, "filepath", {});

for ds_idx = 1:num_datasets
    ds_name = dataset_names{ds_idx};
    ds_folder = fullfile(data_root, ds_name);

    % 列出该文件夹内所有 rstart*.mat 文件并排序
    mat_files = dir(fullfile(ds_folder, "rstart*.mat"));
    mat_names = sort({mat_files.name});

    if isempty(mat_names)
        error("数据集 %s 中没有找到 rstart*.mat 文件", ds_name);
    end

    % 用种子取固定位置（与Exp1_MainResult一致）
    pick_idx = mod(seed, numel(mat_names)) + 1;
    picked_mat = mat_names{pick_idx};

    selected_mats(ds_idx).dataset = ds_name;
    selected_mats(ds_idx).folder = ds_folder;
    selected_mats(ds_idx).filename = picked_mat;
    selected_mats(ds_idx).filepath = fullfile(ds_folder, picked_mat);

    fprintf("  [%02d] %s → %s (共%d个mat，取第%d个)\n", ...
        ds_idx, ds_name, picked_mat, numel(mat_names), pick_idx);
end

%% ==================== 构建全部样本缓存 ====================
fprintf("\n=== 构建样本缓存 (共 %d 个数据集 × %d 帧 = %d 个样本) ===\n", ...
    num_datasets, num_samples_per_dataset, total_samples);

sample_cache = repmat(struct( ...
    "dataset_idx", 0, ...
    "sample_idx", 0, ...
    "dataset_name", "", ...
    "c_start", 0, ...
    "signal60_input", [], ...
    "img_gt", []), total_samples, 1);

global_sample_idx = 0;

for ds_idx = 1:num_datasets
    mat_path = selected_mats(ds_idx).filepath;
    fprintf("  加载: %s\n", mat_path);

    loaded_data = load(mat_path);
    var_names = fieldnames(loaded_data);
    raw_data = loaded_data.(var_names{1});

    raw_width = size(raw_data, 2);
    sample_starts = build_stratified_window_starts(raw_width, S60.nrn, num_samples_per_dataset);

    for s_idx = 1:num_samples_per_dataset
        global_sample_idx = global_sample_idx + 1;
        c_start = sample_starts(s_idx);

        % 提取60MHz信号（与Exp1_MainResult一致）
        channel_block = raw_data(:, c_start:c_start + S60.nrn - 1);
        signal60 = channel_block(1:3:end, :);

        % 构建GT图像
        img_gt = build_gt_image(signal60, S60);

        sample_cache(global_sample_idx).dataset_idx = ds_idx;
        sample_cache(global_sample_idx).sample_idx = s_idx;
        sample_cache(global_sample_idx).dataset_name = dataset_names{ds_idx};
        sample_cache(global_sample_idx).c_start = c_start;
        sample_cache(global_sample_idx).signal60_input = signal60;
        sample_cache(global_sample_idx).img_gt = img_gt;

        fprintf("    样本 %03d / %03d: %s 帧%02d, c_start=%d\n", ...
            global_sample_idx, total_samples, dataset_names{ds_idx}, s_idx, c_start);
    end
end

%% ==================== 逐组合评测 ====================
fprintf("\n=== 开始逐组合评测 ===\n");
psnr_all = zeros(num_groups, total_samples);
ssim_all = zeros(num_groups, total_samples);

for group_idx = 1:num_groups
    current_group = group_defs(group_idx);
    fprintf("  处理组合 %02d / %02d: %s (Q=%.2f)\n", ...
        group_idx, num_groups, current_group.group_name, current_group.Q);

    % 每个组合用独立的种子偏移，保证RT相位可复现
    rng(seed + group_idx);

    for s_idx = 1:total_samples
        signal60 = sample_cache(s_idx).signal60_input;
        img_gt = sample_cache(s_idx).img_gt;

        % 统一走 build_rxa_image（已验证可处理 R1A1、单向、双向所有情况）
        % build_rxa_image 内部对 q=1 自动跳过上/下采样，对 R1A1 等价于无上采样
        img_out = build_rxa_image(signal60, S60, ...
            current_group.Range_q, current_group.Azimuth_q, As);

        psnr_all(group_idx, s_idx) = psnr(img_out, img_gt);
        ssim_all(group_idx, s_idx) = ssim(img_out, img_gt);
    end
end

%% ==================== 汇总统计 ====================
psnr_mean = mean(psnr_all, 2);
psnr_std  = std(psnr_all, 0, 2);
ssim_mean = mean(ssim_all, 2);
ssim_std  = std(ssim_all, 0, 2);

%% ==================== 配对 Wilcoxon 检验 ====================
fprintf("\n=== 配对 Wilcoxon signed-rank test（每个非整数Q下双向 vs 最佳单向）===\n");

has_signrank = exist("signrank", "file") == 2 || exist("signrank", "file") == 5;

% 用cell数组存储增益表数据，避免double×string混合问题
set_ids = unique([group_defs.set_id]);
set_ids(set_ids == 0) = [];  % 排除NoUpsample基线(set_id=0)
gain_cell = cell(numel(set_ids), 7);

for si = 1:numel(set_ids)
    set_id = set_ids(si);

    % 找该set下的全部组合
    set_indices = find([group_defs(:).set_id]' == set_id);

    % 分类：双向 vs 单向
    bidir_indices = [];
    unidir_indices = [];

    for i = 1:numel(set_indices)
        gt = group_defs(set_indices(i)).group_type;
        if strcmp(gt, "bidir")
            bidir_indices(end + 1) = set_indices(i); %#ok<AGROW>
        elseif strcmp(gt, "range_only") || strcmp(gt, "azimuth_only")
            unidir_indices(end + 1) = set_indices(i); %#ok<AGROW>
        end
    end

    % 该set的Q值
    Q_val = group_defs(set_indices(1)).Q;

    if ~isempty(bidir_indices) && ~isempty(unidir_indices)
        bidir_idx = bidir_indices(1);  % 每个set只有一个双向
        % 找最佳单向（PSNR最高）
        uni_psnr_vals = psnr_mean(unidir_indices);
        best_uni_local = find(uni_psnr_vals == max(uni_psnr_vals), 1, 'first');
        best_unidir_idx = unidir_indices(best_uni_local);

        delta_psnr = psnr_mean(bidir_idx) - psnr_mean(best_unidir_idx);
        delta_ssim = ssim_mean(bidir_idx) - ssim_mean(best_unidir_idx);

        % Wilcoxon 配对检验（第一个输出才是p-value）
        if has_signrank
            p_psnr = signrank(psnr_all(bidir_idx, :), psnr_all(best_unidir_idx, :));
            p_ssim = signrank(ssim_all(bidir_idx, :), ssim_all(best_unidir_idx, :));
        else
            p_psnr = NaN;
            p_ssim = NaN;
            fprintf("  [警告] signrank 函数不可用，需安装 Statistics and Machine Learning Toolbox。\n");
        end

        best_bidir_name = group_defs(bidir_idx).group_name;
        best_unidir_name = group_defs(best_unidir_idx).group_name;

        fprintf("  Q=%.2f (set=%d): 双向=%s vs 最佳单向=%s → ΔPSNR=%.4f dB, ΔSSIM=%.4f, p(PSNR)=%.4e, p(SSIM)=%.4e\n", ...
            Q_val, set_id, best_bidir_name, best_unidir_name, delta_psnr, delta_ssim, p_psnr, p_ssim);
    else
        delta_psnr = NaN;
        delta_ssim = NaN;
        p_psnr = NaN;
        p_ssim = NaN;
        best_bidir_name = "N/A";
        best_unidir_name = "N/A";
        fprintf("  Q=%.2f (set=%d): 无法找到双向或单向组\n", Q_val, set_id);
    end

    gain_cell{si, 1} = Q_val;
    gain_cell{si, 2} = best_bidir_name;
    gain_cell{si, 3} = best_unidir_name;
    gain_cell{si, 4} = delta_psnr;
    gain_cell{si, 5} = delta_ssim;
    gain_cell{si, 6} = p_psnr;
    gain_cell{si, 7} = p_ssim;
end

%% ==================== 保存汇总表 ====================
summary_table = table( ...
    [group_defs.Q].', ...
    [group_defs.set_id].', ...
    string({group_defs.group_name}).', ...
    [group_defs.Range_q].', ...
    [group_defs.Azimuth_q].', ...
    string({group_defs.group_type}).', ...
    string({group_defs.group_desc}).', ...
    repmat(total_samples, num_groups, 1), ...
    repmat(As, num_groups, 1), ...
    psnr_mean, psnr_std, ...
    ssim_mean, ssim_std, ...
    'VariableNames', { ...
    'Q', 'SetID', 'GroupName', 'Range_q', 'Azimuth_q', ...
    'GroupType', 'Description', 'SampleCount', 'As', ...
    'PSNR_Mean', 'PSNR_Std', 'SSIM_Mean', 'SSIM_Std'});

writetable(summary_table, fullfile(output_dir, "Exp1_NonInteger_Summary.csv"));

%% ==================== 保存增益表 ====================
gain_table = cell2table(gain_cell, ...
    'VariableNames', {'Q', 'BestBidir', 'BestUnidir', 'DeltaPSNR', 'DeltaSSIM', 'p_PSNR', 'p_SSIM'});
gain_table.Q = double(gain_table.Q);
gain_table.DeltaPSNR = double(gain_table.DeltaPSNR);
gain_table.DeltaSSIM = double(gain_table.DeltaSSIM);
gain_table.p_PSNR = double(gain_table.p_PSNR);
gain_table.p_SSIM = double(gain_table.p_SSIM);

writetable(gain_table, fullfile(output_dir, "Exp1_NonInteger_Gain.csv"));

%% ==================== 保存明细表 ====================
% 同时构建明细数据、数据集名和组合名
detail_data = zeros(num_groups * total_samples, 7);
detail_ds_name = strings(num_groups * total_samples, 1);
detail_group_names = strings(num_groups * total_samples, 1);
row_ptr = 1;

for group_idx = 1:num_groups
    for s_idx = 1:total_samples
        detail_data(row_ptr, :) = [ ...
            group_defs(group_idx).Q, ...
            group_defs(group_idx).set_id, ...
            group_defs(group_idx).Range_q, ...
            group_defs(group_idx).Azimuth_q, ...
            sample_cache(s_idx).dataset_idx, ...
            psnr_all(group_idx, s_idx), ...
            ssim_all(group_idx, s_idx)];
        detail_ds_name(row_ptr) = sample_cache(s_idx).dataset_name;
        detail_group_names(row_ptr) = string(group_defs(group_idx).group_name);
        row_ptr = row_ptr + 1;
    end
end

detail_table = table( ...
    detail_data(:, 1), detail_data(:, 2), detail_group_names, ...
    detail_data(:, 3), detail_data(:, 4), ...
    detail_ds_name, detail_data(:, 5), ...
    detail_data(:, 6), detail_data(:, 7), ...
    'VariableNames', {'Q', 'SetID', 'GroupName', 'Range_q', 'Azimuth_q', ...
    'Dataset', 'DatasetIdx', 'PSNR', 'SSIM'});

writetable(detail_table, fullfile(output_dir, "Exp1_NonInteger_Detail.csv"));

%% ==================== 保存 mat 结果 ====================
save(fullfile(output_dir, "Exp1_NonInteger_Data.mat"), ...
    "As", "seed", "dataset_names", "selected_mats", ...
    "num_samples_per_dataset", "total_samples", ...
    "group_defs", "psnr_all", "ssim_all", ...
    "psnr_mean", "psnr_std", "ssim_mean", "ssim_std", ...
    "gain_cell", "sample_cache");

%% ==================== 绘制对比柱状图 ====================
plot_noninteger_bars(group_defs, psnr_mean, psnr_std, ssim_mean, ssim_std, output_dir);

fprintf("\n全部完成，结果已保存到目录：%s\n", output_dir);


%% =========================================================
%% ==================== 局部函数区 =========================
%% =========================================================

% ---- 非整数组合定义 ----

% 手动定义4组非整数Q，每组含双向+2单向，加NoUpsample基线
function group_defs = build_noninteger_group_definitions()
    group_defs = struct( ...
        "Q", {}, "set_id", {}, "Range_q", {}, "Azimuth_q", {}, ...
        "group_name", {}, "group_type", {}, "group_desc", {});

    % Set 1: Q=3, R1.5×A2
    group_defs = add_combo(group_defs, 3, 1, 1.5, 2, "R1.5A2", "bidir", "非整数双向(距离非整数)");
    group_defs = add_combo(group_defs, 3, 1, 3, 1, "R3A1", "range_only", "距离向单向对照");
    group_defs = add_combo(group_defs, 3, 1, 1, 3, "R1A3", "azimuth_only", "方位向单向对照");

    % Set 2: Q=4.5, R1.5×A3
    group_defs = add_combo(group_defs, 4.5, 2, 1.5, 3, "R1.5A3", "bidir", "非整数双向(距离非整数)");
    group_defs = add_combo(group_defs, 4.5, 2, 4.5, 1, "R4.5A1", "range_only", "距离向单向对照");
    group_defs = add_combo(group_defs, 4.5, 2, 1, 4.5, "R1A4.5", "azimuth_only", "方位向单向对照");

    % Set 3: Q=5, R2.5×A2
    group_defs = add_combo(group_defs, 5, 3, 2.5, 2, "R2.5A2", "bidir", "非整数双向(方位非整数)");
    group_defs = add_combo(group_defs, 5, 3, 5, 1, "R5A1", "range_only", "距离向单向对照");
    group_defs = add_combo(group_defs, 5, 3, 1, 5, "R1A5", "azimuth_only", "方位向单向对照");

    % Set 4: Q=7.5, R2.5×A3
    group_defs = add_combo(group_defs, 7.5, 4, 2.5, 3, "R2.5A3", "bidir", "非整数双向(两方向都非整数)");
    group_defs = add_combo(group_defs, 7.5, 4, 7.5, 1, "R7.5A1", "range_only", "距离向单向对照");
    group_defs = add_combo(group_defs, 7.5, 4, 1, 7.5, "R1A7.5", "azimuth_only", "方位向单向对照");

    % NoUpsample 基线（set_id=0）
    group_defs = add_combo(group_defs, 1, 0, 1, 1, "R1A1_NoUp", "no_upsample", "无上采样基线");
end

% 添加单个组合到group_defs
function group_defs = add_combo(group_defs, Q, set_id, range_q, azimuth_q, name, gtype, desc)
    group_defs(end + 1).Q = Q;
    group_defs(end).set_id = set_id;
    group_defs(end).Range_q = range_q;
    group_defs(end).Azimuth_q = azimuth_q;
    group_defs(end).group_name = name;
    group_defs(end).group_type = gtype;
    group_defs(end).group_desc = desc;
end

% ---- 数据集相关 ----

% 分层抽样：在序列宽度内均匀抽取num_samples个窗口起始位置
function sample_starts = build_stratified_window_starts(raw_width, window_width, num_samples)
    max_start = raw_width - window_width + 1;
    if max_start < 1
        error("序列宽度不足以裁出完整窗口。");
    end
    sample_starts = zeros(num_samples, 1);
    for s_idx = 1:num_samples
        center_pos = round((s_idx - 0.5) / num_samples * max_start);
        center_pos = max(center_pos, 1);
        center_pos = min(center_pos, max_start);
        sample_starts(s_idx) = center_pos;
    end
end

% ---- 图像构建 ----

% 构建GT参考图像（无量化、无上采样）
function img_gt = build_gt_image(signal60, S60)
    RC_gt   = Range_Compress(signal60, S60.fc, S60.tnrn, S60.gama, S60.R0, S60.C, S60.Fs, S60.Tp);
    RCMC_gt = RCMC(RC_gt, S60.lambda, S60.fnrn, S60.fnan, S60.R0, S60.C, S60.v);
    IMG_gt  = SAR_Imaging(RCMC_gt, S60.lambda, S60.Fs, S60.R0, S60.C, S60.v, S60.tnan, S60.Ta, S60.prf);

    roi_gt = abs(IMG_gt( ...
        S60.nrn / 2 - S60.R_total / 2 + 1 : S60.nrn / 2 + S60.R_total / 2, ...
        S60.nan / 2 - S60.A_num / 2 : S60.nan / 2 + S60.A_num / 2 - 1));

    img_gt = normalize_image(roi_gt);
end

% 对指定的 RxAx 组合构建最终成像结果
% 统一处理：双向、单向(R=Q或A=Q)、NoUpsample(R1A1)
% 内部对 q=1 自动跳过上/下采样，对R1A1等价于无上采样
function img_out = build_rxa_image(signal60, S60, range_q, azimuth_q, As)
    % 生成SplitRT阈值（上采样后尺寸；q=1时尺寸不变）
    [U, ~, ~] = Build_2D_SplitRT(signal60, azimuth_q, range_q, As);

    % 二维上采样（q=1时该方向跳过）
    signal_up = two_dim_upsample_fft(signal60, azimuth_q, range_q);

    % 构造距离向上采样后的RD参数（range_q=1时为原始参数）
    nrn_up = size(signal_up, 1);
    Fs_up  = range_q * S60.Fs;
    Tnrn_up   = 1 / Fs_up;
    Tstart_up = 2 * S60.R0 / S60.C - nrn_up / 2 / Fs_up;
    Tend_up   = 2 * S60.R0 / S60.C + (nrn_up / 2 - 1) / Fs_up;
    tnrn_up   = (Tstart_up : Tnrn_up : Tend_up).';

    % 1-bit量化
    channel_1bit = quantize_1bit_with_U(signal_up, U);

    % 距离压缩（range_q=1时Fs_up=S60.Fs，等价原始参数）
    RC = Range_Compress(channel_1bit, S60.fc, tnrn_up, S60.gama, S60.R0, S60.C, Fs_up, S60.Tp);

    % 二维下采样回原尺寸（q=1时该方向跳过）
    RC_crop = two_dim_downsample_fft(RC, azimuth_q, range_q, S60);

    % RCMC + 方位聚焦
    RCMC_crop = RCMC(RC_crop, S60.lambda, S60.fnrn, S60.fnan, S60.R0, S60.C, S60.v);
    IMG = SAR_Imaging(RCMC_crop, S60.lambda, S60.Fs, S60.R0, S60.C, S60.v, S60.tnan, S60.Ta, S60.prf);

    roi = abs(IMG( ...
        S60.nrn / 2 - S60.R_total / 2 + 1 : S60.nrn / 2 + S60.R_total / 2, ...
        S60.nan / 2 - S60.A_num / 2 : S60.nan / 2 + S60.A_num / 2 - 1));

    img_out = normalize_image(roi);
end

% ---- RT阈值与量化 ----

% 生成可分离的二维 RT 阈值场
function [U, sigma, A_rt] = Build_2D_SplitRT(input60, azimuth_q, range_q, As)
    signal_up = two_dim_upsample_fft(input60, azimuth_q, range_q);
    [Nr_up, Na_up] = size(signal_up);

    phi_r = 2 * pi * rand(Nr_up, 1);
    phi_a = 2 * pi * rand(1, Na_up);

    sigma = sqrt(2 / pi) * mean(abs(signal_up(:)));
    A_rt = As * sigma;

    U = A_rt * exp(1i * (phi_r + phi_a));
end

% 带RT阈值的1-bit量化
function S1 = quantize_1bit_with_U(S, U)
    re = ones(size(S), "like", real(S));
    im = ones(size(S), "like", real(S));

    re(real(S) + real(U) < 0) = -1;
    im(imag(S) + imag(U) < 0) = -1;

    S1 = complex(re, im);
end

% ---- 上采样 / 下采样 ----

% 二维上采样：先距离向，再方位向
function S_up = two_dim_upsample_fft(S, q_azimuth, q_range)
    S_up = S;
    if q_range > 1
        S_up = range_upsample_fft(S_up, q_range);
    end
    if q_azimuth > 1
        S_up = azimuth_upsample_fft(S_up, q_azimuth);
    end
end

% 二维下采样：先裁方位，再裁距离
function S_down = two_dim_downsample_fft(S, q_azimuth, q_range, meta)
    S_down = S;
    if q_azimuth > 1
        S_down = crop_azimuth_doppler_to_width(S_down, meta.nan);
    end
    if q_range > 1
        S_down = crop_range_doppler_to_width(S_down, meta.nrn);
    end
end

% 距离向频域零填充上采样（支持非整数q）
function S_up = range_upsample_fft(S, q)
    [Nr, Na] = size(S);
    Nr_up = round(q * Nr);

    Sf = fftshift(fft(S, [], 1), 1);
    pad_total = Nr_up - Nr;
    pad_top    = floor(pad_total / 2);
    pad_bottom = pad_total - pad_top;

    Sf_up = [zeros(pad_top, Na, "like", Sf); ...
             Sf; ...
             zeros(pad_bottom, Na, "like", Sf)];

    S_up = ifft(ifftshift(Sf_up, 1), [], 1) * q;
end

% 方位向频域零填充上采样（支持非整数q）
function S_up = azimuth_upsample_fft(S, q)
    [Nr, Na] = size(S);
    Na_up = round(q * Na);

    Sf = fftshift(fft(S, [], 2), 2);
    pad_total = Na_up - Na;
    pad_left  = floor(pad_total / 2);
    pad_right = pad_total - pad_left;

    Sf_up = [zeros(Nr, pad_left, "like", Sf), ...
             Sf, ...
             zeros(Nr, pad_right, "like", Sf)];

    S_up = ifft(ifftshift(Sf_up, 2), [], 2) * q;
end

% 距离向频域裁剪回原尺寸
function X_crop = crop_range_doppler_to_width(X, target_height)
    [Nr_up, ~] = size(X);
    if target_height > Nr_up
        error("target_height 不能大于当前矩阵高度。");
    end

    Xf = fftshift(fft(X, [], 1), 1);
    c = floor(Nr_up / 2) + 1;
    h = floor(target_height / 2);

    if mod(target_height, 2) == 0
        idx = (c - h):(c + h - 1);
    else
        idx = (c - h):(c + h);
    end

    Xf_crop = Xf(idx, :);
    X_crop = ifft(ifftshift(Xf_crop, 1), [], 1);
end

% 方位向频域裁剪回原尺寸
function X_crop = crop_azimuth_doppler_to_width(X, target_width)
    [~, Na_up] = size(X);
    if target_width > Na_up
        error("target_width 不能大于当前矩阵宽度。");
    end

    Xf = fftshift(fft(X, [], 2), 2);
    c = floor(Na_up / 2) + 1;
    h = floor(target_width / 2);

    if mod(target_width, 2) == 0
        idx = (c - h):(c + h - 1);
    else
        idx = (c - h):(c + h);
    end

    Xf_crop = Xf(:, idx);
    X_crop = ifft(ifftshift(Xf_crop, 2), [], 2);
end

% ---- 绘图 ----

% 绘制非整数组合对比柱状图：每个Q下双向/单向/NoUpsample并排
function plot_noninteger_bars(group_defs, psnr_mean, psnr_std, ssim_mean, ssim_std, output_dir)

    % 颜色定义
    colors = struct( ...
        "no_upsample",   [0.50, 0.50, 0.50], ...  % 灰色
        "range_only",    [0.12, 0.47, 0.71], ...  % 蓝色
        "azimuth_only",  [0.85, 0.33, 0.10], ...  % 橙色
        "bidir",         [0.20, 0.63, 0.17]);     % 绿色

    % 排除NoUpsample，找出非整数set
    set_ids = unique([group_defs.set_id]);
    set_ids(set_ids == 0) = [];
    num_sets = numel(set_ids);

    % NoUpsample基线值
    % 注意：group_type字段是string标量，不能直接放进cell后再用strcmp匹配
    group_types = string({group_defs.group_type});
    noupsample_idx = find(group_types == "no_upsample", 1);
    if isempty(noupsample_idx)
        error("未找到 group_type 为 no_upsample 的基线组，无法绘制非整数对比柱状图。");
    end
    noupsample_psnr = psnr_mean(noupsample_idx);
    noupsample_ssim = ssim_mean(noupsample_idx);

    % 收集每个set的各类别值
    for metric_idx = 1:2
        if metric_idx == 1
            metric_mean = psnr_mean;
            metric_std  = psnr_std;
            noupsample_val = noupsample_psnr;
            y_label = "PSNR (dB)";
            tag = "PSNR";
        else
            metric_mean = ssim_mean;
            metric_std  = ssim_std;
            noupsample_val = noupsample_ssim;
            y_label = "SSIM";
            tag = "SSIM";
        end

        % 每个set收集 bidir / best_unidir 的值
        Q_vals = zeros(num_sets, 1);
        bidir_vals = zeros(num_sets, 1);
        bidir_stds  = zeros(num_sets, 1);
        unidir_vals = zeros(num_sets, 1);
        unidir_stds  = zeros(num_sets, 1);

        for si = 1:num_sets
            set_id = set_ids(si);
            set_indices = find([group_defs(:).set_id]' == set_id);

            Q_vals(si) = group_defs(set_indices(1)).Q;

            bidir_idx = [];
            unidir_indices = [];
            for i = 1:numel(set_indices)
                gt = group_defs(set_indices(i)).group_type;
                if strcmp(gt, "bidir")
                    bidir_idx = set_indices(i);
                elseif strcmp(gt, "range_only") || strcmp(gt, "azimuth_only")
                    unidir_indices(end + 1) = set_indices(i); %#ok<AGROW>
                end
            end

            if ~isempty(bidir_idx)
                bidir_vals(si) = metric_mean(bidir_idx);
                bidir_stds(si) = metric_std(bidir_idx);
            else
                bidir_vals(si) = NaN;
                bidir_stds(si) = NaN;
            end

            if ~isempty(unidir_indices)
                uni_vals = metric_mean(unidir_indices);
                best_local = find(uni_vals == max(uni_vals), 1, 'first');
                best_uni_idx = unidir_indices(best_local);
                unidir_vals(si) = metric_mean(best_uni_idx);
                unidir_stds(si) = metric_std(best_uni_idx);
            else
                unidir_vals(si) = NaN;
                unidir_stds(si) = NaN;
            end
        end

        % 绘制分组柱状图
        figure("Color", "w", "Position", [100, 100, 900, 500]);
        hold on; grid on; box on;

        x_pos = 1:num_sets;
        bar_width = 0.27;

        % 三组柱：双向、最佳单向、NoUpsample
        h1 = bar(x_pos - bar_width, bidir_vals, bar_width, ...
            "FaceColor", colors.bidir, "EdgeColor", "none", ...
            "DisplayName", "双向拆分(非整数)");
        h2 = bar(x_pos, unidir_vals, bar_width, ...
            "FaceColor", colors.range_only, "EdgeColor", "none", ...
            "DisplayName", "最佳单向");
        h3 = bar(x_pos + bar_width, repmat(noupsample_val, num_sets, 1), bar_width, ...
            "FaceColor", colors.no_upsample, "EdgeColor", "none", ...
            "DisplayName", "NoUpsample");

        % 误差线
        errorbar(x_pos - bar_width, bidir_vals, bidir_stds, "k", "LineStyle", "none", "LineWidth", 1, "HandleVisibility", "off");
        errorbar(x_pos, unidir_vals, unidir_stds, "k", "LineStyle", "none", "LineWidth", 1, "HandleVisibility", "off");

        xticks(x_pos);
        xticklabels(arrayfun(@(q) sprintf("Q=%.1f", q), Q_vals, 'UniformOutput', false));
        xlabel("总上采样倍率 Q（非整数）", "FontSize", 13);
        ylabel(y_label, "FontSize", 13);
        title(sprintf("非整数上采样：%s 对比 (As=%.1f, 7数据集×10帧)", tag, 0.6), "FontSize", 14);
        legend([h1, h2, h3], "Location", "best", "FontSize", 10);
        ax = gca; ax.FontSize = 12;

        save_name = sprintf("Exp1_NonInteger_%s_bars.png", tag);
        exportgraphics(gcf, fullfile(output_dir, save_name), "Resolution", 240);
        close(gcf);
    end
end
