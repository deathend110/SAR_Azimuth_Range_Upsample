clc;

data_path = fullfile("Exp4B_ThresholdAs_ByQ_Output", "Exp4B_ThresholdAs_ByQ_Data.mat");
if ~isfile(data_path)
    error("未找到实验数据文件：%s", data_path);
end

% 只读取绘图所需的轻量变量，避免加载 sample_cache 大矩阵。
data = load(data_path, ...
    "rxax_configs", "As_list", ...
    "ssim_mean_nct", "ssim_std_nct", ...
    "ssim_mean_rt", "ssim_std_rt", ...
    "total_samples");

figure("Color", "w", "Position", [100, 100, 1200, 450]);
plot_threshold_panel(1, data.rxax_configs, data.As_list, ...
    data.ssim_mean_nct, "NCT", data.total_samples);
plot_threshold_panel(2, data.rxax_configs, data.As_list, ...
    data.ssim_mean_rt, "SplitRT", data.total_samples);

function plot_threshold_panel(panel_idx, rxax_configs, As_list, ssim_mean, threshold_name, total_samples)
    subplot(1, 2, panel_idx);
    hold on; grid on; box on;

    colors_q = lines(numel(rxax_configs));
    curve_handles = gobjects(1, numel(rxax_configs));
    legend_names = strings(1, numel(rxax_configs));

    fprintf("\n%s 最优 As 汇总：\n", threshold_name);
    for cfg_idx = 1:numel(rxax_configs)
        cfg = rxax_configs(cfg_idx);
        y = ssim_mean(cfg_idx, :);
        [best_ssim, best_idx] = max(y);
        best_As = As_list(best_idx);

        curve_handles(cfg_idx) = plot(As_list, y, "-o", ...
            "Color", colors_q(cfg_idx, :), ...
            "LineWidth", 1.8, ...
            "MarkerSize", 6);
        plot(best_As, best_ssim, "p", ...
            "Color", colors_q(cfg_idx, :), ...
            "MarkerFaceColor", colors_q(cfg_idx, :), ...
            "MarkerSize", 11, ...
            "HandleVisibility", "off");

        legend_names(cfg_idx) = sprintf("%s, Q=%d", cfg.group_name, cfg.Q);
        fprintf("  %-7s Q=%-2d  best As=%.1f  best SSIM=%.6f\n", ...
            cfg.group_name, cfg.Q, best_As, best_ssim);
    end

    xlabel("A_s", "FontSize", 12);
    ylabel("SSIM", "FontSize", 12);
    title(sprintf("(%c) %s: SSIM-A_s curves (n=%d)", ...
        char('a' + panel_idx - 1), threshold_name, total_samples), "FontSize", 13);
    legend(curve_handles, legend_names, "Location", "best", "FontSize", 10);
    set(gca, "FontSize", 11);
end
