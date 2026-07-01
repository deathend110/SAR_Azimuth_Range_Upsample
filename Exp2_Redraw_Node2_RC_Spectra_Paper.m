clear; clc; close all;

%% =========================================================
%  重绘实验二 Node-2 RC 频谱图（论文排版版）
%  只读取 Exp2_Mechanism_Data.mat，不重跑 SAR 成像流程。
%  输出会覆盖 Exp2_Mechanism_Output/Exp2_Node2_RC_Spectra.png。
%% =========================================================

output_dir = fullfile(pwd, "Exp2_Mechanism_Output");
data_file = fullfile(output_dir, "Exp2_Mechanism_Data.mat");
save_file = fullfile(output_dir, "Exp2_Node2_RC_Spectra.png");

if ~isfile(data_file)
    error("找不到机制实验数据文件：%s", data_file);
end

loaded = load(data_file, "results");
results = loaded.results;

export_node2_rc_spectra_paper(results, save_file);
fprintf("论文排版版 Node-2 RC 频谱图已保存：%s\n", save_file);

%% =========================================================
%% 局部函数
%% =========================================================

function export_node2_rc_spectra_paper(results, save_file)
    % 使用 raw RC 频谱展示不同上采样分配造成的二维频谱支撑差异。
    % 统一色标避免每个子图独立拉伸导致视觉比较失真。
    node_field = "node2_rc_raw";
    case_order = ["R1A1_NoUp", "R4A1", "R1A4", "R2A2"];
    panel_titles = [ ...
        "(a) No upsampling (R1A1)", ...
        "(b) Range-only (R4A1)", ...
        "(c) Azimuth-only (R1A4)", ...
        "(d) Bidirectional (R2A2)" ...
    ];

    specs = cell(numel(case_order), 1);
    for i = 1:numel(case_order)
        idx = find(string({results.case_name}) == case_order(i), 1);
        if isempty(idx)
            error("results 中找不到案例：%s", case_order(i));
        end
        specs{i} = compute_log_spectrum(results(idx).(node_field));
    end

    all_values = cell2mat(cellfun(@(x) x(:), specs, "UniformOutput", false));
    color_limits = [local_percentile(all_values, 1), local_percentile(all_values, 99.5)];

    fig = figure("Color", "w", "Units", "centimeters", "Position", [2, 2, 18, 10]);
    layout = tiledlayout(fig, 2, 2, "Padding", "compact", "TileSpacing", "compact");

    for i = 1:numel(specs)
        ax = nexttile(layout);
        range_freq = shifted_frequency_axis(size(specs{i}, 2));
        azimuth_freq = shifted_frequency_axis(size(specs{i}, 1));
        imagesc(ax, range_freq, azimuth_freq, specs{i});
        axis(ax, "image");
        clim(ax, color_limits);
        xlabel(ax, "Range frequency", "FontName", "Times New Roman", "FontSize", 8);
        ylabel(ax, "Azimuth frequency", "FontName", "Times New Roman", "FontSize", 8);
        set(ax, "YDir", "normal", "FontName", "Times New Roman", "FontSize", 7, ...
            "TickDir", "out", "Box", "on");
        title(ax, panel_titles(i), "Interpreter", "none", ...
            "FontName", "Times New Roman", "FontSize", 9, "FontWeight", "normal");
    end

    colormap(fig, turbo);
    cb = colorbar;
    cb.Layout.Tile = "east";
    cb.FontName = "Times New Roman";
    cb.FontSize = 8;
    ylabel(cb, "log(1 + |FFT|)", "FontName", "Times New Roman", "FontSize", 8);

    exportgraphics(fig, save_file, "Resolution", 600);
    close(fig);
end

function spec = compute_log_spectrum(X)
    spec = log1p(abs(fftshift(fft2(X))));
end

function freq = shifted_frequency_axis(n)
    % 归一化频率坐标，与 fftshift 后的二维频谱顺序一致。
    freq = ((0:n-1) - floor(n / 2)) / n;
end

function value = local_percentile(x, p)
    x = sort(x(~isnan(x)));
    if isempty(x)
        value = NaN;
        return;
    end

    pos = 1 + (numel(x) - 1) * p / 100;
    lo = floor(pos);
    hi = ceil(pos);
    if lo == hi
        value = x(lo);
    else
        value = x(lo) + (x(hi) - x(lo)) * (pos - lo);
    end
end
