clear; clc; close all;

%% =========================================================
%  实验3B：阈值鲁棒性实验 (ZT / NCT / RT)
%  核心目的：证明双向拆分优于单向的claim不依赖RT构造。
%  ZT和NCT（常数阈值）下双向仍优于单向，RT只是放大优势。
%  3Q × 3方向方案 × 3阈值 + NoUpsample基线 = 28组合
%  7数据集 × 10帧 = 70配对样本
%% =========================================================

%% ==================== 参数区 ====================
S60 = load("FS60_params.mat");

% 固定随机种子，保证数据集选择、抽样可复现
seed = 2026;
rng(seed);

% 总上采样倍率列表（代表Q: 4, 6, 9）
Q_list = [4, 6, 9];

% 每个Q的RxAx配置：[bidir_R, bidir_A; range_R, range_A; azimuth_R, azimuth_A]
rxax_per_q = {
    [2, 2; 4, 1; 1, 4];   % Q=4
    [2, 3; 6, 1; 1, 6];   % Q=6
    [3, 3; 9, 1; 1, 9]    % Q=9
};

% NCT 分位数搜索参数
num_A_nct = 21;
p_min     = 5;
p_max     = 95;

% RT 参数
As_rt = 0.6;

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

% 每个数据集分层抽样帧数
num_samples_per_dataset = 10;
total_samples = num_datasets * num_samples_per_dataset;

% 输出目录
output_dir = fullfile(pwd, "Exp3B_ZT_NCT_RT_Output");
if ~exist(output_dir, "dir")
    mkdir(output_dir);
end

%% ==================== 组合定义 ====================
% 对每个 Q：3个方向方案(bidir/range_only/azimuth_only) × 3种阈值(ZT/NCT/RT) + 1个NoUpsample(ZT)
direction_types = ["bidir", "range_only", "azimuth_only"];
num_directions  = numel(direction_types);

threshold_types_list = ["ZT", "NCT", "RT"];
num_thresholds = numel(threshold_types_list);

num_Q = numel(Q_list);
num_nonoupsample = num_Q * num_directions * num_thresholds;

% 使用 struct 数组存储所有组合定义
group_defs = struct( ...
    "Q", {}, "set_id", {}, ...
    "Range_q", {}, "Azimuth_q", {}, ...
    "group_name", {}, "group_type", {}, ...
    "threshold_type", {});

g_idx = 0;

% 1) 非NoUpsample组合（27个）
for qi = 1:num_Q
    Q_val = Q_list(qi);
    rxax = rxax_per_q{qi};  % 3×2 矩阵: [R,A] per direction

    for di = 1:num_directions
        R_val = rxax(di, 1);
        A_val = rxax(di, 2);
        dir_type = direction_types(di);

        for ti = 1:num_thresholds
            thresh_type = threshold_types_list(ti);

            g_idx = g_idx + 1;
            group_defs(g_idx).Q          = Q_val;
            group_defs(g_idx).set_id     = qi;   % Q=4→1, Q=6→2, Q=9→3
            group_defs(g_idx).Range_q    = R_val;
            group_defs(g_idx).Azimuth_q  = A_val;
            group_defs(g_idx).group_name = sprintf("Q%d_R%dA%d", Q_val, R_val, A_val);
            group_defs(g_idx).group_type = dir_type;
            group_defs(g_idx).threshold_type = thresh_type;
        end
    end
end

% 2) NoUpsample 基线（仅ZT，R1A1，无上采样）
g_idx = g_idx + 1;
group_defs(g_idx).Q          = 1;
group_defs(g_idx).set_id     = 4;  % 特殊set_id=4表示NoUpsample
group_defs(g_idx).Range_q    = 1;
group_defs(g_idx).Azimuth_q  = 1;
group_defs(g_idx).group_name = "NoUpsample";
group_defs(g_idx).group_type = "NoUpsample";
group_defs(g_idx).threshold_type = "ZT";

num_groups = numel(group_defs);

fprintf("=== 共生成 %d 个评测组合 ===\n", num_groups);
for g_i = 1:num_groups
    fprintf("  [%02d] %-20s  type=%s  thresh=%s\n", ...
        g_i, group_defs(g_i).group_name, ...
        group_defs(g_i).group_type, group_defs(g_i).threshold_type);
end

%% ==================== 数据集选择：种子取固定位置 ====================
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

    fprintf("  [%02d] %s -> %s (共%d个mat，取第%d个)\n", ...
        ds_idx, ds_name, picked_mat, numel(mat_names), pick_idx);
end

%% ==================== 构建全部样本缓存 ====================
fprintf("\n=== 构建样本缓存 (共 %d 个数据集 x %d 帧 = %d 个样本) ===\n", ...
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

total_eval_start = tic;

for group_idx = 1:num_groups
    g = group_defs(group_idx);
    fprintf("  [%02d/%02d] %s (Q=%d, type=%s, thresh=%s) ...\n", ...
        group_idx, num_groups, g.group_name, g.Q, ...
        g.group_type, g.threshold_type);

    % 每组独立RNG
    rng(seed + group_idx);

    if string(g.group_type) == "NoUpsample"
        % NoUpsample 基线：仅ZT，无上采样/下采样
        for s_idx = 1:total_samples
            signal60 = sample_cache(s_idx).signal60_input;
            img_gt = sample_cache(s_idx).img_gt;

            img_out = build_noupsample_zt_image(signal60, S60);

            psnr_all(group_idx, s_idx) = psnr(img_out, img_gt);
            ssim_all(group_idx, s_idx) = ssim(img_out, img_gt);
        end
    else
        if string(g.threshold_type) == "NCT"
            % NCT：每个样本独立分位数搜索（需要img_gt）
            for s_idx = 1:total_samples
                signal60 = sample_cache(s_idx).signal60_input;
                img_gt = sample_cache(s_idx).img_gt;

                t_sample = tic;
                fprintf("    NCT搜索 样本 %02d/%02d ... ", s_idx, total_samples);
                img_out = nct_percentile_search(signal60, S60, ...
                    g.Range_q, g.Azimuth_q, img_gt, num_A_nct, p_min, p_max);
                fprintf("完成 (%.1fs)\n", toc(t_sample));

                psnr_all(group_idx, s_idx) = psnr(img_out, img_gt);
                ssim_all(group_idx, s_idx) = ssim(img_out, img_gt);
            end
        else
            % ZT 或 RT
            for s_idx = 1:total_samples
                signal60 = sample_cache(s_idx).signal60_input;
                img_gt = sample_cache(s_idx).img_gt;

                img_out = build_image_threshold(signal60, S60, ...
                    g.Range_q, g.Azimuth_q, g.threshold_type, As_rt);

                psnr_all(group_idx, s_idx) = psnr(img_out, img_gt);
                ssim_all(group_idx, s_idx) = ssim(img_out, img_gt);
            end
        end
    end

    elapsed = toc(total_eval_start);
    fprintf("    完成 (累计 %.1fs)\n", elapsed);
end

fprintf("\n评测全部完成，总耗时 %.1fs\n", toc(total_eval_start));

%% ==================== 统计分析和输出 ====================
% Summary CSV：每个组合的 PSNR/SSIM mean +- std
fprintf("\n=== 生成Summary CSV ===\n");

summary_Q = repmat([group_defs(:).Q]', 1);
summary_set_id = repmat([group_defs(:).set_id]', 1);
summary_Range_q = repmat([group_defs(:).Range_q]', 1);
summary_Azimuth_q = repmat([group_defs(:).Azimuth_q]', 1);
summary_group_name = string({group_defs(:).group_name}');
summary_group_type = string({group_defs(:).group_type}');
summary_threshold_type = string({group_defs(:).threshold_type}');

psnr_mean = mean(psnr_all, 2);
psnr_std  = std(psnr_all, 0, 2);
ssim_mean = mean(ssim_all, 2);
ssim_std  = std(ssim_all, 0, 2);

summary_table = table(summary_Q, summary_set_id, summary_Range_q, summary_Azimuth_q, ...
    summary_group_name, summary_group_type, summary_threshold_type, ...
    psnr_mean, psnr_std, ssim_mean, ssim_std, ...
    'VariableNames', {'Q', 'SetID', 'Range_q', 'Azimuth_q', ...
                      'GroupName', 'GroupType', 'ThresholdType', ...
                      'PSNR_Mean', 'PSNR_Std', 'SSIM_Mean', 'SSIM_Std'});

writetable(summary_table, fullfile(output_dir, "Exp3B_ZT_NCT_RT_Summary.csv"));
fprintf("  Summary CSV 已保存。\n");

%% ==================== 增益表 + Wilcoxon检验 ====================
% 对每个 (set_id, threshold_type)：比较 bidirectional vs 最佳 unidirectional
% set_id: 1=Q4, 2=Q6, 3=Q9, 4=NoUpsample(跳过)
fprintf("\n=== 增益分析 (双向 vs 最佳单向, Wilcoxon signed-rank) ===\n");

gain_rows = struct( ...
    "set_id", {}, "Q", {}, "threshold_type", {}, ...
    "bidir_group_name", {}, "best_uni_group_name", {}, ...
    "bidir_psnr_mean", {}, "best_uni_psnr_mean", {}, ...
    "delta_psnr_mean", {}, "p_value", {}, ...
    "n_samples", {});

% 获取所有group_defs的字段值为方便查询
group_threshold_types = string({group_defs(:).threshold_type}');
group_group_types = string({group_defs(:).group_type}');
group_set_ids = [group_defs(:).set_id]';
group_Qs = [group_defs(:).Q]';
group_names = string({group_defs(:).group_name}');

for si = 1:3  % 仅遍历Q=4/6/9 (set_id=1/2/3)
    for ti = 1:num_thresholds
        thresh_type = threshold_types_list(ti);

        % 找bidir组合
        bidir_mask = (group_set_ids == si) & ...
                     (group_group_types == "bidir") & ...
                     (group_threshold_types == thresh_type);
        bidir_idx = find(bidir_mask, 1);

        % 找range_only和azimuth_only组合
        range_mask = (group_set_ids == si) & ...
                     (group_group_types == "range_only") & ...
                     (group_threshold_types == thresh_type);
        range_idx = find(range_mask, 1);

        azimuth_mask = (group_set_ids == si) & ...
                       (group_group_types == "azimuth_only") & ...
                       (group_threshold_types == thresh_type);
        azimuth_idx = find(azimuth_mask, 1);

        if isempty(bidir_idx) || isempty(range_idx) || isempty(azimuth_idx)
            continue;
        end

        % 双向PSNR向量
        psnr_bidir = psnr_all(bidir_idx, :);
        psnr_range = psnr_all(range_idx, :);
        psnr_azimuth = psnr_all(azimuth_idx, :);

        % 最佳单向：逐样本取PSNR更高者
        psnr_best_uni = max(psnr_range, psnr_azimuth);

        % 增益（逐样本）
        gain_per_sample = psnr_bidir - psnr_best_uni;

        % Wilcoxon signed-rank test
        p_val = signrank(psnr_bidir(:), psnr_best_uni(:));

        % 决定哪个单向更优
        mean_range = mean(psnr_range);
        mean_azimuth = mean(psnr_azimuth);
        if mean_range >= mean_azimuth
            best_uni_type = "range_only";
            best_uni_idx = range_idx;
        else
            best_uni_type = "azimuth_only";
            best_uni_idx = azimuth_idx;
        end

        % 记录
        gr = struct();
        gr.set_id = si;
        gr.Q = group_Qs(bidir_idx);
        gr.threshold_type = thresh_type;
        gr.bidir_group_name = group_names(bidir_idx);
        gr.best_uni_group_name = group_names(best_uni_idx);
        gr.bidir_psnr_mean = mean(psnr_bidir);
        gr.best_uni_psnr_mean = mean(psnr_best_uni);
        gr.delta_psnr_mean = mean(gain_per_sample);
        gr.p_value = p_val;
        gr.n_samples = total_samples;
        gain_rows(end+1) = gr;

        sig_mark = "";
        if p_val < 0.001
            sig_mark = "***";
        elseif p_val < 0.01
            sig_mark = "**";
        elseif p_val < 0.05
            sig_mark = "*";
        end

        fprintf("  Q=%d, %-3s: bidir=%-20s, best_uni=%-20s, delta=%.4f dB, p=%.2e %s\n", ...
            gr.Q, thresh_type, gr.bidir_group_name, ...
            gr.best_uni_group_name, gr.delta_psnr_mean, p_val, sig_mark);
    end
end

% 保存增益表为CSV
num_gain_rows = numel(gain_rows);
gain_Q = repmat([gain_rows(:).Q]', 1);
gain_threshold = string({gain_rows(:).threshold_type}');
gain_bidir_name = string({gain_rows(:).bidir_group_name}');
gain_bestuni_name = string({gain_rows(:).best_uni_group_name}');
gain_bidir_psnr = [gain_rows(:).bidir_psnr_mean]';
gain_bestuni_psnr = [gain_rows(:).best_uni_psnr_mean]';
gain_delta = [gain_rows(:).delta_psnr_mean]';
gain_pval = [gain_rows(:).p_value]';
gain_nsamp = repmat([gain_rows(:).n_samples]', 1);

gain_table = table(gain_Q, gain_threshold, ...
    gain_bidir_name, gain_bestuni_name, ...
    gain_bidir_psnr, gain_bestuni_psnr, gain_delta, gain_pval, gain_nsamp, ...
    'VariableNames', {'Q', 'ThresholdType', ...
                      'BidirGroup', 'BestUniGroup', ...
                      'BidirPSNR_Mean', 'BestUniPSNR_Mean', ...
                      'DeltaPSNR_Mean', 'P_Value', 'N_Samples'});

writetable(gain_table, fullfile(output_dir, "Exp3B_ZT_NCT_RT_Gains.csv"));
fprintf("\n  增益表 CSV 已保存。\n");

%% ==================== 保存mat结果 ====================
fprintf("\n=== 保存Mat结果 ===\n");
save(fullfile(output_dir, "Exp3B_ZT_NCT_RT_Data.mat"), ...
    "group_defs", "Q_list", "rxax_per_q", "seed", ...
    "num_A_nct", "p_min", "p_max", "As_rt", ...
    "dataset_names", "num_samples_per_dataset", "total_samples", ...
    "psnr_all", "ssim_all", ...
    "psnr_mean", "psnr_std", "ssim_mean", "ssim_std", ...
    "gain_rows", ...
    "sample_cache", "selected_mats", "-v7.3");

%% ==================== 绘图 ====================
fprintf("\n=== 生成绘图 ===\n");

% 图1 — 增益对比柱状图（论文核心图）
plot_gain_bars(gain_rows, output_dir);

% 图2 — 绝对值柱状图
plot_absolute_bars(group_defs, psnr_mean, psnr_std, Q_list, threshold_types_list, output_dir);

fprintf("\n全部完成，结果已保存到目录：%s\n", output_dir);


%% =========================================================
%% ==================== 局部函数区 =========================
%% =========================================================

% ===================== 数据集相关 =====================

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

% ===================== 图像构建 =====================

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

% NoUpsample ZT基线：原始分辨率下直接ZT量化 + 标准SAR链
function img_out = build_noupsample_zt_image(signal60, S60)
    % 零阈值1-bit量化（无上采样）
    channel_1bit = quantize_1bit_zero(signal60);

    % 标准SAR处理链（原始分辨率）
    RC   = Range_Compress(channel_1bit, S60.fc, S60.tnrn, S60.gama, S60.R0, S60.C, S60.Fs, S60.Tp);
    RCMC_val = RCMC(RC, S60.lambda, S60.fnrn, S60.fnan, S60.R0, S60.C, S60.v);
    IMG  = SAR_Imaging(RCMC_val, S60.lambda, S60.Fs, S60.R0, S60.C, S60.v, S60.tnan, S60.Ta, S60.prf);

    roi = abs(IMG( ...
        S60.nrn / 2 - S60.R_total / 2 + 1 : S60.nrn / 2 + S60.R_total / 2, ...
        S60.nan / 2 - S60.A_num / 2 : S60.nan / 2 + S60.A_num / 2 - 1));

    img_out = roi / max(roi(:) + eps);
end

% ZT或RT阈值图像构建（上采样→量化→RC→下采样→RCMC→成像）
function img_out = build_image_threshold(signal60, S60, range_q, azimuth_q, threshold_type, As_rt)
    % 二维上采样
    signal_up = two_dim_upsample_fft(signal60, azimuth_q, range_q);

    % 根据阈值类型生成阈值场并量化
    if threshold_type == "ZT"
        channel_1bit = quantize_1bit_zero(signal_up);
    elseif threshold_type == "RT"
        [U, ~, ~] = Build_2D_SplitRT(signal60, azimuth_q, range_q, As_rt);
        channel_1bit = quantize_1bit_with_U(signal_up, U);
    else
        error("build_image_threshold: 未知threshold_type=%s", threshold_type);
    end

    % 构造距离向上采样后的时间轴
    nrn_up = size(signal_up, 1);
    Fs_up  = range_q * S60.Fs;
    Tnrn_up   = 1 / Fs_up;
    Tstart_up = 2 * S60.R0 / S60.C - nrn_up / 2 / Fs_up;
    Tend_up   = 2 * S60.R0 / S60.C + (nrn_up / 2 - 1) / Fs_up;
    tnrn_up   = (Tstart_up : Tnrn_up : Tend_up).';

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

    img_out = roi / max(roi(:) + eps);
end

% ===================== NCT分位数搜索 =====================

function img_out = nct_percentile_search(signal60, S60, range_q, azimuth_q, img_gt, num_A, p_min, p_max)
    % 上采样信号用于计算参考幅值分布
    signal_up = two_dim_upsample_fft(signal60, azimuth_q, range_q);
    ref_mag = abs(signal_up(:));

    % 分位数对应的A值列表，去重（保留稳定顺序）
    p_list = linspace(p_min, p_max, num_A);
    A_list = prctile(ref_mag, p_list);
    [A_list, uniq_idx] = unique(double(A_list(:).'), "stable");

    % 构建上采样后的RC参数
    nrn_up = size(signal_up, 1);
    Fs_up  = range_q * S60.Fs;
    Tnrn_up   = 1 / Fs_up;
    Tstart_up = 2 * S60.R0 / S60.C - nrn_up / 2 / Fs_up;
    Tend_up   = 2 * S60.R0 / S60.C + (nrn_up / 2 - 1) / Fs_up;
    tnrn_up   = (Tstart_up : Tnrn_up : Tend_up).';

    best_psnr_val = -inf;
    best_img = [];

    for iA = 1:numel(A_list)
        A_nct = A_list(iA);

        % NCT量化（psi=0，全场均匀常数阈值）
        channel_nct = quantize_1bit_nct(signal_up, A_nct, 0);

        % 标准SAR处理链
        RC = Range_Compress(channel_nct, S60.fc, tnrn_up, S60.gama, S60.R0, S60.C, Fs_up, S60.Tp);
        RC_crop = two_dim_downsample_fft(RC, azimuth_q, range_q, S60);
        RCMC_crop = RCMC(RC_crop, S60.lambda, S60.fnrn, S60.fnan, S60.R0, S60.C, S60.v);
        IMG = SAR_Imaging(RCMC_crop, S60.lambda, S60.Fs, S60.R0, S60.C, S60.v, S60.tnan, S60.Ta, S60.prf);

        roi = abs(IMG( ...
            S60.nrn / 2 - S60.R_total / 2 + 1 : S60.nrn / 2 + S60.R_total / 2, ...
            S60.nan / 2 - S60.A_num / 2 : S60.nan / 2 + S60.A_num / 2 - 1));

        roi = roi / max(roi(:) + eps);

        cur_psnr_val = psnr(roi, img_gt);
        if cur_psnr_val > best_psnr_val
            best_psnr_val = cur_psnr_val;
            best_img = roi;
        end
    end

    img_out = best_img;
end

% ===================== RT阈值构造与量化 =====================

% 生成可分离的二维RT阈值场 (SplitRT)
% 相位分解为距离向列相位 + 方位向行相位，自由度 = Nr_up + Na_up
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

% ===================== 零阈值与常数阈值量化 =====================

% ZT: 零阈值1-bit量化（直接取符号）
function S1 = quantize_1bit_zero(S)
    re = ones(size(S), "like", real(S));
    im = ones(size(S), "like", real(S));

    re(real(S) < 0) = -1;
    im(imag(S) < 0) = -1;

    S1 = complex(re, im);
end

% NCT: 非减法常数阈值1-bit量化
% u = A * exp(1i * psi)，加在信号上再取符号
function S1 = quantize_1bit_nct(S, A, psi)
    u = A * exp(1i * psi);
    ur = real(u);
    ui = imag(u);

    re = ones(size(S), "like", real(S));
    im = ones(size(S), "like", real(S));

    re(real(S) + ur < 0) = -1;
    im(imag(S) + ui < 0) = -1;

    S1 = complex(re, im);
end

% ===================== 上采样 / 下采样 =====================

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

% ===================== 图像归一化 =====================

% 归一化图像到[0,1]
function y = normalize_image(x)
    mag = abs(x);
    peak = max(mag(:));
    if peak == 0
        y = mag;
    else
        y = mag / peak;
    end
end

% ===================== 绘图函数 =====================

% 图1 — 增益对比柱状图
% 横轴：阈值类型（ZT / NCT / RT），纵轴：Delta PSNR（双向 - 最佳单向）
% 每组3个柱子（Q=4/6/9），不同颜色
function plot_gain_bars(gain_rows, output_dir)
    figure("Color", "w", "Position", [100, 100, 900, 550]);
    hold on; grid on; box on;

    % gain_rows 有9行：3 set_id × 3 threshold_type
    % 提取数据
    gain_set_ids = [gain_rows(:).set_id]';
    gain_thresh = string({gain_rows(:).threshold_type}');
    gain_delta = [gain_rows(:).delta_psnr_mean]';
    gain_pval = [gain_rows(:).p_value]';

    % 阈值类型顺序
    thresh_order = ["ZT", "NCT", "RT"];
    num_thresh = numel(thresh_order);
    num_sets = 3;  % Q=4,6,9

    % 按阈值分组，每组内3个Q的柱子
    bar_data = zeros(num_sets, num_thresh);
    pval_data = strings(num_sets, num_thresh);

    for ti = 1:num_thresh
        for si = 1:num_sets
            mask = (gain_set_ids == si) & (gain_thresh == thresh_order(ti));
            if any(mask)
                bar_data(si, ti) = gain_delta(mask);
                pv = gain_pval(mask);
                if pv < 0.001
                    pval_data(si, ti) = "***";
                elseif pv < 0.01
                    pval_data(si, ti) = "**";
                elseif pv < 0.05
                    pval_data(si, ti) = "*";
                else
                    pval_data(si, ti) = sprintf("p=%.2f", pv);
                end
            end
        end
    end

    % 绘制分组柱状图
    x_centers = 1:num_thresh;
    bar_width = 0.22;
    offsets = [-1, 0, 1] * bar_width;

    colors_q = lines(num_sets);

    b_handles = zeros(num_sets, 1);
    leg_labels = strings(num_sets, 1);
    Q_labels = [4, 6, 9];

    for si = 1:num_sets
        b_handles(si) = bar(x_centers + offsets(si), bar_data(si, :), ...
            bar_width, "FaceColor", colors_q(si, :), ...
            "DisplayName", sprintf("Q=%d", Q_labels(si)));
        leg_labels(si) = sprintf("Q=%d", Q_labels(si));
    end

    % 在柱子上方标注显著性
    y_max = max(bar_data(:));
    y_min = min(bar_data(:));
    y_range = y_max - y_min;
    if y_range == 0
        y_range = 1;
    end
    for ti = 1:num_thresh
        for si = 1:num_sets
            x_pos = x_centers(ti) + offsets(si);
            y_pos = bar_data(si, ti);
            if y_pos >= 0
                text_y = y_pos + 0.03 * y_range;
            else
                text_y = y_pos - 0.08 * y_range;
            end
            text(x_pos, text_y, pval_data(si, ti), ...
                "HorizontalAlignment", "center", "FontSize", 9, ...
                "FontWeight", "bold", "Color", colors_q(si, :));
        end
    end

    % y=0 参考线
    yline(0, "k--", "LineWidth", 1.2);

    set(gca, "XTick", x_centers, "XTickLabel", thresh_order);
    xlabel("Threshold Type", "FontSize", 13);
    ylabel("\Delta PSNR (Bidir - Best Uni) [dB]", "FontSize", 13);
    title("Gain Robustness Across Threshold Types (70 paired samples)", "FontSize", 14);
    legend(b_handles, leg_labels, "Location", "best", "FontSize", 11);
    ax = gca;
    ax.FontSize = 12;

    save_name = "Exp3B_GainBars.png";
    exportgraphics(gcf, fullfile(output_dir, save_name), "Resolution", 240);
    close(gcf);
    fprintf("  图1 (增益柱状图) 已保存: %s\n", fullfile(output_dir, save_name));
end

% 图2 — 绝对值柱状图
% 每个Q下，三类阈值的双向/最佳单向PSNR柱状并排
function plot_absolute_bars(group_defs, psnr_mean, psnr_std, Q_list, threshold_types_list, output_dir)
    figure("Color", "w", "Position", [100, 100, 1200, 550]);
    hold on; grid on; box on;

    num_Q = numel(Q_list);
    num_thresh = numel(threshold_types_list);

    group_set_ids = [group_defs(:).set_id]';
    group_thresh = string({group_defs(:).threshold_type}');
    group_types = string({group_defs(:).group_type}');

    for qi = 1:num_Q
        subplot(1, num_Q, qi);
        hold on; grid on; box on;

        Q_val = Q_list(qi);
        si = qi;  % set_id = qi

        % 每个阈值类型一组柱子：[bidir, best_uni] 及其误差
        x_centers = 1:num_thresh;
        bar_width = 0.35;
        bar_data_bidir = zeros(1, num_thresh);
        bar_data_bestuni = zeros(1, num_thresh);
        bar_std_bidir = zeros(1, num_thresh);
        bar_std_bestuni = zeros(1, num_thresh);

        for ti = 1:num_thresh
            thresh_type = threshold_types_list(ti);

            % 找bidir
            bidir_mask = (group_set_ids == si) & ...
                         (group_thresh == thresh_type) & ...
                         (group_types == "bidir");
            bidir_idx = find(bidir_mask, 1);

            % 找range和azimuth
            range_mask = (group_set_ids == si) & ...
                         (group_thresh == thresh_type) & ...
                         (group_types == "range_only");
            range_idx = find(range_mask, 1);

            az_mask = (group_set_ids == si) & ...
                      (group_thresh == thresh_type) & ...
                      (group_types == "azimuth_only");
            az_idx = find(az_mask, 1);

            if ~isempty(bidir_idx)
                bar_data_bidir(ti) = psnr_mean(bidir_idx);
                bar_std_bidir(ti) = psnr_std(bidir_idx);
            end
            if ~isempty(range_idx) && ~isempty(az_idx)
                % 最佳单向：取PSNR更高者
                if psnr_mean(range_idx) >= psnr_mean(az_idx)
                    bar_data_bestuni(ti) = psnr_mean(range_idx);
                    bar_std_bestuni(ti) = psnr_std(range_idx);
                else
                    bar_data_bestuni(ti) = psnr_mean(az_idx);
                    bar_std_bestuni(ti) = psnr_std(az_idx);
                end
            end
        end

        b1 = bar(x_centers - bar_width/2, bar_data_bidir, bar_width, ...
            "FaceColor", [0.3, 0.6, 1.0], "DisplayName", "Bidir");
        b2 = bar(x_centers + bar_width/2, bar_data_bestuni, bar_width, ...
            "FaceColor", [1.0, 0.5, 0.3], "DisplayName", "Best Uni");

        % 误差线
        errorbar(x_centers - bar_width/2, bar_data_bidir, bar_std_bidir, ...
            "k", "LineStyle", "none", "LineWidth", 1, "HandleVisibility", "off");
        errorbar(x_centers + bar_width/2, bar_data_bestuni, bar_std_bestuni, ...
            "k", "LineStyle", "none", "LineWidth", 1, "HandleVisibility", "off");

        set(gca, "XTick", x_centers, "XTickLabel", threshold_types_list);
        xlabel("Threshold Type", "FontSize", 11);
        ylabel("PSNR (dB)", "FontSize", 11);
        title(sprintf("Q = %d", Q_val), "FontSize", 12);

        if qi == 1
            legend([b1, b2], "Location", "best", "FontSize", 9);
        end

        ax = gca;
        ax.FontSize = 10;
    end

    sgtitle("Absolute PSNR by Threshold Type and Direction Scheme (70 paired samples)", ...
        "FontSize", 14, "FontWeight", "bold");

    save_name = "Exp3B_AbsoluteBars.png";
    exportgraphics(gcf, fullfile(output_dir, save_name), "Resolution", 240);
    close(gcf);
    fprintf("  图2 (绝对值柱状图) 已保存: %s\n", fullfile(output_dir, save_name));
end
