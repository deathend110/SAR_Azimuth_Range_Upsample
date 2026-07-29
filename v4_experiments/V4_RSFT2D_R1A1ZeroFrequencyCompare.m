function V4_RSFT2D_R1A1ZeroFrequencyCompare()
% 对比R1A1下搜索最优二维RSFT阈值与双零频阈值。
%
% 两组实验固定使用相同STR，仅将fr/Br和fa/Ba设为0，
% 从而单独考察阈值相位调制对1-bit SAR成像结果的影响。

cfg = V4Core.config();
addpath(cfg.repo_root, cfg.experiment_dir);

search_file = fullfile(cfg.output_root, ...
    "RSFT2DAllocationSearch", "RSFT2D_AllData.mat");
assert(isfile(search_file), "未找到二维RSFT搜索结果：%s", search_file);

loaded = load(search_file, ...
    "group_defs", "group_results", "sample_manifest", ...
    "test_indices", "signature");
validateSearchResult(loaded);

group_names = string({loaded.group_defs.GroupName});
r1a1_idx = find(group_names == "R1A1");
assert(isscalar(r1a1_idx), "搜索结果中R1A1组必须且只能出现一次。");

group = loaded.group_defs(r1a1_idx);
best = loaded.group_results{r1a1_idx}.best;
assert(group.Range_q == 1 && group.Azimuth_q == 1, ...
    "R1A1组的上采样倍率与名称不一致。");
assert(abs(best.STRdB - 4) < 1e-12 && ...
    abs(best.FrOverBr - 2) < 1e-12 && ...
    abs(best.FaOverBa) < 1e-12, ...
    "当前R1A1搜索最优参数不是预期的(4 dB, 2, 0)。");

optimal_params = struct( ...
    "STRdB", best.STRdB, ...
    "FrOverBr", best.FrOverBr, ...
    "FaOverBa", best.FaOverBa);
zero_params = optimal_params;
zero_params.FrOverBr = 0;
zero_params.FaOverBa = 0;

S60 = load(cfg.parameter_file);
[sample_cache, manifest_now] = V4Core.buildSampleCache(cfg, S60);
assert(isequaln(manifest_now, loaded.sample_manifest), ...
    "当前样本清单与二维RSFT搜索结果不一致。");

test_indices = loaded.test_indices(:);
validateTestSplit(loaded.sample_manifest, test_indices);
test_manifest = loaded.sample_manifest(test_indices, :);
num_test = numel(test_indices);

azimuth_bandwidth_Hz = loaded.signature.azimuth_bandwidth_Hz;
assert(isscalar(azimuth_bandwidth_Hz) && ...
    isfinite(azimuth_bandwidth_Hz) && azimuth_bandwidth_Hz > 0, ...
    "搜索结果中的方位带宽无效。");

optimal_psnr = nan(num_test, 1);
optimal_ssim = nan(num_test, 1);
zero_psnr = nan(num_test, 1);
zero_ssim = nan(num_test, 1);

dataset_ids = unique(test_manifest.DatasetIdx, "stable");
representative_images = repmat(struct( ...
    "DatasetIdx", 0, "Dataset", "", "SampleID", 0, ...
    "LocalSampleIdx", 0, "GT", [], ...
    "SearchOptimal", [], "ZeroFrequency", [], ...
    "OptimalPSNR", NaN, "OptimalSSIM", NaN, ...
    "ZeroPSNR", NaN, "ZeroSSIM", NaN), numel(dataset_ids), 1);
representative_ptr = 0;

fprintf("\n=== R1A1二维RSFT双零频对比：%d个测试样本 ===\n", num_test);
fprintf("搜索最优：STR=%+.2f dB，fr/Br=%.3f，fa/Ba=%.3f\n", ...
    optimal_params.STRdB, optimal_params.FrOverBr, ...
    optimal_params.FaOverBa);
fprintf("双零频：  STR=%+.2f dB，fr/Br=0，fa/Ba=0\n", ...
    zero_params.STRdB);

for local_idx = 1:num_test
    sample_idx = test_indices(local_idx);
    signal60 = sample_cache(sample_idx).signal60_input;
    img_gt = sample_cache(sample_idx).img_gt;
    signal_up = V4Core.twoDimUpsample( ...
        signal60, group.Azimuth_q, group.Range_q);

    img_optimal = reconstructWithRSFT2D( ...
        signal_up, S60, group, optimal_params, azimuth_bandwidth_Hz);
    img_zero = reconstructWithRSFT2D( ...
        signal_up, S60, group, zero_params, azimuth_bandwidth_Hz);

    optimal_psnr(local_idx) = psnr(img_optimal, img_gt);
    optimal_ssim(local_idx) = ssim(img_optimal, img_gt);
    zero_psnr(local_idx) = psnr(img_zero, img_gt);
    zero_ssim(local_idx) = ssim(img_zero, img_gt);

    % 每个数据集的第一个测试窗口固定为LocalSampleIdx=2。
    if test_manifest.LocalSampleIdx(local_idx) == 2
        representative_ptr = representative_ptr + 1;
        representative_images(representative_ptr) = struct( ...
            "DatasetIdx", test_manifest.DatasetIdx(local_idx), ...
            "Dataset", test_manifest.Dataset(local_idx), ...
            "SampleID", test_manifest.SampleID(local_idx), ...
            "LocalSampleIdx", test_manifest.LocalSampleIdx(local_idx), ...
            "GT", img_gt, ...
            "SearchOptimal", img_optimal, ...
            "ZeroFrequency", img_zero, ...
            "OptimalPSNR", optimal_psnr(local_idx), ...
            "OptimalSSIM", optimal_ssim(local_idx), ...
            "ZeroPSNR", zero_psnr(local_idx), ...
            "ZeroSSIM", zero_ssim(local_idx));
    end

    fprintf("  测试样本 %02d/%02d 完成。\n", local_idx, num_test);
end

assert(representative_ptr == numel(dataset_ids), ...
    "代表样本数量与数据集数量不一致。");
assert(all(isfinite([optimal_psnr; optimal_ssim; zero_psnr; zero_ssim])), ...
    "对比指标中存在非有限值。");

existing_test = loaded.group_results{r1a1_idx}.test_result;
assert(abs(mean(optimal_psnr) - mean(existing_test.PSNR)) < 1e-9 && ...
    abs(mean(optimal_ssim) - mean(existing_test.SSIM)) < 1e-9, ...
    "重新计算的搜索最优指标与已有R1A1测试结果不一致。");

detail_table = test_manifest;
detail_table.Optimal_STRdB = repmat(optimal_params.STRdB, num_test, 1);
detail_table.Optimal_FrOverBr = repmat( ...
    optimal_params.FrOverBr, num_test, 1);
detail_table.Optimal_FaOverBa = repmat( ...
    optimal_params.FaOverBa, num_test, 1);
detail_table.Zero_STRdB = repmat(zero_params.STRdB, num_test, 1);
detail_table.Zero_FrOverBr = zeros(num_test, 1);
detail_table.Zero_FaOverBa = zeros(num_test, 1);
detail_table.Optimal_PSNR = optimal_psnr;
detail_table.Optimal_SSIM = optimal_ssim;
detail_table.Zero_PSNR = zero_psnr;
detail_table.Zero_SSIM = zero_ssim;
detail_table.DeltaPSNR_ZeroMinusOptimal = zero_psnr - optimal_psnr;
detail_table.DeltaSSIM_ZeroMinusOptimal = zero_ssim - optimal_ssim;

summary_table = buildSummaryTable( ...
    optimal_params, zero_params, ...
    optimal_psnr, optimal_ssim, zero_psnr, zero_ssim);

output_dir = fullfile(cfg.output_root, ...
    "RSFT2D_R1A1ZeroFrequencyCompare");
V4Core.ensureDir(output_dir);

detail_path = fullfile(output_dir, ...
    "R1A1_ZeroFrequencyCompare_Detail.csv");
summary_path = fullfile(output_dir, ...
    "R1A1_ZeroFrequencyCompare_Summary.csv");
figure_path = fullfile(output_dir, ...
    "R1A1_ZeroFrequencyCompare_Representative.png");
mat_path = fullfile(output_dir, ...
    "R1A1_ZeroFrequencyCompare_Data.mat");

writetable(detail_table, detail_path);
writetable(summary_table, summary_path);
exportRepresentativeFigure(representative_images, figure_path);
save(mat_path, ...
    "group", "optimal_params", "zero_params", ...
    "test_indices", "test_manifest", ...
    "detail_table", "summary_table", "representative_images", "-v7.3");

fprintf("\n搜索最优：PSNR=%.6f dB，SSIM=%.6f\n", ...
    mean(optimal_psnr), mean(optimal_ssim));
fprintf("双零频：  PSNR=%.6f dB，SSIM=%.6f\n", ...
    mean(zero_psnr), mean(zero_ssim));
fprintf("双零频-最优：DeltaPSNR=%+.6f dB，DeltaSSIM=%+.6f\n", ...
    mean(zero_psnr - optimal_psnr), ...
    mean(zero_ssim - optimal_ssim));
fprintf("结果已保存：%s\n", output_dir);
end


function validateSearchResult(loaded)
required_fields = [ ...
    "group_defs", "group_results", "sample_manifest", ...
    "test_indices", "signature"];
for idx = 1:numel(required_fields)
    assert(isfield(loaded, required_fields(idx)), ...
        "二维RSFT搜索结果缺少字段：%s", required_fields(idx));
end
assert(isfield(loaded.signature, "azimuth_bandwidth_Hz"), ...
    "二维RSFT搜索签名缺少方位带宽。");
end


function validateTestSplit(sample_manifest, test_indices)
test_manifest = sample_manifest(test_indices, :);
dataset_ids = unique(sample_manifest.DatasetIdx);

assert(numel(test_indices) == 35, "R1A1测试样本数不是35。");
assert(numel(unique(test_manifest.DatasetIdx)) == 7, ...
    "R1A1测试集未覆盖7个数据集。");
assert(all(mod(test_manifest.LocalSampleIdx, 2) == 0), ...
    "测试集中包含非偶数LocalSampleIdx。");

for idx = 1:numel(dataset_ids)
    assert(sum(test_manifest.DatasetIdx == dataset_ids(idx)) == 5, ...
        "数据集%d的测试样本数不是5。", dataset_ids(idx));
end
end


function img_out = reconstructWithRSFT2D( ...
        signal_up, S60, group, params, azimuth_bandwidth_Hz)
U = buildRSFT2DThreshold( ...
    signal_up, S60, group.Range_q, group.Azimuth_q, ...
    params.STRdB, params.FrOverBr, params.FaOverBa, ...
    azimuth_bandwidth_Hz);
channel_1bit = V4Core.quantizeWithThreshold(signal_up, U);
img_out = V4Core.focusUpsampledChannel( ...
    channel_1bit, S60, group.Range_q, group.Azimuth_q);
end


function U = buildRSFT2DThreshold( ...
        signal_up, S60, range_q, azimuth_q, ...
        STR_dB, fr_over_Br, fa_over_Ba, azimuth_bandwidth_Hz)
% 与二维RSFT搜索保持一致的恒模、距离-方位相位和阈值。

[Nr_up, Na_up] = size(signal_up);
fast_time_rel = ...
    ((0:Nr_up - 1).' - floor(Nr_up / 2)) / (range_q * S60.Fs);
slow_time_rel = ...
    ((0:Na_up - 1) - floor(Na_up / 2)) / (azimuth_q * S60.prf);

fr_Hz = fr_over_Br * S60.B;
fa_Hz = fa_over_Ba * azimuth_bandwidth_Hz;
sigma_hat = sqrt(2 / pi) * mean(abs(signal_up(:)));
threshold_amplitude = sigma_hat / (10 ^ (STR_dB / 20));

phase_range = 2 * pi * fr_Hz * fast_time_rel;
phase_azimuth = 2 * pi * fa_Hz * slow_time_rel;
U = threshold_amplitude * exp(1i * (phase_range + phase_azimuth));
end


function summary_table = buildSummaryTable( ...
        optimal_params, zero_params, ...
        optimal_psnr, optimal_ssim, zero_psnr, zero_ssim)
Condition = ["SearchOptimal"; "ZeroFrequency"];
STRdB = [optimal_params.STRdB; zero_params.STRdB];
FrOverBr = [optimal_params.FrOverBr; zero_params.FrOverBr];
FaOverBa = [optimal_params.FaOverBa; zero_params.FaOverBa];
PSNR_Mean = [mean(optimal_psnr); mean(zero_psnr)];
PSNR_Std = [std(optimal_psnr, 0); std(zero_psnr, 0)];
SSIM_Mean = [mean(optimal_ssim); mean(zero_ssim)];
SSIM_Std = [std(optimal_ssim, 0); std(zero_ssim, 0)];
DeltaPSNR_vs_Optimal = [0; mean(zero_psnr - optimal_psnr)];
DeltaSSIM_vs_Optimal = [0; mean(zero_ssim - optimal_ssim)];
TestSampleCount = [numel(optimal_psnr); numel(zero_psnr)];

summary_table = table( ...
    Condition, STRdB, FrOverBr, FaOverBa, ...
    PSNR_Mean, PSNR_Std, SSIM_Mean, SSIM_Std, ...
    DeltaPSNR_vs_Optimal, DeltaSSIM_vs_Optimal, TestSampleCount);
end


function exportRepresentativeFigure(representative_images, save_path)
num_datasets = numel(representative_images);
fig = figure("Color", "w", "Units", "centimeters", ...
    "Position", [2, 2, 18, 29], "Visible", "off");
layout = tiledlayout(fig, num_datasets, 3, ...
    "Padding", "compact", "TileSpacing", "compact");

for idx = 1:num_datasets
    current = representative_images(idx);
    dataset_label = replace(current.Dataset, "SAR_Dataset_", "");

    ax = nexttile(layout);
    imagesc(ax, current.GT, [0, 1]);
    axis(ax, "image", "off");
    title(ax, sprintf("%s | GT", dataset_label), ...
        "Interpreter", "none", "FontSize", 7, "FontWeight", "normal");

    ax = nexttile(layout);
    imagesc(ax, current.SearchOptimal, [0, 1]);
    axis(ax, "image", "off");
    title(ax, sprintf("最优 | %.2f dB, %.4f", ...
        current.OptimalPSNR, current.OptimalSSIM), ...
        "FontSize", 7, "FontWeight", "normal");

    ax = nexttile(layout);
    imagesc(ax, current.ZeroFrequency, [0, 1]);
    axis(ax, "image", "off");
    title(ax, sprintf("双零频 | %.2f dB, %.4f", ...
        current.ZeroPSNR, current.ZeroSSIM), ...
        "FontSize", 7, "FontWeight", "normal");
end

colormap(fig, gray(256));
title(layout, ...
    "R1A1：搜索最优阈值与双零频阈值成像对比", ...
    "FontSize", 10, "FontWeight", "normal");
exportgraphics(fig, save_path, "Resolution", 300);
close(fig);
end
