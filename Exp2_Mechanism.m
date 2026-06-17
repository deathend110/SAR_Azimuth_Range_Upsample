clear; clc; close all;

%% =========================================================
%  实验二：机制取证实验
%  目标：沿 SAR 成像 pipeline 保存关键中间节点，
%  比较 NoUp / RangeOnly / AzimuthOnly / R2A2 的二维噪声塑形差异
%% =========================================================

%% ==================== 参数区 ====================
S60 = load("FS60_params.mat");

seed = 42;
rng(seed);

As = 0.6;

data_root = "G:\MATLAB-G\SAR Full PSF";
dataset_name = "SAR_Dataset_city2_histeq";
file_name = "rstart 301.mat";
c_start = 6500;

case_defs = struct( ...
    "case_name", {"R1A1_NoUp", "R4A1", "R1A4", "R2A2"}, ...
    "range_q",   {1, 4, 1, 2}, ...
    "azimuth_q", {1, 1, 4, 2}, ...
    "group_type",{ "no_upsample", "range_only", "azimuth_only", "bidir" });

output_dir = fullfile(pwd, "Exp2_Mechanism_Output");
if ~exist(output_dir, "dir")
    mkdir(output_dir);
end

%% ==================== 取证节点说明 ====================
% Node-0: signal_up
% Node-1: channel_1bit
% Node-2: RC
% Node-3: RCMC
% Node-4: IMG / ROI

%% ==================== 加载确定性样本 ====================
data_path = fullfile(data_root, dataset_name, file_name);
signal60_input = load_signal60_case(data_path, c_start, S60.nrn);
img_gt = build_gt_image(signal60_input, S60);

assert(size(signal60_input, 1) == S60.nrn, "signal60_input 高度不匹配 S60.nrn");
assert(size(signal60_input, 2) == S60.nan, "signal60_input 宽度不匹配 S60.nan");

%% ==================== 执行四组机制案例 ====================
case_result = struct( ...
    "case_name", "", ...
    "range_q", 0, ...
    "azimuth_q", 0, ...
    "group_type", "", ...
    "node0_signal_up", [], ...
    "node1_channel_1bit", [], ...
    "node1_residual", [], ...
    "node2_rc_raw", [], ...
    "node2_rc", [], ...
    "node3_rcmc", [], ...
    "node4_img", [], ...
    "node4_roi", [], ...
    "metrics", struct());

results = repmat(case_result, numel(case_defs), 1);

for case_idx = 1:numel(case_defs)
    current_case = case_defs(case_idx);
    rng(seed + case_idx);
    results(case_idx) = run_mechanism_case(signal60_input, S60, current_case, As);
end

%% ==================== 计算机制指标 ====================
[metric_table, metric_rows] = compute_mechanism_metrics(results, signal60_input, S60);

%% ==================== 导出图表 ====================
export_spectrum_panel(results, output_dir, "node1_residual", "Exp2_Node1_Residual_Spectra.png", "Node-1 Residual Spectra");
export_spectrum_panel(results, output_dir, "node2_rc_raw", "Exp2_Node2_RC_Spectra.png", "Node-2 RC Spectra");
export_center_profiles(results, output_dir, "node1_residual", "range", "Exp2_Node1_Residual_Range_Profile.png");
export_center_profiles(results, output_dir, "node1_residual", "azimuth", "Exp2_Node1_Residual_Azimuth_Profile.png");
export_stage_montage(results, output_dir);
export_metric_table(metric_table, output_dir);

%% ==================== 保存可复现输出 ====================
save(fullfile(output_dir, "Exp2_Mechanism_Data.mat"), ...
    "seed", "As", "dataset_name", "file_name", "c_start", ...
    "case_defs", "results", "metric_table", "metric_rows", "img_gt", ...
    "-v7.3");

fid = fopen(fullfile(output_dir, "Exp2_Mechanism_Metadata.txt"), "w");
fprintf(fid, "seed=%d\nAs=%.3f\ndataset=%s\nfile=%s\nc_start=%d\n", seed, As, dataset_name, file_name, c_start);
fclose(fid);

fprintf("\n全部完成，结果已保存到目录：%s\n", output_dir);

%% =========================================================
%% 局部函数区
%% =========================================================

function signal60 = load_signal60_case(data_path, c_start, nrn)
    % 与实验一保持一致，优先使用 MATLAB 原生 load 还原复数矩阵和维度
    loaded_data = load(data_path);
    var_names = fieldnames(loaded_data);
    raw = loaded_data.(var_names{1});

    if size(raw, 2) < c_start + nrn - 1
        error("数据宽度不足，无法抽取 c_start=%d, nrn=%d 的窗口。", c_start, nrn);
    end

    channel_block = raw(:, c_start:c_start + nrn - 1);
    signal60 = channel_block(1:3:end, :);
end

function result = run_mechanism_case(signal60, S60, case_def, As)
    result = struct();
    result.case_name = string(case_def.case_name);
    result.range_q = case_def.range_q;
    result.azimuth_q = case_def.azimuth_q;
    result.group_type = string(case_def.group_type);

    [signal_up, U, channel_1bit, RC_raw, RC_crop, RCMC_out, IMG, roi] = build_forensic_nodes(signal60, S60, case_def.range_q, case_def.azimuth_q, As);

    result.node0_signal_up = signal_up;
    result.node1_channel_1bit = channel_1bit;
    result.node1_residual = channel_1bit - signal_up;
    result.node2_rc_raw = RC_raw;
    result.node2_rc = RC_crop;
    result.node3_rcmc = RCMC_out;
    result.node4_img = IMG;
    result.node4_roi = roi;
    result.metrics = struct("U_mean_abs", mean(abs(U(:))));
end

function [signal_up, U, channel_1bit, RC_raw, RC_crop, RCMC_crop, IMG, roi] = build_forensic_nodes(signal60, S60, range_q, azimuth_q, As)
    if range_q == 1 && azimuth_q == 1
        signal_up = signal60;
    else
        signal_up = two_dim_upsample_fft(signal60, azimuth_q, range_q);
    end

    U = build_splitrt_threshold(signal_up, As);
    channel_1bit = quantize_1bit_with_U(signal_up, U);

    [tnrn_up, Fs_up] = build_range_axis_for_upsampled_signal(size(signal_up, 1), range_q, S60);
    RC_raw = Range_Compress(channel_1bit, S60.fc, tnrn_up, S60.gama, S60.R0, S60.C, Fs_up, S60.Tp);

    RC_crop = two_dim_downsample_fft(RC_raw, azimuth_q, range_q, S60);
    RCMC_crop = RCMC(RC_crop, S60.lambda, S60.fnrn, S60.fnan, S60.R0, S60.C, S60.v);
    IMG = SAR_Imaging(RCMC_crop, S60.lambda, S60.Fs, S60.R0, S60.C, S60.v, S60.tnan, S60.Ta, S60.prf);

    roi = abs(IMG( ...
        S60.nrn / 2 - S60.R_total / 2 + 1 : S60.nrn / 2 + S60.R_total / 2, ...
        S60.nan / 2 - S60.A_num / 2 : S60.nan / 2 + S60.A_num / 2 - 1));
    roi = normalize_image(roi);
end

function [tnrn_up, Fs_up] = build_range_axis_for_upsampled_signal(nrn_up, range_q, S60)
    Fs_up = range_q * S60.Fs;
    Tnrn_up = 1 / Fs_up;
    Tstart_up = 2 * S60.R0 / S60.C - nrn_up / 2 / Fs_up;
    Tend_up = 2 * S60.R0 / S60.C + (nrn_up / 2 - 1) / Fs_up;
    tnrn_up = (Tstart_up : Tnrn_up : Tend_up).';
end

function [metric_table, metric_rows] = compute_mechanism_metrics(results, signal60_input, S60)
    tracked_nodes = {"node1_residual", "node2_rc", "node3_rcmc"};
    num_rows = numel(results) * numel(tracked_nodes);

    metric_rows = repmat(struct( ...
        "case_name", "", ...
        "node_name", "", ...
        "off_support_ratio", NaN, ...
        "range_leakage_ratio", NaN, ...
        "azimuth_leakage_ratio", NaN), num_rows, 1);

    row_ptr = 0;
    for case_idx = 1:numel(results)
        for node_idx = 1:numel(tracked_nodes)
            node_name = tracked_nodes{node_idx};
            X = results(case_idx).(node_name);
            reference_matrix = build_reference_matrix_for_node(signal60_input, S60, ...
                results(case_idx).range_q, results(case_idx).azimuth_q, node_name);
            reference_mask = estimate_support_mask(reference_matrix, 0.35);
            [off_ratio, range_ratio, azimuth_ratio] = compute_leakage_metrics(X, reference_mask);

            row_ptr = row_ptr + 1;
            row = struct();
            row.case_name = results(case_idx).case_name;
            row.node_name = string(node_name);
            row.off_support_ratio = off_ratio;
            row.range_leakage_ratio = range_ratio;
            row.azimuth_leakage_ratio = azimuth_ratio;
            metric_rows(row_ptr, 1) = row;
        end
    end

    metric_rows = metric_rows(1:row_ptr);
    metric_table = struct2table(metric_rows);
end

function support_mask = estimate_support_mask(reference_matrix, threshold_ratio)
    ref_spec = abs(fftshift(fft2(reference_matrix)));
    support_mask = ref_spec >= threshold_ratio * max(ref_spec(:));
end

function reference_matrix = build_reference_matrix_for_node(signal60_input, S60, range_q, azimuth_q, node_name)
    if range_q == 1 && azimuth_q == 1
        signal_up_ref = signal60_input;
    else
        signal_up_ref = two_dim_upsample_fft(signal60_input, azimuth_q, range_q);
    end

    [tnrn_up, Fs_up] = build_range_axis_for_upsampled_signal(size(signal_up_ref, 1), range_q, S60);
    RC_ref = Range_Compress(signal_up_ref, S60.fc, tnrn_up, S60.gama, S60.R0, S60.C, Fs_up, S60.Tp);
    RC_ref_crop = two_dim_downsample_fft(RC_ref, azimuth_q, range_q, S60);
    RCMC_ref_crop = RCMC(RC_ref_crop, S60.lambda, S60.fnrn, S60.fnan, S60.R0, S60.C, S60.v);

    if node_name == "node1_residual"
        reference_matrix = signal_up_ref;
    elseif node_name == "node2_rc"
        reference_matrix = RC_ref_crop;
    elseif node_name == "node3_rcmc"
        reference_matrix = RCMC_ref_crop;
    else
        error("未知节点名：%s", node_name);
    end
end

function [off_ratio, range_ratio, azimuth_ratio] = compute_leakage_metrics(X, support_mask)
    spec = abs(fftshift(fft2(X))).^2;
    total_energy = sum(spec(:)) + eps;
    off_ratio = sum(spec(~support_mask), "all") / total_energy;

    % 用整轴投影代替单条中心切片，避免支撑恰好压不到中心行/列时指标退化
    range_profile = sum(spec, 2);
    azimuth_profile = sum(spec, 1).';

    range_mask = any(support_mask, 2);
    azimuth_mask = any(support_mask, 1).';

    range_ratio = sum(range_profile(~range_mask)) / (sum(range_profile) + eps);
    azimuth_ratio = sum(azimuth_profile(~azimuth_mask)) / (sum(azimuth_profile) + eps);
end

function export_metric_table(metric_table, output_dir)
    writetable(metric_table, fullfile(output_dir, "Exp2_Mechanism_Metrics.csv"));
end

function export_spectrum_panel(results, output_dir, node_field, save_name, panel_title)
    figure("Color", "w", "Position", [100, 100, 1200, 600]);
    tiledlayout(2, 2, "Padding", "compact", "TileSpacing", "compact");
    for i = 1:numel(results)
        nexttile;
        imagesc(compute_log_spectrum(results(i).(node_field)));
        axis image off;
        colorbar;
        title(results(i).case_name, "Interpreter", "none");
    end
    sgtitle(panel_title);
    exportgraphics(gcf, fullfile(output_dir, save_name), "Resolution", 240);
    close(gcf);
end

function export_center_profiles(results, output_dir, node_field, direction_name, save_name)
    figure("Color", "w", "Position", [100, 100, 1000, 600]);
    hold on; grid on; box on;
    for i = 1:numel(results)
        spec = compute_log_spectrum(results(i).(node_field));
        if direction_name == "range"
            y = spec(:, round(size(spec, 2) / 2));
        else
            y = spec(round(size(spec, 1) / 2), :).';
        end
        plot(y, "LineWidth", 1.5, "DisplayName", results(i).case_name);
    end
    legend("Location", "best");
    xlabel("样本索引");
    ylabel("log1p(|FFT|)");
    title(sprintf("%s 中心剖面", direction_name), "Interpreter", "none");
    exportgraphics(gcf, fullfile(output_dir, save_name), "Resolution", 240);
    close(gcf);
end

function export_stage_montage(results, output_dir)
    figure("Color", "w", "Position", [100, 100, 1400, 900]);
    tiledlayout(3, 4, "Padding", "compact", "TileSpacing", "compact");
    for i = 1:numel(results)
        nexttile(i);
        imagesc(normalize_image(results(i).node2_rc));
        axis image off;
        title(sprintf("%s RC", results(i).case_name), "Interpreter", "none");
    end
    for i = 1:numel(results)
        nexttile(i + 4);
        imagesc(normalize_image(results(i).node3_rcmc));
        axis image off;
        title(sprintf("%s RCMC", results(i).case_name), "Interpreter", "none");
    end
    for i = 1:numel(results)
        nexttile(i + 8);
        imagesc(results(i).node4_roi);
        axis image off;
        title(sprintf("%s ROI", results(i).case_name), "Interpreter", "none");
    end
    sgtitle("Node-2 / Node-3 / Node-4 总览");
    exportgraphics(gcf, fullfile(output_dir, "Exp2_Montage_RC_RCMC_Final.png"), "Resolution", 240);
    close(gcf);
end

function spec = compute_log_spectrum(X)
    spec = log1p(abs(fftshift(fft2(X))));
end

function [U, sigma, A_rt] = build_splitrt_threshold(signal_up, As)
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

function X_crop = crop_azimuth_doppler_to_width(X, target_width)
    [~, Na_up] = size(X);
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

function img_gt = build_gt_image(signal60, S60)
    RC_gt = Range_Compress(signal60, S60.fc, S60.tnrn, S60.gama, S60.R0, S60.C, S60.Fs, S60.Tp);
    RCMC_gt = RCMC(RC_gt, S60.lambda, S60.fnrn, S60.fnan, S60.R0, S60.C, S60.v);
    IMG_gt = SAR_Imaging(RCMC_gt, S60.lambda, S60.Fs, S60.R0, S60.C, S60.v, S60.tnan, S60.Ta, S60.prf);
    roi_gt = abs(IMG_gt( ...
        S60.nrn / 2 - S60.R_total / 2 + 1 : S60.nrn / 2 + S60.R_total / 2, ...
        S60.nan / 2 - S60.A_num / 2 : S60.nan / 2 + S60.A_num / 2 - 1));
    img_gt = normalize_image(roi_gt);
end
