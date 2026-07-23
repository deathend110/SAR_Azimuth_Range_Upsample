function V4_RSFTCalibration()
% 统一校准V4完整预算实验所需的距离向RSFT参数。

cfg = V4Core.config();
addpath(cfg.repo_root, cfg.experiment_dir);
V4Core.ensureDir(cfg.rsft_calibration_dir);

S60 = load(cfg.parameter_file);
[sample_cache, sample_manifest] = V4Core.buildSampleCache(cfg, S60);
total_samples = numel(sample_cache);
range_q_list = requiredRangeFactors(cfg.Q_list);
base_STR_dB = -10:2:8;
base_f0_over_Br = 0.2:0.2:2.2;
initial_phase = 0;
num_parallel_workers = min(8, feature("numcores"));
if isempty(gcp("nocreate"))
    parpool("threads", num_parallel_workers);
end
checkpoint_path = fullfile( ...
    cfg.rsft_calibration_dir, "V4_RSFT_Calibration_Checkpoint.mat");

signature = struct( ...
    "seed", cfg.seed, ...
    "total_samples", total_samples, ...
    "range_q_list", range_q_list, ...
    "base_STR_dB", base_STR_dB, ...
    "base_f0_over_Br", base_f0_over_Br, ...
    "initial_phase", initial_phase);

state = initializeState(signature, numel(range_q_list));
if isfile(checkpoint_path)
    loaded = load(checkpoint_path, "state");
    assert(isfield(loaded, "state") && ...
        isequaln(loaded.state.signature, signature), ...
        "现有RSFT校准检查点与当前配置不匹配，请人工核查。");
    state = loaded.state;
    fprintf("恢复RSFT校准检查点：已完成%d/%d个R。\n", ...
        state.range_index - 1, numel(range_q_list));
end

for r_idx = state.range_index:numel(range_q_list)
    range_q = range_q_list(r_idx);
    if state.active_range_q ~= range_q
        state = startRange(state, range_q, ...
            base_STR_dB, base_f0_over_Br, total_samples);
    end

    while true
        fprintf("\n=== RSFT校准 R=%d，扩展轮次=%d ===\n", ...
            range_q, state.expansion_round);
        for sample_idx = state.completed_samples + 1:total_samples
            signal_up = V4Core.twoDimUpsample( ...
                sample_cache(sample_idx).signal60_input, 1, range_q);
            img_gt = sample_cache(sample_idx).img_gt;
            num_STR = numel(state.STR_dB_list);
            num_f0 = numel(state.f0_over_Br_list);
            num_configs = num_STR * num_f0;
            psnr_values = nan(num_configs, 1);
            ssim_values = nan(num_configs, 1);
            STR_dB_list = state.STR_dB_list;
            f0_over_Br_list = state.f0_over_Br_list;
            workers_for_range = workerCount(num_parallel_workers);

            parfor (config_idx = 1:num_configs, workers_for_range)
                [str_idx, f_idx] = ind2sub( ...
                    [num_STR, num_f0], config_idx);
                U = V4Core.buildRSFTThreshold( ...
                    signal_up, S60, range_q, ...
                    STR_dB_list(str_idx), ...
                    f0_over_Br_list(f_idx), initial_phase);
                channel_1bit = V4Core.quantizeWithThreshold(signal_up, U);
                img_out = V4Core.focusUpsampledChannel( ...
                    channel_1bit, S60, range_q, 1);
                psnr_values(config_idx) = psnr(img_out, img_gt);
                ssim_values(config_idx) = ssim(img_out, img_gt);
            end
            state.psnr_cube(:, :, sample_idx) = ...
                reshape(psnr_values, [num_STR, num_f0]);
            state.ssim_cube(:, :, sample_idx) = ...
                reshape(ssim_values, [num_STR, num_f0]);

            state.completed_samples = sample_idx;
            save(checkpoint_path, "state", "-v7.3");
            fprintf("  R=%d：样本 %02d/%02d 完成。\n", ...
                range_q, sample_idx, total_samples);
        end

        result = summarizeRange(state, total_samples);
        if result.TouchesBoundary && state.expansion_round == 0
            [expanded_STR, expanded_f0] = expandBoundaryGrid( ...
                state.STR_dB_list, state.f0_over_Br_list, result);
            state = startRange(state, range_q, ...
                expanded_STR, expanded_f0, total_samples);
            state.expansion_round = 1;
            save(checkpoint_path, "state", "-v7.3");
            fprintf("  R=%d最优点触碰边界，扩展搜索网格后重跑。\n", range_q);
            continue;
        end

        state.results{r_idx} = result;
        state.range_index = r_idx + 1;
        state.active_range_q = NaN;
        state.completed_samples = 0;
        state.psnr_cube = [];
        state.ssim_cube = [];
        save(checkpoint_path, "state", "-v7.3");
        fprintf("  R=%d完成：STR=%+.1f dB，f0/Br=%.1f，SSIM=%.6f。\n", ...
            range_q, result.Best_STR_dB, ...
            result.Best_F0OverBr, result.Best_SSIM);
        break;
    end
end

[grid_table, summary_table] = buildOutputTables(state.results, S60.B);
writetable(grid_table, fullfile(cfg.rsft_calibration_dir, ...
    "V4_RSFT_Calibration_Grid.csv"));
writetable(summary_table, fullfile(cfg.rsft_calibration_dir, ...
    "V4_RSFT_Calibration_Summary.csv"));
result_cells = state.results; %#ok<NASGU>
save(fullfile(cfg.rsft_calibration_dir, ...
    "V4_RSFT_Calibration_Data.mat"), ...
    "cfg", "signature", "sample_manifest", ...
    "result_cells", "grid_table", "summary_table", "-v7.3");

plotParameterMap(state.results, cfg.rsft_figure);
writeMetadata(cfg, signature, summary_table);
fprintf("\nRSFT统一校准完成：%s\n", cfg.rsft_calibration_dir);
end

function count = workerCount(pool_size)
% 每个并行任务只保留当前参数点的中间量；实测高倍率下8线程内存可控。
count = min(8, pool_size);
end

function range_q_list = requiredRangeFactors(Q_list)
range_q_list = 1;
for Q = Q_list
    pairs = V4Core.factorPairs(Q);
    range_q_list = union(range_q_list, pairs(:, 1).');
end
range_q_list = sort(range_q_list);
end

function state = initializeState(signature, num_ranges)
state = struct();
state.signature = signature;
state.range_index = 1;
state.active_range_q = NaN;
state.expansion_round = 0;
state.STR_dB_list = [];
state.f0_over_Br_list = [];
state.psnr_cube = [];
state.ssim_cube = [];
state.completed_samples = 0;
state.results = cell(num_ranges, 1);
end

function state = startRange( ...
        state, range_q, STR_dB_list, f0_over_Br_list, total_samples)
state.active_range_q = range_q;
state.expansion_round = 0;
state.STR_dB_list = STR_dB_list;
state.f0_over_Br_list = f0_over_Br_list;
state.psnr_cube = nan( ...
    numel(STR_dB_list), numel(f0_over_Br_list), total_samples);
state.ssim_cube = nan( ...
    numel(STR_dB_list), numel(f0_over_Br_list), total_samples);
state.completed_samples = 0;
end

function result = summarizeRange(state, total_samples)
assert(state.completed_samples == total_samples, "RSFT校准样本未完成。");
psnr_mean = mean(state.psnr_cube, 3, "omitnan");
ssim_mean = mean(state.ssim_cube, 3, "omitnan");
assert(all(isfinite(psnr_mean), "all") && ...
    all(isfinite(ssim_mean), "all"), "RSFT校准指标存在非有限值。");

[STR_grid, f0_grid] = ndgrid( ...
    state.STR_dB_list, state.f0_over_Br_list);
candidate_table = table( ...
    STR_grid(:), f0_grid(:), ssim_mean(:), psnr_mean(:), ...
    abs(STR_grid(:)), ...
    'VariableNames', { ...
    'STRdB', 'F0OverBr', 'SSIM_Mean', 'PSNR_Mean', 'AbsSTR'});
candidate_table = sortrows(candidate_table, ...
    {'SSIM_Mean', 'PSNR_Mean', 'AbsSTR', 'F0OverBr'}, ...
    {'descend', 'descend', 'ascend', 'ascend'});
best = candidate_table(1, :);

best_str_idx = find(state.STR_dB_list == best.STRdB, 1);
best_f_idx = find(state.f0_over_Br_list == best.F0OverBr, 1);
touches_STR = best_str_idx == 1 || ...
    best_str_idx == numel(state.STR_dB_list);
touches_f0 = best_f_idx == 1 || ...
    best_f_idx == numel(state.f0_over_Br_list);

result = struct();
result.Range_q = state.active_range_q;
result.STR_dB_list = state.STR_dB_list;
result.f0_over_Br_list = state.f0_over_Br_list;
result.psnr_cube = state.psnr_cube;
result.ssim_cube = state.ssim_cube;
result.PSNR_Mean = psnr_mean;
result.SSIM_Mean = ssim_mean;
result.Best_STR_dB = best.STRdB;
result.Best_F0OverBr = best.F0OverBr;
result.Best_PSNR = best.PSNR_Mean;
result.Best_SSIM = best.SSIM_Mean;
result.Best_STR_Index = best_str_idx;
result.Best_F0_Index = best_f_idx;
result.TouchesSTRBoundary = touches_STR;
result.TouchesF0Boundary = touches_f0;
result.TouchesBoundary = touches_STR || touches_f0;
result.ExpansionRound = state.expansion_round;
end

function [STR_list, f0_list] = expandBoundaryGrid( ...
        STR_list, f0_list, result)
if result.TouchesSTRBoundary
    if result.Best_STR_Index == 1
        STR_list = [(min(STR_list) - 4):2:(min(STR_list) - 2), STR_list];
    else
        STR_list = [STR_list, ...
            (max(STR_list) + 2):2:(max(STR_list) + 4)];
    end
end
if result.TouchesF0Boundary
    if result.Best_F0_Index == 1
        new_min = max(0, min(f0_list) - 0.4);
        prefix = new_min:0.2:(min(f0_list) - 0.2);
        f0_list = unique([prefix, f0_list]);
    else
        f0_list = [f0_list, ...
            (max(f0_list) + 0.2):0.2:(max(f0_list) + 0.4)];
    end
end
end

function [grid_table, summary_table] = buildOutputTables(results, bandwidth_Hz)
grid_table = table();
num_ranges = numel(results);
Range_q = zeros(num_ranges, 1);
Best_STR_dB = zeros(num_ranges, 1);
Best_F0OverBr = zeros(num_ranges, 1);
Best_F0Hz = zeros(num_ranges, 1);
Best_SSIM = zeros(num_ranges, 1);
PSNR_AtBestSSIM = zeros(num_ranges, 1);
TouchesBoundary = false(num_ranges, 1);
ExpansionRound = zeros(num_ranges, 1);
SampleCount = zeros(num_ranges, 1);

for r_idx = 1:num_ranges
    result = results{r_idx};
    [STR_grid, f0_grid] = ndgrid( ...
        result.STR_dB_list, result.f0_over_Br_list);
    rows = table( ...
        repmat(result.Range_q, numel(STR_grid), 1), ...
        STR_grid(:), f0_grid(:), ...
        result.PSNR_Mean(:), result.SSIM_Mean(:), ...
        'VariableNames', { ...
        'Range_q', 'STRdB', 'F0OverBr', 'PSNR_Mean', 'SSIM_Mean'});
    grid_table = [grid_table; rows]; %#ok<AGROW>

    Range_q(r_idx) = result.Range_q;
    Best_STR_dB(r_idx) = result.Best_STR_dB;
    Best_F0OverBr(r_idx) = result.Best_F0OverBr;
    Best_F0Hz(r_idx) = result.Best_F0OverBr * bandwidth_Hz;
    Best_SSIM(r_idx) = result.Best_SSIM;
    PSNR_AtBestSSIM(r_idx) = result.Best_PSNR;
    TouchesBoundary(r_idx) = result.TouchesBoundary;
    ExpansionRound(r_idx) = result.ExpansionRound;
    SampleCount(r_idx) = size(result.psnr_cube, 3);
end

summary_table = table( ...
    Range_q, Best_STR_dB, Best_F0OverBr, Best_F0Hz, ...
    Best_SSIM, PSNR_AtBestSSIM, TouchesBoundary, ...
    ExpansionRound, SampleCount);
end

function plotParameterMap(results, save_path)
selected_R = [2, 3];
fig = figure("Color", "w", "Units", "centimeters", ...
    "Position", [2, 2, 18, 7.5], "Visible", "off");
layout = tiledlayout(fig, 1, 2, ...
    "Padding", "compact", "TileSpacing", "compact");

for idx = 1:numel(selected_R)
    result_idx = find(cellfun( ...
        @(x) x.Range_q == selected_R(idx), results), 1);
    result = results{result_idx};
    ax = nexttile(layout);
    imagesc(ax, result.f0_over_Br_list, ...
        result.STR_dB_list, result.SSIM_Mean);
    set(ax, "YDir", "normal");
    colormap(ax, turbo);
    colorbar(ax);
    hold(ax, "on");
    plot(ax, result.Best_F0OverBr, result.Best_STR_dB, ...
        "wp", "MarkerFaceColor", "k", "MarkerSize", 9);
    xlabel(ax, "$f_0/B_r$", "Interpreter", "latex");
    ylabel(ax, "STR (dB)");
    title(ax, sprintf("RSFT, $R=%d$", result.Range_q), ...
        "Interpreter", "latex");
end

exportgraphics(fig, save_path, "Resolution", 300);
close(fig);
end

function writeMetadata(cfg, signature, summary_table)
metadata_path = fullfile( ...
    cfg.rsft_calibration_dir, "V4_RSFT_Calibration_Metadata.txt");
fid = fopen(metadata_path, "w");
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "Experiment=V4_RSFTCalibration\n");
fprintf(fid, "Seed=%d\n", signature.seed);
fprintf(fid, "SampleCount=%d\n", signature.total_samples);
fprintf(fid, "RangeQ=%s\n", mat2str(signature.range_q_list));
fprintf(fid, "BaseSTRdB=%s\n", mat2str(signature.base_STR_dB));
fprintf(fid, "BaseF0OverBr=%s\n", mat2str(signature.base_f0_over_Br));
fprintf(fid, "InitialPhase=%.16g\n", signature.initial_phase);
fprintf(fid, "ParallelPoolWorkers=%d\n", min(8, feature("numcores")));
fprintf(fid, "WorkerPolicy=AllRangeFactors:8\n");
fprintf(fid, "SelectionMetric=mean SSIM\n");
fprintf(fid, "CalibrationAllocation=(R,1)\n");
fprintf(fid, "ThresholdAmplitude=sigma_hat/10^(STR_dB/20)\n");
fprintf(fid, "ThresholdFrequency=f0_over_Br*Br\n");
fprintf(fid, "BestSettings=%s\n", jsonencode(table2struct(summary_table)));
end
