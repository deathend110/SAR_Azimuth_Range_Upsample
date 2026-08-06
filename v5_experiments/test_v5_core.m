function tests = test_v5_core
% V5共享核心的轻量单元测试，不读取外部SAR数据。
tests = functiontests(localfunctions);
if nargout == 0
    results = runtests(mfilename);
    assert(all([results.Passed]), "V5Core单元测试未全部通过。");
    clear tests;
end
end

function testConfig(test_case)
cfg = V5Core.config();
verifyEqual(test_case, cfg.SNR_dB_list, -2:0.5:12);
verifyEqual(test_case, cfg.noise_repeats, 100);
verifyEqual(test_case, cfg.noise_seed_protocol, "decimal_v2_r100");
verifyEqual(test_case, cfg.table_Q_list, cfg.Q_list);
end

function testOrderedFactorPairs(test_case)
verifyEqual(test_case, V5Core.factorPairs(6), [1 6; 2 3; 3 2; 6 1]);
verifyEqual(test_case, V5Core.factorPairs(10), [1 10; 2 5; 5 2; 10 1]);
end

function testNoiseGroups(test_case)
defs = V5Core.noiseGroupDefinitions();
verifyEqual(test_case, string({defs.GroupName}), ["R4A1", "R1A4", "R2A2"]);
verifyEqual(test_case, [defs.Range_q; defs.Azimuth_q], [4 1 2; 1 4 2]);
end

function testUpsampleDimensions(test_case)
S = complex(randn(12, 10), randn(12, 10));
S_up = V5Core.twoDimUpsample(S, 2, 3);
verifySize(test_case, S_up, [36, 20]);
meta = struct("nrn", 12, "nan", 10);
verifySize(test_case, V5Core.twoDimDownsample(S_up, 2, 3, meta), size(S));
end

function testSplitRTDimensionsAndSigns(test_case)
rng(17);
S = complex(randn(18, 14), randn(18, 14));
U = V5Core.buildSplitRTThreshold(S, 0.6);
verifySize(test_case, U, size(S));
S1 = V5Core.quantizeWithThreshold(S, U);
verifyTrue(test_case, all(ismember(real(S1(:)), [-1, 1])));
verifyTrue(test_case, all(ismember(imag(S1(:)), [-1, 1])));
end

function testGaussianSNRAndZeroMean(test_case)
rng(23);
S = complex(randn(600, 400), randn(600, 400));
[noise, stats] = gaussian(S, 5, false);
verifySize(test_case, noise, size(S));
verifyLessThan(test_case, abs(stats.ActualSNRdB - 5), 0.05);
verifyLessThan(test_case, abs(stats.NoiseMean), 1e-10);
end

function testSharedNoiseIsDeterministic(test_case)
cfg = V5Core.config();
S = complex(randn(40, 30), randn(40, 30));
seed = V5Core.noiseSeed(cfg, 7, 2);
rng(seed); n1 = gaussian(S, 3, false);
rng(seed); n2 = gaussian(S, 3, false);
verifyEqual(test_case, n1, n2);
end

function testSeedMapping(test_case)
cfg = V5Core.config();
noise_seeds = zeros(70, cfg.noise_repeats);
for sample_idx = 1:70
    for repeat_idx = 1:cfg.noise_repeats
        noise_seeds(sample_idx, repeat_idx) = ...
            V5Core.noiseSeed(cfg, sample_idx, repeat_idx);
    end
end
verifyEqual(test_case, numel(unique(noise_seeds)), numel(noise_seeds));

rt_seeds = zeros(numel(cfg.SNR_dB_list), 3, 70, cfg.noise_repeats);
for snr_idx = 1:numel(cfg.SNR_dB_list)
    for group_idx = 1:3
        for sample_idx = 1:70
            for repeat_idx = 1:cfg.noise_repeats
                rt_seeds(snr_idx, group_idx, sample_idx, repeat_idx) = ...
                    V5Core.rtSeed(cfg, snr_idx, group_idx, ...
                    sample_idx, repeat_idx);
            end
        end
    end
end
verifyEqual(test_case, numel(unique(rt_seeds)), numel(rt_seeds));
verifyLessThanOrEqual(test_case,max(rt_seeds(:)),2^32-1);
verifyEqual(test_case, V5Core.noiseSeed(cfg, 7, 2), ...
    V5Core.noiseSeed(cfg, 7, 2));
verifyEqual(test_case, V5Core.rtSeed(cfg, 4, 2, 7, 2), ...
    V5Core.rtSeed(cfg, 4, 2, 7, 2));
end

function testEntropyAndROI(test_case)
verifyEqual(test_case, V5Core.imageEntropy(zeros(8), 256), 0, ...
    "AbsTol", 1e-12);
rng(7); img = 0.5 + 0.1 * randn(96);
img(33:64, 33:64) = 0.4 + 0.001 * randn(32);
[top1, left1, score1] = V5Core.selectUniformROI(img, 32, 8);
[top2, left2, score2] = V5Core.selectUniformROI(img, 32, 8);
verifyEqual(test_case, [top1, left1, score1], [top2, left2, score2]);
end

function testENLFormula(test_case)
intensity = [1, 2; 3, 4];
img = sqrt(intensity);
expected = mean(intensity(:))^2 / var(intensity(:), 0);
verifyEqual(test_case, V5Core.enl(img, 1, 1, 2), expected, ...
    "AbsTol", 1e-12);
verifyEqual(test_case, V5Core.enl(ones(4), 1, 1, 4), Inf);
end

function testSharedENLRegionSelection(test_case)
cfg = V5Core.config();
rng(31);
cache = struct( ...
    "dataset_name", {"SAR_Dataset_filed", "SAR_Dataset_city1_histeq"}, ...
    "img_gt", {rand(96), rand(96)});
manifest = table((1:2).', ["SAR_Dataset_filed"; "SAR_Dataset_city1_histeq"], ...
    'VariableNames', {'SampleID','Dataset'});
[is_enl,tops,lefts,scores,roi_manifest] = ...
    V5Core.buildENLRegions(cache,manifest,cfg);
[top,left,score] = V5Core.selectUniformROI(cache(1).img_gt, ...
    cfg.enl_window_size,cfg.enl_stride);
verifyEqual(test_case,is_enl,[true; false]);
verifyEqual(test_case,[tops(1),lefts(1),scores(1)],[top,left,score]);
verifyEqual(test_case,height(roi_manifest),1);
verifyEqual(test_case,roi_manifest.SampleID,1);
end
