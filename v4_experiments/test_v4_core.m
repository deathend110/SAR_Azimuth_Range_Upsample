function tests = test_v4_core
% V4共享核心的轻量单元测试。
tests = functiontests(localfunctions);
if nargout == 0
    results = runtests(mfilename);
    assert(all([results.Passed]), "V4Core单元测试未全部通过。");
    clear tests;
end
end

function testOrderedFactorPairs(test_case)
verifyEqual(test_case, V4Core.factorPairs(6), [1 6; 2 3; 3 2; 6 1]);
verifyEqual(test_case, V4Core.factorPairs(8), [1 8; 2 4; 4 2; 8 1]);
end

function testEntropy(test_case)
verifyEqual(test_case, V4Core.imageEntropy(zeros(8), 256), 0, ...
    "AbsTol", 1e-12);
img = [zeros(8, 4), ones(8, 4)];
verifyEqual(test_case, V4Core.imageEntropy(img, 256), 1, ...
    "AbsTol", 1e-12);
end

function testUniformROIIsDeterministic(test_case)
rng(7);
img = 0.5 + 0.1 * randn(128);
img(33:96, 33:96) = 0.4 + 0.001 * randn(64);
[top1, left1, score1] = V4Core.selectUniformROI(img, 32, 8);
[top2, left2, score2] = V4Core.selectUniformROI(img, 32, 8);
verifyEqual(test_case, [top1, left1, score1], [top2, left2, score2]);
end

function testRSFTSourceFiguresExist(test_case)
cfg = V4Core.config();
verifyTrue(test_case, isfile(cfg.rt_figure));
verifyTrue(test_case, isfile(cfg.rsft_figure));
end

function testUpsampleDimensions(test_case)
S = complex(randn(12, 10), randn(12, 10));
S_up = V4Core.twoDimUpsample(S, 2, 3);
verifySize(test_case, S_up, [36, 20]);
meta = struct("nrn", 12, "nan", 10);
S_down = V4Core.twoDimDownsample(S_up, 2, 3, meta);
verifySize(test_case, S_down, [12, 10]);
end
