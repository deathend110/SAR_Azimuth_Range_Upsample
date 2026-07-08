clear; clc;

old_visibility = get(groot, "defaultFigureVisible");
set(groot, "defaultFigureVisible", "off");
cleanup = onCleanup(@() set(groot, "defaultFigureVisible", old_visibility));

close all;
run("Plot_Exp4B_SSIM_ByQ.m");

figs = findall(groot, "Type", "figure");
assert(numel(figs) == 1, "应只生成一张图。");

axes_list = findall(figs(1), "Type", "axes");
axes_list = axes_list(~strcmp(get(axes_list, "Tag"), "legend"));
assert(numel(axes_list) == 2, "应生成两个子图：NCT 与 SplitRT。");

for ax_idx = 1:numel(axes_list)
    line_list = findall(axes_list(ax_idx), "Type", "line");
    assert(numel(line_list) >= 6, "每个子图应包含3条曲线和3个最优点标记。");
end

assert(~exist("sample_cache", "var"), "绘图脚本不应加载 sample_cache。");
disp("test_plot_exp4b_ssim_byq passed.");
