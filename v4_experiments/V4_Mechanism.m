function V4_Mechanism()
% V4机制实验：统一4x4频率画布、共享色标和共享场景色条。

cfg = V4Core.config();
addpath(cfg.repo_root, cfg.experiment_dir);
output_dir = fullfile(cfg.output_root, "Mechanism");
V4Core.ensureDir(cfg.output_root);
V4Core.ensureDir(output_dir);
S60 = load(cfg.parameter_file);

seed = 42;
As = 0.6;
dataset_name = "SAR_Dataset_city2_histeq";
file_name = "rstart 301.mat";
c_start = 6500;
data_path = fullfile(cfg.data_root, dataset_name, file_name);
signal60 = loadSignal(data_path, c_start, S60.nrn);

case_defs = struct( ...
    "Name", {"R1A1", "R4A1", "R1A4", "R2A2"}, ...
    "Range_q", {1, 4, 1, 2}, ...
    "Azimuth_q", {1, 1, 4, 2});
num_cases = numel(case_defs);
results = repmat(struct( ...
    "Name", "", "Range_q", 0, "Azimuth_q", 0, ...
    "RC_raw", [], "RC_crop", [], "ROI", [], "ReferenceRC", [], ...
    "ThresholdMeanAbs", NaN), num_cases, 1);

for idx = 1:num_cases
    rng(seed + idx);
    [nodes, reference_rc] = V4Core.buildMechanismNodes( ...
        signal60, S60, case_defs(idx).Range_q, ...
        case_defs(idx).Azimuth_q, As);
    results(idx).Name = string(case_defs(idx).Name);
    results(idx).Range_q = case_defs(idx).Range_q;
    results(idx).Azimuth_q = case_defs(idx).Azimuth_q;
    results(idx).RC_raw = nodes.RC_raw;
    results(idx).RC_crop = nodes.RC_crop;
    results(idx).ROI = nodes.ROI;
    results(idx).ReferenceRC = reference_rc;
    results(idx).ThresholdMeanAbs = nodes.ThresholdMeanAbs;
end

metric_table = buildMetricTable(results);
writetable(metric_table, fullfile(output_dir, "V4_Mechanism_Metrics.csv"));
exportSpectrumFigure(results, S60, ...
    fullfile(output_dir, "V4_Mechanism_Common4x4.png"));
img_gt = V4Core.buildGTImage(signal60, S60);
exportSceneFigure(img_gt, results, ...
    fullfile(output_dir, "V4_Scene_SharedColorbar.png"));

scene_rois = cat(3, img_gt, results(2).ROI, results(3).ROI, results(4).ROI);
save(fullfile(output_dir, "V4_Mechanism_Data.mat"), ...
    "seed", "As", "dataset_name", "file_name", "c_start", ...
    "case_defs", "metric_table", "scene_rois", "-v7.3");
writeMetadata(cfg, seed, As, dataset_name, file_name, c_start, output_dir);
fprintf("V4机制实验完成：%s\n", output_dir);
end

function signal60 = loadSignal(data_path, c_start, nrn)
loaded = load(data_path);
names = fieldnames(loaded);
raw = loaded.(names{1});
if size(raw, 2) < c_start + nrn - 1
    error("固定机制样本宽度不足。");
end
block = raw(:, c_start:c_start + nrn - 1);
signal60 = block(1:3:end, :);
end

function metric_table = buildMetricTable(results)
num_cases = numel(results);
Allocation = strings(num_cases, 1);
Range_q = zeros(num_cases, 1);
Azimuth_q = zeros(num_cases, 1);
OffSupport = zeros(num_cases, 1);
RangeLeakage = zeros(num_cases, 1);
AzimuthLeakage = zeros(num_cases, 1);
ThresholdMeanAbs = zeros(num_cases, 1);

for idx = 1:num_cases
    [OffSupport(idx), RangeLeakage(idx), AzimuthLeakage(idx)] = ...
        V4Core.leakageMetrics( ...
        results(idx).RC_crop, ...
        results(idx).ReferenceRC, 0.35);
    Allocation(idx) = results(idx).Name;
    Range_q(idx) = results(idx).Range_q;
    Azimuth_q(idx) = results(idx).Azimuth_q;
    ThresholdMeanAbs(idx) = results(idx).ThresholdMeanAbs;
end

metric_table = table( ...
    Allocation, Range_q, Azimuth_q, ...
    OffSupport, RangeLeakage, AzimuthLeakage, ThresholdMeanAbs);
end

function exportSpectrumFigure(results, S60, save_path)
num_cases = numel(results);
specs = cell(num_cases, 1);
sample_values = [];
for idx = 1:num_cases
    specs{idx} = log1p(abs(fftshift(fft2(results(idx).RC_raw))));
    step = max(1, floor(numel(specs{idx}) / 200000));
    sampled = specs{idx}(1:step:end);
    sample_values = [sample_values; sampled(:)]; %#ok<AGROW>
end
color_limits = [ ...
    V4Core.percentile(sample_values, 1), ...
    V4Core.percentile(sample_values, 99.5)];

fig = figure("Color", "w", "Units", "centimeters", ...
    "Position", [2, 2, 18, 10], "Visible", "off");
layout = tiledlayout(fig, 2, 2, ...
    "Padding", "compact", "TileSpacing", "compact");
cmap = turbo(256);
panel_labels = ["(a)", "(b)", "(c)", "(d)"];
for idx = 1:num_cases
    ax = nexttile(layout);
    range_q = results(idx).Range_q;
    azimuth_q = results(idx).Azimuth_q;
    x_azimuth = ((0:size(specs{idx}, 2) - 1) - ...
        floor(size(specs{idx}, 2) / 2)) / S60.nan;
    y_range = ((0:size(specs{idx}, 1) - 1) - ...
        floor(size(specs{idx}, 1) / 2)) / S60.nrn;
    imagesc(ax, x_azimuth, y_range, specs{idx});
    set(ax, "YDir", "normal", "Color", cmap(1, :), ...
        "FontName", "Times New Roman", "FontSize", 7, ...
        "TickDir", "out", "Box", "on");
    axis(ax, "image");
    xlim(ax, [-2, 2]);
    ylim(ax, [-2, 2]);
    clim(ax, color_limits);
    xlabel(ax, "Azimuth frequency", ...
        "FontName", "Times New Roman", "FontSize", 8);
    ylabel(ax, "Range frequency", ...
        "FontName", "Times New Roman", "FontSize", 8);
    title(ax, sprintf("%s R%dA%d", ...
        panel_labels(idx), range_q, azimuth_q), ...
        "FontName", "Times New Roman", "FontSize", 9, ...
        "FontWeight", "normal");
end
colormap(fig, cmap);
cb = colorbar;
cb.Layout.Tile = "east";
cb.FontName = "Times New Roman";
cb.FontSize = 8;
ylabel(cb, "log(1 + |FFT|)", ...
    "FontName", "Times New Roman", "FontSize", 8);
exportgraphics(fig, save_path, "Resolution", 300);
close(fig);
end

function exportSceneFigure(img_gt, results, save_path)
fig = figure("Color", "w", "Units", "centimeters", ...
    "Position", [2, 2, 18, 5.2], "Visible", "off");
layout = tiledlayout(fig, 1, 4, ...
    "Padding", "compact", "TileSpacing", "compact");
panel_labels = ["(a)", "(b)", "(c)", "(d)"];
scene_names = ["GT", "R4A1", "R1A4", "R2A2"];
scene_images = {img_gt, results(2).ROI, results(3).ROI, results(4).ROI};
for idx = 1:numel(scene_images)
    ax = nexttile(layout);
    imagesc(ax, scene_images{idx}, [0, 1]);
    axis(ax, "image", "off");
    title(ax, sprintf("%s %s", panel_labels(idx), scene_names(idx)), ...
        "FontName", "Times New Roman", "FontSize", 9, ...
        "FontWeight", "normal");
end
colormap(fig, gray);
cb = colorbar;
cb.Layout.Tile = "east";
cb.FontName = "Times New Roman";
cb.FontSize = 8;
ylabel(cb, "Normalized amplitude", ...
    "FontName", "Times New Roman", "FontSize", 8);
exportgraphics(fig, save_path, "Resolution", 300);
close(fig);
end

function writeMetadata( ...
        cfg, seed, As, dataset_name, file_name, c_start, output_dir)
fid = fopen(fullfile(output_dir, "V4_Mechanism_Metadata.txt"), "w");
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, "Seed=%d\n", seed);
fprintf(fid, "As=%.16g\n", As);
fprintf(fid, "Dataset=%s\n", dataset_name);
fprintf(fid, "File=%s\n", file_name);
fprintf(fid, "CStart=%d\n", c_start);
fprintf(fid, "SpectrumX=Azimuth frequency\n");
fprintf(fid, "SpectrumY=Range frequency\n");
fprintf(fid, "SpectrumLimits=[-2,2]x[-2,2]\n");
fprintf(fid, "RTFigureReuse=%s\n", cfg.rt_figure);
fprintf(fid, "RSFTFigureReuse=%s\n", cfg.rsft_figure);
end
