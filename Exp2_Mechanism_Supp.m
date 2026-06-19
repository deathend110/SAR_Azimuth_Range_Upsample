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

%% ==================== 跨样本汇总 ====================
fprintf("\n===== 跨样本汇总 =====\n");

%% 4.1 构建汇总结构体
% 对每个 τ，汇总所有样本的 Node-2 指标
summary_rows = {};
for t_idx = 1:numel(tau_list)
    tau = tau_list(t_idx);
    for s = 1:numel(sample_configs)
        sc = sample_configs(s);
        metric_table = compute_mechanism_metrics(all_results{s}, all_signal60{s}, S60, tau);

        % 提取 Node-2 ("node2_rc") 的各方案指标
        node2_rows = metric_table(string(metric_table.node_name) == "node2_rc", :);

        r2a2_row = node2_rows(string(node2_rows.case_name) == "R2A2", :);
        r4a1_row = node2_rows(string(node2_rows.case_name) == "R4A1", :);
        r1a4_row = node2_rows(string(node2_rows.case_name) == "R1A4", :);
        noup_row = node2_rows(string(node2_rows.case_name) == "R1A1_NoUp", :);

        % 确定最佳单向方案
        if r4a1_row.off_support_ratio <= r1a4_row.off_support_ratio
            best_uni_name = "R4A1";
            best_uni_off = r4a1_row.off_support_ratio;
        else
            best_uni_name = "R1A4";
            best_uni_off = r1a4_row.off_support_ratio;
        end

        summary_rows{end+1, 1} = struct( ...
            "tau", tau, ...
            "scene", sc.scene_label, ...
            "R2A2_off", r2a2_row.off_support_ratio, ...
            "R2A2_range_leak", r2a2_row.range_leakage_ratio, ...
            "R2A2_az_leak", r2a2_row.azimuth_leakage_ratio, ...
            "R4A1_off", r4a1_row.off_support_ratio, ...
            "R1A4_off", r1a4_row.off_support_ratio, ...
            "NoUp_off", noup_row.off_support_ratio, ...
            "best_uni_name", best_uni_name, ...
            "best_uni_off", best_uni_off, ...
            "delta_off", best_uni_off - r2a2_row.off_support_ratio); %#ok<AGROW>
    end
end
summary_table = struct2table(vertcat(summary_rows{:, 1}));

%% 4.2 排名一致性：每个 τ 下 R2A2 排第一的场景数
tau_ranking = zeros(numel(tau_list), 1);
tau_avg_r2a2 = zeros(numel(tau_list), 1);
tau_avg_bestuni = zeros(numel(tau_list), 1);
for t_idx = 1:numel(tau_list)
    tau = tau_list(t_idx);
    tau_scenes = summary_table(summary_table.tau == tau, :);
    % R2A2 排第一 = R2A2_off < R4A1_off AND R2A2_off < R1A4_off
    r2a2_wins = (tau_scenes.R2A2_off < tau_scenes.R4A1_off) & ...
                (tau_scenes.R2A2_off < tau_scenes.R1A4_off);
    tau_ranking(t_idx) = sum(r2a2_wins);
    tau_avg_r2a2(t_idx) = mean(tau_scenes.R2A2_off);
    tau_avg_bestuni(t_idx) = mean(tau_scenes.best_uni_off);
end
fprintf("τ ranking counts: %s\n", mat2str(tau_ranking'));

%% 4.3 导出汇总表
writetable(summary_table, fullfile(output_dir, "Exp2_Supp_Summary.csv"));
fprintf("汇总表已保存: Exp2_Supp_Summary.csv\n");

% τ稳定性子表
tau_stability_table = table( ...
    tau_list(:), tau_ranking, tau_avg_r2a2, tau_avg_bestuni, ...
    tau_avg_bestuni - tau_avg_r2a2, ...
    "VariableNames", {'tau', 'R2A2_num1_count', 'Avg_R2A2_off', 'Avg_BestUni_off', 'Avg_Delta'});
writetable(tau_stability_table, fullfile(output_dir, "Exp2_Supp_Summary.csv"), ...
    "WriteMode", "append");
fprintf("τ稳定性子表已追加: Exp2_Supp_Summary.csv\n");

%% ==================== 可复现性检查 ====================
fprintf("\n===== 可复现性检查 (city2, τ=0.35 vs 原始Exp2) =====\n");
orig_metrics_path = fullfile(pwd, "Exp2_Mechanism_Output", "Exp2_Mechanism_Metrics.csv");
supp_metrics_path = fullfile(output_dir, "Exp2_Supp_city2_Metrics_tau0.35.csv");

if exist(orig_metrics_path, "file") && exist(supp_metrics_path, "file")
    orig_table = readtable(orig_metrics_path);
    supp_table = readtable(supp_metrics_path);

    % 对齐列顺序
    orig_table = sortrows(orig_table, ["case_name", "node_name"]);
    supp_table = sortrows(supp_table, ["case_name", "node_name"]);

    diff_off = abs(orig_table.off_support_ratio - supp_table.off_support_ratio);
    diff_range = abs(orig_table.range_leakage_ratio - supp_table.range_leakage_ratio);
    diff_az = abs(orig_table.azimuth_leakage_ratio - supp_table.azimuth_leakage_ratio);

    tol = 1e-6;
    max_diff = max([diff_off; diff_range; diff_az]);
    if max_diff < tol
        fprintf("✅ 可复现性通过：city2 τ=0.35 指标与原始 Exp2 完全一致 (max diff=%.2e)\n", max_diff);
    else
        fprintf("❌ 可复现性失败：max diff=%.2e > tol=%.1e\n", max_diff, tol);
        fprintf("   off_support 差异: [%s]\n", mat2str(diff_off', 6));
        fprintf("   range_leak   差异: [%s]\n", mat2str(diff_range', 6));
        fprintf("   az_leak      差异: [%s]\n", mat2str(diff_az', 6));
    end
else
    fprintf("⚠ 无法执行可复现性检查（缺少原始或补充指标文件）\n");
end

%% ==================== 导出元数据文件 ====================
fid = fopen(fullfile(output_dir, "Exp2_Supp_Metadata.txt"), "w");
fprintf(fid, "script=Exp2_Mechanism_Supp.m\n");
fprintf(fid, "date=%s\n", datestr(now, "yyyy-mm-dd HH:MM:SS"));
fprintf(fid, "As=%.3f\n", As);
fprintf(fid, "tau_list=%s\n", mat2str(tau_list));
for s = 1:numel(sample_configs)
    sc = sample_configs(s);
    fprintf(fid, "scene_%s: dataset=%s, file=%s, c_start=%d, seed=%d\n", ...
        sc.scene_label, sc.dataset_name, sc.file_name, sc.c_start, sc.seed);
end
fclose(fid);
fprintf("元数据已保存: Exp2_Supp_Metadata.txt\n");

%% ==================== 机制证据汇总图 ====================
export_multi_sample_summary(summary_table, tau_list, tau_ranking, sample_configs, output_dir);

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

function export_multi_sample_summary(summary_table, tau_list, tau_ranking, sample_configs, output_dir)
    % 只使用 τ=0.35 的数据做面板(a)多场景排名
    ref_tau = 0.35;
    tau_scenes = summary_table(abs(summary_table.tau - ref_tau) < 1e-6, :);

    scene_labels = {sample_configs.scene_label};
    scene_display = {"city2", "port", "suburb", "filed"};
    scheme_labels = {"NoUp", "R4A1", "R1A4", "R2A2"};
    colors = [0.7 0.7 0.7; 0.2 0.6 0.8; 0.8 0.4 0.2; 0.2 0.7 0.3];

    fig = figure("Color", "w", "Position", [100, 100, 1400, 550], "Visible", "off");
    cleanup_obj = onCleanup(@() close_valid_figure(fig)); %#ok<NASGU>

    %% 面板(a): 多场景 Node-2 off-support 排名
    ax1 = subplot(1, 2, 1);
    hold(ax1, "on");

    bar_width = 0.18;
    group_positions = 1:numel(scene_display);

    % 为每个场景构建数据矩阵 [NoUp, R4A1, R1A4, R2A2]
    off_data = zeros(numel(scene_display), 4);
    for s = 1:numel(scene_display)
        scene_rows = tau_scenes(string(tau_scenes.scene) == string(scene_labels{s}), :);
        if isempty(scene_rows)
            continue;
        end
        off_data(s, 1) = scene_rows.NoUp_off;
        off_data(s, 2) = scene_rows.R4A1_off;
        off_data(s, 3) = scene_rows.R1A4_off;
        off_data(s, 4) = scene_rows.R2A2_off;
    end

    for scheme = 1:4
        x_pos = group_positions + (scheme - 2.5) * bar_width;
        bar(ax1, x_pos, off_data(:, scheme), bar_width, ...
            "FaceColor", colors(scheme, :), ...
            "DisplayName", scheme_labels{scheme});
    end

    set(ax1, "XTick", group_positions, "XTickLabel", scene_display);
    ylabel(ax1, "Off-Support Energy Ratio (Node-2)");
    legend(ax1, "Location", "northeast");
    title(ax1, "(a) Multi-Scene Node-2 Off-Support Ranking (\tau=0.35)");
    grid(ax1, "on");
    box(ax1, "on");

    %% 面板(b): τ 敏感性 — R2A2 排名稳定性
    ax2 = subplot(1, 2, 2);
    plot(ax2, tau_list, tau_ranking, "o-", "LineWidth", 2, "MarkerSize", 10, ...
        "Color", [0.2 0.6 0.3], "MarkerFaceColor", [0.2 0.6 0.3]);
    ylim(ax2, [0, 5]);
    yticks(ax2, 0:1:4);
    xlabel(ax2, "Support Mask Threshold \tau");
    ylabel(ax2, "Scenes where R2A2 ranks #1 (out of 4)");
    title(ax2, "(b) \tau Sensitivity: Ranking Stability");
    grid(ax2, "on");
    box(ax2, "on");

    set(findall(fig, "-property", "FontName"), "FontName", "Times New Roman");
    set(findall(fig, "-property", "FontSize"), "FontSize", 12);

    exportgraphics(fig, fullfile(output_dir, "Exp2_Supp_MultiSample_Summary.png"), "Resolution", 300);
    fprintf("汇总图已保存: Exp2_Supp_MultiSample_Summary.png\n");
end

function close_valid_figure(fig)
    if isgraphics(fig)
        close(fig);
    end
end
