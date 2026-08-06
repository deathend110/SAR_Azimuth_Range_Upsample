function V5_MainEvaluation()
% V5主实验：SplitRT固定预算结果、ENL/Entropy和配对检验。

cfg = V5Core.config();
addpath(cfg.repo_root, cfg.experiment_dir);
output_dir = fullfile(cfg.output_root, "MainEvaluation");
V5Core.ensureDir(output_dir);
S60 = load(cfg.parameter_file);
[sample_cache, sample_manifest] = V5Core.buildSampleCache(cfg, S60);
group_defs = V5Core.buildGroupDefinitions(cfg.Q_list);
num_groups = numel(group_defs);
num_samples = numel(sample_cache);

[is_enl, enl_top, enl_left, ~, roi_manifest] = ...
    V5Core.buildENLRegions(sample_cache, sample_manifest, cfg);
writetable(sample_manifest, fullfile(output_dir, "V5_SampleManifest.csv"));
writetable(roi_manifest, fullfile(output_dir, "V5_ENL_ROI_Manifest.csv"));

psnr_all = nan(num_groups, num_samples);
ssim_all = nan(num_groups, num_samples);
entropy_all = nan(num_groups, num_samples);
enl_all = nan(num_groups, num_samples);
completed_groups = false(num_groups, 1);
signature = struct("Experiment", "V5_MainEvaluation", ...
    "Seed", cfg.seed, "As", cfg.As, "QList", cfg.Q_list, ...
    "SampleID", sample_manifest.SampleID, ...
    "Dataset", sample_manifest.Dataset, "CStart", sample_manifest.CStart);
checkpoint_path = fullfile(output_dir, "V5_Main_Checkpoint.mat");
if isfile(checkpoint_path)
    checkpoint = load(checkpoint_path);
    if ~isfield(checkpoint, "signature") || ...
            ~isequaln(checkpoint.signature, signature)
        error("现有V5主实验checkpoint签名不匹配。");
    end
    psnr_all = checkpoint.psnr_all;
    ssim_all = checkpoint.ssim_all;
    entropy_all = checkpoint.entropy_all;
    enl_all = checkpoint.enl_all;
    completed_groups = checkpoint.completed_groups;
end

fprintf("=== V5主实验：%d组 × %d样本 ===\n", num_groups, num_samples);
for group_idx = 1:num_groups
    if completed_groups(group_idx), continue; end
    current = group_defs(group_idx);
    fprintf("[%02d/%02d] %s\n", group_idx, num_groups, current.GroupName);
    rng(cfg.seed + group_idx);
    for sample_idx = 1:num_samples
        img_out = V5Core.buildSplitRTImage( ...
            sample_cache(sample_idx).signal60_input, S60, ...
            current.Range_q, current.Azimuth_q, cfg.As);
        img_gt = sample_cache(sample_idx).img_gt;
        psnr_all(group_idx, sample_idx) = psnr(img_out, img_gt);
        ssim_all(group_idx, sample_idx) = ssim(img_out, img_gt);
        entropy_all(group_idx, sample_idx) = ...
            V5Core.imageEntropy(img_out, cfg.entropy_num_bins);
        if is_enl(sample_idx)
            enl_all(group_idx, sample_idx) = V5Core.enl(img_out, ...
                enl_top(sample_idx), enl_left(sample_idx), cfg.enl_window_size);
        end
    end
    completed_groups(group_idx) = true;
    save(checkpoint_path, "signature", "psnr_all", "ssim_all", ...
        "entropy_all", "enl_all", "completed_groups", "-v7.3");
end

gt_entropy = arrayfun(@(s) V5Core.imageEntropy( ...
    s.img_gt, cfg.entropy_num_bins), sample_cache).';
gt_enl = nan(num_samples, 1);
for sample_idx = find(is_enl).'
    gt_enl(sample_idx) = V5Core.enl(sample_cache(sample_idx).img_gt, ...
        enl_top(sample_idx), enl_left(sample_idx), cfg.enl_window_size);
end

summary_table = buildSummary(group_defs, cfg.As, ...
    psnr_all, ssim_all, entropy_all, enl_all);
detail_table = buildDetail(group_defs, sample_manifest, ...
    psnr_all, ssim_all, entropy_all, enl_all);
gt_summary = table(0, "GT", 0, 0, "reference", num_samples, sum(is_enl), ...
    NaN, Inf, NaN, 1, 0, mean(gt_entropy), std(gt_entropy), ...
    mean(gt_enl, "omitnan"), std(gt_enl, 0, "omitnan"), ...
    'VariableNames', summary_table.Properties.VariableNames);
table_metrics = [gt_summary; summary_table];
paired_tests = buildPairedTests(group_defs, psnr_all, ssim_all, cfg.Q_list);

writetable(summary_table, fullfile(output_dir, "V5_Main_Summary.csv"));
writetable(detail_table, fullfile(output_dir, "V5_Main_Detail.csv"));
writetable(table_metrics, fullfile(output_dir, "V5_TableIII_Metrics.csv"));
writetable(paired_tests, fullfile(output_dir, "V5_RT_PairedTests.csv"));
save(fullfile(output_dir, "V5_Main_Data.mat"), "cfg", "group_defs", ...
    "sample_manifest", "roi_manifest", "psnr_all", "ssim_all", ...
    "entropy_all", "enl_all", "summary_table", "paired_tests", "-v7.3");
exportROIAudit(sample_cache, is_enl, enl_top, enl_left, ...
    cfg.enl_window_size, fullfile(output_dir, "V5_ENL_ROI_Audit.png"));
writeMetadata(cfg, num_samples, sum(is_enl), output_dir);
fprintf("V5主实验完成：%s\n", output_dir);
end

function T = buildSummary(defs, As, psnr_all, ssim_all, entropy_all, enl_all)
n = numel(defs);
T = table([defs.Q].', string({defs.GroupName}).', [defs.Range_q].', ...
    [defs.Azimuth_q].', string({defs.GroupType}).', ...
    repmat(size(psnr_all, 2), n, 1), sum(~isnan(enl_all), 2), ...
    repmat(As, n, 1), mean(psnr_all, 2), std(psnr_all, 0, 2), ...
    mean(ssim_all, 2), std(ssim_all, 0, 2), ...
    mean(entropy_all, 2), std(entropy_all, 0, 2), ...
    mean(enl_all, 2, "omitnan"), std(enl_all, 0, 2, "omitnan"), ...
    'VariableNames', {'Q','GroupName','Range_q','Azimuth_q','GroupType', ...
    'SampleCount','ENLSampleCount','As','PSNR_Mean','PSNR_Std', ...
    'SSIM_Mean','SSIM_Std','Entropy_Mean','Entropy_Std','ENL_Mean','ENL_Std'});
end

function T = buildDetail(defs, manifest, psnr_all, ssim_all, entropy_all, enl_all)
n_groups = numel(defs); n_samples = height(manifest); n_rows = n_groups*n_samples;
Q = zeros(n_rows,1); GroupName = strings(n_rows,1); Range_q = zeros(n_rows,1);
Azimuth_q = zeros(n_rows,1); GroupType = strings(n_rows,1);
SampleID = zeros(n_rows,1); Dataset = strings(n_rows,1); File = strings(n_rows,1);
CStart = zeros(n_rows,1); PSNR = zeros(n_rows,1); SSIM = zeros(n_rows,1);
Entropy = zeros(n_rows,1); ENL = nan(n_rows,1);
for g = 1:n_groups
    rows = (g-1)*n_samples+(1:n_samples);
    Q(rows)=defs(g).Q; GroupName(rows)=defs(g).GroupName;
    Range_q(rows)=defs(g).Range_q; Azimuth_q(rows)=defs(g).Azimuth_q;
    GroupType(rows)=defs(g).GroupType; SampleID(rows)=manifest.SampleID;
    Dataset(rows)=manifest.Dataset; File(rows)=manifest.File; CStart(rows)=manifest.CStart;
    PSNR(rows)=psnr_all(g,:).'; SSIM(rows)=ssim_all(g,:).';
    Entropy(rows)=entropy_all(g,:).'; ENL(rows)=enl_all(g,:).';
end
T = table(Q,GroupName,Range_q,Azimuth_q,GroupType,SampleID,Dataset,File, ...
    CStart,PSNR,SSIM,Entropy,ENL);
end

function T = buildPairedTests(defs, psnr_all, ssim_all, Q_list)
n = numel(Q_list); Q = Q_list(:); BestBidirectional = strings(n,1);
BestUnidirectional = strings(n,1); DeltaPSNR = zeros(n,1); DeltaSSIM = zeros(n,1);
P_PSNR = zeros(n,1); P_SSIM = zeros(n,1);
for idx = 1:n
    q = Q(idx); q_mask = [defs.Q].' == q;
    bi = find(q_mask & [defs.Range_q].'>1 & [defs.Azimuth_q].'>1);
    uni = find(q_mask & ([defs.Range_q].'==1 | [defs.Azimuth_q].'==1));
    [~, ib] = max(mean(psnr_all(bi,:),2)); [~, iu] = max(mean(psnr_all(uni,:),2));
    b = bi(ib); u = uni(iu); BestBidirectional(idx)=defs(b).GroupName;
    BestUnidirectional(idx)=defs(u).GroupName;
    bpsnr=psnr_all(b,:).'; upsnr=psnr_all(u,:).';
    bssim=ssim_all(b,:).'; ussim=ssim_all(u,:).';
    DeltaPSNR(idx)=mean(bpsnr-upsnr); DeltaSSIM(idx)=mean(bssim-ussim);
    P_PSNR(idx)=signrank(bpsnr,upsnr); P_SSIM(idx)=signrank(bssim,ussim);
end
T = table(Q,BestBidirectional,BestUnidirectional,DeltaPSNR,DeltaSSIM,P_PSNR,P_SSIM);
end

function exportROIAudit(cache, is_enl, tops, lefts, window_size, save_path)
indices = find(is_enl); fig=figure("Visible","off","Color","w", ...
    "Position",[50 50 1200 700]); layout=tiledlayout(fig,4,5,"Padding","compact");
for idx = indices.'
    ax=nexttile(layout); imagesc(ax,cache(idx).img_gt,[0 1]); axis(ax,"image","off");
    rectangle(ax,"Position",[lefts(idx),tops(idx),window_size,window_size], ...
        "EdgeColor","r","LineWidth",1); title(ax,sprintf("S%d",idx));
end
exportgraphics(fig,save_path,"Resolution",200); close(fig);
end

function writeMetadata(cfg, sample_count, enl_count, output_dir)
fid=fopen(fullfile(output_dir,"V5_Main_Metadata.txt"),"w");
cleanup=onCleanup(@() fclose(fid));
fprintf(fid,"Seed=%d\nAs=%.16g\nQList=%s\nSampleCount=%d\n", ...
    cfg.seed,cfg.As,mat2str(cfg.Q_list),sample_count);
fprintf(fid,"ENLSampleCount=%d\nENLWindow=%d\nEntropyBins=%d\n", ...
    enl_count,cfg.enl_window_size,cfg.entropy_num_bins);
end
