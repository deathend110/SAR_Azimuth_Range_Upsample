clear; clc; close all;

%% =========================================================
%  不同总上采样倍率 Q 下的 RxAx 组合对比脚本
%
%  功能说明：
%  1. 输入一个总上采样倍率序列 Q_list，例如 [4 6 8 9 12]；
%  2. 对每个 Q 自动生成所有满足 R * A = Q 的整数因子组合；
%  3. 其中 R1AQ 和 RQA1 会自然作为单向上采样对照组；
%  4. 固定一个 SAR 序列文件，在该文件内分层抽取 10 个窗口；
%  5. 统一使用 Split RT 阈值场，计算每个组合的 PSNR / SSIM；
%  6. 输出汇总 csv、明细 csv，以及 PSNR / SSIM 两张分组图。
%% =========================================================

%% ==================== 参数区 ====================
S60 = load("FS60_params.mat");

% 固定随机种子，保证抽样与随机相位可复现
seed = 2026;
rng(seed);

% 总上采样倍率列表，可按需修改
Q_list = [4,6,8,9,12,16];

% Split RT 阈值强度
As = 0.6;

% 固定数据源：从单个 SAR 序列文件中抽样
data_figure = "SAR_Dataset_city2_histeq";
data_root = "G:\MATLAB-G\SAR Full PSF";
data_folder = fullfile(data_root, data_figure);
data_name = "rstart 2401.mat";
data_path = fullfile(data_folder, data_name);

% 每个文件内固定抽样数量
num_samples = 10;

% 输出目录
output_dir = fullfile(pwd, "Q_Group_Compare_Output");
if ~exist(output_dir, "dir")
    mkdir(output_dir);
end

%% ==================== 读取原始回波并构建样本 ====================
if ~exist(data_path, "file")
    error("未找到指定数据文件：%s", data_path);
end

fprintf("正在读取数据文件：%s\n", data_path);
loaded_data = load(data_path);
var_names = fieldnames(loaded_data);
raw_data = loaded_data.(var_names{1});

% 在单个回波序列内做分层抽样，尽量覆盖整个有效宽度
sample_starts = build_stratified_window_starts(size(raw_data, 2), S60.nrn, num_samples);

% 预先缓存 10 个样本对应的 60MHz 输入和 GT，避免后续重复计算
sample_cache = repmat(struct( ...
    "sample_index", 0, ...
    "c_start", 0, ...
    "signal60_input", [], ...
    "img_gt", []), num_samples, 1);

fprintf("正在预计算固定 GT 样本，共 %d 个窗口...\n", num_samples);
for sample_idx = 1:num_samples
    c_start = sample_starts(sample_idx);
    channel_block = raw_data(:, c_start:c_start + S60.nrn - 1);
    signal60_input = channel_block(1:3:end, :);

    sample_cache(sample_idx).sample_index = sample_idx;
    sample_cache(sample_idx).c_start = c_start;
    sample_cache(sample_idx).signal60_input = signal60_input;
    sample_cache(sample_idx).img_gt = build_gt_image(signal60_input, S60);

    fprintf("  GT 样本 %02d / %02d 已完成，c_start = %d\n", sample_idx, num_samples, c_start);
end

%% ==================== 生成全部 RxAx 组合 ====================
group_defs = build_all_group_definitions(Q_list);
num_groups = numel(group_defs);

if num_groups == 0
    error("没有生成任何有效的 RxAx 组合，请检查 Q_list。");
end

fprintf("共生成 %d 个 RxAx 组合。\n", num_groups);

%% ==================== 逐组合评测 ====================
psnr_all = zeros(num_groups, num_samples);
ssim_all = zeros(num_groups, num_samples);

for group_idx = 1:num_groups
    current_group = group_defs(group_idx);
    fprintf("正在处理组合 %02d / %02d: %s (Q=%d)\n", ...
        group_idx, num_groups, current_group.group_name, current_group.Q);

    % 对每个组合固定一套随机种子，保证不同组合的结果可复现
    rng(seed + group_idx);

    for sample_idx = 1:num_samples
        signal60_input = sample_cache(sample_idx).signal60_input;
        img_gt = sample_cache(sample_idx).img_gt;

        img_out = build_rxa_image( ...
            signal60_input, S60, ...
            current_group.Range_q, current_group.Azimuth_q, As);

        psnr_all(group_idx, sample_idx) = psnr(img_out, img_gt);
        ssim_all(group_idx, sample_idx) = ssim(img_out, img_gt);
    end
end

%% ==================== 汇总统计 ====================
psnr_mean = mean(psnr_all, 2);
psnr_std = std(psnr_all, 0, 2);
ssim_mean = mean(ssim_all, 2);
ssim_std = std(ssim_all, 0, 2);

%% ==================== 保存汇总表 ====================
summary_table = table( ...
    [group_defs.Q].', ...
    string({group_defs.group_name}).', ...
    [group_defs.Range_q].', ...
    [group_defs.Azimuth_q].', ...
    string({group_defs.group_type}).', ...
    string({group_defs.group_desc}).', ...
    repmat(num_samples, num_groups, 1), ...
    repmat(As, num_groups, 1), ...
    psnr_mean, psnr_std, ...
    ssim_mean, ssim_std, ...
    'VariableNames', { ...
    'Q', ...
    'GroupName', ...
    'Range_q', ...
    'Azimuth_q', ...
    'GroupType', ...
    'Description', ...
    'SampleCount', ...
    'As', ...
    'PSNR_Mean', 'PSNR_Std', ...
    'SSIM_Mean', 'SSIM_Std'});

writetable(summary_table, fullfile(output_dir, "RxAx_Group_Compare_Summary.csv"));

%% ==================== 保存明细表 ====================
detail_Q = zeros(num_groups * num_samples, 1);
detail_group_name = strings(num_groups * num_samples, 1);
detail_range_q = zeros(num_groups * num_samples, 1);
detail_azimuth_q = zeros(num_groups * num_samples, 1);
detail_sample_idx = zeros(num_groups * num_samples, 1);
detail_c_start = zeros(num_groups * num_samples, 1);
detail_psnr = zeros(num_groups * num_samples, 1);
detail_ssim = zeros(num_groups * num_samples, 1);

row_ptr = 1;
for group_idx = 1:num_groups
    for sample_idx = 1:num_samples
        detail_Q(row_ptr) = group_defs(group_idx).Q;
        detail_group_name(row_ptr) = string(group_defs(group_idx).group_name);
        detail_range_q(row_ptr) = group_defs(group_idx).Range_q;
        detail_azimuth_q(row_ptr) = group_defs(group_idx).Azimuth_q;
        detail_sample_idx(row_ptr) = sample_idx;
        detail_c_start(row_ptr) = sample_cache(sample_idx).c_start;
        detail_psnr(row_ptr) = psnr_all(group_idx, sample_idx);
        detail_ssim(row_ptr) = ssim_all(group_idx, sample_idx);
        row_ptr = row_ptr + 1;
    end
end

detail_table = table( ...
    detail_Q, detail_group_name, ...
    detail_range_q, detail_azimuth_q, ...
    detail_sample_idx, detail_c_start, ...
    detail_psnr, detail_ssim, ...
    'VariableNames', { ...
    'Q', 'GroupName', ...
    'Range_q', 'Azimuth_q', ...
    'SampleIndex', 'CStart', ...
    'PSNR', 'SSIM'});

writetable(detail_table, fullfile(output_dir, "RxAx_Group_Compare_Detail.csv"));

%% ==================== 保存 mat 结果 ====================
save(fullfile(output_dir, "RxAx_Group_Compare_Result.mat"), ...
    "Q_list", "As", "data_figure", "data_name", ...
    "num_samples", "sample_starts", ...
    "group_defs", "psnr_all", "ssim_all", ...
    "psnr_mean", "psnr_std", "ssim_mean", "ssim_std");

%% ==================== 按 Q 分别绘制 PSNR 图 ====================
plot_metric_one_figure_per_q( ...
    Q_list, group_defs, ...
    psnr_mean, psnr_std, ...
    "PSNR (dB)", ...
    "Split RT 下不同 RxAx 组合的 PSNR 对比", ...
    As, ...
    output_dir, ...
    "PSNR");

%% ==================== 按 Q 分别绘制 SSIM 图 ====================
plot_metric_one_figure_per_q( ...
    Q_list, group_defs, ...
    ssim_mean, ssim_std, ...
    "SSIM", ...
    "Split RT 下不同 RxAx 组合的 SSIM 对比", ...
    As, ...
    output_dir, ...
    "SSIM");

fprintf("全部完成，结果已保存到目录：%s\n", output_dir);


%% =========================================================
%% ==================== 局部函数区 =========================
%% =========================================================

% 在单个序列宽度范围内做分层抽样，保证 10 个窗口尽量均匀覆盖全序列
function sample_starts = build_stratified_window_starts(raw_width, window_width, num_samples)
    max_start = raw_width - window_width + 1;
    if max_start < 1
        error("序列宽度不足以裁出完整窗口。");
    end

    sample_starts = zeros(num_samples, 1);
    for sample_idx = 1:num_samples
        center_pos = round((sample_idx - 0.5) / num_samples * max_start);
        center_pos = max(center_pos, 1);
        center_pos = min(center_pos, max_start);
        sample_starts(sample_idx) = center_pos;
    end
end

% 构建 GT 图像，作为所有组合共享的固定参考
function img_gt = build_gt_image(signal60_input, S60)
    RC_gt = Range_Compress(signal60_input, S60.fc, S60.tnrn, S60.gama, S60.R0, S60.C, S60.Fs, S60.Tp);
    RCMC_gt = RCMC(RC_gt, S60.lambda, S60.fnrn, S60.fnan, S60.R0, S60.C, S60.v);
    IMG_gt = SAR_Imaging(RCMC_gt, S60.lambda, S60.Fs, S60.R0, S60.C, S60.v, S60.tnan, S60.Ta, S60.prf);

    roi_gt = abs(IMG_gt( ...
        S60.nrn / 2 - S60.R_total / 2 + 1:S60.nrn / 2 + S60.R_total / 2, ...
        S60.nan / 2 - S60.A_num / 2:S60.nan / 2 + S60.A_num / 2 - 1));

    img_gt = normalize_image(roi_gt);
end

% 自动生成所有 Q 对应的 RxAx 组合
function group_defs = build_all_group_definitions(Q_list)
    group_defs = struct( ...
        "Q", {}, ...
        "Range_q", {}, ...
        "Azimuth_q", {}, ...
        "group_name", {}, ...
        "group_type", {}, ...
        "group_desc", {});

    for q_idx = 1:numel(Q_list)
        Q = Q_list(q_idx);
        if Q < 1 || abs(Q - round(Q)) > 0
            error("Q_list 中存在非法元素，Q 必须为正整数。");
        end

        factor_pairs = factor_pairs_for_q(Q);
        for pair_idx = 1:size(factor_pairs, 1)
            range_q = factor_pairs(pair_idx, 1);
            azimuth_q = factor_pairs(pair_idx, 2);

            [group_type, group_desc] = describe_group(range_q, azimuth_q, Q);

            current_group.Q = Q;
            current_group.Range_q = range_q;
            current_group.Azimuth_q = azimuth_q;
            current_group.group_name = sprintf("R%dA%d", range_q, azimuth_q);
            current_group.group_type = group_type;
            current_group.group_desc = group_desc;

            group_defs(end + 1) = current_group; %#ok<AGROW>
        end
    end
end

% 返回所有满足 R * A = Q 的有序整数因子对
function factor_pairs = factor_pairs_for_q(Q)
    factor_pairs = zeros(0, 2);
    for range_q = 1:Q
        if mod(Q, range_q) == 0
            azimuth_q = Q / range_q;
            factor_pairs(end + 1, :) = [range_q, azimuth_q]; %#ok<AGROW>
        end
    end
end

% 根据组合属性给出组类型和中文说明
function [group_type, group_desc] = describe_group(range_q, azimuth_q, Q)
    if range_q == 1 && azimuth_q == Q
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

% 对指定的 RxAx 组合构建最终成像结果
function img_out = build_rxa_image(signal60_input, S60, range_q, azimuth_q, As)
    [U_master_patch, ~, ~] = Build_2D_SplitRT(signal60_input, azimuth_q, range_q, As);

    signal60_patch_high = two_dim_upsample_fft(signal60_input, azimuth_q, range_q);
    tnrn_up = build_range_time_axis(signal60_patch_high, range_q, S60);

    channel_1bit_high = quantize_1bit_with_U(signal60_patch_high, U_master_patch);
    RC_high = Range_Compress(channel_1bit_high, S60.fc, tnrn_up, S60.gama, S60.R0, S60.C, range_q * S60.Fs, S60.Tp);
    RC_crop = two_dim_downsample_fft(RC_high, azimuth_q, range_q, S60);
    RCMC_crop = RCMC(RC_crop, S60.lambda, S60.fnrn, S60.fnan, S60.R0, S60.C, S60.v);
    IMG_high = SAR_Imaging(RCMC_crop, S60.lambda, S60.Fs, S60.R0, S60.C, S60.v, S60.tnan, S60.Ta, S60.prf);

    roi_crop = abs(IMG_high( ...
        S60.nrn / 2 - S60.R_total / 2 + 1:S60.nrn / 2 + S60.R_total / 2, ...
        S60.nan / 2 - S60.A_num / 2:S60.nan / 2 + S60.A_num / 2 - 1));

    img_out = normalize_image(roi_crop);
end

% 为距离向上采样后的回波重建对应时间轴
function tnrn_up = build_range_time_axis(signal_up, range_q, S60)
    nrn_up = size(signal_up, 1);
    Fs_up = range_q * S60.Fs;
    Tnrn_up = 1 / Fs_up;
    Tstart_up = 2 * S60.R0 / S60.C - nrn_up / 2 / Fs_up;
    Tend_up = 2 * S60.R0 / S60.C + (nrn_up / 2 - 1) / Fs_up;
    tnrn_up = (Tstart_up:Tnrn_up:Tend_up).';
end

% 为每个 Q 单独保存一张图，避免所有组合挤在一张总图中难以阅读
function plot_metric_one_figure_per_q(Q_list, group_defs, metric_mean, metric_std, y_label_text, title_prefix, As, output_dir, metric_tag)
    for q_idx = 1:numel(Q_list)
        Q = Q_list(q_idx);
        group_mask = [group_defs.Q] == Q;
        current_groups = group_defs(group_mask);
        current_mean = metric_mean(group_mask);
        current_std = metric_std(group_mask);

        figure("Color", "w", "Position", [120, 100, 1400, 220 + 95 * numel(current_groups)]);
        hold on;
        box on;
        grid on;
        grid minor;

        num_groups = numel(current_groups);
        y_pos = 1:num_groups;
        bar_handle = barh(y_pos, current_mean, 0.64, "FaceColor", "flat", "EdgeColor", "none");

        % 通过颜色区分单向对照、均衡方案和非均衡方案
        color_map = zeros(num_groups, 3);
        for group_idx = 1:num_groups
            color_map(group_idx, :) = choose_group_color(current_groups(group_idx).group_type);
        end
        bar_handle.CData = color_map;

        % 手动画横向误差线，避免默认误差棒在横向条形图上显示不清楚
        for group_idx = 1:num_groups
            x_left = current_mean(group_idx) - current_std(group_idx);
            x_right = current_mean(group_idx) + current_std(group_idx);
            y_center = y_pos(group_idx);
            plot([x_left, x_right], [y_center, y_center], "k-", "LineWidth", 1.2);
            plot([x_left, x_left], [y_center - 0.10, y_center + 0.10], "k-", "LineWidth", 1.2);
            plot([x_right, x_right], [y_center - 0.10, y_center + 0.10], "k-", "LineWidth", 1.2);
        end

        yticks(y_pos);
        yticklabels({current_groups.group_name});
        xlabel(y_label_text, "FontSize", 13, "FontWeight", "bold");
        title(sprintf("%s | Q = %d | As = %.1f", title_prefix, Q, As), ...
            "FontSize", 15, "FontWeight", "bold");

        ax = gca;
        ax.FontSize = 12;
        ax.LineWidth = 1.0;
        ax.YDir = "reverse";

        x_min = min(current_mean - current_std);
        x_max = max(current_mean + current_std);
        x_span = x_max - x_min + eps;
        ax.XLim = [x_min - 0.05 * x_span, x_max + 0.35 * x_span];

        % 在误差线右端之外标注均值和标准差，避免与误差线本身重叠
        for group_idx = 1:num_groups
            label_x = current_mean(group_idx) + current_std(group_idx) + 0.02 * x_span;
            text(label_x, y_pos(group_idx), ...
                sprintf("%.4f ± %.4f", current_mean(group_idx), current_std(group_idx)), ...
                "VerticalAlignment", "middle", ...
                "HorizontalAlignment", "left", ...
                "FontSize", 10, ...
                "FontWeight", "bold", ...
                "BackgroundColor", "w", ...
                "Margin", 1.5);
        end

        % 在图下方补充颜色说明，避免用户反复对照 csv
        text(ax.XLim(1), num_groups + 0.85, ...
            "蓝色: 距离单向对照  橙色: 方位单向对照  绿色: 均衡组  紫色: 非均衡混合组", ...
            "FontSize", 10, ...
            "Color", [0.20, 0.20, 0.20], ...
            "HorizontalAlignment", "left");

        save_name = sprintf("RxAx_Group_Compare_%s_Q%d.png", metric_tag, Q);
        exportgraphics(gcf, fullfile(output_dir, save_name), "Resolution", 240);
        close(gcf);
    end
end

% 给不同类型的组合分配固定颜色
function rgb = choose_group_color(group_type)
    switch string(group_type)
        case "range_only"
            rgb = [0.12, 0.47, 0.71];
        case "azimuth_only"
            rgb = [0.85, 0.33, 0.10];
        case "balanced"
            rgb = [0.20, 0.63, 0.17];
        otherwise
            rgb = [0.49, 0.18, 0.56];
    end
end

% 生成可分离的二维 RT 阈值场
function [U, sigma, A_rt] = Build_2D_SplitRT(input60, azimuth_q, range_q, As)
    signal_up_2d = two_dim_upsample_fft(input60, azimuth_q, range_q);
    [Nr_up, Na_up] = size(signal_up_2d);

    phi_r = 2 * pi * rand(Nr_up, 1);
    phi_a = 2 * pi * rand(1, Na_up);

    sigma = sqrt(2 / pi) * mean(abs(signal_up_2d(:)));
    A_rt = As * sigma;

    U = A_rt * exp(1i * (phi_r + phi_a));
end

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

% 带 RT 阈值的 1-bit 量化
function S1 = quantize_1bit_with_U(S, U)
    re = ones(size(S), "like", real(S));
    im = ones(size(S), "like", real(S));

    re(real(S) + real(U) < 0) = -1;
    im(imag(S) + imag(U) < 0) = -1;

    S1 = complex(re, im);
end

% 距离向频域零填充上采样
function S_up = range_upsample_fft(S, q)
    [Nr, Na] = size(S);
    Nr_up = q * Nr;

    Sf = fftshift(fft(S, [], 1), 1);
    pad_total = Nr_up - Nr;
    pad_top = floor(pad_total / 2);
    pad_bottom = pad_total - pad_top;

    Sf_up = [zeros(pad_top, Na, "like", Sf); ...
             Sf; ...
             zeros(pad_bottom, Na, "like", Sf)];

    S_up = ifft(ifftshift(Sf_up, 1), [], 1) * q;
end

% 距离向频域裁剪回原尺寸
function X_crop = crop_range_doppler_to_width(X, target_height)
    [Nr_up, ~] = size(X);
    if target_height > Nr_up
        error("target_height cannot be larger than current height.");
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

% 方位向频域零填充上采样
function S_up = azimuth_upsample_fft(S, q)
    [Nr, Na] = size(S);
    Na_up = q * Na;

    Sf = fftshift(fft(S, [], 2), 2);
    pad_total = Na_up - Na;
    pad_left = floor(pad_total / 2);
    pad_right = pad_total - pad_left;

    Sf_up = [zeros(Nr, pad_left, "like", Sf), ...
             Sf, ...
             zeros(Nr, pad_right, "like", Sf)];

    S_up = ifft(ifftshift(Sf_up, 2), [], 2) * q;
end

% 方位向频域裁剪回原尺寸
function X_crop = crop_azimuth_doppler_to_width(X, target_width)
    [~, Na_up] = size(X);
    if target_width > Na_up
        error("target_width cannot be larger than current width.");
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
