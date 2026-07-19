clear; clc; close all;

%% =========================================================
%  Exp5：RSFT 二维参数响应图（Fig. 2(a)）
%
%  目标：
%  1) 只研究距离向 RSFT，距离向上采样倍率 R = 2 和 R = 3；
%  2) 初相位固定为 0；
%  3) 根据已有最优参数表自动构造统一的 STR-f0 搜索网格；
%  4) 在 7 个数据集 × 10 个分层样本上计算平均 PSNR / SSIM；
%  5) 输出两个共享色标的 SSIM 热力图，并绘制
%       mean SSIM >= best mean SSIM - 0.002
%     的近最优等高线。
%
%  输出：
%    Exp5_RSFT_ParameterMap_Output/
%      Exp5_RSFT_ParameterMap_Data.mat
%      Exp5_RSFT_ParameterMap_Grid.csv
%      Exp5_RSFT_ParameterMap_Summary.csv
%      Exp5_RSFT_ParameterMap_Metadata.txt
%      Exp5_RSFT_ParameterMap_Checkpoint.mat
%
%  图由 Plot_Exp5_RSFT_ParameterMap.m 独立绘制。
%% =========================================================

%% ==================== 基础参数 ====================
S60 = load("FS60_params.mat");

seed = 2026;
rng(seed);

range_q_list = [2, 3];
initial_phase = 0;                 % 固定相位，避免引入第三个自由变量
near_optimal_delta = 0.002;        % 等高线：SSIM_max - 0.002

best_parameter_csv = "RSFT_BestParameter_q1_2_3_4_5_6_8_9.csv";

% 根据已有最优参数自动构造统一网格
str_step_db = 2;
str_margin_db = 8;
f0_step_over_br = 0.2;
f0_margin_over_br = 0.8;

% 完整实验数据
data_root = "G:\MATLAB-G\SAR Full PSF";
dataset_names = { ...
    "SAR_Dataset_Bangkok_1", ...
    "SAR_Dataset_city1_histeq", ...
    "SAR_Dataset_city2_histeq", ...
    "SAR_Dataset_SAR_figure", ...
    "SAR_Dataset_filed", ...
    "SAR_Dataset_port", ...
    "SAR_Dataset_suburb"
};
num_samples_per_dataset = 10;
total_samples = numel(dataset_names) * num_samples_per_dataset;

output_dir = fullfile(pwd, "Exp5_RSFT_ParameterMap_Output");
ensure_output_dir(output_dir);

checkpoint_path = fullfile(output_dir, "Exp5_RSFT_ParameterMap_Checkpoint.mat");
data_path = fullfile(output_dir, "Exp5_RSFT_ParameterMap_Data.mat");
grid_csv_path = fullfile(output_dir, "Exp5_RSFT_ParameterMap_Grid.csv");
summary_csv_path = fullfile(output_dir, "Exp5_RSFT_ParameterMap_Summary.csv");
metadata_path = fullfile(output_dir, "Exp5_RSFT_ParameterMap_Metadata.txt");

%% ==================== 读取最优参数表 ====================
assert(isfile(best_parameter_csv), ...
    "未找到最优参数表：%s。请将其放在当前工作目录。", best_parameter_csv);

best_table_all = readtable(best_parameter_csv, "TextType", "string");

required_columns = [ ...
    "Q", "Mode", "SelectionMetric", "STRdB", ...
    "F0OverBr", "F0Hz", "SSIM_Mean", "PSNR_Mean"];
assert(all(ismember(required_columns, string(best_table_all.Properties.VariableNames))), ...
    "最优参数表缺少必要列。");

% 仅使用 1D + SSIM 最优行；Q 在本实验中等同于距离向倍率 R。
best_mask = ...
    best_table_all.Mode == "1D" & ...
    best_table_all.SelectionMetric == "SSIM" & ...
    ismember(best_table_all.Q, range_q_list);

best_reference = best_table_all(best_mask, :);
assert(height(best_reference) == numel(range_q_list), ...
    "最优参数表中应恰好包含 R=2 和 R=3 的 1D/SSIM 最优行。");

best_reference = sortrows(best_reference, "Q");
assert(all(best_reference.Q(:).' == range_q_list), ...
    "最优参数表中的 Q 与 range_q_list 不一致。");

reference_STR_dB = best_reference.STRdB(:).';
reference_f0_over_Br = best_reference.F0OverBr(:).';
reference_f0_Hz = best_reference.F0Hz(:).';
reference_SSIM = best_reference.SSIM_Mean(:).';
reference_PSNR = best_reference.PSNR_Mean(:).';

fprintf("=== Exp5 RSFT 参考最优参数（来自 CSV）===\n");
for r_idx = 1:numel(range_q_list)
    fprintf("  R=%d: STR=%.2f dB, f0/Br=%.3f, f0=%.3f MHz, SSIM=%.6f\n", ...
        range_q_list(r_idx), reference_STR_dB(r_idx), ...
        reference_f0_over_Br(r_idx), reference_f0_Hz(r_idx) / 1e6, ...
        reference_SSIM(r_idx));
end

%% ==================== 自动构造统一搜索网格 ====================
str_min = floor((min(reference_STR_dB) - str_margin_db) / str_step_db) * str_step_db;
str_max = ceil((max(reference_STR_dB) + str_margin_db) / str_step_db) * str_step_db;
STR_dB_list = str_min:str_step_db:str_max;

f0_min = max(f0_step_over_br, ...
    floor((min(reference_f0_over_Br) - f0_margin_over_br) / f0_step_over_br) * f0_step_over_br);
f0_max = ceil((max(reference_f0_over_Br) + f0_margin_over_br) / f0_step_over_br) * f0_step_over_br;
f0_over_Br_list = f0_min:f0_step_over_br:f0_max;
f0_Hz_list = f0_over_Br_list * S60.B;

num_R = numel(range_q_list);
num_STR = numel(STR_dB_list);
num_f0 = numel(f0_over_Br_list);

fprintf("\n=== 参数网格 ===\n");
fprintf("  R: %s\n", mat2str(range_q_list));
fprintf("  STR (dB): %s\n", mat2str(STR_dB_list));
fprintf("  f0/Br: %s\n", mat2str(f0_over_Br_list));
fprintf("  总评测次数: %d × %d × %d × %d = %d\n", ...
    num_R, num_STR, num_f0, total_samples, ...
    num_R * num_STR * num_f0 * total_samples);

%% ==================== 构建70样本缓存 ====================
sample_cache = build_sample_cache( ...
    dataset_names, data_root, S60, seed, num_samples_per_dataset);

%% ==================== 预分配 / 断点恢复 ====================
result_size = [num_R, num_STR, num_f0, total_samples];

psnr_all = nan(result_size);
ssim_all = nan(result_size);
sigma_all = nan(num_R, total_samples);
completed_rows = false(num_R, num_STR);

if isfile(checkpoint_path)
    checkpoint = load(checkpoint_path);
    checkpoint_matches = ...
        isfield(checkpoint, "range_q_list") && ...
        isfield(checkpoint, "STR_dB_list") && ...
        isfield(checkpoint, "f0_over_Br_list") && ...
        isequal(checkpoint.range_q_list, range_q_list) && ...
        isequal(checkpoint.STR_dB_list, STR_dB_list) && ...
        isequal(checkpoint.f0_over_Br_list, f0_over_Br_list);

    if checkpoint_matches
        psnr_all = checkpoint.psnr_all;
        ssim_all = checkpoint.ssim_all;
        sigma_all = checkpoint.sigma_all;
        completed_rows = checkpoint.completed_rows;
        fprintf("\n已恢复断点：完成 %d / %d 个 (R, STR) 行。\n", ...
            nnz(completed_rows), numel(completed_rows));
    else
        warning("检测到旧 checkpoint，但参数网格不一致，将从头计算。");
    end
end

%% ==================== 完整参数扫描 ====================
total_timer = tic;

for r_idx = 1:num_R
    range_q = range_q_list(r_idx);
    fprintf("\n===== R=%d (%d/%d) =====\n", range_q, r_idx, num_R);

    % 同一个 R 下，上采样结果和距离时间轴与 STR/f0 无关，只计算一次。
    upsampled_cache = build_upsampled_cache(sample_cache, S60, range_q);

    for s_idx = 1:total_samples
        sigma_all(r_idx, s_idx) = upsampled_cache(s_idx).sigma_hat;
    end

    for str_idx = 1:num_STR
        if completed_rows(r_idx, str_idx)
            fprintf("  跳过已完成 STR=%+.1f dB\n", STR_dB_list(str_idx));
            continue;
        end

        STR_dB = STR_dB_list(str_idx);
        row_timer = tic;
        fprintf("  STR=%+.1f dB (%d/%d)\n", STR_dB, str_idx, num_STR);

        for f_idx = 1:num_f0
            f0_Hz = f0_Hz_list(f_idx);

            for sample_idx = 1:total_samples
                cached = upsampled_cache(sample_idx);
                img_gt = sample_cache(sample_idx).img_gt;

                threshold_amplitude = ...
                    cached.sigma_hat / (10 ^ (STR_dB / 20));

                U = build_rsft_threshold( ...
                    cached.signal_up, cached.fast_time_rel, ...
                    threshold_amplitude, f0_Hz, initial_phase);

                channel_1bit = quantize_1bit_with_U(cached.signal_up, U);

                img_out = focus_range_upsampled_channel( ...
                    channel_1bit, S60, range_q, cached.tnrn_up);

                psnr_all(r_idx, str_idx, f_idx, sample_idx) = ...
                    psnr(img_out, img_gt);
                ssim_all(r_idx, str_idx, f_idx, sample_idx) = ...
                    ssim(img_out, img_gt);
            end
        end

        completed_rows(r_idx, str_idx) = true;

        save(checkpoint_path, ...
            "range_q_list", "STR_dB_list", ...
            "f0_over_Br_list", "f0_Hz_list", ...
            "initial_phase", "near_optimal_delta", ...
            "psnr_all", "ssim_all", "sigma_all", ...
            "completed_rows", "seed", "-v7.3");

        fprintf("    行完成，用时 %.1f s；累计 %.1f min\n", ...
            toc(row_timer), toc(total_timer) / 60);
    end
end

%% ==================== 汇总统计 ====================
psnr_mean = mean(psnr_all, 4, "omitnan");
psnr_std = std(psnr_all, 0, 4, "omitnan");
ssim_mean = mean(ssim_all, 4, "omitnan");
ssim_std = std(ssim_all, 0, 4, "omitnan");

best_STR_dB = nan(num_R, 1);
best_f0_over_Br = nan(num_R, 1);
best_f0_Hz = nan(num_R, 1);
best_SSIM = nan(num_R, 1);
PSNR_at_best_SSIM = nan(num_R, 1);
near_optimal_level = nan(num_R, 1);
near_optimal_mask = false(num_R, num_STR, num_f0);
near_optimal_touches_boundary = false(num_R, 1);

for r_idx = 1:num_R
    surface_ssim = squeeze(ssim_mean(r_idx, :, :));
    [best_SSIM(r_idx), linear_idx] = max(surface_ssim(:));
    [best_str_idx, best_f_idx] = ind2sub(size(surface_ssim), linear_idx);

    best_STR_dB(r_idx) = STR_dB_list(best_str_idx);
    best_f0_over_Br(r_idx) = f0_over_Br_list(best_f_idx);
    best_f0_Hz(r_idx) = f0_Hz_list(best_f_idx);
    PSNR_at_best_SSIM(r_idx) = psnr_mean(r_idx, best_str_idx, best_f_idx);

    near_optimal_level(r_idx) = best_SSIM(r_idx) - near_optimal_delta;
    mask_r = surface_ssim >= near_optimal_level(r_idx);
    near_optimal_mask(r_idx, :, :) = mask_r;

    near_optimal_touches_boundary(r_idx) = ...
        any(mask_r(1, :)) || any(mask_r(end, :)) || ...
        any(mask_r(:, 1)) || any(mask_r(:, end));

    if near_optimal_touches_boundary(r_idx)
        warning("R=%d 的近最优区域触碰搜索边界，建议检查是否需要扩大网格。", ...
            range_q_list(r_idx));
    end
end

%% ==================== 导出 Grid CSV ====================
num_grid_rows = num_R * num_STR * num_f0;

grid_R = zeros(num_grid_rows, 1);
grid_STR_dB = zeros(num_grid_rows, 1);
grid_f0_over_Br = zeros(num_grid_rows, 1);
grid_f0_Hz = zeros(num_grid_rows, 1);
grid_PSNR_mean = zeros(num_grid_rows, 1);
grid_PSNR_std = zeros(num_grid_rows, 1);
grid_SSIM_mean = zeros(num_grid_rows, 1);
grid_SSIM_std = zeros(num_grid_rows, 1);
grid_is_near_optimal = false(num_grid_rows, 1);

row_ptr = 0;
for r_idx = 1:num_R
    for str_idx = 1:num_STR
        for f_idx = 1:num_f0
            row_ptr = row_ptr + 1;
            grid_R(row_ptr) = range_q_list(r_idx);
            grid_STR_dB(row_ptr) = STR_dB_list(str_idx);
            grid_f0_over_Br(row_ptr) = f0_over_Br_list(f_idx);
            grid_f0_Hz(row_ptr) = f0_Hz_list(f_idx);
            grid_PSNR_mean(row_ptr) = psnr_mean(r_idx, str_idx, f_idx);
            grid_PSNR_std(row_ptr) = psnr_std(r_idx, str_idx, f_idx);
            grid_SSIM_mean(row_ptr) = ssim_mean(r_idx, str_idx, f_idx);
            grid_SSIM_std(row_ptr) = ssim_std(r_idx, str_idx, f_idx);
            grid_is_near_optimal(row_ptr) = ...
                near_optimal_mask(r_idx, str_idx, f_idx);
        end
    end
end

grid_table = table( ...
    grid_R, grid_STR_dB, grid_f0_over_Br, grid_f0_Hz, ...
    grid_PSNR_mean, grid_PSNR_std, ...
    grid_SSIM_mean, grid_SSIM_std, grid_is_near_optimal, ...
    "VariableNames", { ...
    "Range_q", "STR_dB", "F0OverBr", "F0Hz", ...
    "PSNR_Mean", "PSNR_Std", ...
    "SSIM_Mean", "SSIM_Std", "IsNearOptimal"});

writetable(grid_table, grid_csv_path);

%% ==================== 导出 Summary CSV ====================
summary_table = table( ...
    range_q_list(:), ...
    best_STR_dB, best_f0_over_Br, best_f0_Hz, ...
    best_SSIM, PSNR_at_best_SSIM, ...
    near_optimal_level, near_optimal_touches_boundary, ...
    reference_STR_dB(:), reference_f0_over_Br(:), ...
    reference_f0_Hz(:), reference_SSIM(:), reference_PSNR(:), ...
    repmat(total_samples, num_R, 1), ...
    repmat(initial_phase, num_R, 1), ...
    "VariableNames", { ...
    "Range_q", ...
    "Best_STR_dB", "Best_F0OverBr", "Best_F0Hz", ...
    "Best_SSIM", "PSNR_AtBestSSIM", ...
    "NearOptimalLevel", "NearOptimalTouchesBoundary", ...
    "Reference_STR_dB", "Reference_F0OverBr", ...
    "Reference_F0Hz", "Reference_SSIM", "Reference_PSNR", ...
    "SampleCount", "InitialPhase"});

writetable(summary_table, summary_csv_path);

%% ==================== 保存完整数据 ====================
sample_manifest = build_sample_manifest(sample_cache);

save(data_path, ...
    "range_q_list", "STR_dB_list", ...
    "f0_over_Br_list", "f0_Hz_list", ...
    "initial_phase", "near_optimal_delta", ...
    "seed", "dataset_names", "num_samples_per_dataset", ...
    "total_samples", "sample_manifest", ...
    "best_reference", ...
    "psnr_all", "ssim_all", "sigma_all", ...
    "psnr_mean", "psnr_std", "ssim_mean", "ssim_std", ...
    "best_STR_dB", "best_f0_over_Br", "best_f0_Hz", ...
    "best_SSIM", "PSNR_at_best_SSIM", ...
    "near_optimal_level", "near_optimal_mask", ...
    "near_optimal_touches_boundary", "-v7.3");

%% ==================== 元数据 ====================
fid = fopen(metadata_path, "w");
assert(fid ~= -1, "无法创建元数据文件：%s", metadata_path);
cleanup_fid = onCleanup(@() fclose(fid));

fprintf(fid, "Experiment=Exp5_RSFT_ParameterMap\n");
fprintf(fid, "Purpose=Fig2a RSFT STR-f0 mean-SSIM maps\n");
fprintf(fid, "Seed=%d\n", seed);
fprintf(fid, "RangeQ=%s\n", mat2str(range_q_list));
fprintf(fid, "InitialPhase=%.16g\n", initial_phase);
fprintf(fid, "NearOptimalDelta=%.16g\n", near_optimal_delta);
fprintf(fid, "STRdBList=%s\n", mat2str(STR_dB_list));
fprintf(fid, "F0OverBrList=%s\n", mat2str(f0_over_Br_list));
fprintf(fid, "BandwidthHz=%.16g\n", S60.B);
fprintf(fid, "SignalScale=sqrt(2/pi)*mean(abs(signal_up(:)))\n");
fprintf(fid, "ThresholdAmplitude=sigma_hat/10^(STR_dB/20)\n");
fprintf(fid, "ThresholdPhase=2*pi*f0*t_fast_relative+initial_phase\n");
fprintf(fid, "ThresholdMode=1D range single-frequency threshold\n");
fprintf(fid, "SampleCount=%d\n", total_samples);
fprintf(fid, "BestParameterCSV=%s\n", best_parameter_csv);

clear cleanup_fid;

fprintf("\n=== Exp5 完成 ===\n");
disp(summary_table);
fprintf("Data: %s\n", data_path);
fprintf("Grid CSV: %s\n", grid_csv_path);
fprintf("Summary CSV: %s\n", summary_csv_path);
fprintf("下一步运行 Plot_Exp5_RSFT_ParameterMap.m 生成 Fig. 2(a)。\n");

%% =========================================================
%% 局部函数
%% =========================================================

function ensure_output_dir(output_dir)
    if ~exist(output_dir, "dir")
        [ok, msg] = mkdir(output_dir);
        if ~ok
            error("无法创建输出目录 %s：%s", output_dir, msg);
        end
    end
end

function sample_cache = build_sample_cache( ...
        dataset_names, data_root, S60, seed, num_samples_per_dataset)

    total_samples = numel(dataset_names) * num_samples_per_dataset;
    sample_cache = repmat(struct( ...
        "dataset_idx", 0, ...
        "sample_idx", 0, ...
        "dataset_name", "", ...
        "filename", "", ...
        "filepath", "", ...
        "c_start", 0, ...
        "signal60_input", [], ...
        "img_gt", []), total_samples, 1);

    global_sample_idx = 0;

    fprintf("\n=== 构建样本缓存：%d 个样本 ===\n", total_samples);

    for ds_idx = 1:numel(dataset_names)
        ds_name = dataset_names{ds_idx};
        ds_folder = fullfile(data_root, ds_name);

        mat_files = dir(fullfile(ds_folder, "rstart*.mat"));
        mat_names = sort({mat_files.name});

        if isempty(mat_names)
            error("数据集 %s 中未找到 rstart*.mat。", ds_name);
        end

        pick_idx = mod(seed, numel(mat_names)) + 1;
        picked_name = mat_names{pick_idx};
        mat_path = fullfile(ds_folder, picked_name);

        loaded_data = load(mat_path);
        var_names = fieldnames(loaded_data);
        raw_data = loaded_data.(var_names{1});

        sample_starts = build_stratified_window_starts( ...
            size(raw_data, 2), S60.nrn, num_samples_per_dataset);

        fprintf("  [%d/%d] %s -> %s\n", ...
            ds_idx, numel(dataset_names), ds_name, picked_name);

        for local_idx = 1:num_samples_per_dataset
            global_sample_idx = global_sample_idx + 1;
            c_start = sample_starts(local_idx);

            channel_block = raw_data(:, c_start:c_start + S60.nrn - 1);
            signal60 = channel_block(1:3:end, :);

            assert(isequal(size(signal60), [S60.nrn, S60.nan]), ...
                "样本尺寸与 S60 参数不一致。");

            sample_cache(global_sample_idx).dataset_idx = ds_idx;
            sample_cache(global_sample_idx).sample_idx = local_idx;
            sample_cache(global_sample_idx).dataset_name = string(ds_name);
            sample_cache(global_sample_idx).filename = string(picked_name);
            sample_cache(global_sample_idx).filepath = string(mat_path);
            sample_cache(global_sample_idx).c_start = c_start;
            sample_cache(global_sample_idx).signal60_input = signal60;
            sample_cache(global_sample_idx).img_gt = ...
                build_gt_image(signal60, S60);
        end
    end
end

function starts = build_stratified_window_starts( ...
        raw_width, window_width, num_samples)

    max_start = raw_width - window_width + 1;
    if max_start < 1
        error("原始序列宽度不足以裁出完整窗口。");
    end

    starts = zeros(num_samples, 1);
    for idx = 1:num_samples
        center_pos = round((idx - 0.5) / num_samples * max_start);
        starts(idx) = min(max(center_pos, 1), max_start);
    end
end

function img_gt = build_gt_image(signal60, S60)
    RC_gt = Range_Compress( ...
        signal60, S60.fc, S60.tnrn, S60.gama, ...
        S60.R0, S60.C, S60.Fs, S60.Tp);

    RCMC_gt = RCMC( ...
        RC_gt, S60.lambda, S60.fnrn, S60.fnan, ...
        S60.R0, S60.C, S60.v);

    IMG_gt = SAR_Imaging( ...
        RCMC_gt, S60.lambda, S60.Fs, S60.R0, ...
        S60.C, S60.v, S60.tnan, S60.Ta, S60.prf);

    roi_gt = extract_roi(IMG_gt, S60);
    img_gt = normalize_image(roi_gt);
end

function upsampled_cache = build_upsampled_cache(sample_cache, S60, range_q)
    total_samples = numel(sample_cache);

    upsampled_cache = repmat(struct( ...
        "signal_up", [], ...
        "tnrn_up", [], ...
        "fast_time_rel", [], ...
        "sigma_hat", NaN), total_samples, 1);

    Fs_up = range_q * S60.Fs;

    fprintf("  预计算 R=%d 的距离向上采样缓存...\n", range_q);

    for sample_idx = 1:total_samples
        signal_up = range_upsample_fft( ...
            sample_cache(sample_idx).signal60_input, range_q);

        nrn_up = size(signal_up, 1);
        tnrn_up = build_range_time_axis(nrn_up, Fs_up, S60);

        % 以网格中心为 t=0，使 initial_phase=0 的含义明确。
        fast_time_rel = ((0:nrn_up - 1).' - floor(nrn_up / 2)) / Fs_up;

        sigma_hat = sqrt(2 / pi) * mean(abs(signal_up(:)));

        upsampled_cache(sample_idx).signal_up = signal_up;
        upsampled_cache(sample_idx).tnrn_up = tnrn_up;
        upsampled_cache(sample_idx).fast_time_rel = fast_time_rel;
        upsampled_cache(sample_idx).sigma_hat = sigma_hat;
    end
end

function tnrn_up = build_range_time_axis(nrn_up, Fs_up, S60)
    Tstart_up = 2 * S60.R0 / S60.C - nrn_up / 2 / Fs_up;
    tnrn_up = Tstart_up + (0:nrn_up - 1).' / Fs_up;
end

function U = build_rsft_threshold( ...
        signal_up, fast_time_rel, threshold_amplitude, ...
        f0_Hz, initial_phase)

    phase = 2 * pi * f0_Hz * fast_time_rel + initial_phase;
    U_column = threshold_amplitude * exp(1i * phase);

    % 1D RSFT：同一距离向阈值序列复制到全部方位脉冲。
    U = repmat(U_column, 1, size(signal_up, 2));
end

function channel_1bit = quantize_1bit_with_U(signal_up, U)
    assert(isequal(size(signal_up), size(U)), ...
        "RSFT 阈值矩阵尺寸与上采样回波不一致。");

    re = ones(size(signal_up), "like", real(signal_up));
    im = ones(size(signal_up), "like", real(signal_up));

    re(real(signal_up) + real(U) < 0) = -1;
    im(imag(signal_up) + imag(U) < 0) = -1;

    channel_1bit = complex(re, im);
end

function img_out = focus_range_upsampled_channel( ...
        channel_1bit, S60, range_q, tnrn_up)

    Fs_up = range_q * S60.Fs;

    RC_up = Range_Compress( ...
        channel_1bit, S60.fc, tnrn_up, S60.gama, ...
        S60.R0, S60.C, Fs_up, S60.Tp);

    RC_crop = crop_range_doppler_to_width(RC_up, S60.nrn);

    RCMC_crop = RCMC( ...
        RC_crop, S60.lambda, S60.fnrn, S60.fnan, ...
        S60.R0, S60.C, S60.v);

    IMG = SAR_Imaging( ...
        RCMC_crop, S60.lambda, S60.Fs, S60.R0, ...
        S60.C, S60.v, S60.tnan, S60.Ta, S60.prf);

    roi = extract_roi(IMG, S60);
    img_out = normalize_image(roi);
end

function roi = extract_roi(IMG, S60)
    row_idx = ...
        S60.nrn / 2 - S60.R_total / 2 + 1 : ...
        S60.nrn / 2 + S60.R_total / 2;

    col_idx = ...
        S60.nan / 2 - S60.A_num / 2 : ...
        S60.nan / 2 + S60.A_num / 2 - 1;

    roi = abs(IMG(row_idx, col_idx));
end

function S_up = range_upsample_fft(S, q)
    [Nr, Na] = size(S);
    Nr_up = round(q * Nr);

    Sf = fftshift(fft(S, [], 1), 1);

    pad_total = Nr_up - Nr;
    pad_top = floor(pad_total / 2);
    pad_bottom = pad_total - pad_top;

    Sf_up = [ ...
        zeros(pad_top, Na, "like", Sf); ...
        Sf; ...
        zeros(pad_bottom, Na, "like", Sf)];

    S_up = ifft(ifftshift(Sf_up, 1), [], 1) * q;
end

function X_crop = crop_range_doppler_to_width(X, target_height)
    [Nr_up, ~] = size(X);

    if target_height > Nr_up
        error("target_height 不能大于当前矩阵高度。");
    end

    Xf = fftshift(fft(X, [], 1), 1);

    center_idx = floor(Nr_up / 2) + 1;
    half_width = floor(target_height / 2);

    if mod(target_height, 2) == 0
        idx = (center_idx - half_width):(center_idx + half_width - 1);
    else
        idx = (center_idx - half_width):(center_idx + half_width);
    end

    X_crop = ifft(ifftshift(Xf(idx, :), 1), [], 1);
end

function y = normalize_image(x)
    magnitude = abs(x);
    peak = max(magnitude(:));

    if peak == 0
        y = magnitude;
    else
        y = magnitude / peak;
    end
end

function manifest = build_sample_manifest(sample_cache)
    count = numel(sample_cache);

    DatasetIndex = zeros(count, 1);
    SampleIndex = zeros(count, 1);
    DatasetName = strings(count, 1);
    Filename = strings(count, 1);
    CStart = zeros(count, 1);

    for idx = 1:count
        DatasetIndex(idx) = sample_cache(idx).dataset_idx;
        SampleIndex(idx) = sample_cache(idx).sample_idx;
        DatasetName(idx) = sample_cache(idx).dataset_name;
        Filename(idx) = sample_cache(idx).filename;
        CStart(idx) = sample_cache(idx).c_start;
    end

    manifest = table( ...
        DatasetIndex, SampleIndex, DatasetName, Filename, CStart);
end
