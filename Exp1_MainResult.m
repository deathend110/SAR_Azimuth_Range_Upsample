clear; clc; close all;

%% =========================================================
%  实验一：主结果实验
%  四类统一对照：NoUpsample / RangeOnly / AzimuthOnly / Bidirectional
%  多数据集（7个）× 每个数据集分层抽样10帧 = 70个配对观测
%  单种子 seed=2026，配对 Wilcoxon signed-rank test
%% =========================================================

%% ==================== 参数区 ====================
S60 = load("FS60_params.mat");

% 固定随机种子，保证数据集选择、抽样与随机相位可复现
seed = 2026;
rng(seed);

% 总上采样倍率列表（1-bit SAR场景下Q上限为10）
Q_list = [4, 6, 8, 9, 10];

% Split RT 阈值强度
As = 0.6;

% 数据根目录
data_root = "G:\MATLAB-G\SAR Full PSF";

% 7个数据集文件夹名
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
output_dir = fullfile(pwd, "Exp1_MainResult_Output");
if ~exist(output_dir, "dir")
    mkdir(output_dir);
end

%% ==================== 数据集选择：种子取固定位置 ====================
% 对每个数据集文件夹，列出所有 rstart*.mat 文件，排序后用种子取一个
fprintf("=== 数据集选择 ===\n");
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

    % 用种子取固定位置
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
% 每个数据集 × 10帧 = 70个样本，预先计算GT和signal60_input
fprintf("\n=== 构建样本缓存 (共 %d 个数据集 × %d 帧 = %d 个样本) ===\n", ...
    num_datasets, num_samples_per_dataset, total_samples);

% 样本缓存结构：dataset_idx, sample_idx, c_start, signal60_input, img_gt
sample_cache = repmat(struct( ...
    "dataset_idx", 0, ...
    "sample_idx", 0, ...
    "dataset_name", "", ...
    "c_start", 0, ...
    "signal60_input", [], ...
    "img_gt", []), total_samples, 1);

global_sample_idx = 0;

for ds_idx = 1:num_datasets
    % 加载该数据集选定的mat文件
    mat_path = selected_mats(ds_idx).filepath;
    fprintf("  加载: %s\n", mat_path);

    loaded_data = load(mat_path);
    var_names = fieldnames(loaded_data);
    raw_data = loaded_data.(var_names{1});

    raw_width = size(raw_data, 2);

    % 分层抽样10帧
    sample_starts = build_stratified_window_starts(raw_width, S60.nrn, num_samples_per_dataset);

    for s_idx = 1:num_samples_per_dataset
        global_sample_idx = global_sample_idx + 1;
        c_start = sample_starts(s_idx);

        % 提取60MHz信号
        channel_block = raw_data(:, c_start:c_start + S60.nrn - 1);
        signal60 = channel_block(1:3:end, :);

        % 构建GT图像
        img_gt = build_gt_image(signal60, S60);

        % 存入缓存
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

%% ==================== 生成全部 RxAx 组合（含 NoUpsample） ====================
group_defs = build_all_group_definitions_with_noupsample(Q_list);
num_groups = numel(group_defs);

fprintf("\n=== 共生成 %d 个评测组合 ===\n", num_groups);
for g_idx = 1:num_groups
    fprintf("  [%02d] %s (Q=%d, type=%s)\n", ...
        g_idx, group_defs(g_idx).group_name, group_defs(g_idx).Q, group_defs(g_idx).group_type);
end

%% ==================== 逐组合评测 ====================
fprintf("\n=== 开始逐组合评测 ===\n");
psnr_all = zeros(num_groups, total_samples);
ssim_all = zeros(num_groups, total_samples);

for group_idx = 1:num_groups
    current_group = group_defs(group_idx);
    fprintf("  处理组合 %02d / %02d: %s (Q=%d)\n", ...
        group_idx, num_groups, current_group.group_name, current_group.Q);

    % 每个组合用独立的种子偏移，保证不同组合的RT相位可复现
    rng(seed + group_idx);

    for s_idx = 1:total_samples
        signal60 = sample_cache(s_idx).signal60_input;
        img_gt = sample_cache(s_idx).img_gt;

        % NoUpsample 走特殊pipeline
        if current_group.Range_q == 1 && current_group.Azimuth_q == 1
            img_out = build_noupsample_image(signal60, S60, As);
        else
            img_out = build_rxa_image(signal60, S60, ...
                current_group.Range_q, current_group.Azimuth_q, As);
        end

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
fprintf("\n=== 配对 Wilcoxon signed-rank test ===\n");

% 检查统计工具箱是否可用
has_signrank = exist("signrank", "file") == 2 || exist("signrank", "file") == 5;

gain_table_data = [];

% NoUpsample的索引和结果（对所有Q相同）
noupsample_idx = find(strcmp({group_defs.group_type}, "no_upsample"), 1);

for q_idx = 1:numel(Q_list)
    Q = Q_list(q_idx);

    % 找该Q下的全部组合索引（列向量）
    q_indices = find([group_defs(:).Q]' == Q);

    % 从q_indices中分类：单向 vs 双向
    unidir_indices = [];
    bidir_indices  = [];

    for i = 1:numel(q_indices)
        gt = group_defs(q_indices(i)).group_type;
        if strcmp(gt, "range_only") || strcmp(gt, "azimuth_only")
            unidir_indices(end + 1) = q_indices(i); %#ok<AGROW>
        elseif strcmp(gt, "balanced") || strcmp(gt, "mixed")
            bidir_indices(end + 1) = q_indices(i); %#ok<AGROW>
        end
    end

    % 找PSNR最高的最佳单向组和最佳双向组
    if ~isempty(unidir_indices)
        uni_psnr_vals = psnr_mean(unidir_indices);
        best_unidir_idx = unidir_indices(uni_psnr_vals == max(uni_psnr_vals));
        best_unidir_idx = best_unidir_idx(1);  % 若多个并列取第一个
        best_unidir_name = group_defs(best_unidir_idx).group_name;
    else
        best_unidir_idx = 0;
        best_unidir_name = "N/A";
    end

    if ~isempty(bidir_indices)
        bi_psnr_vals = psnr_mean(bidir_indices);
        best_bidir_idx = bidir_indices(bi_psnr_vals == max(bi_psnr_vals));
        best_bidir_idx = best_bidir_idx(1);  % 若多个并列取第一个
        best_bidir_name = group_defs(best_bidir_idx).group_name;
    else
        best_bidir_idx = 0;
        best_bidir_name = "N/A";
    end

    % 计算增益和统计检验
    if best_bidir_idx > 0 && best_unidir_idx > 0
        delta_psnr = psnr_mean(best_bidir_idx) - psnr_mean(best_unidir_idx);
        delta_ssim = ssim_mean(best_bidir_idx) - ssim_mean(best_unidir_idx);

        % Wilcoxon 配对检验：每个样本配对（70个观测）
        if has_signrank
            [~, p_psnr] = signrank(psnr_all(best_bidir_idx, :), psnr_all(best_unidir_idx, :));
            [~, p_ssim] = signrank(ssim_all(best_bidir_idx, :), ssim_all(best_unidir_idx, :));
        else
            p_psnr = NaN;
            p_ssim = NaN;
            fprintf("  [警告] signrank 函数不可用，跳过统计检验。需安装 Statistics and Machine Learning Toolbox。\n");
        end

        fprintf("  Q=%d: 最佳双向=%s vs 最佳单向=%s → ΔPSNR=%.4f dB, ΔSSIM=%.4f, p(PSNR)=%.4e, p(SSIM)=%.4e\n", ...
            Q, best_bidir_name, best_unidir_name, delta_psnr, delta_ssim, p_psnr, p_ssim);
    else
        delta_psnr = NaN;
        delta_ssim = NaN;
        p_psnr = NaN;
        p_ssim = NaN;
        fprintf("  Q=%d: 无法找到双向或单向组\n", Q);
    end

    gain_table_data = [gain_table_data; Q, best_bidir_name, best_unidir_name, delta_psnr, delta_ssim, p_psnr, p_ssim];
end

%% ==================== 保存汇总表 ====================
summary_table = table( ...
    [group_defs.Q].', ...
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
    'Q', 'GroupName', 'Range_q', 'Azimuth_q', ...
    'GroupType', 'Description', 'SampleCount', 'As', ...
    'PSNR_Mean', 'PSNR_Std', 'SSIM_Mean', 'SSIM_Std'});

writetable(summary_table, fullfile(output_dir, "Exp1_MainResult_Summary.csv"));

%% ==================== 保存增益表 ====================
gain_table = table( ...
    gain_table_data(:, 1), ...
    string(gain_table_data(:, 2)), ...
    string(gain_table_data(:, 3)), ...
    gain_table_data(:, 4), ...
    gain_table_data(:, 5), ...
    gain_table_data(:, 6), ...
    gain_table_data(:, 7), ...
    'VariableNames', {'Q', 'BestBidir', 'BestUnidir', 'DeltaPSNR', 'DeltaSSIM', 'p_PSNR', 'p_SSIM'});

writetable(gain_table, fullfile(output_dir, "Exp1_MainResult_Gain.csv"));

%% ==================== 保存明细表 ====================
% 先构建GroupName列：每个group重复total_samples次
detail_group_names = strings(num_groups * total_samples, 1);
row_ptr = 1;
for group_idx = 1:num_groups
    for s_idx = 1:total_samples
        detail_group_names(row_ptr) = string(group_defs(group_idx).group_name);
        row_ptr = row_ptr + 1;
    end
end

detail_table = table( ...
    detail_data(:, 1), detail_group_names, ...
    detail_data(:, 2), detail_data(:, 3), ...
    detail_ds_name, detail_data(:, 4), ...
    detail_data(:, 5), ...
    detail_data(:, 6), detail_data(:, 7), ...
    'VariableNames', {'Q', 'GroupName', 'Range_q', 'Azimuth_q', ...
    'Dataset', 'DatasetIdx', 'CStart', 'PSNR', 'SSIM'});

writetable(detail_table, fullfile(output_dir, "Exp1_MainResult_Detail.csv"));

%% ==================== 保存 mat 结果 ====================
save(fullfile(output_dir, "Exp1_MainResult_Data.mat"), ...
    "Q_list", "As", "seed", "dataset_names", "selected_mats", ...
    "num_samples_per_dataset", "total_samples", ...
    "group_defs", "psnr_all", "ssim_all", ...
    "psnr_mean", "psnr_std", "ssim_mean", "ssim_std", ...
    "gain_table_data", "sample_cache");

%% ==================== 绘制主结果图 ====================
plot_main_result_curves(Q_list, group_defs, psnr_mean, psnr_std, ...
    ssim_mean, ssim_std, output_dir);

fprintf("\n全部完成，结果已保存到目录：%s\n", output_dir);


%% =========================================================
%% ==================== 局部函数区 =========================
%% =========================================================

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

% NoUpsample（R1A1）：无上采样但有SplitRT阈值
% pipeline: 原尺寸SplitRT → 1-bit量化 → 原参数RC → RCMC → Imaging → ROI → normalize
function img_out = build_noupsample_image(signal60, S60, As)
    rng_state = rng;  % 保存当前RNG状态

    % 在原始尺寸上构建SplitRT阈值（azimuth_q=1, range_q=1）
    signal_up = signal60;  % 无上采样，信号尺寸不变
    [Nr, Na] = size(signal60);

    phi_r = 2 * pi * rand(Nr, 1);
    phi_a = 2 * pi * rand(1, Na);

    sigma = sqrt(2 / pi) * mean(abs(signal_up(:)));
    A_rt = As * sigma;

    U = A_rt * exp(1i * (phi_r + phi_a));

    % 1-bit量化
    channel_1bit = quantize_1bit_with_U(signal60, U);

    % 距离压缩（使用原始参数，无上采样）
    RC = Range_Compress(channel_1bit, S60.fc, S60.tnrn, S60.gama, S60.R0, S60.C, S60.Fs, S60.Tp);

    % RCMC + 方位聚焦
    RCMC_out = RCMC(RC, S60.lambda, S60.fnrn, S60.fnan, S60.R0, S60.C, S60.v);
    IMG = SAR_Imaging(RCMC_out, S60.lambda, S60.Fs, S60.R0, S60.C, S60.v, S60.tnan, S60.Ta, S60.prf);

    roi = abs(IMG( ...
        S60.nrn / 2 - S60.R_total / 2 + 1 : S60.nrn / 2 + S60.R_total / 2, ...
        S60.nan / 2 - S60.A_num / 2 : S60.nan / 2 + S60.A_num / 2 - 1));

    img_out = normalize_image(roi);
end

% 对指定的 RxAx 组合构建最终成像结果（上采样路径）
function img_out = build_rxa_image(signal60, S60, range_q, azimuth_q, As)
    % 生成SplitRT阈值（上采样后尺寸）
    [U, ~, ~] = Build_2D_SplitRT(signal60, azimuth_q, range_q, As);

    % 二维上采样
    signal_up = two_dim_upsample_fft(signal60, azimuth_q, range_q);

    % 构造距离向上采样后的RD参数
    nrn_up = size(signal_up, 1);
    Fs_up  = range_q * S60.Fs;
    Tnrn_up   = 1 / Fs_up;
    Tstart_up = 2 * S60.R0 / S60.C - nrn_up / 2 / Fs_up;
    Tend_up   = 2 * S60.R0 / S60.C + (nrn_up / 2 - 1) / Fs_up;
    tnrn_up   = (Tstart_up : Tnrn_up : Tend_up).';

    % 1-bit量化
    channel_1bit = quantize_1bit_with_U(signal_up, U);

    % 距离压缩（使用上采样后参数）
    RC = Range_Compress(channel_1bit, S60.fc, tnrn_up, S60.gama, S60.R0, S60.C, Fs_up, S60.Tp);

    % 二维下采样回原尺寸
    RC_crop = two_dim_downsample_fft(RC, azimuth_q, range_q, S60);

    % RCMC + 方位聚焦
    RCMC_crop = RCMC(RC_crop, S60.lambda, S60.fnrn, S60.fnan, S60.R0, S60.C, S60.v);
    IMG = SAR_Imaging(RCMC_crop, S60.lambda, S60.Fs, S60.R0, S60.C, S60.v, S60.tnan, S60.Ta, S60.prf);

    roi = abs(IMG( ...
        S60.nrn / 2 - S60.R_total / 2 + 1 : S60.nrn / 2 + S60.R_total / 2, ...
        S60.nan / 2 - S60.A_num / 2 : S60.nan / 2 + S60.A_num / 2 - 1));

    img_out = normalize_image(roi);
end

% ---- 组合定义 ----

% 生成全部RxAx组合，包含NoUpsample（R1A1）作为通用基线
% NoUpsample只在Q列表第一个Q下出现一次，但数值对所有Q相同
function group_defs = build_all_group_definitions_with_noupsample(Q_list)
    group_defs = struct( ...
        "Q", {}, "Range_q", {}, "Azimuth_q", {}, ...
        "group_name", {}, "group_type", {}, "group_desc", {});

    % 首先加入 NoUpsample（R1A1），它的Q值标记为1（不上采样）
    % 但在结果表中会为每个Q重复列出，方便对照
    noupsample = struct( ...
        "Q", 1, "Range_q", 1, "Azimuth_q", 1, ...
        "group_name", "R1A1_NoUp", "group_type", "no_upsample", ...
        "group_desc", "无上采样基线（1-bit量化+SplitRT，无上采样）");
    group_defs(end + 1) = noupsample;

    % 对每个Q枚举全部整数因子对
    for q_idx = 1:numel(Q_list)
        Q = Q_list(q_idx);
        factor_pairs = factor_pairs_for_q(Q);

        for pair_idx = 1:size(factor_pairs, 1)
            range_q = factor_pairs(pair_idx, 1);
            azimuth_q = factor_pairs(pair_idx, 2);

            [group_type, group_desc] = describe_group(range_q, azimuth_q, Q);

            current = struct( ...
                "Q", Q, "Range_q", range_q, "Azimuth_q", azimuth_q, ...
                "group_name", sprintf("R%dA%d", range_q, azimuth_q), ...
                "group_type", group_type, "group_desc", group_desc);

            group_defs(end + 1) = current;
        end
    end
end

% 返回所有满足 R * A = Q 的有序整数因子对
function factor_pairs = factor_pairs_for_q(Q)
    factor_pairs = zeros(0, 2);
    for range_q = 1:Q
        if mod(Q, range_q) == 0
            azimuth_q = Q / range_q;
            factor_pairs(end + 1, :) = [range_q, azimuth_q];
        end
    end
end

% 根据组合属性给出组类型和中文说明
function [group_type, group_desc] = describe_group(range_q, azimuth_q, Q)
    if range_q == 1 && azimuth_q == 1
        group_type = "no_upsample";
        group_desc = "无上采样基线";
    elseif range_q == 1 && azimuth_q == Q
        group_type = "azimuth_only";
        group_desc = "方位向单方向上采样对照";
    elseif azimuth_q == 1 && range_q == Q
        group_type = "range_only";
        group_desc = "距离向单方向上采样对照";
    elseif range_q == azimuth_q
        group_type = "balanced";
        group_desc = "双向均衡上采样方案";
    else
        group_type = "mixed";
        group_desc = "双向非均衡混合上采样方案";
    end
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

% 距离向频域零填充上采样
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

% 方位向频域零填充上采样
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

% 绘制主结果曲线图：横轴Q，纵轴PSNR/SSIM
function plot_main_result_curves(Q_list, group_defs, psnr_mean, psnr_std, ...
    ssim_mean, ssim_std, output_dir)

    % 颜色定义
    colors = struct( ...
        "no_upsample",   [0.50, 0.50, 0.50], ...  % 灰色
        "range_only",    [0.12, 0.47, 0.71], ...  % 蓝色
        "azimuth_only",  [0.85, 0.33, 0.10], ...  % 橙色
        "balanced",      [0.20, 0.63, 0.17], ...  % 绿色
        "mixed",         [0.49, 0.18, 0.56]);     % 紫色

    % NoUpsample数据（对所有Q相同）
    noupsample_mask = strcmp([group_defs.group_type], "no_upsample");
    noupsample_psnr = psnr_mean(noupsample_mask);
    noupsample_ssim = ssim_mean(noupsample_mask);

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

        figure("Color", "w", "Position", [100, 100, 800, 500]);
        hold on; grid on; box on;

        % 画NoUpsample水平线
        plot(Q_list, noupsample_val * ones(numel(Q_list), 1), ...
            "--", "Color", colors.no_upsample, "LineWidth", 1.5, "DisplayName", "NoUpsample (R1A1)");

        % 画各类曲线
        for q_idx = 1:numel(Q_list)
            Q = Q_list(q_idx);
            group_mask = [group_defs.Q] == Q & ~noupsample_mask;

            current_groups = group_defs(group_mask);
            current_mean = metric_mean(group_mask);

            % 找最佳单向和最佳双向
            unidir_mask_local = strcmp({current_groups.group_type}, "range_only") | ...
                                strcmp({current_groups.group_type}, "azimuth_only");
            bidir_mask_local  = strcmp({current_groups.group_type}, "balanced") | ...
                                strcmp({current_groups.group_type}, "mixed");

            if any(unidir_mask_local)
                best_uni_val = max(current_mean(unidir_mask_local));
                plot(Q, best_uni_val, "o", ...
                    "Color", [0.12, 0.47, 0.71], "MarkerSize", 8, "LineWidth", 1.5, ...
                    "DisplayName", "最佳单向 (Q=" + num2str(Q) + ")");
            end

            if any(bidir_mask_local)
                best_bi_val = max(current_mean(bidir_mask_local));
                plot(Q, best_bi_val, "s", ...
                    "Color", [0.20, 0.63, 0.17], "MarkerSize", 8, "LineWidth", 1.5, ...
                    "DisplayName", "最佳双向 (Q=" + num2str(Q) + ")");
            end
        end

        % 连接最佳单向点
        best_uni_vals = zeros(numel(Q_list), 1);
        best_bi_vals  = zeros(numel(Q_list), 1);
        for q_idx = 1:numel(Q_list)
            Q = Q_list(q_idx);
            group_mask_Q = [group_defs.Q] == Q & ~noupsample_mask;
            current_groups = group_defs(group_mask_Q);
            current_mean = metric_mean(group_mask_Q);

            unidir_mask_local = strcmp({current_groups.group_type}, "range_only") | ...
                                strcmp({current_groups.group_type}, "azimuth_only");
            bidir_mask_local  = strcmp({current_groups.group_type}, "balanced") | ...
                                strcmp({current_groups.group_type}, "mixed");

            best_uni_vals(q_idx) = max(current_mean(unidir_mask_local));
            best_bi_vals(q_idx)  = max(current_mean(bidir_mask_local));
        end

        plot(Q_list, best_uni_vals, "-", "Color", [0.12, 0.47, 0.71], "LineWidth", 1.8, "DisplayName", "最佳单向趋势");
        plot(Q_list, best_bi_vals, "-", "Color", [0.20, 0.63, 0.17], "LineWidth", 1.8, "DisplayName", "最佳双向趋势");

        xlabel("总上采样倍率 Q", "FontSize", 13);
        ylabel(y_label, "FontSize", 13);
        title(sprintf("主结果：四类对照 %s vs Q (As=%.1f, 7数据集×10帧)", tag, 0.6), ...
            "FontSize", 14);

        legend("Location", "best", "FontSize", 10);
        ax = gca; ax.FontSize = 12;

        save_name = sprintf("Exp1_MainResult_%s_curves.png", tag);
        exportgraphics(gcf, fullfile(output_dir, save_name), "Resolution", 240);
        close(gcf);
    end
end
