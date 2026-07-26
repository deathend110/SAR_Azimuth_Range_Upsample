function V4_RSFT2DThresholdTransfer()
% V4_RSFT2DThresholdTransfer
%
% 固定2D RSFT阈值迁移实验：
% 1) 从RSFT2DAllocationSearch结果中读取每个分配的最优参数；
% 2) 将来源分配(Source)的最优阈值参数固定；
% 3) 在同预算目标分配(Target)上重新生成目标网格对应阈值；
% 4) 比较固定阈值下不同R×A分配性能。
%
% 不进行任何参数搜索。

clear; clc;

cfg = V4Core.config();
addpath(cfg.repo_root, cfg.experiment_dir);

search_file = fullfile(cfg.output_root, ...
    "RSFT2DAllocationSearch", "RSFT2D_AllData.mat");

assert(isfile(search_file), ...
    "未找到RSFT2D搜索结果：%s", search_file);

loaded = load(search_file);

required = ["group_results", "group_defs", ...
    "sample_manifest", "calibration_indices", "test_indices"];

for k = 1:numel(required)
    assert(isfield(loaded, required(k)), ...
        "搜索结果缺少字段：%s", required(k));
end

S60 = load(cfg.parameter_file);
[sample_cache, manifest_now] = V4Core.buildSampleCache(cfg, S60);

validateManifest(manifest_now, loaded.sample_manifest);

output_dir = fullfile(cfg.output_root, ...
    "RSFT2DThresholdTransfer");

if ~exist(output_dir, "dir")
    mkdir(output_dir);
end

pair_dir = fullfile(output_dir, "PairResults");
if ~exist(pair_dir, "dir")
    mkdir(pair_dir);
end

azimuth_bandwidth_Hz = resolveAzimuthBandwidth(S60);

% 阶段A：双向锚点迁移
transfer_defs = buildAnchorTransferDefinitions(loaded.group_defs, ...
    loaded.group_results);

writetable(transfer_defs, ...
    fullfile(output_dir, "RSFT2D_AnchorDefinitions.csv"));

detail = table();

for idx = 1:height(transfer_defs)

    src = transfer_defs.SourceGroup(idx);
    tgt = transfer_defs.TargetGroup(idx);

    fprintf("\n[%d/%d] %s -> %s\n", ...
        idx, height(transfer_defs), src, tgt);

    result_file = fullfile(pair_dir, ...
        sprintf("%s_to_%s.mat", src, tgt));

    if isfile(result_file)
        temp = load(result_file, "pair_result");
        pair_result = temp.pair_result;
    else
        pair_result = evaluateTransferPair( ...
            transfer_defs(idx,:), ...
            loaded.group_results, ...
            loaded.group_defs, ...
            sample_cache, ...
            loaded.test_indices, ...
            S60, ...
            azimuth_bandwidth_Hz);

        save(result_file, "pair_result", "-v7.3");
    end

    detail = [detail; pair_result.detail_table]; %#ok<AGROW>

end

summary = summarizeTransfer(detail);

writetable(detail, ...
    fullfile(output_dir, "RSFT2D_TransferDetail.csv"));

writetable(summary, ...
    fullfile(output_dir, "RSFT2D_TransferSummary.csv"));

save(fullfile(output_dir, "RSFT2D_ThresholdTransfer.mat"), ...
    "transfer_defs", "detail", "summary", "-v7.3");

fprintf("\n完成：%s\n", output_dir);

end


function defs = buildAnchorTransferDefinitions(group_defs, group_results)

anchors = ["R2A2","R2A3","R2A4","R3A3"];

rows = cell(0,6);

for i = 1:numel(anchors)

    src = anchors(i);

    src_idx = find(strcmp(string({group_defs.GroupName}), src));

    assert(~isempty(src_idx), ...
        "找不到来源组%s", src);

    Q = group_defs(src_idx).Q;

    targets = group_defs( ...
        [group_defs.Q] == Q);

    for j = 1:numel(targets)

        rows = [rows; ...
            {Q, string(src), string(targets(j).GroupName), ...
            group_results{src_idx}.best.STRdB, ...
            group_results{src_idx}.best.FrOverBr, ...
            group_results{src_idx}.best.FaOverBa}]; %#ok<AGROW>

    end

end

defs = cell2table(rows, ...
    'VariableNames', ...
    {'Q','SourceGroup','TargetGroup', ...
    'STRdB','FrOverBr','FaOverBa'});

end


function pair_result = evaluateTransferPair(def, ...
    group_results, group_defs, sample_cache, ...
    test_indices, S60, azimuth_bandwidth_Hz)

target_name = string(def.TargetGroup);

target_idx = find(strcmp(string({group_defs.GroupName}), ...
    target_name));

target = group_defs(target_idx);

num_samples = numel(test_indices);

PSNR = zeros(num_samples,1);
SSIM = zeros(num_samples,1);

for k = 1:num_samples

    sample_idx = test_indices(k);

    signal60 = sample_cache(sample_idx).signal60_input;
    img_gt = sample_cache(sample_idx).img_gt;

    signal_up = V4Core.twoDimUpsample( ...
        signal60, ...
        target.Azimuth_q, ...
        target.Range_q);

    U = buildRSFT2DThreshold( ...
        signal_up, S60, ...
        target.Range_q, ...
        target.Azimuth_q, ...
        def.STRdB, ...
        def.FrOverBr, ...
        def.FaOverBa, ...
        azimuth_bandwidth_Hz);

    one_bit = V4Core.quantizeWithThreshold( ...
        signal_up, U);

    img_out = V4Core.focusUpsampledChannel( ...
        one_bit, S60, ...
        target.Range_q, ...
        target.Azimuth_q);

    PSNR(k) = psnr(img_out,img_gt);
    SSIM(k) = ssim(img_out,img_gt);

end

detail = table( ...
    strings(num_samples,1), ...
    strings(num_samples,1), ...
    zeros(num_samples,1), ...
    PSNR, ...
    SSIM, ...
    'VariableNames', ...
    {'SourceGroup','TargetGroup','Q','PSNR','SSIM'});

detail.SourceGroup(:) = string(def.SourceGroup);
detail.TargetGroup(:) = string(def.TargetGroup);
detail.Q(:) = def.Q;

pair_result.detail_table = detail;

end


function summary = summarizeTransfer(detail)

groups = unique(detail(:, ...
    ["SourceGroup","TargetGroup","Q"]));

PSNR_mean = zeros(height(groups),1);
SSIM_mean = zeros(height(groups),1);

for i = 1:height(groups)

    mask = detail.SourceGroup == groups.SourceGroup(i) & ...
           detail.TargetGroup == groups.TargetGroup(i);

    PSNR_mean(i)=mean(detail.PSNR(mask));
    SSIM_mean(i)=mean(detail.SSIM(mask));

end

summary = [groups table(PSNR_mean,SSIM_mean)];

end


function validateManifest(a,b)

vars = ["SampleID","DatasetIdx", ...
    "LocalSampleIdx","Dataset","File","CStart"];

for i = 1:numel(vars)

    assert(isequal(string(a.(vars(i))), ...
        string(b.(vars(i)))), ...
        "样本清单不一致:%s", vars(i));

end

end


function U = buildRSFT2DThreshold(signal_up,S60,...
    range_q,azimuth_q,...
    STR_dB,fr_over_Br,fa_over_Ba,...
    azimuth_bandwidth_Hz)

[Nr,Na] = size(signal_up);

Fs_up = range_q*S60.Fs;
PRF_up = azimuth_q*S60.prf;

tau = ((0:Nr-1).' - floor(Nr/2))/Fs_up;
eta = ((0:Na-1) - floor(Na/2))/PRF_up;

fr = fr_over_Br*S60.B;
fa = fa_over_Ba*azimuth_bandwidth_Hz;

sigma_hat = sqrt(2/pi)*mean(abs(signal_up(:)));

Au = sigma_hat/(10^(STR_dB/20));

U = Au*exp(1i*(2*pi*fr*tau + ...
    2*pi*fa*eta));

end


function Ba = resolveAzimuthBandwidth(S60)

if isfield(S60,"Ba")
    Ba = S60.Ba;
elseif isfield(S60,"Bd")
    Ba = S60.Bd;
else
    Ba = 2*S60.v/S60.Da;
end

end
