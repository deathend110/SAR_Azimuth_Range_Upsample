clear; clc; close all;

%% =========================================================
%  实验4B：不同Q下NCT与SplitRT阈值幅度曲线
%  输出：NCT/RT分别对应PSNR与SSIM四张多Q曲线图
%% =========================================================

S60 = load("FS60_params.mat");
seed = 2026;
rng(seed);

rxax_configs = struct( ...
    "Q", {4, 6, 9}, ...
    "Range_q", {2, 2, 3}, ...
    "Azimuth_q", {2, 3, 3}, ...
    "group_name", {"R2A2", "R2A3", "R3A3"});
As_list = 0:0.1:1.5;

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

output_dir = fullfile(pwd, "Exp4B_ThresholdAs_ByQ_Output");
if ~exist(output_dir, "dir")
    mkdir(output_dir);
end

sample_cache = build_sample_cache(dataset_names, data_root, S60, seed, num_samples_per_dataset);
num_configs = numel(rxax_configs);
num_As = numel(As_list);

psnr_all_nct = zeros(num_configs, num_As, total_samples);
ssim_all_nct = zeros(num_configs, num_As, total_samples);
psnr_all_rt  = zeros(num_configs, num_As, total_samples);
ssim_all_rt  = zeros(num_configs, num_As, total_samples);

fprintf("=== Exp4B: %d configs, %d As values, %d samples ===\n", num_configs, num_As, total_samples);
for c_idx = 1:num_configs
    cfg = rxax_configs(c_idx);
    fprintf("  Config %d/%d: Q=%d/%s\n", c_idx, num_configs, cfg.Q, cfg.group_name);

    for as_idx = 1:num_As
        As_val = As_list(as_idx);
        fprintf("    As %.1f (%d/%d)\n", As_val, as_idx, num_As);
        rng(seed + c_idx * 1000 + as_idx * 10);

        for s_idx = 1:total_samples
            signal60 = sample_cache(s_idx).signal60_input;
            img_gt = sample_cache(s_idx).img_gt;

            img_nct = build_image_nct(signal60, S60, cfg.Range_q, cfg.Azimuth_q, As_val);
            img_rt = build_image_splitrt(signal60, S60, cfg.Range_q, cfg.Azimuth_q, As_val);

            psnr_all_nct(c_idx, as_idx, s_idx) = psnr(img_nct, img_gt);
            ssim_all_nct(c_idx, as_idx, s_idx) = ssim(img_nct, img_gt);
            psnr_all_rt(c_idx, as_idx, s_idx)  = psnr(img_rt, img_gt);
            ssim_all_rt(c_idx, as_idx, s_idx)  = ssim(img_rt, img_gt);
        end
    end
end

psnr_mean_nct = mean(psnr_all_nct, 3);
psnr_std_nct  = std(psnr_all_nct, 0, 3);
ssim_mean_nct = mean(ssim_all_nct, 3);
ssim_std_nct  = std(ssim_all_nct, 0, 3);
psnr_mean_rt  = mean(psnr_all_rt, 3);
psnr_std_rt   = std(psnr_all_rt, 0, 3);
ssim_mean_rt  = mean(ssim_all_rt, 3);
ssim_std_rt   = std(ssim_all_rt, 0, 3);

summary_table = build_summary_table(rxax_configs, As_list, ...
    psnr_mean_nct, psnr_std_nct, ssim_mean_nct, ssim_std_nct, ...
    psnr_mean_rt, psnr_std_rt, ssim_mean_rt, ssim_std_rt, total_samples);
writetable(summary_table, fullfile(output_dir, "Exp4B_ThresholdAs_ByQ_Summary.csv"));

save(fullfile(output_dir, "Exp4B_ThresholdAs_ByQ_Data.mat"), ...
    "rxax_configs", "As_list", "seed", "dataset_names", "num_samples_per_dataset", ...
    "total_samples", "psnr_all_nct", "ssim_all_nct", "psnr_all_rt", "ssim_all_rt", ...
    "psnr_mean_nct", "psnr_std_nct", "ssim_mean_nct", "ssim_std_nct", ...
    "psnr_mean_rt", "psnr_std_rt", "ssim_mean_rt", "ssim_std_rt", "sample_cache", "-v7.3");

plot_multi_q_curve(rxax_configs, As_list, psnr_mean_nct, psnr_std_nct, "PSNR (dB)", "NCT", "PSNR", output_dir);
plot_multi_q_curve(rxax_configs, As_list, ssim_mean_nct, ssim_std_nct, "SSIM", "NCT", "SSIM", output_dir);
plot_multi_q_curve(rxax_configs, As_list, psnr_mean_rt, psnr_std_rt, "PSNR (dB)", "SplitRT", "PSNR", output_dir);
plot_multi_q_curve(rxax_configs, As_list, ssim_mean_rt, ssim_std_rt, "SSIM", "SplitRT", "SSIM", output_dir);

fprintf("Exp4B完成，结果已保存到：%s\n", output_dir);

function summary_table = build_summary_table(rxax_configs, As_list, psnr_mean_nct, psnr_std_nct, ssim_mean_nct, ssim_std_nct, psnr_mean_rt, psnr_std_rt, ssim_mean_rt, ssim_std_rt, total_samples)
    num_configs = numel(rxax_configs);
    num_As = numel(As_list);
    num_rows = num_configs * num_As * 2;

    csv_Q = zeros(num_rows, 1);
    csv_R = zeros(num_rows, 1);
    csv_A = zeros(num_rows, 1);
    csv_group = strings(num_rows, 1);
    csv_threshold = strings(num_rows, 1);
    csv_As = zeros(num_rows, 1);
    csv_psnr_mean = zeros(num_rows, 1);
    csv_psnr_std = zeros(num_rows, 1);
    csv_ssim_mean = zeros(num_rows, 1);
    csv_ssim_std = zeros(num_rows, 1);

    row_idx = 1;
    for c_idx = 1:num_configs
        cfg = rxax_configs(c_idx);
        for as_idx = 1:num_As
            csv_Q(row_idx) = cfg.Q;
            csv_R(row_idx) = cfg.Range_q;
            csv_A(row_idx) = cfg.Azimuth_q;
            csv_group(row_idx) = cfg.group_name;
            csv_threshold(row_idx) = "NCT";
            csv_As(row_idx) = As_list(as_idx);
            csv_psnr_mean(row_idx) = psnr_mean_nct(c_idx, as_idx);
            csv_psnr_std(row_idx) = psnr_std_nct(c_idx, as_idx);
            csv_ssim_mean(row_idx) = ssim_mean_nct(c_idx, as_idx);
            csv_ssim_std(row_idx) = ssim_std_nct(c_idx, as_idx);
            row_idx = row_idx + 1;

            csv_Q(row_idx) = cfg.Q;
            csv_R(row_idx) = cfg.Range_q;
            csv_A(row_idx) = cfg.Azimuth_q;
            csv_group(row_idx) = cfg.group_name;
            csv_threshold(row_idx) = "SplitRT";
            csv_As(row_idx) = As_list(as_idx);
            csv_psnr_mean(row_idx) = psnr_mean_rt(c_idx, as_idx);
            csv_psnr_std(row_idx) = psnr_std_rt(c_idx, as_idx);
            csv_ssim_mean(row_idx) = ssim_mean_rt(c_idx, as_idx);
            csv_ssim_std(row_idx) = ssim_std_rt(c_idx, as_idx);
            row_idx = row_idx + 1;
        end
    end

    summary_table = table(csv_Q, csv_R, csv_A, csv_group, csv_threshold, csv_As, ...
        csv_psnr_mean, csv_psnr_std, csv_ssim_mean, csv_ssim_std, ...
        repmat(total_samples, num_rows, 1), ...
        'VariableNames', {'Q', 'Range_q', 'Azimuth_q', 'GroupName', 'ThresholdType', ...
                          'As', 'PSNR_Mean', 'PSNR_Std', 'SSIM_Mean', 'SSIM_Std', 'SampleCount'});
end

function sample_cache = build_sample_cache(dataset_names, data_root, S60, seed, num_samples_per_dataset)
    total_samples = numel(dataset_names) * num_samples_per_dataset;
    sample_cache = repmat(struct("dataset_idx", 0, "sample_idx", 0, "dataset_name", "", ...
        "c_start", 0, "signal60_input", [], "img_gt", []), total_samples, 1);

    global_sample_idx = 0;
    for ds_idx = 1:numel(dataset_names)
        ds_name = dataset_names{ds_idx};
        ds_folder = fullfile(data_root, ds_name);
        mat_files = dir(fullfile(ds_folder, "rstart*.mat"));
        mat_names = sort({mat_files.name});
        if isempty(mat_names)
            error("数据集 %s 中没有找到 rstart*.mat 文件", ds_name);
        end

        pick_idx = mod(seed, numel(mat_names)) + 1;
        mat_path = fullfile(ds_folder, mat_names{pick_idx});
        loaded_data = load(mat_path);
        var_names = fieldnames(loaded_data);
        raw_data = loaded_data.(var_names{1});
        sample_starts = build_stratified_window_starts(size(raw_data, 2), S60.nrn, num_samples_per_dataset);

        for s_idx = 1:num_samples_per_dataset
            global_sample_idx = global_sample_idx + 1;
            c_start = sample_starts(s_idx);
            channel_block = raw_data(:, c_start:c_start + S60.nrn - 1);
            signal60 = channel_block(1:3:end, :);

            sample_cache(global_sample_idx).dataset_idx = ds_idx;
            sample_cache(global_sample_idx).sample_idx = s_idx;
            sample_cache(global_sample_idx).dataset_name = ds_name;
            sample_cache(global_sample_idx).c_start = c_start;
            sample_cache(global_sample_idx).signal60_input = signal60;
            sample_cache(global_sample_idx).img_gt = build_gt_image(signal60, S60);
        end
    end
end

function sample_starts = build_stratified_window_starts(raw_width, window_width, num_samples)
    max_start = raw_width - window_width + 1;
    if max_start < 1
        error("序列宽度不足以裁出完整窗口。");
    end
    sample_starts = zeros(num_samples, 1);
    for s_idx = 1:num_samples
        center_pos = round((s_idx - 0.5) / num_samples * max_start);
        sample_starts(s_idx) = min(max(center_pos, 1), max_start);
    end
end

function img_gt = build_gt_image(signal60, S60)
    RC_gt = Range_Compress(signal60, S60.fc, S60.tnrn, S60.gama, S60.R0, S60.C, S60.Fs, S60.Tp);
    RCMC_gt = RCMC(RC_gt, S60.lambda, S60.fnrn, S60.fnan, S60.R0, S60.C, S60.v);
    IMG_gt = SAR_Imaging(RCMC_gt, S60.lambda, S60.Fs, S60.R0, S60.C, S60.v, S60.tnan, S60.Ta, S60.prf);
    roi_gt = abs(IMG_gt( ...
        S60.nrn / 2 - S60.R_total / 2 + 1 : S60.nrn / 2 + S60.R_total / 2, ...
        S60.nan / 2 - S60.A_num / 2 : S60.nan / 2 + S60.A_num / 2 - 1));
    img_gt = normalize_image(roi_gt);
end

function img_out = build_image_nct(signal60, S60, range_q, azimuth_q, As)
    signal_up = two_dim_upsample_fft(signal60, azimuth_q, range_q);
    sigma = sqrt(2 / pi) * mean(abs(signal_up(:)));
    channel_1bit = quantize_1bit_nct(signal_up, As * sigma, 0);
    img_out = focus_upsampled_channel(channel_1bit, S60, range_q, azimuth_q);
end

function img_out = build_image_splitrt(signal60, S60, range_q, azimuth_q, As)
    signal_up = two_dim_upsample_fft(signal60, azimuth_q, range_q);
    [U, ~, ~] = Build_2D_SplitRT_from_up(signal_up, As);
    channel_1bit = quantize_1bit_with_U(signal_up, U);
    img_out = focus_upsampled_channel(channel_1bit, S60, range_q, azimuth_q);
end

function img_out = focus_upsampled_channel(channel_1bit, S60, range_q, azimuth_q)
    nrn_up = size(channel_1bit, 1);
    Fs_up = range_q * S60.Fs;
    Tnrn_up = 1 / Fs_up;
    Tstart_up = 2 * S60.R0 / S60.C - nrn_up / 2 / Fs_up;
    Tend_up = 2 * S60.R0 / S60.C + (nrn_up / 2 - 1) / Fs_up;
    tnrn_up = (Tstart_up:Tnrn_up:Tend_up).';

    RC = Range_Compress(channel_1bit, S60.fc, tnrn_up, S60.gama, S60.R0, S60.C, Fs_up, S60.Tp);
    RC_crop = two_dim_downsample_fft(RC, azimuth_q, range_q, S60);
    RCMC_crop = RCMC(RC_crop, S60.lambda, S60.fnrn, S60.fnan, S60.R0, S60.C, S60.v);
    IMG = SAR_Imaging(RCMC_crop, S60.lambda, S60.Fs, S60.R0, S60.C, S60.v, S60.tnan, S60.Ta, S60.prf);
    roi = abs(IMG( ...
        S60.nrn / 2 - S60.R_total / 2 + 1 : S60.nrn / 2 + S60.R_total / 2, ...
        S60.nan / 2 - S60.A_num / 2 : S60.nan / 2 + S60.A_num / 2 - 1));
    img_out = normalize_image(roi);
end

function [U, sigma, A_rt] = Build_2D_SplitRT_from_up(signal_up, As)
    [Nr_up, Na_up] = size(signal_up);
    phi_r = 2 * pi * rand(Nr_up, 1);
    phi_a = 2 * pi * rand(1, Na_up);
    sigma = sqrt(2 / pi) * mean(abs(signal_up(:)));
    A_rt = As * sigma;
    U = A_rt * exp(1i * (phi_r + phi_a));
end

function S1 = quantize_1bit_with_U(S, U)
    re = ones(size(S), "like", real(S));
    im = ones(size(S), "like", real(S));
    re(real(S) + real(U) < 0) = -1;
    im(imag(S) + imag(U) < 0) = -1;
    S1 = complex(re, im);
end

function S1 = quantize_1bit_nct(S, A, psi)
    u = A * exp(1i * psi);
    re = ones(size(S), "like", real(S));
    im = ones(size(S), "like", real(S));
    re(real(S) + real(u) < 0) = -1;
    im(imag(S) + imag(u) < 0) = -1;
    S1 = complex(re, im);
end

function S_up = two_dim_upsample_fft(S, q_azimuth, q_range)
    S_up = S;
    if q_range > 1
        S_up = range_upsample_fft(S_up, q_range);
    end
    if q_azimuth > 1
        S_up = azimuth_upsample_fft(S_up, q_azimuth);
    end
end

function S_down = two_dim_downsample_fft(S, q_azimuth, q_range, meta)
    S_down = S;
    if q_azimuth > 1
        S_down = crop_azimuth_doppler_to_width(S_down, meta.nan);
    end
    if q_range > 1
        S_down = crop_range_doppler_to_width(S_down, meta.nrn);
    end
end

function S_up = range_upsample_fft(S, q)
    [Nr, Na] = size(S);
    Nr_up = round(q * Nr);
    Sf = fftshift(fft(S, [], 1), 1);
    pad_total = Nr_up - Nr;
    pad_top = floor(pad_total / 2);
    pad_bottom = pad_total - pad_top;
    Sf_up = [zeros(pad_top, Na, "like", Sf); Sf; zeros(pad_bottom, Na, "like", Sf)];
    S_up = ifft(ifftshift(Sf_up, 1), [], 1) * q;
end

function S_up = azimuth_upsample_fft(S, q)
    [Nr, Na] = size(S);
    Na_up = round(q * Na);
    Sf = fftshift(fft(S, [], 2), 2);
    pad_total = Na_up - Na;
    pad_left = floor(pad_total / 2);
    pad_right = pad_total - pad_left;
    Sf_up = [zeros(Nr, pad_left, "like", Sf), Sf, zeros(Nr, pad_right, "like", Sf)];
    S_up = ifft(ifftshift(Sf_up, 2), [], 2) * q;
end

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
    X_crop = ifft(ifftshift(Xf(idx, :), 1), [], 1);
end

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
    X_crop = ifft(ifftshift(Xf(:, idx), 2), [], 2);
end

function y = normalize_image(x)
    mag = abs(x);
    peak = max(mag(:));
    if peak == 0
        y = mag;
    else
        y = mag / peak;
    end
end

function plot_multi_q_curve(rxax_configs, As_list, metric_mean, metric_std, y_label, threshold_name, metric_tag, output_dir)
    figure("Color", "w", "Position", [100, 100, 900, 500]);
    hold on; grid on; box on;
    colors_q = lines(numel(rxax_configs));
    h_leg = gobjects(1, numel(rxax_configs));
    leg_names = strings(1, numel(rxax_configs));

    for c_idx = 1:numel(rxax_configs)
        cfg = rxax_configs(c_idx);
        h_leg(c_idx) = errorbar(As_list, metric_mean(c_idx, :), metric_std(c_idx, :), "-o", ...
            "Color", colors_q(c_idx, :), "LineWidth", 1.8, "MarkerSize", 6, "CapSize", 7);
        leg_names(c_idx) = sprintf("%s %s", cfg.group_name, threshold_name);
    end

    xlabel("As", "FontSize", 13);
    ylabel(y_label, "FontSize", 13);
    title(sprintf("%s: %s-As curves (7 datasets x 10 samples)", threshold_name, metric_tag), "FontSize", 14);
    legend(h_leg, leg_names, "Location", "best", "FontSize", 10);
    ax = gca;
    ax.FontSize = 12;
    save_name = sprintf("Exp4B_%s_%s_AsCurves.png", threshold_name, metric_tag);
    exportgraphics(gcf, fullfile(output_dir, save_name), "Resolution", 600);
    close(gcf);
end
