function Exp6_Runtime(mode)
%EXP6_RUNTIME 测量固定上采样预算下完整1-bit SAR处理链的运行时间。
%   Exp6_Runtime() 或 Exp6_Runtime("smoke") 仅执行1个样本、4个组合的轻量测试。
%   Exp6_Runtime("full") 执行19个组合、70个样本的正式实验；正式实验需单独授权。

if nargin < 1
    mode = "smoke";
end
mode = string(validatestring(char(string(mode)), {'smoke', 'full'}));

repo_root = fileparts(mfilename("fullpath"));
addpath(repo_root, fullfile(repo_root, "v5_experiments"));

cfg = build_config(repo_root);
S60 = load(cfg.parameter_file);
all_group_defs = build_group_definitions(cfg.Q_list);
validate_group_definitions(all_group_defs, cfg.Q_list);

if mode == "smoke"
    smoke_names = ["R1A1", "R4A1", "R2A2", "R1A4"];
    [found, group_indices] = ismember(smoke_names, string({all_group_defs.GroupName}));
    assert(all(found), "Smoke test所需组合定义不完整。");
    group_defs = all_group_defs(group_indices);
    [sample_cache, sample_manifest] = build_sample_cache(cfg, S60, true);
    output_dir = fullfile(cfg.output_root, ...
        "SmokeTest_" + string(datetime("now", "Format", "yyyyMMdd_HHmmss")));
else
    group_defs = all_group_defs;
    [sample_cache, sample_manifest] = build_sample_cache(cfg, S60, false);
    output_dir = cfg.output_root;
end
V5Core.ensureDir(output_dir);

% 先验证消除重复上采样不会改变原处理路径的数值结果。
regression_result = run_single_upsample_regression( ...
    sample_cache(1).signal60_input, S60, cfg);

environment_metadata = collect_environment_metadata();
signature = build_signature(cfg, group_defs, sample_manifest, ...
    environment_metadata, S60, mode);

if mode == "full"
    assert_formal_outputs_absent(output_dir);
    checkpoint_path = fullfile(output_dir, "Exp6_Runtime_Checkpoint.mat");
    [runtime_ms, completed_groups] = load_or_initialize_checkpoint( ...
        checkpoint_path, signature, numel(group_defs), numel(sample_cache));
else
    checkpoint_path = "";
    runtime_ms = nan(numel(group_defs), numel(sample_cache));
    completed_groups = false(numel(group_defs), 1);
end

fprintf("=== Exp6 Runtime：%s，%d组 × %d样本 ===\n", ...
    mode, numel(group_defs), numel(sample_cache));
for group_idx = 1:numel(group_defs)
    if completed_groups(group_idx)
        fprintf("[%02d/%02d] %s 已由checkpoint完成，跳过。\n", ...
            group_idx, numel(group_defs), group_defs(group_idx).GroupName);
        continue;
    end

    current = group_defs(group_idx);
    fprintf("[%02d/%02d] %s warm-up并计时。\n", ...
        group_idx, numel(group_defs), current.GroupName);

    % Warm-up不进入统计；随后重置RNG，保证正式样本阈值序列可复现。
    rng(cfg.seed + current.SeedOffset);
    build_runtime_image(sample_cache(1).signal60_input, S60, ...
        current.Range_q, current.Azimuth_q, cfg.As);
    rng(cfg.seed + current.SeedOffset);

    for sample_idx = 1:numel(sample_cache)
        signal60 = sample_cache(sample_idx).signal60_input;
        timer_id = tic;
        img_out = build_runtime_image(signal60, S60, ...
            current.Range_q, current.Azimuth_q, cfg.As);
        runtime_ms(group_idx, sample_idx) = 1000 * toc(timer_id);

        assert(all(isfinite(img_out(:))), "成像结果存在非有限值。");
        assert(isfinite(runtime_ms(group_idx, sample_idx)) && ...
            runtime_ms(group_idx, sample_idx) > 0, "Runtime_ms必须为有限正数。");
    end

    completed_groups(group_idx) = true;
    if mode == "full"
        save(checkpoint_path, "signature", "runtime_ms", ...
            "completed_groups", "-v7.3");
    end
end

detail_table = build_detail_table(group_defs, sample_manifest, runtime_ms);
summary_table = build_summary_table(group_defs, runtime_ms);
validate_results(mode, group_defs, sample_manifest, runtime_ms, ...
    detail_table, summary_table);

detail_path = fullfile(output_dir, "Exp6_Runtime_Detail.csv");
summary_path = fullfile(output_dir, "Exp6_Runtime_Summary.csv");
data_path = fullfile(output_dir, "Exp6_Runtime_Data.mat");

writetable(detail_table, detail_path);
writetable(summary_table, summary_path);
save(data_path, "cfg", "group_defs", "sample_manifest", "runtime_ms", ...
    "summary_table", "environment_metadata", "regression_result", ...
    "signature", "-v7.3");

fprintf("Exp6 Runtime %s完成：%s\n", mode, output_dir);
fprintf("R2A2单次上采样回归最大绝对误差：%.3e\n", ...
    regression_result.MaxAbsError);
end


function cfg = build_config(repo_root)
% 固定实验配置与论文主实验保持一致。
cfg = struct();
cfg.experiment_name = "Exp6_Runtime";
cfg.repo_root = repo_root;
cfg.output_root = fullfile(repo_root, "Exp6_Runtime_Output");
cfg.data_root = "G:\MATLAB-G\SAR Full PSF";
cfg.parameter_file = fullfile(repo_root, "FS60_params.mat");
cfg.seed = 2026;
cfg.As = 0.6;
cfg.Q_list = [4, 6, 8, 9, 10];
cfg.num_samples_per_dataset = 10;
cfg.dataset_names = { ...
    "SAR_Dataset_Bangkok_1", ...
    "SAR_Dataset_city1_histeq", ...
    "SAR_Dataset_city2_histeq", ...
    "SAR_Dataset_SAR_figure", ...
    "SAR_Dataset_filed", ...
    "SAR_Dataset_port", ...
    "SAR_Dataset_suburb"};
cfg.regression_group = "R2A2";
cfg.regression_tolerance = 1e-12;
cfg.seed_protocol = "rng(seed + full group index); reset after warm-up";
end


function group_defs = build_group_definitions(Q_list)
% 复用V5整数因子定义，并保留其组索引作为随机种子偏移。
group_defs = V5Core.buildGroupDefinitions(Q_list);
group_defs(1).GroupName = "R1A1";
for idx = 1:numel(group_defs)
    group_defs(idx).SeedOffset = idx;
end
end


function validate_group_definitions(group_defs, Q_list)
expected_names = [ ...
    "R1A1", ...
    "R4A1", "R2A2", "R1A4", ...
    "R6A1", "R3A2", "R2A3", "R1A6", ...
    "R8A1", "R4A2", "R2A4", "R1A8", ...
    "R9A1", "R3A3", "R1A9", ...
    "R10A1", "R5A2", "R2A5", "R1A10"];
actual_names = string({group_defs.GroupName});

assert(numel(group_defs) == 19, "正式runtime实验必须包含19个组合。");
assert(numel(unique(actual_names)) == numel(actual_names), "组合名称存在重复。");
assert(isempty(setxor(actual_names, expected_names)), "组合定义与论文Table III不一致。");

for idx = 2:numel(group_defs)
    assert(group_defs(idx).Range_q * group_defs(idx).Azimuth_q == ...
        group_defs(idx).Q, "组合%s不满足Q=R*A。", group_defs(idx).GroupName);
    assert(any(group_defs(idx).Q == Q_list), "组合%s使用了未授权Q。", ...
        group_defs(idx).GroupName);
end
end


function [sample_cache, sample_manifest] = build_sample_cache(cfg, S60, smoke_only)
% 缓存仅保存runtime所需的复回波和样本元数据，不构造参考图像。
if smoke_only
    dataset_indices = 1;
    local_sample_indices = 1;
else
    dataset_indices = 1:numel(cfg.dataset_names);
    local_sample_indices = 1:cfg.num_samples_per_dataset;
end

total_samples = numel(dataset_indices) * numel(local_sample_indices);
sample_cache = repmat(struct( ...
    "sample_id", 0, "dataset_idx", 0, "sample_idx", 0, ...
    "dataset_name", "", "filename", "", "c_start", 0, ...
    "signal60_input", []), total_samples, 1);

sample_id = 0;
for ds_idx = dataset_indices
    ds_name = cfg.dataset_names{ds_idx};
    mat_files = dir(fullfile(cfg.data_root, ds_name, "rstart*.mat"));
    mat_names = sort({mat_files.name});
    if isempty(mat_names)
        error("数据集%s中未找到rstart*.mat。", ds_name);
    end

    pick_idx = mod(cfg.seed, numel(mat_names)) + 1;
    picked_name = mat_names{pick_idx};
    loaded = load(fullfile(cfg.data_root, ds_name, picked_name));
    variable_names = fieldnames(loaded);
    raw_data = loaded.(variable_names{1});
    starts = build_stratified_window_starts( ...
        size(raw_data, 2), S60.nrn, cfg.num_samples_per_dataset);

    for local_idx = local_sample_indices
        sample_id = sample_id + 1;
        c_start = starts(local_idx);
        channel_block = raw_data(:, c_start:c_start + S60.nrn - 1);
        signal60 = channel_block(1:3:end, :);
        assert(isequal(size(signal60), [S60.nrn, S60.nan]), ...
            "样本尺寸与FS60参数不一致。");

        sample_cache(sample_id).sample_id = sample_id;
        sample_cache(sample_id).dataset_idx = ds_idx;
        sample_cache(sample_id).sample_idx = local_idx;
        sample_cache(sample_id).dataset_name = string(ds_name);
        sample_cache(sample_id).filename = string(picked_name);
        sample_cache(sample_id).c_start = c_start;
        sample_cache(sample_id).signal60_input = signal60;
    end
    clear raw_data loaded;
end

sample_manifest = table( ...
    [sample_cache.sample_id].', [sample_cache.dataset_idx].', ...
    [sample_cache.sample_idx].', string({sample_cache.dataset_name}).', ...
    string({sample_cache.filename}).', [sample_cache.c_start].', ...
    'VariableNames', {'SampleID', 'DatasetIdx', 'SampleIdx', ...
    'Dataset', 'File', 'CStart'});
end


function sample_starts = build_stratified_window_starts( ...
        raw_width, window_width, num_samples)
max_start = raw_width - window_width + 1;
if max_start < 1
    error("序列宽度不足以裁出完整窗口。");
end
sample_starts = zeros(num_samples, 1);
for sample_idx = 1:num_samples
    center_pos = round((sample_idx - 0.5) / num_samples * max_start);
    sample_starts(sample_idx) = min(max(center_pos, 1), max_start);
end
end


function img_out = build_runtime_image(signal60, S60, range_q, azimuth_q, As)
% 计时链只计算一次上采样结果，阈值和后续处理复用同一signal_up。
signal_up = V5Core.twoDimUpsample(signal60, azimuth_q, range_q);
threshold = V5Core.buildSplitRTThreshold(signal_up, As);
channel_1bit = V5Core.quantizeWithThreshold(signal_up, threshold);
img_out = V5Core.focusUpsampledChannel( ...
    channel_1bit, S60, range_q, azimuth_q);
end


function img_out = build_legacy_reference_image( ...
        signal60, S60, range_q, azimuth_q, As)
% 精确保留Exp1旧路径的冗余：阈值构造和实际处理分别计算一次上采样。
threshold_signal = V5Core.twoDimUpsample(signal60, azimuth_q, range_q);
threshold = V5Core.buildSplitRTThreshold(threshold_signal, As);
processing_signal = V5Core.twoDimUpsample(signal60, azimuth_q, range_q);
channel_1bit = V5Core.quantizeWithThreshold(processing_signal, threshold);
img_out = V5Core.focusUpsampledChannel( ...
    channel_1bit, S60, range_q, azimuth_q);
end


function result = run_single_upsample_regression(signal60, S60, cfg)
range_q = 2;
azimuth_q = 2;
regression_seed = cfg.seed + 3;

rng(regression_seed);
legacy_image = build_legacy_reference_image( ...
    signal60, S60, range_q, azimuth_q, cfg.As);
rng(regression_seed);
clean_image = build_runtime_image( ...
    signal60, S60, range_q, azimuth_q, cfg.As);

max_abs_error = max(abs(legacy_image - clean_image), [], "all");
assert(max_abs_error <= cfg.regression_tolerance, ...
    "单次上采样路径与原路径不一致，最大绝对误差为%.3e。", max_abs_error);

result = struct( ...
    "GroupName", cfg.regression_group, ...
    "Seed", regression_seed, ...
    "Tolerance", cfg.regression_tolerance, ...
    "MaxAbsError", max_abs_error, ...
    "Passed", true);
end


function metadata = collect_environment_metadata()
metadata = struct();
metadata.Timestamp = datetime("now", "TimeZone", "local");
metadata.MATLABVersion = string(version);
metadata.MATLABRelease = string(version("-release"));
metadata.OS = string(system_dependent("getos"));
metadata.Computer = string(computer);
metadata.Architecture = string(computer("arch"));
metadata.CPUModel = string(getenv("PROCESSOR_IDENTIFIER"));

logical_processors = str2double(getenv("NUMBER_OF_PROCESSORS"));
if ~isfinite(logical_processors)
    logical_processors = NaN;
end
metadata.LogicalProcessorCount = logical_processors;
try
    metadata.MATLABReportedCoreCount = feature("numcores");
catch
    metadata.MATLABReportedCoreCount = NaN;
end

metadata.ParallelPoolState = "toolbox_unavailable";
metadata.ParallelPoolType = "";
metadata.ParallelPoolWorkers = 0;
if exist("gcp", "file") == 2
    pool = gcp("nocreate");
    if isempty(pool)
        metadata.ParallelPoolState = "closed";
    else
        metadata.ParallelPoolState = "open";
        metadata.ParallelPoolType = string(class(pool));
        metadata.ParallelPoolWorkers = pool.NumWorkers;
    end
end
end


function signature = build_signature( ...
        cfg, group_defs, sample_manifest, metadata, S60, mode)
signature = struct();
signature.Experiment = cfg.experiment_name;
signature.Mode = mode;
signature.Seed = cfg.seed;
signature.SeedProtocol = cfg.seed_protocol;
signature.As = cfg.As;
signature.QList = cfg.Q_list;
signature.GroupName = string({group_defs.GroupName}).';
signature.Range_q = [group_defs.Range_q].';
signature.Azimuth_q = [group_defs.Azimuth_q].';
signature.SeedOffset = [group_defs.SeedOffset].';
signature.SampleID = sample_manifest.SampleID;
signature.Dataset = sample_manifest.Dataset;
signature.File = sample_manifest.File;
signature.CStart = sample_manifest.CStart;
signature.RangeSamplingFrequency = S60.Fs;
signature.AzimuthPRF = S60.prf;
signature.MATLABRelease = metadata.MATLABRelease;
signature.Architecture = metadata.Architecture;
signature.CPUModel = metadata.CPUModel;
end


function assert_formal_outputs_absent(output_dir)
final_paths = [ ...
    string(fullfile(output_dir, "Exp6_Runtime_Detail.csv")); ...
    string(fullfile(output_dir, "Exp6_Runtime_Summary.csv")); ...
    string(fullfile(output_dir, "Exp6_Runtime_Data.mat"))];
assert(~any(isfile(final_paths)), ...
    "正式runtime结果已存在；为避免覆盖，请先人工确认现有输出。");
end


function [runtime_ms, completed_groups] = load_or_initialize_checkpoint( ...
        checkpoint_path, signature, num_groups, num_samples)
runtime_ms = nan(num_groups, num_samples);
completed_groups = false(num_groups, 1);
if ~isfile(checkpoint_path)
    return;
end

checkpoint = load(checkpoint_path);
assert(isfield(checkpoint, "signature") && ...
    isequaln(checkpoint.signature, signature), ...
    "现有Exp6 checkpoint签名不匹配，拒绝静默恢复。");
assert(isequal(size(checkpoint.runtime_ms), [num_groups, num_samples]), ...
    "Checkpoint runtime矩阵尺寸不正确。");
assert(isequal(size(checkpoint.completed_groups), [num_groups, 1]), ...
    "Checkpoint完成状态尺寸不正确。");

runtime_ms = checkpoint.runtime_ms;
completed_groups = checkpoint.completed_groups;
end


function detail_table = build_detail_table( ...
        group_defs, sample_manifest, runtime_ms)
num_groups = numel(group_defs);
num_samples = height(sample_manifest);
num_rows = num_groups * num_samples;

Q = zeros(num_rows, 1);
GroupName = strings(num_rows, 1);
Range_q = zeros(num_rows, 1);
Azimuth_q = zeros(num_rows, 1);
Dataset = strings(num_rows, 1);
DatasetIdx = zeros(num_rows, 1);
SampleIdx = zeros(num_rows, 1);
CStart = zeros(num_rows, 1);
Runtime_ms = zeros(num_rows, 1);

for group_idx = 1:num_groups
    rows = ((group_idx - 1) * num_samples + (1:num_samples)).';
    Q(rows) = repmat(group_defs(group_idx).Q, num_samples, 1);
    GroupName(rows) = repmat(string(group_defs(group_idx).GroupName), num_samples, 1);
    Range_q(rows) = repmat(group_defs(group_idx).Range_q, num_samples, 1);
    Azimuth_q(rows) = repmat(group_defs(group_idx).Azimuth_q, num_samples, 1);
    Dataset(rows) = sample_manifest.Dataset;
    DatasetIdx(rows) = sample_manifest.DatasetIdx;
    SampleIdx(rows) = sample_manifest.SampleIdx;
    CStart(rows) = sample_manifest.CStart;
    Runtime_ms(rows) = runtime_ms(group_idx, :).';
end

detail_table = table(Q, GroupName, Range_q, Azimuth_q, Dataset, ...
    DatasetIdx, SampleIdx, CStart, Runtime_ms);
end


function summary_table = build_summary_table(group_defs, runtime_ms)
num_groups = numel(group_defs);
Q = [group_defs.Q].';
GroupName = string({group_defs.GroupName}).';
Range_q = [group_defs.Range_q].';
Azimuth_q = [group_defs.Azimuth_q].';
SampleCount = repmat(size(runtime_ms, 2), num_groups, 1);
Mean_ms = mean(runtime_ms, 2);
Std_ms = std(runtime_ms, 0, 2);
Median_ms = median(runtime_ms, 2);
Min_ms = min(runtime_ms, [], 2);
Max_ms = max(runtime_ms, [], 2);

baseline_idx = find(Range_q == 1 & Azimuth_q == 1, 1);
assert(~isempty(baseline_idx), "缺少R1A1 baseline。");
RelativeToR1A1 = Mean_ms / Mean_ms(baseline_idx);
RelativeToBestUnidirectional = nan(num_groups, 1);

for group_idx = 1:num_groups
    if Q(group_idx) == 1
        continue;
    end
    unidirectional_mask = Q == Q(group_idx) & ...
        ((Range_q == Q) | (Azimuth_q == Q));
    if any(unidirectional_mask)
        best_unidirectional = min(Mean_ms(unidirectional_mask));
        RelativeToBestUnidirectional(group_idx) = ...
            Mean_ms(group_idx) / best_unidirectional;
    end
end

summary_table = table(Q, GroupName, Range_q, Azimuth_q, SampleCount, ...
    Mean_ms, Std_ms, Median_ms, Min_ms, Max_ms, RelativeToR1A1, ...
    RelativeToBestUnidirectional);
end


function validate_results(mode, group_defs, sample_manifest, runtime_ms, ...
        detail_table, summary_table)
assert(isequal(size(runtime_ms), [numel(group_defs), height(sample_manifest)]), ...
    "Runtime矩阵尺寸错误。");
assert(all(isfinite(runtime_ms), "all") && all(runtime_ms > 0, "all"), ...
    "Runtime矩阵必须全部为有限正数。");
assert(height(detail_table) == numel(group_defs) * height(sample_manifest), ...
    "Runtime明细表行数错误。");
assert(height(summary_table) == numel(group_defs), "Runtime汇总表行数错误。");
assert(all(summary_table.SampleCount == height(sample_manifest)), ...
    "各组合样本数不一致。");

if mode == "full"
    assert(numel(group_defs) == 19 && height(sample_manifest) == 70, ...
        "正式实验必须为19组×70样本。");
    assert(height(detail_table) == 1330, "正式runtime明细应包含1330行。");
else
    assert(numel(group_defs) == 4 && height(sample_manifest) == 1, ...
        "Smoke test必须为4组×1样本。");
end
end
