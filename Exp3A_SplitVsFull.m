clear; clc; close all;

%% =========================================================
%  实验3A：SplitRT vs FullRT 对比实验
%  核心目的：证明双向拆分(SplitRT)优于单向的claim对RT内部
%           构造方式鲁棒——SplitRT ≈ FullRT。
%  代表Q: [4, 6, 9]，均衡双向组: R2A2 / R2A3 / R3A3
%  As扫参: 0:0.1:1.0，7数据集×10帧=70样本
%% =========================================================

%% ==================== 参数区 ====================
S60 = load("FS60_params.mat");
seed = 2026;
rng(seed);

% 代表Q及其均衡双向组
rxax_configs = struct( ...
    "Q", {4, 6, 9}, ...
    "Range_q", {2, 2, 3}, ...
    "Azimuth_q", {2, 3, 3}, ...
    "group_name", {"R2A2", "R2A3", "R3A3"});

% As扫参范围
As_list = 0:0.1:1.0;

% 数据根目录
data_root = "G:\MATLAB-G\SAR Full PSF";

% 7个数据集（与Exp1完全一致）
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

num_configs = numel(rxax_configs);
num_As = numel(As_list);

% 输出目录
output_dir = fullfile(pwd, "Exp3A_SplitVsFull_Output");
if ~exist(output_dir, "dir")
    mkdir(output_dir);
end

%% ==================== 数据集选择 + 样本缓存 ====================
fprintf("=== 数据集选择（与Exp1一致）===\n");
selected_mats = struct("dataset", {}, "folder", {}, "filename", {}, "filepath", {});

for ds_idx = 1:num_datasets
    ds_name = dataset_names{ds_idx};
    ds_folder = fullfile(data_root, ds_name);

    mat_files = dir(fullfile(ds_folder, "rstart*.mat"));
    mat_names = sort({mat_files.name});

    if isempty(mat_names)
        error("数据集 %s 中没有找到 rstart*.mat 文件", ds_name);
    end

    pick_idx = mod(seed, numel(mat_names)) + 1;
    picked_mat = mat_names{pick_idx};

    selected_mats(ds_idx).dataset = ds_name;
    selected_mats(ds_idx).folder = ds_folder;
    selected_mats(ds_idx).filename = picked_mat;
    selected_mats(ds_idx).filepath = fullfile(ds_folder, picked_mat);

    fprintf("  [%02d] %s -> %s (共%d个mat，取第%d个)\n", ...
        ds_idx, ds_name, picked_mat, numel(mat_names), pick_idx);
end

% 构建样本缓存：7数据集 × 10帧 = 70个样本
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

    % 分层抽样10帧（与Exp1完全一致的抽样逻辑）
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

%% ==================== As扫参评测 ====================
fprintf("\n=== 开始As扫参评测: %d配置 × %d As值 × %d样本 = %d次成像 ===\n", ...
    num_configs, num_As, total_samples, num_configs * num_As * total_samples * 2);

% 预分配结果数组：维度为 (配置, As, 样本)
psnr_all_split = zeros(num_configs, num_As, total_samples);
ssim_all_split = zeros(num_configs, num_As, total_samples);
psnr_all_full  = zeros(num_configs, num_As, total_samples);
ssim_all_full  = zeros(num_configs, num_As, total_samples);

for c_idx = 1:num_configs
    cfg = rxax_configs(c_idx);
    fprintf("  配置 %d/%d: %s (Q=%d, R%dA%d)\n", ...
        c_idx, num_configs, cfg.group_name, cfg.Q, cfg.Range_q, cfg.Azimuth_q);

    for as_idx = 1:num_As
        As_val = As_list(as_idx);

        % 每个(配置, As)组合使用固定种子，SplitRT和FullRT共享同一RNG起点
        rng(seed + c_idx * 1000 + as_idx * 10 + 1);

        for s_idx = 1:total_samples
            signal60 = sample_cache(s_idx).signal60_input;
            img_gt = sample_cache(s_idx).img_gt;

            % SplitRT: 用Build_2D_SplitRT生成阈值
            [U_split, ~, ~] = Build_2D_SplitRT(signal60, cfg.Azimuth_q, cfg.Range_q, As_val);
            img_split = build_image_from_U(signal60, S60, cfg.Range_q, cfg.Azimuth_q, U_split);

            % FullRT: 用Build_2D_RT生成阈值
            [U_full, ~, ~] = Build_2D_RT(signal60, cfg.Azimuth_q, cfg.Range_q, As_val);
            img_full = build_image_from_U(signal60, S60, cfg.Range_q, cfg.Azimuth_q, U_full);

            psnr_all_split(c_idx, as_idx, s_idx) = psnr(img_split, img_gt);
            ssim_all_split(c_idx, as_idx, s_idx) = ssim(img_split, img_gt);
            psnr_all_full(c_idx, as_idx, s_idx)  = psnr(img_full, img_gt);
            ssim_all_full(c_idx, as_idx, s_idx)  = ssim(img_full, img_gt);
        end
    end
    fprintf("    配置 %s 完成\n", cfg.group_name);
end

fprintf("评测全部完成。\n");

%% ==================== 汇总统计 ====================
% 沿样本维（第3维）求均值和标准差
psnr_mean_split = mean(psnr_all_split, 3);
psnr_std_split  = std(psnr_all_split, 0, 3);
psnr_mean_full  = mean(psnr_all_full, 3);
psnr_std_full   = std(psnr_all_full, 0, 3);

ssim_mean_split = mean(ssim_all_split, 3);
ssim_std_split  = std(ssim_all_split, 0, 3);
ssim_mean_full  = mean(ssim_all_full, 3);
ssim_std_full   = std(ssim_all_full, 0, 3);

%% ==================== CSV输出 ====================
% 构建汇总表：每行一个(Q, As, RT_Type)组合
num_rows = num_configs * num_As * 2;  % SplitRT + FullRT
csv_Q = zeros(num_rows, 1);
csv_As = zeros(num_rows, 1);
csv_RT_Type = strings(num_rows, 1);
csv_PSNR_Mean = zeros(num_rows, 1);
csv_PSNR_Std  = zeros(num_rows, 1);
csv_SSIM_Mean = zeros(num_rows, 1);
csv_SSIM_Std  = zeros(num_rows, 1);

row_idx = 1;
for c_idx = 1:num_configs
    for as_idx = 1:num_As
        % SplitRT行
        csv_Q(row_idx) = rxax_configs(c_idx).Q;
        csv_As(row_idx) = As_list(as_idx);
        csv_RT_Type(row_idx) = "SplitRT";
        csv_PSNR_Mean(row_idx) = psnr_mean_split(c_idx, as_idx);
        csv_PSNR_Std(row_idx)  = psnr_std_split(c_idx, as_idx);
        csv_SSIM_Mean(row_idx) = ssim_mean_split(c_idx, as_idx);
        csv_SSIM_Std(row_idx)  = ssim_std_split(c_idx, as_idx);
        row_idx = row_idx + 1;

        % FullRT行
        csv_Q(row_idx) = rxax_configs(c_idx).Q;
        csv_As(row_idx) = As_list(as_idx);
        csv_RT_Type(row_idx) = "FullRT";
        csv_PSNR_Mean(row_idx) = psnr_mean_full(c_idx, as_idx);
        csv_PSNR_Std(row_idx)  = psnr_std_full(c_idx, as_idx);
        csv_SSIM_Mean(row_idx) = ssim_mean_full(c_idx, as_idx);
        csv_SSIM_Std(row_idx)  = ssim_std_full(c_idx, as_idx);
        row_idx = row_idx + 1;
    end
end

summary_table = table(csv_Q, csv_As, csv_RT_Type, ...
    csv_PSNR_Mean, csv_PSNR_Std, csv_SSIM_Mean, csv_SSIM_Std, ...
    'VariableNames', {'Q', 'As', 'RT_Type', 'PSNR_Mean', 'PSNR_Std', 'SSIM_Mean', 'SSIM_Std'});

writetable(summary_table, fullfile(output_dir, "Exp3A_SplitVsFull_Summary.csv"));

%% ==================== 保存mat结果 ====================
save(fullfile(output_dir, "Exp3A_SplitVsFull_Data.mat"), ...
    "rxax_configs", "As_list", "seed", "dataset_names", ...
    "num_samples_per_dataset", "total_samples", ...
    "psnr_all_split", "ssim_all_split", ...
    "psnr_all_full",  "ssim_all_full", ...
    "psnr_mean_split", "psnr_std_split", ...
    "psnr_mean_full",  "psnr_std_full", ...
    "ssim_mean_split", "ssim_std_split", ...
    "ssim_mean_full",  "ssim_std_full", ...
    "sample_cache", "selected_mats");

%% ==================== 绘图 ====================
% PSNR-As曲线
plot_as_curves(rxax_configs, As_list, ...
    psnr_mean_split, psnr_mean_full, ...
    "PSNR (dB)", "PSNR", output_dir);

% SSIM-As曲线
plot_as_curves(rxax_configs, As_list, ...
    ssim_mean_split, ssim_mean_full, ...
    "SSIM", "SSIM", output_dir);

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

% 从已有阈值U构建最终图像（内部不含阈值生成）
% pipeline: 上采样 → 量化 → RC → 下采样 → RCMC → Imaging → ROI → normalize
function img_out = build_image_from_U(signal60, S60, range_q, azimuth_q, U)
    % 二维上采样
    signal_up = two_dim_upsample_fft(signal60, azimuth_q, range_q);

    % 构造距离向上采样后的时间轴
    nrn_up = size(signal_up, 1);
    Fs_up  = range_q * S60.Fs;
    Tnrn_up   = 1 / Fs_up;
    Tstart_up = 2 * S60.R0 / S60.C - nrn_up / 2 / Fs_up;
    Tend_up   = 2 * S60.R0 / S60.C + (nrn_up / 2 - 1) / Fs_up;
    tnrn_up   = (Tstart_up : Tnrn_up : Tend_up).';

    % 1-bit量化（U已在上采样后尺寸）
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

% ---- RT阈值与量化 ----

% 生成全随机二维RT阈值场 (FullRT)
% 每个像素独立随机相位，自由度 = Nr_up × Na_up
function [U, sigma, A_rt] = Build_2D_RT(input60, azimuth_q, range_q, As)
    signal_up = two_dim_upsample_fft(input60, azimuth_q, range_q);

    sigma = sqrt(2 / pi) * mean(abs(signal_up(:)));
    A_rt = As * sigma;

    phi = 2 * pi * rand(size(signal_up));
    U = A_rt * exp(1i * phi);
end

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

% ---- 绘图 ----

% 绘制As扫参曲线：每个Q一对SplitRT/FullRT曲线
% data_split和data_full为(num_configs, num_As)矩阵，已沿样本维取均值
function plot_as_curves(rxax_configs, As_list, data_split, data_full, y_label, tag, output_dir)
    figure("Color", "w", "Position", [100, 100, 900, 500]);
    hold on; grid on; box on;

    colors_q = lines(numel(rxax_configs));
    h_leg = [];
    leg_names = {};

    for c_idx = 1:numel(rxax_configs)
        cfg = rxax_configs(c_idx);
        vals_split = data_split(c_idx, :);
        vals_full  = data_full(c_idx, :);

        h1 = plot(As_list, vals_split, "-o", ...
            "Color", colors_q(c_idx, :), "LineWidth", 1.8, "MarkerSize", 6);
        h2 = plot(As_list, vals_full, "--s", ...
            "Color", colors_q(c_idx, :), "LineWidth", 1.8, "MarkerSize", 6);
        h_leg = [h_leg, h1, h2];
        leg_names = [leg_names, {[cfg.group_name + " SplitRT"]}, {[cfg.group_name + " FullRT"]}];
    end

    xlabel("As", "FontSize", 13);
    ylabel(y_label, "FontSize", 13);
    title(sprintf("SplitRT vs FullRT: %s-As曲线 (7数据集×10帧)", tag), "FontSize", 14);
    legend(h_leg, leg_names, "Location", "best", "FontSize", 10);

    ax = gca;
    ax.FontSize = 12;

    save_name = sprintf("Exp3A_SplitVsFull_%s_curves.png", tag);
    exportgraphics(gcf, fullfile(output_dir, save_name), "Resolution", 240);
    close(gcf);
end
