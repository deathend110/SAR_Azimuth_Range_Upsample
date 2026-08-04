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
verifyEqual(test_case, cfg.noise_repeats, 3);
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
verifyNotEqual(test_case, ...
    V5Core.noiseSeed(cfg, 1, 1), V5Core.noiseSeed(cfg, 1, 2));
verifyNotEqual(test_case, ...
    V5Core.rtSeed(cfg, 1, 1, 1, 1), V5Core.rtSeed(cfg, 1, 2, 1, 1));
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
