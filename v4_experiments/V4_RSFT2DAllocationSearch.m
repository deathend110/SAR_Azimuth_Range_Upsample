function V4_RSFT2DAllocationSearch()
% V4_RSFT2DAllocationSearch
% 针对Q=1:10的全部整数(R,A)分配，分别搜索最优二维RSFT参数：
%   STR、fr/Br、fa/Ba
%
% 二维RSFT：
%   U(m,n) = Au * exp(j*(2*pi*fr*tau_m + 2*pi*fa*eta_n + phi0))
%   Au     = sigma_hat / 10^(STR/20)
%
% 运行方式（仓库根目录）：
%   addpath("v4_experiments");
%   V4_RSFT2DAllocationSearch;
%
% 依赖：
%   - v4_experiments/V4Core.m
%   - FS60_params.mat
%   - 仓库现有Range_Compress、RCMC、SAR_Imaging、normalize_image等函数
%   - Image Processing Toolbox（psnr、ssim）
%   - Parallel Computing Toolbox（沿用V4现有并行协议）
%
% 输出目录：
%   V4_Experiments_Output/RSFT2DAllocationSearch
%
% 主要输出：
%   RSFT2D_GroupSummary.csv          每个(R,A)的最优参数与测试结果
%   RSFT2D_TestDetail.csv            测试集逐样本结果
%   RSFT2D_SearchGrid.csv            粗搜索和细搜索的均值网格
%   RSFT2D_BudgetBest.csv            每个固定预算Q下的最佳分配
%   RSFT2D_PairedTests.csv           最佳双向与最佳单向的配对检验
%   RSFT2D_SampleSplit.csv           35/35分层划分清单
%   RSFT2D_AllData.mat               完整结果
%
% 说明：
%   1. 每个(R,A)独立校准参数，属于allocation-conditioned calibration。
%   2. 校准集使用每个数据集的奇数LocalSampleIdx，测试集使用偶数LocalSampleIdx。
%   3. 参数只在校准集上选择；测试集不参与参数选择。
%   4. 频率网格包含0，使二维RSFT可退化为距离单频、方位单频或常阈值，
%      避免人为限制单向分配的最优阈值结构。

cfg = V4Core.config();
addpath(cfg.repo_root, cfg.experiment_dir);

output_dir = fullfile(cfg.output_root, "RSFT2DAllocationSearch");
checkpoint_dir = fullfile(output_dir, "Checkpoints");
group_result_dir = fullfile(output_dir, "GroupResults");
V4Core.ensureDir(output_dir);
V4Core.ensureDir(checkpoint_dir);
V4Core.ensureDir(group_result_dir);

search_cfg = buildSearchConfig();
S60 = load(cfg.parameter_file);
validateEnvironment(S60);

[sample_cache, sample_manifest] = V4Core.buildSampleCache(cfg, S60);
[calibration_indices, test_indices, split_table] = ...
    buildStratifiedSplit(sample_manifest);

writetable(split_table, fullfile(output_dir, "RSFT2D_SampleSplit.csv"));

group_defs = buildAllGroupDefinitions(search_cfg.Q_list);
num_groups = numel(group_defs);
azimuth_bandwidth_Hz = resolveAzimuthBandwidth(S60);

signature = struct( ...
    "experiment", "V4_RSFT2DAllocationSearch", ...
    "seed", cfg.seed, ...
    "Q_list", search_cfg.Q_list, ...
    "coarse_STR_dB", search_cfg.coarse_STR_dB, ...
    "coarse_fr_over_Br", search_cfg.coarse_fr_over_Br, ...
    "coarse_fa_over_Ba", search_cfg.coarse_fa_over_Ba, ...
    "fine_STR_offsets", search_cfg.fine_STR_offsets, ...
    "fine_fr_offsets", search_cfg.fine_fr_offsets, ...
    "fine_fa_offsets", search_cfg.fine_fa_offsets, ...
    "max_refinement_rounds", search_cfg.max_refinement_rounds, ...
    "initial_phase", search_cfg.initial_phase, ...
    "calibration_sample_ids", sample_manifest.SampleID(calibration_indices).', ...
    "test_sample_ids", sample_manifest.SampleID(test_indices).', ...
    "range_bandwidth_Hz", S60.B, ...
    "azimuth_bandwidth_Hz", azimuth_bandwidth_Hz);

num_parallel_workers = min( ...
    search_cfg.max_parallel_workers, max(1, feature("numcores")));
if isempty(gcp("nocreate"))
    parpool("threads", num_parallel_workers);
end
workers_for_search = min(num_parallel_workers, search_cfg.max_parallel_workers);

fprintf("\n=== 2D RSFT分配条件参数搜索 ===\n");
fprintf("分配组数量：%d\n", num_groups);
fprintf("校准样本：%d；测试样本：%d\n", ...
    numel(calibration_indices), numel(test_indices));
fprintf("方位带宽Ba：%.6f Hz\n", azimuth_bandwidth_Hz);
fprintf("并行线程：%d\n", workers_for_search);

group_results = cell(num_groups, 1);

for group_idx = 1:num_groups
    current = group_defs(group_idx);
    group_result_path = fullfile(group_result_dir, ...
        sprintf("RSFT2D_Q%02d_R%02d_A%02d.mat", ...
        current.Q, current.Range_q, current.Azimuth_q));

    group_signature = struct( ...
        "global_signature", signature, ...
        "Q", current.Q, ...
        "Range_q", current.Range_q, ...
        "Azimuth_q", current.Azimuth_q);

    if isfile(group_result_path)
        loaded = load(group_result_path, "group_result");
        assert(isfield(loaded, "group_result"), ...
            "组结果文件缺少group_result：%s", group_result_path);
        assert(isequaln(loaded.group_result.signature, group_signature), ...
            "组结果与当前配置不匹配，请删除后重跑：%s", group_result_path);
        group_results{group_idx} = loaded.group_result;
        fprintf("[%02d/%02d] %s：读取已完成结果。\n", ...
            group_idx, num_groups, current.GroupName);
        continue;
    end

    fprintf("\n[%02d/%02d] %s，Q=%d，R=%d，A=%d\n", ...
        group_idx, num_groups, current.GroupName, ...
        current.Q, current.Range_q, current.Azimuth_q);

    stage_results = cell(search_cfg.max_refinement_rounds + 1, 1);

    % 第一阶段：全局粗网格。
    coarse_stage_name = "coarse";
    stage_results{1} = runGridStage( ...
        current, coarse_stage_name, ...
        search_cfg.coarse_STR_dB, ...
        search_cfg.coarse_fr_over_Br, ...
        search_cfg.coarse_fa_over_Ba, ...
        sample_cache, calibration_indices, S60, ...
        azimuth_bandwidth_Hz, search_cfg.initial_phase, ...
        workers_for_search, checkpoint_dir, group_signature);

    best = stage_results{1}.best;
    completed_stage_count = 1;

    % 第二阶段：围绕当前最优点局部细化。
    for refine_round = 1:search_cfg.max_refinement_rounds
        [fine_STR, fine_fr, fine_fa] = buildFineGrid(best, search_cfg);
        stage_name = "fine" + string(refine_round);

        stage_results{refine_round + 1} = runGridStage( ...
            current, stage_name, fine_STR, fine_fr, fine_fa, ...
            sample_cache, calibration_indices, S60, ...
            azimuth_bandwidth_Hz, search_cfg.initial_phase, ...
            workers_for_search, checkpoint_dir, group_signature);

        best = stage_results{refine_round + 1}.best;
        completed_stage_count = refine_round + 1;

        if ~stage_results{refine_round + 1}.TouchesExpandableBoundary
            break;
        end

        fprintf("  %s最优点仍触碰可扩展边界，继续局部细化。\n", stage_name);
    end

    stage_results = stage_results(1:completed_stage_count);

    % 锁定校准集最优参数，仅在测试集上评价。
    test_result = evaluateLockedParameters( ...
        current, best, sample_cache, test_indices, S60, ...
        azimuth_bandwidth_Hz, search_cfg.initial_phase, ...
        checkpoint_dir, group_signature);

    group_result = struct();
    group_result.signature = group_signature;
    group_result.group = current;
    group_result.stage_results = stage_results;
    group_result.best = best;
    group_result.test_result = test_result;
    group_result.summary_row = buildGroupSummaryRow( ...
        current, best, test_result, S60.B, azimuth_bandwidth_Hz, ...
        numel(calibration_indices), numel(test_indices), ...
        stage_results{end}.TouchesBoundary, ...
        stage_results{end}.TouchesExpandableBoundary);

    save(group_result_path, "group_result", "-v7.3");
    group_results{group_idx} = group_result;

    fprintf("  完成：STR=%+.2f dB，fr/Br=%.3f，fa/Ba=%.3f，", ...
        best.STRdB, best.FrOverBr, best.FaOverBa);
    fprintf("Test SSIM=%.6f，Test PSNR=%.4f dB。\n", ...
        mean(test_result.SSIM), mean(test_result.PSNR));
end

[summary_table, detail_table, search_grid_table, ...
    test_psnr_all, test_ssim_all] = aggregateResults( ...
    group_results, group_defs, sample_manifest, test_indices);

budget_best_table = buildBudgetBest(summary_table);
paired_tests_table = buildPairedTests( ...
    group_defs, summary_table, test_psnr_all, test_ssim_all);

writetable(summary_table, ...
    fullfile(output_dir, "RSFT2D_GroupSummary.csv"));
writetable(detail_table, ...
    fullfile(output_dir, "RSFT2D_TestDetail.csv"));
writetable(search_grid_table, ...
    fullfile(output_dir, "RSFT2D_SearchGrid.csv"));
writetable(budget_best_table, ...
    fullfile(output_dir, "RSFT2D_BudgetBest.csv"));
writetable(paired_tests_table, ...
    fullfile(output_dir, "RSFT2D_PairedTests.csv"));

save(fullfile(output_dir, "RSFT2D_AllData.mat"), ...
    "cfg", "search_cfg", "signature", "group_defs", ...
    "sample_manifest", "split_table", ...
    "calibration_indices", "test_indices", ...
    "group_results", "summary_table", "detail_table", ...
    "search_grid_table", "budget_best_table", ...
    "paired_tests_table", "test_psnr_all", "test_ssim_all", "-v7.3");

writeMetadata( ...
    output_dir, signature, search_cfg, summary_table, ...
    budget_best_table, paired_tests_table);

fprintf("\n2D RSFT参数搜索完成：%s\n", output_dir);
end


function search_cfg = buildSearchConfig()
% 搜索范围参考仓库V4_RSFTCalibration，并为第三个方位频率维度采用粗到细搜索。

search_cfg = struct();
search_cfg.Q_list = 1:10;

% 粗搜索包含0频率，使阈值允许退化为1D RSFT或常阈值。
search_cfg.coarse_STR_dB = -10:4:10;
search_cfg.coarse_fr_over_Br = 0:0.4:2.4;
search_cfg.coarse_fa_over_Ba = 0:0.4:2.4;

% 每轮围绕当前最优点细化；最多两轮，避免一次高密度三维全网格。
search_cfg.fine_STR_offsets = -2:1:2;
search_cfg.fine_fr_offsets = -0.2:0.1:0.2;
search_cfg.fine_fa_offsets = -0.2:0.1:0.2;
search_cfg.max_refinement_rounds = 2;

search_cfg.initial_phase = 0;
search_cfg.max_parallel_workers = 8;
end


function validateEnvironment(S60)
required_fields = { ...
    "B", "Fs", "prf", "nrn", "nan", "fc", "gama", ...
    "R0", "C", "Tp", "lambda", "fnrn", "fnan", ...
    "v", "tnan", "Ta", "R_total", "A_num"};

for idx = 1:numel(required_fields)
    assert(isfield(S60, required_fields{idx}), ...
        "FS60_params.mat缺少字段：%s", required_fields{idx});
end

assert(exist("psnr", "file") == 2, "未找到psnr函数。");
assert(exist("ssim", "file") == 2, "未找到ssim函数。");
assert(exist("Range_Compress", "file") == 2, "未找到Range_Compress.m。");
assert(exist("RCMC", "file") == 2, "未找到RCMC.m。");
assert(exist("SAR_Imaging", "file") == 2, "未找到SAR_Imaging.m。");
assert(exist("normalize_image", "file") == 2, "未找到normalize_image.m。");
end


function [calibration_indices, test_indices, split_table] = ...
        buildStratifiedSplit(sample_manifest)
% 每个数据集10个分层窗口：奇数序号用于校准，偶数序号用于测试。

calibration_mask = mod(sample_manifest.LocalSampleIdx, 2) == 1;
test_mask = ~calibration_mask;

dataset_ids = unique(sample_manifest.DatasetIdx);
for idx = 1:numel(dataset_ids)
    ds = dataset_ids(idx);
    assert(sum(calibration_mask & sample_manifest.DatasetIdx == ds) == 5, ...
        "数据集%d的校准样本不是5个。", ds);
    assert(sum(test_mask & sample_manifest.DatasetIdx == ds) == 5, ...
        "数据集%d的测试样本不是5个。", ds);
end

calibration_indices = find(calibration_mask);
test_indices = find(test_mask);

Split = strings(height(sample_manifest), 1);
Split(calibration_mask) = "calibration";
Split(test_mask) = "test";
split_table = [sample_manifest, table(Split)];
end


function group_defs = buildAllGroupDefinitions(Q_list)
num_groups = 0;
for Q = Q_list
    num_groups = num_groups + size(V4Core.factorPairs(Q), 1);
end

empty_group = struct( ...
    "Q", 0, ...
    "Range_q", 0, ...
    "Azimuth_q", 0, ...
    "GroupName", "", ...
    "GroupType", "");

group_defs = repmat(empty_group, num_groups, 1);
ptr = 0;

for Q = Q_list
    pairs = V4Core.factorPairs(Q);
    for pair_idx = 1:size(pairs, 1)
        ptr = ptr + 1;
        range_q = pairs(pair_idx, 1);
        azimuth_q = pairs(pair_idx, 2);

        if Q == 1
            group_type = "no_upsample";
        elseif range_q == Q && azimuth_q == 1
            group_type = "range_only";
        elseif range_q == 1 && azimuth_q == Q
            group_type = "azimuth_only";
        elseif range_q == azimuth_q
            group_type = "balanced";
        else
            group_type = "mixed";
        end

        group_defs(ptr) = struct( ...
            "Q", Q, ...
            "Range_q", range_q, ...
            "Azimuth_q", azimuth_q, ...
            "GroupName", sprintf("R%dA%d", range_q, azimuth_q), ...
            "GroupType", group_type);
    end
end
end


function stage_result = runGridStage( ...
        group, stage_name, STR_dB_list, fr_over_Br_list, fa_over_Ba_list, ...
        sample_cache, calibration_indices, S60, azimuth_bandwidth_Hz, ...
        initial_phase, workers_for_search, checkpoint_dir, group_signature)

STR_dB_list = unique(round(STR_dB_list(:).', 10));
fr_over_Br_list = unique(round(fr_over_Br_list(:).', 10));
fa_over_Ba_list = unique(round(fa_over_Ba_list(:).', 10));

assert(all(fr_over_Br_list >= 0), "fr/Br不能为负。");
assert(all(fa_over_Ba_list >= 0), "fa/Ba不能为负。");

checkpoint_path = fullfile(checkpoint_dir, ...
    sprintf("Q%02d_R%02d_A%02d_%s.mat", ...
    group.Q, group.Range_q, group.Azimuth_q, stage_name));

stage_signature = struct( ...
    "group_signature", group_signature, ...
    "stage_name", stage_name, ...
    "STR_dB_list", STR_dB_list, ...
    "fr_over_Br_list", fr_over_Br_list, ...
    "fa_over_Ba_list", fa_over_Ba_list, ...
    "calibration_indices", calibration_indices(:).');

num_STR = numel(STR_dB_list);
num_fr = numel(fr_over_Br_list);
num_fa = numel(fa_over_Ba_list);
num_samples = numel(calibration_indices);
num_configs = num_STR * num_fr * num_fa;

state = struct();
state.signature = stage_signature;
state.completed_samples = 0;
state.psnr_cube = nan(num_STR, num_fr, num_fa, num_samples);
state.ssim_cube = nan(num_STR, num_fr, num_fa, num_samples);

if isfile(checkpoint_path)
    loaded = load(checkpoint_path, "state");
    assert(isfield(loaded, "state") && ...
        isequaln(loaded.state.signature, stage_signature), ...
        "搜索检查点与当前配置不匹配：%s", checkpoint_path);
    state = loaded.state;
    fprintf("  %s：恢复检查点 %d/%d 个校准样本。\n", ...
        stage_name, state.completed_samples, num_samples);
end

fprintf("  %s：%d×%d×%d=%d个参数点。\n", ...
    stage_name, num_STR, num_fr, num_fa, num_configs);

for local_sample_idx = state.completed_samples + 1:num_samples
    sample_idx = calibration_indices(local_sample_idx);
    signal_up = V4Core.twoDimUpsample( ...
        sample_cache(sample_idx).signal60_input, ...
        group.Azimuth_q, group.Range_q);
    img_gt = sample_cache(sample_idx).img_gt;

    psnr_values = nan(num_configs, 1);
    ssim_values = nan(num_configs, 1);

    range_q = group.Range_q;
    azimuth_q = group.Azimuth_q;
    current_STR = STR_dB_list;
    current_fr = fr_over_Br_list;
    current_fa = fa_over_Ba_list;

    parfor (config_idx = 1:num_configs, workers_for_search)
        [str_idx, fr_idx, fa_idx] = ind2sub( ...
            [num_STR, num_fr, num_fa], config_idx);

        U = buildRSFT2DThreshold( ...
            signal_up, S60, range_q, azimuth_q, ...
            current_STR(str_idx), ...
            current_fr(fr_idx), ...
            current_fa(fa_idx), ...
            azimuth_bandwidth_Hz, initial_phase);

        channel_1bit = V4Core.quantizeWithThreshold(signal_up, U);
        img_out = V4Core.focusUpsampledChannel( ...
            channel_1bit, S60, range_q, azimuth_q);

        psnr_values(config_idx) = psnr(img_out, img_gt);
        ssim_values(config_idx) = ssim(img_out, img_gt);
    end

    state.psnr_cube(:, :, :, local_sample_idx) = ...
        reshape(psnr_values, [num_STR, num_fr, num_fa]);
    state.ssim_cube(:, :, :, local_sample_idx) = ...
        reshape(ssim_values, [num_STR, num_fr, num_fa]);

    state.completed_samples = local_sample_idx;
    save(checkpoint_path, "state", "-v7.3");

    fprintf("    %s：校准样本 %02d/%02d 完成。\n", ...
        stage_name, local_sample_idx, num_samples);
end

stage_result = summarizeGridStage(state);
end


function stage_result = summarizeGridStage(state)
assert(state.completed_samples == size(state.psnr_cube, 4), ...
    "参数搜索尚未完成全部校准样本。");

psnr_mean = mean(state.psnr_cube, 4, "omitnan");
ssim_mean = mean(state.ssim_cube, 4, "omitnan");

assert(all(isfinite(psnr_mean), "all"), "PSNR搜索结果存在非有限值。");
assert(all(isfinite(ssim_mean), "all"), "SSIM搜索结果存在非有限值。");

STR_dB_list = state.signature.STR_dB_list;
fr_over_Br_list = state.signature.fr_over_Br_list;
fa_over_Ba_list = state.signature.fa_over_Ba_list;

[STR_grid, fr_grid, fa_grid] = ndgrid( ...
    STR_dB_list, fr_over_Br_list, fa_over_Ba_list);

candidate_table = table( ...
    STR_grid(:), fr_grid(:), fa_grid(:), ...
    psnr_mean(:), ssim_mean(:), abs(STR_grid(:)), ...
    'VariableNames', { ...
    'STRdB', 'FrOverBr', 'FaOverBa', ...
    'PSNR_Mean', 'SSIM_Mean', 'AbsSTR'});

candidate_table = sortrows(candidate_table, ...
    {'SSIM_Mean', 'PSNR_Mean', 'AbsSTR', 'FrOverBr', 'FaOverBa'}, ...
    {'descend', 'descend', 'ascend', 'ascend', 'ascend'});

best_row = candidate_table(1, :);
str_idx = nearestIndex(STR_dB_list, best_row.STRdB);
fr_idx = nearestIndex(fr_over_Br_list, best_row.FrOverBr);
fa_idx = nearestIndex(fa_over_Ba_list, best_row.FaOverBa);

touches_STR = str_idx == 1 || str_idx == numel(STR_dB_list);
touches_fr = fr_idx == 1 || fr_idx == numel(fr_over_Br_list);
touches_fa = fa_idx == 1 || fa_idx == numel(fa_over_Ba_list);

% 频率0是物理允许边界，不需要向负频率方向扩展。
expandable_fr = fr_idx == numel(fr_over_Br_list) || ...
    (fr_idx == 1 && min(fr_over_Br_list) > 0);
expandable_fa = fa_idx == numel(fa_over_Ba_list) || ...
    (fa_idx == 1 && min(fa_over_Ba_list) > 0);

best = struct();
best.STRdB = best_row.STRdB;
best.FrOverBr = best_row.FrOverBr;
best.FaOverBa = best_row.FaOverBa;
best.PSNR_Mean = best_row.PSNR_Mean;
best.SSIM_Mean = best_row.SSIM_Mean;

stage_result = struct();
stage_result.signature = state.signature;
stage_result.best = best;
stage_result.grid_table = removevars(candidate_table, "AbsSTR");
stage_result.psnr_cube = state.psnr_cube;
stage_result.ssim_cube = state.ssim_cube;
stage_result.TouchesSTRBoundary = touches_STR;
stage_result.TouchesFrBoundary = touches_fr;
stage_result.TouchesFaBoundary = touches_fa;
stage_result.TouchesBoundary = touches_STR || touches_fr || touches_fa;
stage_result.TouchesExpandableBoundary = ...
    touches_STR || expandable_fr || expandable_fa;
end


function idx = nearestIndex(values, target)
[distance, idx] = min(abs(values - target));
assert(distance < 1e-9, "无法在参数网格中定位最优值。");
end


function [fine_STR, fine_fr, fine_fa] = buildFineGrid(best, search_cfg)
fine_STR = best.STRdB + search_cfg.fine_STR_offsets;
fine_fr = best.FrOverBr + search_cfg.fine_fr_offsets;
fine_fa = best.FaOverBa + search_cfg.fine_fa_offsets;

fine_fr = fine_fr(fine_fr >= 0);
fine_fa = fine_fa(fine_fa >= 0);

fine_STR = unique(round(fine_STR, 10));
fine_fr = unique(round(fine_fr, 10));
fine_fa = unique(round(fine_fa, 10));
end


function [U, sigma_hat, threshold_amplitude] = buildRSFT2DThreshold( ...
        signal_up, S60, range_q, azimuth_q, ...
        STR_dB, fr_over_Br, fa_over_Ba, ...
        azimuth_bandwidth_Hz, initial_phase)
% 生成恒模二维单频阈值。
%
% 相位采用距离相位与方位相位相加，而不是两个复阈值直接相加：
%   phi(m,n) = 2*pi*fr*tau_m + 2*pi*fa*eta_n + phi0
%
% 上采样后等效采样率：
%   Fs_r_up = R * Fs
%   PRF_up  = A * PRF

arguments
    signal_up
    S60
    range_q (1, 1) double {mustBePositive}
    azimuth_q (1, 1) double {mustBePositive}
    STR_dB (1, 1) double
    fr_over_Br (1, 1) double {mustBeNonnegative}
    fa_over_Ba (1, 1) double {mustBeNonnegative}
    azimuth_bandwidth_Hz (1, 1) double {mustBePositive}
    initial_phase (1, 1) double = 0
end

[Nr_up, Na_up] = size(signal_up);

Fs_range_up = range_q * S60.Fs;
PRF_up = azimuth_q * S60.prf;

fast_time_rel = ...
    ((0:Nr_up - 1).' - floor(Nr_up / 2)) / Fs_range_up;
slow_time_rel = ...
    ((0:Na_up - 1) - floor(Na_up / 2)) / PRF_up;

fr_Hz = fr_over_Br * S60.B;
fa_Hz = fa_over_Ba * azimuth_bandwidth_Hz;

sigma_hat = sqrt(2 / pi) * mean(abs(signal_up(:)));
threshold_amplitude = sigma_hat / (10 ^ (STR_dB / 20));

phase_range = 2 * pi * fr_Hz * fast_time_rel;
phase_azimuth = 2 * pi * fa_Hz * slow_time_rel;

U = threshold_amplitude * exp( ...
    1i * (phase_range + phase_azimuth + initial_phase));
end


function azimuth_bandwidth_Hz = resolveAzimuthBandwidth(S60)
% 优先读取参数文件中已有的方位多普勒带宽；否则按Bd=2v/Da计算。

if isfield(S60, "Ba")
    azimuth_bandwidth_Hz = S60.Ba;
elseif isfield(S60, "Bd")
    azimuth_bandwidth_Hz = S60.Bd;
elseif isfield(S60, "Da")
    azimuth_bandwidth_Hz = 2 * S60.v / S60.Da;
else
    error([ ...
        "无法确定方位带宽Ba。FS60_params.mat需包含Ba、Bd或Da字段。" ...
    ]);
end

assert(isscalar(azimuth_bandwidth_Hz) && ...
    isfinite(azimuth_bandwidth_Hz) && azimuth_bandwidth_Hz > 0, ...
    "方位带宽Ba无效。");
end


function test_result = evaluateLockedParameters( ...
        group, best, sample_cache, test_indices, S60, ...
        azimuth_bandwidth_Hz, initial_phase, ...
        checkpoint_dir, group_signature)

checkpoint_path = fullfile(checkpoint_dir, ...
    sprintf("Q%02d_R%02d_A%02d_test.mat", ...
    group.Q, group.Range_q, group.Azimuth_q));

test_signature = struct( ...
    "group_signature", group_signature, ...
    "STRdB", best.STRdB, ...
    "FrOverBr", best.FrOverBr, ...
    "FaOverBa", best.FaOverBa, ...
    "test_indices", test_indices(:).');

num_samples = numel(test_indices);

state = struct();
state.signature = test_signature;
state.completed_samples = 0;
state.PSNR = nan(num_samples, 1);
state.SSIM = nan(num_samples, 1);

if isfile(checkpoint_path)
    loaded = load(checkpoint_path, "state");
    assert(isfield(loaded, "state") && ...
        isequaln(loaded.state.signature, test_signature), ...
        "测试检查点与当前参数不匹配：%s", checkpoint_path);
    state = loaded.state;
    fprintf("  test：恢复检查点 %d/%d。\n", ...
        state.completed_samples, num_samples);
end

for local_idx = state.completed_samples + 1:num_samples
    sample_idx = test_indices(local_idx);

    signal_up = V4Core.twoDimUpsample( ...
        sample_cache(sample_idx).signal60_input, ...
        group.Azimuth_q, group.Range_q);

    U = buildRSFT2DThreshold( ...
        signal_up, S60, group.Range_q, group.Azimuth_q, ...
        best.STRdB, best.FrOverBr, best.FaOverBa, ...
        azimuth_bandwidth_Hz, initial_phase);

    channel_1bit = V4Core.quantizeWithThreshold(signal_up, U);
    img_out = V4Core.focusUpsampledChannel( ...
        channel_1bit, S60, group.Range_q, group.Azimuth_q);

    img_gt = sample_cache(sample_idx).img_gt;
    state.PSNR(local_idx) = psnr(img_out, img_gt);
    state.SSIM(local_idx) = ssim(img_out, img_gt);

    state.completed_samples = local_idx;
    save(checkpoint_path, "state", "-v7.3");
end

assert(all(isfinite(state.PSNR)) && all(isfinite(state.SSIM)), ...
    "测试指标存在非有限值。");

test_result = struct();
test_result.signature = test_signature;
test_result.PSNR = state.PSNR;
test_result.SSIM = state.SSIM;
end


function summary_row = buildGroupSummaryRow( ...
        group, best, test_result, range_bandwidth_Hz, ...
        azimuth_bandwidth_Hz, calibration_count, test_count, ...
        touches_boundary, touches_expandable_boundary)

summary_row = table( ...
    group.Q, string(group.GroupName), ...
    group.Range_q, group.Azimuth_q, string(group.GroupType), ...
    best.STRdB, best.FrOverBr, best.FaOverBa, ...
    best.FrOverBr * range_bandwidth_Hz, ...
    best.FaOverBa * azimuth_bandwidth_Hz, ...
    best.PSNR_Mean, best.SSIM_Mean, ...
    mean(test_result.PSNR), std(test_result.PSNR, 0), ...
    mean(test_result.SSIM), std(test_result.SSIM, 0), ...
    calibration_count, test_count, ...
    logical(touches_boundary), logical(touches_expandable_boundary), ...
    'VariableNames', { ...
    'Q', 'GroupName', 'Range_q', 'Azimuth_q', 'GroupType', ...
    'Best_STRdB', 'Best_FrOverBr', 'Best_FaOverBa', ...
    'Best_FrHz', 'Best_FaHz', ...
    'Calibration_PSNR_Mean', 'Calibration_SSIM_Mean', ...
    'Test_PSNR_Mean', 'Test_PSNR_Std', ...
    'Test_SSIM_Mean', 'Test_SSIM_Std', ...
    'CalibrationSampleCount', 'TestSampleCount', ...
    'FinalTouchesBoundary', 'FinalTouchesExpandableBoundary'});
end


function [summary_table, detail_table, search_grid_table, ...
        test_psnr_all, test_ssim_all] = aggregateResults( ...
        group_results, group_defs, sample_manifest, test_indices)

num_groups = numel(group_results);
num_test = numel(test_indices);

summary_rows = cell(num_groups, 1);
detail_rows = cell(num_groups, 1);
grid_rows = {};

test_psnr_all = nan(num_groups, num_test);
test_ssim_all = nan(num_groups, num_test);

grid_ptr = 0;

for group_idx = 1:num_groups
    result = group_results{group_idx};
    summary_rows{group_idx} = result.summary_row;

    test_psnr_all(group_idx, :) = result.test_result.PSNR.';
    test_ssim_all(group_idx, :) = result.test_result.SSIM.';

    current = group_defs(group_idx);
    test_manifest = sample_manifest(test_indices, :);

    detail_rows{group_idx} = table( ...
        repmat(current.Q, num_test, 1), ...
        repmat(string(current.GroupName), num_test, 1), ...
        repmat(current.Range_q, num_test, 1), ...
        repmat(current.Azimuth_q, num_test, 1), ...
        repmat(string(current.GroupType), num_test, 1), ...
        repmat(result.best.STRdB, num_test, 1), ...
        repmat(result.best.FrOverBr, num_test, 1), ...
        repmat(result.best.FaOverBa, num_test, 1), ...
        test_manifest.SampleID, test_manifest.DatasetIdx, ...
        test_manifest.LocalSampleIdx, test_manifest.Dataset, ...
        test_manifest.File, test_manifest.CStart, ...
        result.test_result.PSNR, result.test_result.SSIM, ...
        'VariableNames', { ...
        'Q', 'GroupName', 'Range_q', 'Azimuth_q', 'GroupType', ...
        'STRdB', 'FrOverBr', 'FaOverBa', ...
        'SampleID', 'DatasetIdx', 'LocalSampleIdx', ...
        'Dataset', 'File', 'CStart', 'PSNR', 'SSIM'});

    for stage_idx = 1:numel(result.stage_results)
        stage = result.stage_results{stage_idx};
        rows = stage.grid_table;
        row_count = height(rows);

        prefix = table( ...
            repmat(current.Q, row_count, 1), ...
            repmat(string(current.GroupName), row_count, 1), ...
            repmat(current.Range_q, row_count, 1), ...
            repmat(current.Azimuth_q, row_count, 1), ...
            repmat(string(current.GroupType), row_count, 1), ...
            repmat(string(stage.signature.stage_name), row_count, 1), ...
            'VariableNames', { ...
            'Q', 'GroupName', 'Range_q', 'Azimuth_q', ...
            'GroupType', 'SearchStage'});

        grid_ptr = grid_ptr + 1;
        grid_rows{grid_ptr, 1} = [prefix, rows]; %#ok<AGROW>
    end
end

summary_table = vertcat(summary_rows{:});
detail_table = vertcat(detail_rows{:});
search_grid_table = vertcat(grid_rows{:});
end


function budget_best_table = buildBudgetBest(summary_table)
Q_values = unique(summary_table.Q);
num_Q = numel(Q_values);

Q = zeros(num_Q, 1);
BestAllocation = strings(num_Q, 1);
BestRangeQ = zeros(num_Q, 1);
BestAzimuthQ = zeros(num_Q, 1);
BestGroupType = strings(num_Q, 1);
IsBidirectional = false(num_Q, 1);
BestTestPSNR = zeros(num_Q, 1);
BestTestSSIM = zeros(num_Q, 1);
BestSTRdB = zeros(num_Q, 1);
BestFrOverBr = zeros(num_Q, 1);
BestFaOverBa = zeros(num_Q, 1);

for q_idx = 1:num_Q
    current_Q = Q_values(q_idx);
    candidates = summary_table(summary_table.Q == current_Q, :);
    candidates = sortrows(candidates, ...
        {'Test_SSIM_Mean', 'Test_PSNR_Mean', ...
        'Best_FrOverBr', 'Best_FaOverBa'}, ...
        {'descend', 'descend', 'ascend', 'ascend'});

    best = candidates(1, :);

    Q(q_idx) = current_Q;
    BestAllocation(q_idx) = best.GroupName;
    BestRangeQ(q_idx) = best.Range_q;
    BestAzimuthQ(q_idx) = best.Azimuth_q;
    BestGroupType(q_idx) = best.GroupType;
    IsBidirectional(q_idx) = best.Range_q > 1 && best.Azimuth_q > 1;
    BestTestPSNR(q_idx) = best.Test_PSNR_Mean;
    BestTestSSIM(q_idx) = best.Test_SSIM_Mean;
    BestSTRdB(q_idx) = best.Best_STRdB;
    BestFrOverBr(q_idx) = best.Best_FrOverBr;
    BestFaOverBa(q_idx) = best.Best_FaOverBa;
end

budget_best_table = table( ...
    Q, BestAllocation, BestRangeQ, BestAzimuthQ, ...
    BestGroupType, IsBidirectional, ...
    BestTestPSNR, BestTestSSIM, ...
    BestSTRdB, BestFrOverBr, BestFaOverBa);
end


function paired_tests = buildPairedTests( ...
        group_defs, summary_table, test_psnr_all, test_ssim_all)

Q_values = unique(summary_table.Q);
rows = cell(numel(Q_values), 1);
row_ptr = 0;
group_types = string({group_defs.GroupType}).';

for q_idx = 1:numel(Q_values)
    current_Q = Q_values(q_idx);

    bidir_idx = find( ...
        [group_defs.Q].' == current_Q & ...
        ismember(group_types, ["balanced", "mixed"]));
    unidir_idx = find( ...
        [group_defs.Q].' == current_Q & ...
        ismember(group_types, ["range_only", "azimuth_only"]));

    if isempty(bidir_idx) || isempty(unidir_idx)
        continue;
    end

    bidir_rows = summary_table(bidir_idx, :);
    unidir_rows = summary_table(unidir_idx, :);

    bidir_rows = sortrows(bidir_rows, ...
        {'Test_SSIM_Mean', 'Test_PSNR_Mean'}, {'descend', 'descend'});
    unidir_rows = sortrows(unidir_rows, ...
        {'Test_SSIM_Mean', 'Test_PSNR_Mean'}, {'descend', 'descend'});

    best_b_name = bidir_rows.GroupName(1);
    best_u_name = unidir_rows.GroupName(1);

    best_b = find(summary_table.GroupName == best_b_name, 1);
    best_u = find(summary_table.GroupName == best_u_name, 1);

    delta_psnr = summary_table.Test_PSNR_Mean(best_b) - ...
        summary_table.Test_PSNR_Mean(best_u);
    delta_ssim = summary_table.Test_SSIM_Mean(best_b) - ...
        summary_table.Test_SSIM_Mean(best_u);

    if exist("signrank", "file") == 2
        p_psnr = signrank( ...
            test_psnr_all(best_b, :), test_psnr_all(best_u, :), ...
            "tail", "both");
        p_ssim = signrank( ...
            test_ssim_all(best_b, :), test_ssim_all(best_u, :), ...
            "tail", "both");
    else
        p_psnr = NaN;
        p_ssim = NaN;
    end

    row_ptr = row_ptr + 1;
    rows{row_ptr} = table( ...
        current_Q, best_b_name, best_u_name, ...
        delta_psnr, delta_ssim, p_psnr, p_ssim, ...
        'VariableNames', { ...
        'Q', 'BestBidirectional', 'BestUnidirectional', ...
        'DeltaPSNR', 'DeltaSSIM', 'PValuePSNR', 'PValueSSIM'});
end

if row_ptr == 0
    paired_tests = table();
else
    paired_tests = vertcat(rows{1:row_ptr});
end
end


function writeMetadata( ...
        output_dir, signature, search_cfg, summary_table, ...
        budget_best_table, paired_tests_table)

metadata_path = fullfile(output_dir, "RSFT2D_Metadata.txt");
fid = fopen(metadata_path, "w");
assert(fid >= 0, "无法创建元数据文件：%s", metadata_path);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

fprintf(fid, "Experiment=V4_RSFT2DAllocationSearch\n");
fprintf(fid, "Seed=%d\n", signature.seed);
fprintf(fid, "QList=%s\n", mat2str(signature.Q_list));
fprintf(fid, "CalibrationSampleIDs=%s\n", ...
    mat2str(signature.calibration_sample_ids));
fprintf(fid, "TestSampleIDs=%s\n", mat2str(signature.test_sample_ids));
fprintf(fid, "CoarseSTRdB=%s\n", mat2str(search_cfg.coarse_STR_dB));
fprintf(fid, "CoarseFrOverBr=%s\n", ...
    mat2str(search_cfg.coarse_fr_over_Br));
fprintf(fid, "CoarseFaOverBa=%s\n", ...
    mat2str(search_cfg.coarse_fa_over_Ba));
fprintf(fid, "FineSTROffsets=%s\n", ...
    mat2str(search_cfg.fine_STR_offsets));
fprintf(fid, "FineFrOffsets=%s\n", ...
    mat2str(search_cfg.fine_fr_offsets));
fprintf(fid, "FineFaOffsets=%s\n", ...
    mat2str(search_cfg.fine_fa_offsets));
fprintf(fid, "MaxRefinementRounds=%d\n", ...
    search_cfg.max_refinement_rounds);
fprintf(fid, "InitialPhase=%.16g\n", search_cfg.initial_phase);
fprintf(fid, "RangeBandwidthHz=%.16g\n", ...
    signature.range_bandwidth_Hz);
fprintf(fid, "AzimuthBandwidthHz=%.16g\n", ...
    signature.azimuth_bandwidth_Hz);
fprintf(fid, "SelectionMetric=Calibration mean SSIM; PSNR tie-break\n");
fprintf(fid, "Split=Odd LocalSampleIdx calibration; even LocalSampleIdx test\n");
fprintf(fid, "Threshold=Constant-magnitude phase-sum 2D RSFT\n");
fprintf(fid, "GroupSummary=%s\n", ...
    jsonencode(table2struct(summary_table)));
fprintf(fid, "BudgetBest=%s\n", ...
    jsonencode(table2struct(budget_best_table)));
fprintf(fid, "PairedTests=%s\n", ...
    jsonencode(table2struct(paired_tests_table)));
end
