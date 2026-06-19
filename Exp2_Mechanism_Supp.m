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

%% ==================== 主循环：每个样本执行完整管道 ====================
all_results = cell(numel(sample_configs), 1);
all_signal60 = cell(numel(sample_configs), 1);

for s = 1:numel(sample_configs)
    sc = sample_configs(s);
    fprintf("\n===== 样本 %d/%d: %s (seed=%d, c_start=%d) =====\n", ...
        s, numel(sample_configs), sc.scene_label, sc.seed, sc.c_start);

    %% 加载样本
    signal60_input = load_signal60_case(data_root, sc.dataset_name, sc.file_name, sc.c_start, S60.nrn);
    assert(size(signal60_input, 1) == S60.nrn, "signal60_input 高度不匹配 S60.nrn");
    assert(size(signal60_input, 2) == S60.nan, "signal60_input 宽度不匹配 S60.nan");
    all_signal60{s} = signal60_input;

    %% 对每个上采样方案跑管道（只跑一次，复用节点矩阵）
    rng(sc.seed);
    case_results = repmat(struct( ...
        "case_name", "", "range_q", 0, "azimuth_q", 0, "group_type", "", ...
        "node0_signal_up", [], "node1_channel_1bit", [], "node1_residual", [], ...
        "node2_rc_raw", [], "node2_rc", [], "node3_rcmc", [], ...
        "node4_img", [], "node4_roi", [], "metrics", struct()), numel(case_defs), 1);

    for case_idx = 1:numel(case_defs)
        rng(sc.seed + case_idx);
        case_results(case_idx) = run_mechanism_case(signal60_input, S60, case_defs(case_idx), As);
        fprintf("  [%s] 管道完成 (U_mean_abs=%.4f)\n", case_defs(case_idx).case_name, ...
            case_results(case_idx).metrics.U_mean_abs);
    end
    all_results{s} = case_results;

    %% 对每个 τ 计算指标（复用已算好的节点矩阵）
    for t_idx = 1:numel(tau_list)
        tau = tau_list(t_idx);
        [metric_table, ~] = compute_mechanism_metrics(case_results, signal60_input, S60, tau);
        csv_path = fullfile(output_dir, sprintf("Exp2_Supp_%s_Metrics_tau%.2f.csv", sc.scene_label, tau));
        writetable(metric_table, csv_path);
        fprintf("  τ=%.2f 指标已保存: %s\n", tau, csv_path);
    end

    %% 保存该样本的完整管道数据
    save(fullfile(output_dir, sprintf("Exp2_Supp_%s_Data.mat", sc.scene_label)), ...
        "sc", "case_defs", "case_results", "As", "tau_list", "signal60_input", "-v7.3");
    fprintf("  数据已保存: Exp2_Supp_%s_Data.mat\n", sc.scene_label);
end

%% =========================================================
%% 局部函数区
%% =========================================================

function signal60 = load_signal60_case(data_root, dataset_name, file_name, c_start, nrn)
    data_path = fullfile(data_root, dataset_name, file_name);
    loaded_data = load(data_path);
    var_names = fieldnames(loaded_data);
    raw = loaded_data.(var_names{1});

    if size(raw, 2) < c_start + nrn - 1
        error("数据宽度不足 c_start=%d (data_width=%d, need >=%d)", c_start, size(raw, 2), c_start + nrn - 1);
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

function [metric_table, metric_rows] = compute_mechanism_metrics(results, signal60_input, S60, tau)
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
            reference_mask = estimate_support_mask(reference_matrix, tau);
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

function support_mask = estimate_support_mask(reference_matrix, tau)
    ref_spec = abs(fftshift(fft2(reference_matrix)));
    support_mask = ref_spec >= tau * max(ref_spec(:));
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

    range_profile = sum(spec, 2);
    azimuth_profile = sum(spec, 1).';

    range_mask = any(support_mask, 2);
    azimuth_mask = any(support_mask, 1).';

    range_ratio = sum(range_profile(~range_mask)) / (sum(range_profile) + eps);
    azimuth_ratio = sum(azimuth_profile(~azimuth_mask)) / (sum(azimuth_profile) + eps);
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
