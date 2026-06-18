clear; clc; close all;

% 实验二二维机制图：
% 不再绘制概念示意图，而是直接读取 Exp2_Mechanism_Output 中的真实中间数据，
% 用 2x3 面板展示“Node-1 残差谱 -> Node-2 RC 后谱”的实际变化。

script_dir = fileparts(mfilename("fullpath"));
if script_dir == ""
    script_dir = pwd;
end

data_dir = fullfile(script_dir, "Exp2_Mechanism_Output");
data_path = fullfile(data_dir, "Exp2_Mechanism_Data.mat");
output_png = fullfile(data_dir, "Exp2_2D_Mechanism_Figure.png");
output_pdf = fullfile(data_dir, "Exp2_2D_Mechanism_Figure.pdf");

assert(exist(data_path, "file") == 2, "未找到实验二数据文件：%s", data_path);

loaded_data = load(data_path, "results");
results = loaded_data.results;

required_case_order = ["R1A1_NoUp", "R4A1", "R1A4", "R2A2"];
ordered_results = reorder_results_by_case(results, required_case_order);

% 六个面板的设计：
% 第一行：Node-1 残差谱，分别展示 NoUp / RangeOnly / AzimuthOnly
% 第二行：左侧给出双向方案的 Node-1 残差谱；中间和右侧给出 Node-2 RC 后的
% NoUp 与 R2A2，用于直接观察 RC 如何把双向优势“显影”出来。
panel_defs = [ ...
    struct("case_name", "R1A1_NoUp", "node_field", "node1_residual", "title_text", "(a) Node-1 Residual: NoUp"); ...
    struct("case_name", "R4A1",      "node_field", "node1_residual", "title_text", "(b) Node-1 Residual: Range-only"); ...
    struct("case_name", "R1A4",      "node_field", "node1_residual", "title_text", "(c) Node-1 Residual: Azimuth-only"); ...
    struct("case_name", "R2A2",      "node_field", "node1_residual", "title_text", "(d) Node-1 Residual: Bidirectional"); ...
    struct("case_name", "R1A1_NoUp", "node_field", "node2_rc_raw",   "title_text", "(e) Node-2 RC: NoUp"); ...
    struct("case_name", "R2A2",      "node_field", "node2_rc_raw",   "title_text", "(f) Node-2 RC: Bidirectional") ...
    ];

[global_clim_node1, global_clim_node2] = compute_global_clim(ordered_results);

fig = figure( ...
    "Color", "w", ...
    "Position", [80, 80, 1500, 900], ...
    "Visible", "off", ...
    "Renderer", "painters");
cleanup_obj = onCleanup(@() close_valid_figure(fig)); %#ok<NASGU>

t = tiledlayout(fig, 2, 3, "Padding", "compact", "TileSpacing", "compact");

for panel_idx = 1:numel(panel_defs)
    ax = nexttile(t, panel_idx);
    panel_def = panel_defs(panel_idx);
    result_struct = get_case_result(ordered_results, panel_def.case_name);

    if panel_def.node_field == "node1_residual"
        clim_range = global_clim_node1;
    else
        clim_range = global_clim_node2;
    end

    draw_spectrum_panel(ax, result_struct.(panel_def.node_field), panel_def.title_text, clim_range);
end

title_text = build_exp2_mechanism_figure_title();
sgtitle(t, title_text, "FontWeight", "bold", "FontSize", 15);

exportgraphics(fig, output_png, "Resolution", 300);
exportgraphics(fig, output_pdf, "ContentType", "image", "Resolution", 300);

fprintf("已导出 PNG：%s\n", output_png);
fprintf("已导出 PDF：%s\n", output_pdf);

function ordered_results = reorder_results_by_case(results, case_order)
    ordered_results = repmat(results(1), numel(case_order), 1);
    for idx = 1:numel(case_order)
        ordered_results(idx) = get_case_result(results, case_order(idx));
    end
end

function result_struct = get_case_result(results, case_name)
    case_names = strings(numel(results), 1);
    for idx = 1:numel(results)
        case_names(idx) = string(results(idx).case_name);
    end

    matched_idx = find(case_names == string(case_name), 1, "first");
    assert(~isempty(matched_idx), "未找到案例：%s", case_name);
    result_struct = results(matched_idx);
end

function [clim_node1, clim_node2] = compute_global_clim(results)
    node1_specs = cell(numel(results), 1);
    node2_specs = cell(numel(results), 1);

    for idx = 1:numel(results)
        node1_specs{idx} = compute_log_spectrum(results(idx).node1_residual);
        node2_specs{idx} = compute_log_spectrum(results(idx).node2_rc_raw);
    end

    clim_node1 = build_robust_clim(node1_specs);
    clim_node2 = build_robust_clim(node2_specs);
end

function clim = build_robust_clim(spec_cells)
    all_values = [];
    for idx = 1:numel(spec_cells)
        all_values = [all_values; spec_cells{idx}(:)]; %#ok<AGROW>
    end

    low_val = select_percentile(all_values, 0.05);
    high_val = select_percentile(all_values, 0.995);

    if high_val <= low_val
        low_val = min(all_values);
        high_val = max(all_values);
    end

    clim = [low_val, high_val];
end

function draw_spectrum_panel(ax, X, title_text, clim_range)
    spec = compute_log_spectrum(X);
    imagesc(ax, spec);
    axis(ax, "image");
    set(ax, "YDir", "normal");
    colormap(ax, turbo(256));
    set(ax, "CLim", clim_range);
    colorbar(ax);

    title(ax, title_text, "Interpreter", "none", "FontWeight", "bold");
    xlabel(ax, "方位向频率样本");
    ylabel(ax, "距离向频率样本");

    % 这里只标“样本”，不强行标成物理频率值，因为当前导出的中间结果已经离散在 FFT 网格上。
    set(ax, ...
        "FontName", "Times New Roman", ...
        "LineWidth", 1.0, ...
        "Box", "on");
end

function spec = compute_log_spectrum(X)
    spec = log1p(abs(fftshift(fft2(X))));
end

function value = select_percentile(values, ratio)
    values = sort(values(:));
    idx = max(1, min(numel(values), round(ratio * numel(values))));
    value = values(idx);
end

function close_valid_figure(fig)
    if isgraphics(fig)
        close(fig);
    end
end
