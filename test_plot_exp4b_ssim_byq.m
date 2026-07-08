clear; clc;

old_visibility = get(groot, "defaultFigureVisible");
set(groot, "defaultFigureVisible", "off");
cleanup = onCleanup(@() set(groot, "defaultFigureVisible", old_visibility));

close all;
run("Plot_Exp4B_SSIM_ByQ.m");

figs = findall(groot, "Type", "figure");
assert(numel(figs) == 2, "应生成两个独立窗口：NCT 与 SplitRT。");

for fig_idx = 1:numel(figs)
    axes_list = findall(figs(fig_idx), "Type", "axes");
    axes_list = axes_list(~strcmp(get(axes_list, "Tag"), "legend"));
    assert(numel(axes_list) == 1, "每个窗口应只包含一个坐标轴。");

    err_list = findall(axes_list(1), "Type", "errorbar");
    assert(numel(err_list) == 3, "每个窗口应包含3条 mean ± std 误差棒曲线。");

    line_list = findall(axes_list(1), "Type", "line");
    assert(numel(line_list) >= 3, "每个窗口应包含3个最优点标记。");
end

assert(~exist("sample_cache", "var"), "绘图脚本不应加载 sample_cache。");
disp("test_plot_exp4b_ssim_byq passed.");
