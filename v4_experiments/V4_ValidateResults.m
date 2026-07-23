function V4_ValidateResults()
% 自动验收V4结果完整性，并与旧Exp1/Exp2做数值回归。

cfg = V4Core.config();
main_dir = fullfile(cfg.output_root, "MainEvaluation");
mechanism_dir = fullfile(cfg.output_root, "Mechanism");

new_summary_path = fullfile(main_dir, "V4_Main_Summary.csv");
new_detail_path = fullfile(main_dir, "V4_Main_Detail.csv");
table_iii_path = fullfile(main_dir, "V4_TableIII_Metrics.csv");
old_summary_path = fullfile( ...
    cfg.repo_root, "Exp1_MainResult_Output", "Exp1_MainResult_Summary.csv");

required_files = [ ...
    string(new_summary_path), ...
    string(new_detail_path), ...
    string(table_iii_path), ...
    string(fullfile(main_dir, "V4_ENL_ROI_Manifest.csv")), ...
    string(fullfile(main_dir, "V4_ENL_ROI_Audit.png")), ...
    string(fullfile(mechanism_dir, "V4_Mechanism_Metrics.csv")), ...
    string(fullfile(mechanism_dir, "V4_Mechanism_Common4x4.png")), ...
    string(fullfile(mechanism_dir, "V4_Scene_SharedColorbar.png")), ...
    string(cfg.rt_figure), ...
    string(cfg.rsft_figure) ...
];
assert(all(isfile(required_files)), "V4验收所需文件不完整。");

new_summary = readtable(new_summary_path, "TextType", "string");
new_detail = readtable(new_detail_path, "TextType", "string");
table_iii = readtable(table_iii_path, "TextType", "string");
old_summary = readtable(old_summary_path, "TextType", "string");

assert(height(new_summary) == 19, "主结果应包含19个组。");
assert(height(new_detail) == 19 * 70, "逐样本明细行数不正确。");
assert(all(new_summary.SampleCount == 70), "主指标样本数不是70。");
assert(all(new_summary.ENLSampleCount == 20), "ENL样本数不是20。");
assert(all(isfinite(new_summary.PSNR_Mean)), "PSNR存在非有限值。");
assert(all(isfinite(new_summary.SSIM_Mean)), "SSIM存在非有限值。");
assert(all(isfinite(new_summary.Entropy_Mean)), "Entropy存在非有限值。");
assert(all(isfinite(new_summary.ENL_Mean)), "ENL存在非有限值。");
assert(height(table_iii) == 13, "Table III应包含GT、基线和11个分配。");

max_psnr_diff = 0;
max_ssim_diff = 0;
for idx = 1:height(new_summary)
    old_idx = find(old_summary.GroupName == new_summary.GroupName(idx), 1);
    assert(~isempty(old_idx), "旧Exp1中缺少组：%s", new_summary.GroupName(idx));
    max_psnr_diff = max(max_psnr_diff, abs( ...
        new_summary.PSNR_Mean(idx) - old_summary.PSNR_Mean(old_idx)));
    max_ssim_diff = max(max_ssim_diff, abs( ...
        new_summary.SSIM_Mean(idx) - old_summary.SSIM_Mean(old_idx)));
end
assert(max_psnr_diff < 1e-5, "V4 PSNR未通过Exp1回归检查。");
assert(max_ssim_diff < 1e-6, "V4 SSIM未通过Exp1回归检查。");

new_mechanism = readtable( ...
    fullfile(mechanism_dir, "V4_Mechanism_Metrics.csv"), ...
    "TextType", "string");
old_mechanism = readtable(fullfile( ...
    cfg.repo_root, "Exp2_Mechanism_Output", ...
    "Exp2_Mechanism_Metrics.csv"), "TextType", "string");
old_node2 = old_mechanism(old_mechanism.node_name == "node2_rc", :);
old_node2.case_name(old_node2.case_name == "R1A1_NoUp") = "R1A1";

for idx = 1:height(new_mechanism)
    old_idx = find(old_node2.case_name == new_mechanism.Allocation(idx), 1);
    assert(~isempty(old_idx), ...
        "旧Exp2中缺少机制组：%s", new_mechanism.Allocation(idx));
    assert(abs(new_mechanism.OffSupport(idx) - ...
        old_node2.off_support_ratio(old_idx)) < 1e-6);
    assert(abs(new_mechanism.RangeLeakage(idx) - ...
        old_node2.range_leakage_ratio(old_idx)) < 1e-6);
    assert(abs(new_mechanism.AzimuthLeakage(idx) - ...
        old_node2.azimuth_leakage_ratio(old_idx)) < 1e-6);
end

fprintf("V4结果验收通过。\n");
fprintf("  主结果组数：%d\n", height(new_summary));
fprintf("  逐样本行数：%d\n", height(new_detail));
fprintf("  Max |dPSNR|：%.3g dB\n", max_psnr_diff);
fprintf("  Max |dSSIM|：%.3g\n", max_ssim_diff);
fprintf("  ENL样本数：%d\n", new_summary.ENLSampleCount(1));
end
