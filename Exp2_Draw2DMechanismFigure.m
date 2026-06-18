clear; clc; close all;

% 在批处理环境中优先使用软件渲染，降低导出时的图形驱动崩溃概率。
try
    opengl("software");
catch
    % 某些 MATLAB 环境下可能不允许切换，失败时保持默认设置继续尝试。
end

% 实验二二维机制示意图：
% 用概念图说明双向上采样如何把 1-bit 量化误差从有效二维频谱支撑附近推开，
% 以及为何这种优势会在距离压缩（RC）后更容易被观测。

output_dir = fullfile(pwd, "MD");
output_png = fullfile(output_dir, "Exp2_2D_Mechanism_Figure.png");
output_pdf = fullfile(output_dir, "Exp2_2D_Mechanism_Figure.pdf");

if ~exist(output_dir, "dir")
    mkdir(output_dir);
end

panel_titles = { ...
    "(a) Ideal 2D support", ...
    "(b) No upsampling", ...
    "(c) Range-only upsampling", ...
    "(d) Azimuth-only upsampling", ...
    "(e) Bidirectional upsampling", ...
    "(f) Why visible after RC"};

fig = figure( ...
    "Color", "w", ...
    "Position", [80, 80, 1500, 900], ...
    "Visible", "off", ...
    "Renderer", "painters");
t = tiledlayout(fig, 2, 3, "Padding", "compact", "TileSpacing", "compact");

draw_panel_a(nexttile(t, 1), panel_titles{1});
draw_panel_b(nexttile(t, 2), panel_titles{2});
draw_panel_c(nexttile(t, 3), panel_titles{3});
draw_panel_d(nexttile(t, 4), panel_titles{4});
draw_panel_e(nexttile(t, 5), panel_titles{5});
draw_panel_f(nexttile(t, 6), panel_titles{6});

sgtitle(t, "Experiment 2: 2D Mechanism of Bidirectional Upsampling", ...
    "FontWeight", "bold", "FontSize", 16);

exportgraphics(fig, output_png, "Resolution", 300);
exportgraphics(fig, output_pdf, "ContentType", "vector");
close(fig);

fprintf("已导出 PNG：%s\n", output_png);
fprintf("已导出 PDF：%s\n", output_pdf);

function draw_panel_a(ax, panel_title)
    setup_support_axes(ax);
    draw_support_box(ax);
    draw_signal_core(ax);
    title(ax, panel_title, "Interpreter", "none", "FontWeight", "bold");
    text(ax, 0, -0.76, "signal energy is mainly confined inside the effective support", ...
        "HorizontalAlignment", "center", "FontSize", 9, "Color", [0.20 0.20 0.20]);
end

function draw_panel_b(ax, panel_title)
    setup_support_axes(ax);
    draw_noise_blob(ax, [-0.38, -0.30, 0.76, 0.60], 0.12, 0.26);
    draw_support_box(ax);
    draw_signal_core(ax);
    title(ax, panel_title, "Interpreter", "none", "FontWeight", "bold");
    text(ax, 0, -0.76, "quantization noise heavily overlaps the useful 2D support", ...
        "HorizontalAlignment", "center", "FontSize", 9, "Color", [0.20 0.20 0.20]);
end

function draw_panel_c(ax, panel_title)
    setup_support_axes(ax);
    draw_noise_blob(ax, [-0.30, -0.88, 0.60, 1.76], 0.10, 0.22);
    draw_support_box(ax);
    draw_signal_core(ax);
    draw_arrow(ax, [0.00, 0.32], [0.00, 0.62]);
    draw_arrow(ax, [0.00, -0.32], [0.00, -0.62]);
    title(ax, panel_title, "Interpreter", "none", "FontWeight", "bold");
    text(ax, 0, -0.76, "range redundancy pushes noise upward/downward; azimuth overlap remains", ...
        "HorizontalAlignment", "center", "FontSize", 9, "Color", [0.20 0.20 0.20]);
end

function draw_panel_d(ax, panel_title)
    setup_support_axes(ax);
    draw_noise_blob(ax, [-0.92, -0.28, 1.84, 0.56], 0.10, 0.22);
    draw_support_box(ax);
    draw_signal_core(ax);
    draw_arrow(ax, [0.34, 0.00], [0.66, 0.00]);
    draw_arrow(ax, [-0.34, 0.00], [-0.66, 0.00]);
    title(ax, panel_title, "Interpreter", "none", "FontWeight", "bold");
    text(ax, 0, -0.76, "azimuth redundancy pushes noise left/right; range overlap remains", ...
        "HorizontalAlignment", "center", "FontSize", 9, "Color", [0.20 0.20 0.20]);
end

function draw_panel_e(ax, panel_title)
    setup_support_axes(ax);
    draw_noise_blob(ax, [-0.94, -0.90, 1.88, 1.80], 0.16, 0.16);
    draw_support_box(ax);
    draw_signal_core(ax);
    draw_arrow(ax, [0.28, 0.22], [0.58, 0.52]);
    draw_arrow(ax, [-0.28, 0.22], [-0.58, 0.52]);
    draw_arrow(ax, [0.28, -0.22], [0.58, -0.52]);
    draw_arrow(ax, [-0.28, -0.22], [-0.58, -0.52]);
    title(ax, panel_title, "Interpreter", "none", "FontWeight", "bold");
    text(ax, 0, -0.76, "noise is jointly pushed away in both dimensions, leaving the core cleaner", ...
        "HorizontalAlignment", "center", "FontSize", 9, "Color", [0.20 0.20 0.20]);
end

function draw_panel_f(ax, panel_title)
    axis(ax, [0, 1, 0, 1]);
    axis(ax, "off");
    hold(ax, "on");
    title(ax, panel_title, "Interpreter", "none", "FontWeight", "bold");

    % 左侧表示 RC 前：优势已经存在，但不够显眼。
    draw_filled_box(ax, [0.08, 0.28, 0.23, 0.25], [0.22 0.45 0.88], 0.85);
    rectangle(ax, ...
        "Position", [0.05, 0.24, 0.29, 0.33], ...
        "Curvature", 0.10, ...
        "FaceColor", "none", ...
        "EdgeColor", [0.40 0.40 0.40], ...
        "LineStyle", "--", ...
        "LineWidth", 1.1);
    text(ax, 0.195, 0.68, "Node-1", ...
        "HorizontalAlignment", "center", "FontWeight", "bold", "FontSize", 11);
    text(ax, 0.195, 0.14, "overlap is already reduced," + newline + "but not yet strongly visible", ...
        "HorizontalAlignment", "center", "FontSize", 9, "Color", [0.20 0.20 0.20]);

    % 用局部几何代替 annotation，避免导出时坐标漂移。
    plot(ax, [0.36, 0.61], [0.40, 0.40], "k-", "LineWidth", 1.5);
    plot(ax, [0.58, 0.61], [0.43, 0.40], "k-", "LineWidth", 1.5);
    plot(ax, [0.58, 0.61], [0.37, 0.40], "k-", "LineWidth", 1.5);
    text(ax, 0.485, 0.47, "Range compression", ...
        "HorizontalAlignment", "center", "FontWeight", "bold", "FontSize", 10);

    % 右侧表示 RC 后：有效结构被突出，支撑外误差更像背景泄漏。
    draw_filled_box(ax, [0.68, 0.30, 0.17, 0.21], [0.22 0.45 0.88], 0.92);
    draw_filled_box(ax, [0.62, 0.23, 0.29, 0.35], [0.92 0.40 0.12], 0.08);
    text(ax, 0.765, 0.68, "Node-2 after RC", ...
        "HorizontalAlignment", "center", "FontWeight", "bold", "FontSize", 11);
    text(ax, 0.765, 0.14, "matched filtering makes the" + newline + "bidirectional advantage easier to observe", ...
        "HorizontalAlignment", "center", "FontSize", 9, "Color", [0.20 0.20 0.20]);
end

function setup_support_axes(ax)
    axis(ax, [-1, 1, -1, 1]);
    axis(ax, "square");
    box(ax, "on");
    grid(ax, "off");
    hold(ax, "on");
    set(ax, "XTick", [], "YTick", [], "LineWidth", 1.0, "FontName", "Times New Roman");
    xlabel(ax, "Azimuth frequency / Doppler");
    ylabel(ax, "Range frequency");
end

function draw_support_box(ax)
    rectangle(ax, ...
        "Position", [-0.35, -0.28, 0.70, 0.56], ...
        "LineStyle", "--", ...
        "LineWidth", 1.2, ...
        "EdgeColor", [0.20 0.20 0.20]);
    text(ax, 0, 0.40, "effective 2D signal support", ...
        "HorizontalAlignment", "center", "FontSize", 10, ...
        "BackgroundColor", "w", "Margin", 0.1);
end

function draw_signal_core(ax)
    draw_filled_box(ax, [-0.22, -0.18, 0.44, 0.36], [0.22 0.45 0.88], 0.78, ...
        "EdgeColor", [0.10 0.24 0.56], "LineWidth", 1.0);
    text(ax, 0, 0.00, "useful signal core", ...
        "HorizontalAlignment", "center", "VerticalAlignment", "middle", ...
        "Color", "w", "FontWeight", "bold", "FontSize", 10);
end

function draw_noise_blob(ax, position_vec, curvature_val, face_alpha)
    x0 = position_vec(1);
    y0 = position_vec(2);
    w = position_vec(3);
    h = position_vec(4);
    cx = x0 + w / 2;
    cy = y0 + h / 2;
    theta = linspace(0, 2 * pi, 240);
    x = cx + (w / 2) * cos(theta);
    y = cy + (h / 2) * sin(theta);

    % 用椭圆噪声云替代透明圆角矩形，兼容性比 rectangle RGBA 更稳。
    patch(ax, x, y, [0.92 0.40 0.12], ...
        "FaceAlpha", face_alpha, ...
        "EdgeColor", "none");

    if curvature_val > 0.12
        patch(ax, cx + 0.82 * (w / 2) * cos(theta), cy + 0.82 * (h / 2) * sin(theta), ...
            [0.92 0.40 0.12], ...
            "FaceAlpha", max(face_alpha - 0.04, 0.06), ...
            "EdgeColor", "none");
    end
end

function draw_arrow(ax, start_xy, end_xy)
    quiver(ax, start_xy(1), start_xy(2), ...
        end_xy(1) - start_xy(1), end_xy(2) - start_xy(2), 0, ...
        "Color", [0.76 0.16 0.12], ...
        "LineWidth", 1.4, ...
        "MaxHeadSize", 0.42);
end

function draw_filled_box(ax, position_vec, face_color, face_alpha, varargin)
    x0 = position_vec(1);
    y0 = position_vec(2);
    w = position_vec(3);
    h = position_vec(4);
    x = [x0, x0 + w, x0 + w, x0];
    y = [y0, y0, y0 + h, y0 + h];
    patch(ax, x, y, face_color, ...
        "FaceAlpha", face_alpha, ...
        varargin{:});
end
