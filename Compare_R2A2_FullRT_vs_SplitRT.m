clear; clc; close all;

%% =========================================================
%  R2A2 的两种 RT 阈值生成方式对比脚本
%  目标：
%  1. 固定 GT 生成方式不变；
%  2. 在同一组 As 参数下，对比 Build_2D_RT 和 Build_2D_SplitRT；
%  3. 遍历整套 SAR 回波序列，在全局窗口上做分层抽样；
%  4. 每个 As 抽取 10 个样本，统计 PSNR / SSIM 均值；
%  5. 最后绘制两张曲线图：PSNR-As、SSIM-As。
%% =========================================================

%% ==================== 参数区 ====================
S60 = load("FS60_params.mat");

% 固定随机种子，保证抽样和 RT 随机相位可复现
seed = 42;
rng(seed);

% 数据集与实验配置
% 可选的数据集文件夹名字
DIR_LIST = ["SAR_Dataset_Bangkok_1", "SAR_Dataset_city1_histeq", ...
            "SAR_Dataset_city2_histeq", "SAR_Dataset_SAR_figure", ...
            "SAR_Dataset_filed", "SAR_Dataset_port", "SAR_Dataset_suburb"];
data_figure = "SAR_Dataset_city2_histeq";
data_folder = replace("G:\MATLAB-G\SAR Full PSF\temp\", "temp", data_figure);
file_pattern = "rstart *.mat";

% R2A2 配置：这里固定为 2x 方位 + 2x 距离
Azimuth_q = 2;
Range_q = 2;

% As 扫描范围
As_list = 0:0.1:1.0;

% 每个 As 的分层抽样数量
num_samples = 10;

% 输出目录
output_dir = fullfile(pwd, "RT_Compare_R2A2_Output");
if ~exist(output_dir, "dir")
    mkdir(output_dir);
end

%% ==================== 构建样本列表 ====================
file_structs = dir(fullfile(data_folder, file_pattern));
if isempty(file_structs)
    error("未在数据目录中找到任何 rstart *.mat 文件。");
end

% 按文件名中的数字排序，避免字符串排序导致 1201 排在 301 前面
file_names = {file_structs.name};
file_order_keys = cellfun(@extract_rstart_number, file_names);
[~, order_idx] = sort(file_order_keys);
file_structs = file_structs(order_idx);

% 先统计每个文件能提供多少个有效窗口，再在全局窗口上分层抽样
sample_meta = build_global_stratified_samples(file_structs, data_folder, S60, num_samples);

%% ==================== 预先构建固定 GT 样本 ====================
% GT 与 As 无关，因此只需要为抽中的 10 个样本各算一次
sample_cache = repmat(struct( ...
    "file_name", "", ...
    "file_path", "", ...
    "c_start", 0, ...
    "signal60_input", [], ...
    "img_gt", []), num_samples, 1);

for sample_idx = 1:num_samples
    current_meta = sample_meta(sample_idx);
    current_data = load(current_meta.file_path);
    var_names = fieldnames(current_data);
    raw_data = current_data.(var_names{1});

    % 从当前回波文件中裁出一个有效窗口，再按 60MHz 链路取样
    channel_block = raw_data(:, current_meta.c_start:current_meta.c_start + S60.nrn - 1);
    signal60_input = channel_block(1:3:end, :);

    sample_cache(sample_idx).file_name = current_meta.file_name;
    sample_cache(sample_idx).file_path = current_meta.file_path;
    sample_cache(sample_idx).c_start = current_meta.c_start;
    sample_cache(sample_idx).signal60_input = signal60_input;
    sample_cache(sample_idx).img_gt = build_gt_image(signal60_input, S60);
end

%% ==================== 主循环：遍历 As ====================
num_as = numel(As_list);

psnr_full_all = zeros(num_as, num_samples);
ssim_full_all = zeros(num_as, num_samples);
psnr_split_all = zeros(num_as, num_samples);
ssim_split_all = zeros(num_as, num_samples);

for as_idx = 1:num_as
    As = As_list(as_idx);
    fprintf("正在处理 As = %.1f (%d / %d)\n", As, as_idx, num_as);

    % 每个 As 下都重置随机种子，保证 full RT / split RT 的对比口径稳定
    rng(seed + as_idx);

    for sample_idx = 1:num_samples
        signal60_input = sample_cache(sample_idx).signal60_input;
        img_gt = sample_cache(sample_idx).img_gt;

        % 方案一：逐点独立随机的 full 2D RT
        img_full = build_r2a2_image(signal60_input, S60, Azimuth_q, Range_q, As, "full");
        psnr_full_all(as_idx, sample_idx) = psnr(img_full, img_gt);
        ssim_full_all(as_idx, sample_idx) = ssim(img_full, img_gt);

        % 方案二：可分离的 split 2D RT
        img_split = build_r2a2_image(signal60_input, S60, Azimuth_q, Range_q, As, "split");
        psnr_split_all(as_idx, sample_idx) = psnr(img_split, img_gt);
        ssim_split_all(as_idx, sample_idx) = ssim(img_split, img_gt);
    end
end

%% ==================== 汇总统计 ====================
psnr_full_mean = mean(psnr_full_all, 2);
psnr_split_mean = mean(psnr_split_all, 2);
ssim_full_mean = mean(ssim_full_all, 2);
ssim_split_mean = mean(ssim_split_all, 2);

psnr_full_std = std(psnr_full_all, 0, 2);
psnr_split_std = std(psnr_split_all, 0, 2);
ssim_full_std = std(ssim_full_all, 0, 2);
ssim_split_std = std(ssim_split_all, 0, 2);

%% ==================== 保存数值结果 ====================
% 这里使用字符向量形式的 VariableNames，避免不同 MATLAB 版本
% 把字符串标量误判为普通表变量输入，导致 table 构造报错
result_table = table( ...
    As_list(:), ...
    psnr_full_mean, psnr_full_std, ...
    psnr_split_mean, psnr_split_std, ...
    ssim_full_mean, ssim_full_std, ...
    ssim_split_mean, ssim_split_std, ...
    'VariableNames', { ...
    'As', ...
    'PSNR_FullRT_Mean', 'PSNR_FullRT_Std', ...
    'PSNR_SplitRT_Mean', 'PSNR_SplitRT_Std', ...
    'SSIM_FullRT_Mean', 'SSIM_FullRT_Std', ...
    'SSIM_SplitRT_Mean', 'SSIM_SplitRT_Std'});

writetable(result_table, fullfile(output_dir, "R2A2_FullRT_vs_SplitRT_metrics.csv"));

save(fullfile(output_dir, "R2A2_FullRT_vs_SplitRT_metrics.mat"), ...
    "As_list", ...
    "psnr_full_all", "psnr_split_all", ...
    "ssim_full_all", "ssim_split_all", ...
    "psnr_full_mean", "psnr_split_mean", ...
    "ssim_full_mean", "ssim_split_mean", ...
    "psnr_full_std", "psnr_split_std", ...
    "ssim_full_std", "ssim_split_std", ...
    "sample_meta");

%% ==================== 绘制 PSNR 曲线图 ====================
plot_metric_curve( ...
    As_list, ...
    psnr_full_mean, psnr_split_mean, ...
    psnr_full_std, psnr_split_std, ...
    "PSNR (dB)", ...
    "R2A2: Full RT vs Split RT - PSNR", ...
    fullfile(output_dir, "R2A2_FullRT_vs_SplitRT_PSNR.png"));

%% ==================== 绘制 SSIM 曲线图 ====================
plot_metric_curve( ...
    As_list, ...
    ssim_full_mean, ssim_split_mean, ...
    ssim_full_std, ssim_split_std, ...
    "SSIM", ...
    "R2A2: Full RT vs Split RT - SSIM", ...
    fullfile(output_dir, "R2A2_FullRT_vs_SplitRT_SSIM.png"));

fprintf("全部完成，结果已保存到目录：%s\n", output_dir);


%% =========================================================
%% ==================== 局部函数区 =========================
%% =========================================================

% 从文件名中提取 rstart 的数字，用于排序
function value = extract_rstart_number(file_name)
    tokens = regexp(file_name, "rstart\s+(\d+)\.mat", "tokens", "once");
    if isempty(tokens)
        error("无法从文件名中提取 rstart 数字：%s", file_name);
    end
    value = str2double(tokens{1});
end

% 在全局有效窗口上做分层抽样，尽量覆盖完整 SAR 回波序列
function sample_meta = build_global_stratified_samples(file_structs, data_folder, S60, num_samples)
    num_files = numel(file_structs);
    window_counts = zeros(num_files, 1);
    file_paths = strings(num_files, 1);

    for file_idx = 1:num_files
        file_path = fullfile(data_folder, file_structs(file_idx).name);
        file_paths(file_idx) = string(file_path);

        var_info = whos("-file", file_path);
        if isempty(var_info)
            error("文件中未找到变量：%s", file_path);
        end

        raw_width = var_info(1).size(2);
        max_start = raw_width - S60.nrn + 1;
        if max_start < 1
            error("文件宽度不足以裁出一个完整窗口：%s", file_path);
        end

        window_counts(file_idx) = max_start;
    end

    total_windows = sum(window_counts);
    cumulative_counts = cumsum(window_counts);
    sample_meta = repmat(struct("file_name", "", "file_path", "", "c_start", 0), num_samples, 1);

    for sample_idx = 1:num_samples
        % 使用每个分层区间的中心位置，保证抽样均匀分布
        global_center = round((sample_idx - 0.5) / num_samples * total_windows);
        global_center = max(global_center, 1);
        global_center = min(global_center, total_windows);

        file_idx = find(cumulative_counts >= global_center, 1, "first");
        prev_count = 0;
        if file_idx > 1
            prev_count = cumulative_counts(file_idx - 1);
        end

        local_start = global_center - prev_count;
        sample_meta(sample_idx).file_name = file_structs(file_idx).name;
        sample_meta(sample_idx).file_path = char(file_paths(file_idx));
        sample_meta(sample_idx).c_start = local_start;
    end
end

% 构建固定 GT 图像，GT 不受 As 和 RT 类型影响
function img_gt = build_gt_image(signal60_input, S60)
    RC_gt = Range_Compress(signal60_input, S60.fc, S60.tnrn, S60.gama, S60.R0, S60.C, S60.Fs, S60.Tp);
    RCMC_gt = RCMC(RC_gt, S60.lambda, S60.fnrn, S60.fnan, S60.R0, S60.C, S60.v);
    IMG_gt = SAR_Imaging(RCMC_gt, S60.lambda, S60.Fs, S60.R0, S60.C, S60.v, S60.tnan, S60.Ta, S60.prf);

    roi_gt = abs(IMG_gt( ...
        S60.nrn / 2 - S60.R_total / 2 + 1:S60.nrn / 2 + S60.R_total / 2, ...
        S60.nan / 2 - S60.A_num / 2:S60.nan / 2 + S60.A_num / 2 - 1));

    img_gt = normalize_image(roi_gt);
end

% 根据 RT 类型构建 R2A2 图像
function img_out = build_r2a2_image(signal60_input, S60, Azimuth_q, Range_q, As, rt_mode)
    switch lower(rt_mode)
        case "full"
            [U_master_patch, ~, ~] = Build_2D_RT(signal60_input, Azimuth_q, Range_q, As);
        case "split"
            [U_master_patch, ~, ~] = Build_2D_SplitRT(signal60_input, Azimuth_q, Range_q, As);
        otherwise
            error("未知 RT 模式：%s", rt_mode);
    end

    signal60_patch_high = two_dim_upsample_fft(signal60_input, Azimuth_q, Range_q);
    tnrn_up = build_range_time_axis(signal60_patch_high, Range_q, S60);

    channel_1bit_high = quantize_1bit_with_U(signal60_patch_high, U_master_patch);
    RC_high = Range_Compress(channel_1bit_high, S60.fc, tnrn_up, S60.gama, S60.R0, S60.C, Range_q * S60.Fs, S60.Tp);
    RC_crop = two_dim_downsample_fft(RC_high, Azimuth_q, Range_q, S60);
    RCMC_crop = RCMC(RC_crop, S60.lambda, S60.fnrn, S60.fnan, S60.R0, S60.C, S60.v);
    IMG_high = SAR_Imaging(RCMC_crop, S60.lambda, S60.Fs, S60.R0, S60.C, S60.v, S60.tnan, S60.Ta, S60.prf);

    roi_crop = abs(IMG_high( ...
        S60.nrn / 2 - S60.R_total / 2 + 1:S60.nrn / 2 + S60.R_total / 2, ...
        S60.nan / 2 - S60.A_num / 2:S60.nan / 2 + S60.A_num / 2 - 1));

    img_out = normalize_image(roi_crop);
end

% 为距离向上采样后的回波重建对应的时间轴
function tnrn_up = build_range_time_axis(signal_up, Range_q, S60)
    nrn_up = size(signal_up, 1);
    Fs_up = Range_q * S60.Fs;
    Tnrn_up = 1 / Fs_up;
    Tstart_up = 2 * S60.R0 / S60.C - nrn_up / 2 / Fs_up;
    Tend_up = 2 * S60.R0 / S60.C + (nrn_up / 2 - 1) / Fs_up;
    tnrn_up = (Tstart_up:Tnrn_up:Tend_up).';
end

% 绘制指标曲线，并在图中同时给出均值曲线和标准差误差棒
function plot_metric_curve(x_values, y_full, y_split, std_full, std_split, y_label_text, title_text, save_path)
    figure("Color", "w", "Position", [120, 120, 980, 620]);
    hold on;
    box on;
    grid on;
    grid minor;

    % 使用误差棒体现 10 个样本的离散程度，便于后续判断稳定性
    eb1 = errorbar(x_values, y_full, std_full, "-o", ...
        "LineWidth", 1.8, ...
        "MarkerSize", 7, ...
        "CapSize", 8, ...
        "Color", [0.12, 0.47, 0.71], ...
        "MarkerFaceColor", [0.12, 0.47, 0.71]);

    eb2 = errorbar(x_values, y_split, std_split, "-s", ...
        "LineWidth", 1.8, ...
        "MarkerSize", 7, ...
        "CapSize", 8, ...
        "Color", [0.85, 0.33, 0.10], ...
        "MarkerFaceColor", [0.85, 0.33, 0.10]);

    xlabel("As", "FontSize", 13, "FontWeight", "bold");
    ylabel(y_label_text, "FontSize", 13, "FontWeight", "bold");
    title(title_text, "FontSize", 15, "FontWeight", "bold");
    legend([eb1, eb2], {"Full 2D RT", "Split 2D RT"}, ...
        "Location", "best", "FontSize", 12);

    ax = gca;
    ax.FontSize = 12;
    ax.LineWidth = 1.1;
    ax.XLim = [min(x_values), max(x_values)];

    % 在曲线末端标注最后一个 As 的均值，方便快速读结论
    text(x_values(end), y_full(end), sprintf("  %.4f", y_full(end)), ...
        "Color", [0.12, 0.47, 0.71], "FontSize", 11, "FontWeight", "bold");
    text(x_values(end), y_split(end), sprintf("  %.4f", y_split(end)), ...
        "Color", [0.85, 0.33, 0.10], "FontSize", 11, "FontWeight", "bold");

    exportgraphics(gcf, save_path, "Resolution", 220);
    close(gcf);
end

% 一次生成二维 full RT 阈值场
function [U, sigma, A_rt] = Build_2D_RT(input60, Azimuth_q, Range_q, As)
    signal_up = two_dim_upsample_fft(input60, Azimuth_q, Range_q);

    sigma = sqrt(2 / pi) * mean(abs(signal_up(:)));
    A_rt = As * sigma;

    phi = 2 * pi * rand(size(signal_up));
    U = A_rt * exp(1i * phi);
end

% 生成可分离的二维 RT 阈值场
% 先构造距离向列相位，再构造方位向行相位，最后按点合成二维相位
function [U, sigma, A_rt] = Build_2D_SplitRT(input60, Azimuth_q, Range_q, As)
    signal_up_2d = two_dim_upsample_fft(input60, Azimuth_q, Range_q);
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
