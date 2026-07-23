function V4_MainEvaluation()
% V4主实验：重跑SplitRT主结果，并补充Entropy和固定ROI的ENL。

cfg = V4Core.config();
addpath(cfg.repo_root, cfg.experiment_dir);
output_dir = fullfile(cfg.output_root, "MainEvaluation");
V4Core.ensureDir(cfg.output_root);
V4Core.ensureDir(output_dir);

S60 = load(cfg.parameter_file);
[sample_cache, sample_manifest] = V4Core.buildSampleCache(cfg, S60);
group_defs = V4Core.buildGroupDefinitions(cfg.Q_list);
num_groups = numel(group_defs);
total_samples = numel(sample_cache);

% ENL区域只由GT确定，随后对所有分配复用同一坐标。
is_enl_sample = ismember( ...
    string({sample_cache.dataset_name}), cfg.enl_dataset_names).';
enl_top = zeros(total_samples, 1);
enl_left = zeros(total_samples, 1);
enl_uniformity_score = nan(total_samples, 1);
for sample_idx = find(is_enl_sample).'
    [enl_top(sample_idx), enl_left(sample_idx), ...
        enl_uniformity_score(sample_idx)] = V4Core.selectUniformROI( ...
        sample_cache(sample_idx).img_gt, ...
        cfg.enl_window_size, cfg.enl_stride);
end

roi_manifest = sample_manifest(is_enl_sample, :);
roi_manifest.ROITop = enl_top(is_enl_sample);
roi_manifest.ROILeft = enl_left(is_enl_sample);
roi_manifest.ROIHeight = repmat(cfg.enl_window_size, height(roi_manifest), 1);
roi_manifest.ROIWidth = repmat(cfg.enl_window_size, height(roi_manifest), 1);
roi_manifest.UniformityScore = enl_uniformity_score(is_enl_sample);
writetable(sample_manifest, fullfile(output_dir, "V4_SampleManifest.csv"));
writetable(roi_manifest, fullfile(output_dir, "V4_ENL_ROI_Manifest.csv"));

psnr_all = nan(num_groups, total_samples);
ssim_all = nan(num_groups, total_samples);
entropy_all = nan(num_groups, total_samples);
enl_all = nan(num_groups, total_samples);
completed_groups = false(num_groups, 1);
checkpoint_path = fullfile(output_dir, "V4_Main_Checkpoint.mat");

if isfile(checkpoint_path)
    checkpoint = load(checkpoint_path);
    checkpoint_matches = ...
        isfield(checkpoint, "Q_list") && ...
        isfield(checkpoint, "seed") && ...
        isfield(checkpoint, "As") && ...
        isfield(checkpoint, "total_samples") && ...
        isequal(checkpoint.Q_list, cfg.Q_list) && ...
        checkpoint.seed == cfg.seed && ...
        checkpoint.As == cfg.As && ...
        checkpoint.total_samples == total_samples;
    if checkpoint_matches
        psnr_all = checkpoint.psnr_all;
        ssim_all = checkpoint.ssim_all;
        entropy_all = checkpoint.entropy_all;
        enl_all = checkpoint.enl_all;
        completed_groups = checkpoint.completed_groups;
        fprintf("检测到匹配的检查点，已完成 %d/%d 组。\n", ...
            sum(completed_groups), num_groups);
    else
        error("现有V4主实验检查点与当前配置不匹配，请人工核查。");
    end
end

fprintf("\n=== V4主结果：%d组 × %d样本 ===\n", num_groups, total_samples);
for group_idx = 1:num_groups
    current = group_defs(group_idx);
    if completed_groups(group_idx)
        fprintf("[%02d/%02d] %s：检查点已完成，跳过。\n", ...
            group_idx, num_groups, current.GroupName);
        continue;
    end
    fprintf("[%02d/%02d] %s\n", ...
        group_idx, num_groups, current.GroupName);

    % 与Exp1保持相同的组级随机种子，新增指标不调用随机数。
    rng(cfg.seed + group_idx);
    for sample_idx = 1:total_samples
        img_gt = sample_cache(sample_idx).img_gt;
        img_out = V4Core.buildSplitRTImage( ...
            sample_cache(sample_idx).signal60_input, S60, ...
            current.Range_q, current.Azimuth_q, cfg.As);

        psnr_all(group_idx, sample_idx) = psnr(img_out, img_gt);
        ssim_all(group_idx, sample_idx) = ssim(img_out, img_gt);
        entropy_all(group_idx, sample_idx) = ...
            V4Core.imageEntropy(img_out, cfg.entropy_num_bins);
        if is_enl_sample(sample_idx)
            enl_all(group_idx, sample_idx) = V4Core.enl( ...
                img_out, enl_top(sample_idx), enl_left(sample_idx), ...
                cfg.enl_window_size);
        end
    end

    completed_groups(group_idx) = true;
    Q_list = cfg.Q_list;
    seed = cfg.seed;
    As = cfg.As;
    save(checkpoint_path, ...
        "Q_list", "seed", "As", "total_samples", ...
        "psnr_all", "ssim_all", "entropy_all", "enl_all", ...
        "completed_groups", "-v7.3");
end

gt_entropy = nan(total_samples, 1);
gt_enl = nan(total_samples, 1);
for sample_idx = 1:total_samples
    gt_entropy(sample_idx) = V4Core.imageEntropy( ...
        sample_cache(sample_idx).img_gt, cfg.entropy_num_bins);
    if is_enl_sample(sample_idx)
        gt_enl(sample_idx) = V4Core.enl( ...
            sample_cache(sample_idx).img_gt, ...
            enl_top(sample_idx), enl_left(sample_idx), ...
            cfg.enl_window_size);
    end
end

summary_table = buildSummaryTable( ...
    group_defs, cfg.As, psnr_all, ssim_all, entropy_all, enl_all);
detail_table = buildDetailTable( ...
    group_defs, sample_manifest, psnr_all, ssim_all, entropy_all, enl_all);
gt_detail_table = sample_manifest;
gt_detail_table.PSNR = inf(total_samples, 1);
gt_detail_table.SSIM = ones(total_samples, 1);
gt_detail_table.Entropy = gt_entropy;
gt_detail_table.ENL = gt_enl;

gt_summary = table( ...
    0, "GT", 0, 0, "reference", total_samples, sum(is_enl_sample), NaN, ...
    Inf, NaN, 1, 0, ...
    mean(gt_entropy, "omitnan"), std(gt_entropy, 0, "omitnan"), ...
    mean(gt_enl, "omitnan"), std(gt_enl, 0, "omitnan"), ...
    'VariableNames', summary_table.Properties.VariableNames);

table_iii = [gt_summary; summary_table(1, :)];
for Q = cfg.table_Q_list
    table_iii = [table_iii; summary_table(summary_table.Q == Q, :)]; %#ok<AGROW>
end

writetable(summary_table, fullfile(output_dir, "V4_Main_Summary.csv"));
writetable(detail_table, fullfile(output_dir, "V4_Main_Detail.csv"));
writetable(gt_detail_table, fullfile(output_dir, "V4_GT_Detail.csv"));
writetable(table_iii, fullfile(output_dir, "V4_TableIII_Metrics.csv"));

save(fullfile(output_dir, "V4_Main_Data.mat"), ...
    "cfg", "group_defs", "sample_manifest", "roi_manifest", ...
    "psnr_all", "ssim_all", "entropy_all", "enl_all", ...
    "gt_entropy", "gt_enl", "summary_table", "table_iii", "-v7.3");

exportROIAudit(sample_cache, is_enl_sample, enl_top, enl_left, ...
    cfg.enl_window_size, fullfile(output_dir, "V4_ENL_ROI_Audit.png"));
writeMetadata(cfg, total_samples, sum(is_enl_sample), output_dir);
fprintf("V4主实验完成：%s\n", output_dir);
end

function summary_table = buildSummaryTable( ...
        group_defs, As, psnr_all, ssim_all, entropy_all, enl_all)
num_groups = numel(group_defs);
Q = [group_defs.Q].';
GroupName = string({group_defs.GroupName}).';
Range_q = [group_defs.Range_q].';
Azimuth_q = [group_defs.Azimuth_q].';
GroupType = string({group_defs.GroupType}).';
SampleCount = repmat(size(psnr_all, 2), num_groups, 1);
ENLSampleCount = sum(~isnan(enl_all), 2);
AsColumn = repmat(As, num_groups, 1);

summary_table = table( ...
    Q, GroupName, Range_q, Azimuth_q, GroupType, ...
    SampleCount, ENLSampleCount, AsColumn, ...
    mean(psnr_all, 2, "omitnan"), std(psnr_all, 0, 2, "omitnan"), ...
    mean(ssim_all, 2, "omitnan"), std(ssim_all, 0, 2, "omitnan"), ...
    mean(entropy_all, 2, "omitnan"), std(entropy_all, 0, 2, "omitnan"), ...
    mean(enl_all, 2, "omitnan"), std(enl_all, 0, 2, "omitnan"), ...
    'VariableNames', { ...
    'Q', 'GroupName', 'Range_q', 'Azimuth_q', 'GroupType', ...
    'SampleCount', 'ENLSampleCount', 'As', ...
    'PSNR_Mean', 'PSNR_Std', 'SSIM_Mean', 'SSIM_Std', ...
    'Entropy_Mean', 'Entropy_Std', 'ENL_Mean', 'ENL_Std'});
end

function detail_table = buildDetailTable( ...
        group_defs, sample_manifest, psnr_all, ssim_all, entropy_all, enl_all)
num_groups = numel(group_defs);
total_samples = height(sample_manifest);
num_rows = num_groups * total_samples;

Q = zeros(num_rows, 1);
GroupName = strings(num_rows, 1);
Range_q = zeros(num_rows, 1);
Azimuth_q = zeros(num_rows, 1);
GroupType = strings(num_rows, 1);
SampleID = zeros(num_rows, 1);
Dataset = strings(num_rows, 1);
File = strings(num_rows, 1);
CStart = zeros(num_rows, 1);
PSNR = zeros(num_rows, 1);
SSIM = zeros(num_rows, 1);
Entropy = zeros(num_rows, 1);
ENL = nan(num_rows, 1);

ptr = 0;
for group_idx = 1:num_groups
    rows = ptr + (1:total_samples);
    current = group_defs(group_idx);
    Q(rows) = current.Q;
    GroupName(rows) = current.GroupName;
    Range_q(rows) = current.Range_q;
    Azimuth_q(rows) = current.Azimuth_q;
    GroupType(rows) = current.GroupType;
    SampleID(rows) = sample_manifest.SampleID;
    Dataset(rows) = sample_manifest.Dataset;
    File(rows) = sample_manifest.File;
    CStart(rows) = sample_manifest.CStart;
    PSNR(rows) = psnr_all(group_idx, :).';
    SSIM(rows) = ssim_all(group_idx, :).';
    Entropy(rows) = entropy_all(group_idx, :).';
    ENL(rows) = enl_all(group_idx, :).';
    ptr = ptr + total_samples;
end

detail_table = table( ...
    Q, GroupName, Range_q, Azimuth_q, GroupType, ...
    SampleID, Dataset, File, CStart, PSNR, SSIM, Entropy, ENL);
end

function exportROIAudit( ...
        sample_cache, is_enl_sample, tops, lefts, window_size, save_path)
indices = find(is_enl_sample);
fig = figure("Color", "w", "Units", "centimeters", ...
    "Position", [2, 2, 20, 25], "Visible", "off");
layout = tiledlayout(fig, 5, 4, "Padding", "compact", ...
    "TileSpacing", "compact");
for tile_idx = 1:numel(indices)
    sample_idx = indices(tile_idx);
    ax = nexttile(layout);
    imagesc(ax, sample_cache(sample_idx).img_gt, [0, 1]);
    axis(ax, "image", "off");
    colormap(ax, gray);
    hold(ax, "on");
    rectangle(ax, "Position", [ ...
        lefts(sample_idx), tops(sample_idx), ...
        window_size - 1, window_size - 1], ...
        "EdgeColor", [1, 0.2, 0.1], "LineWidth", 1.2);
    title(ax, sprintf("%s-%02d", ...
        sample_cache(sample_idx).dataset_name, ...
        sample_cache(sample_idx).sample_idx), ...
        "Interpreter", "none", "FontSize", 7);
end
exportgraphics(fig, save_path, "Resolution", 240);
close(fig);
end

function writeMetadata(cfg, total_samples, enl_samples, output_dir)
fid = fopen(fullfile(output_dir, "V4_Main_Metadata.txt"), "w");
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, "Seed=%d\n", cfg.seed);
fprintf(fid, "As=%.16g\n", cfg.As);
fprintf(fid, "QList=%s\n", mat2str(cfg.Q_list));
fprintf(fid, "TableQList=%s\n", mat2str(cfg.table_Q_list));
fprintf(fid, "SampleCount=%d\n", total_samples);
fprintf(fid, "ENLSampleCount=%d\n", enl_samples);
fprintf(fid, "ENLWindow=%d\n", cfg.enl_window_size);
fprintf(fid, "ENLStride=%d\n", cfg.enl_stride);
fprintf(fid, "EntropyBins=%d\n", cfg.entropy_num_bins);
fprintf(fid, "EntropyInput=normalized amplitude [0,1]\n");
fprintf(fid, "ENLInput=normalized amplitude squared to intensity\n");
end
