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
if isfolder(cfg.rsft_calibration_dir)
    verifyTrue(test_case, isfile(cfg.rsft_figure));
end
end

function testRSFTThresholdDefinition(test_case)
rng(11);
signal_up = complex(randn(24, 7), randn(24, 7));
S60 = struct("Fs", 60e6, "B", 45e6);
range_q = 2;
STR_dB = -2;
f0_over_Br = 1.4;
initial_phase = 0;

[U1, sigma_hat, amplitude] = V4Core.buildRSFTThreshold( ...
    signal_up, S60, range_q, STR_dB, f0_over_Br, initial_phase);
U2 = V4Core.buildRSFTThreshold( ...
    signal_up, S60, range_q, STR_dB, f0_over_Br, initial_phase);

verifySize(test_case, U1, size(signal_up));
verifyEqual(test_case, U1, U2);
verifyEqual(test_case, U1, repmat(U1(:, 1), 1, size(U1, 2)));
verifyEqual(test_case, amplitude, ...
    sigma_hat / (10 ^ (STR_dB / 20)), "RelTol", 1e-12);
verifyEqual(test_case, abs(U1), ...
    amplitude * ones(size(U1)), "AbsTol", 1e-10);

expected_step = 2 * pi * (f0_over_Br * S60.B) / ...
    (range_q * S60.Fs);
observed_step = angle(U1(13, 1) / U1(12, 1));
verifyEqual(test_case, observed_step, ...
    angle(exp(1i * expected_step)), "AbsTol", 1e-12);
end

function testUpsampleDimensions(test_case)
S = complex(randn(12, 10), randn(12, 10));
S_up = V4Core.twoDimUpsample(S, 2, 3);
verifySize(test_case, S_up, [36, 20]);
meta = struct("nrn", 12, "nan", 10);
S_down = V4Core.twoDimDownsample(S_up, 2, 3, meta);
verifySize(test_case, S_down, [12, 10]);
end

function testFractionalSplitRTDimensions(test_case)
rng(17);
S = complex(randn(12, 10), randn(12, 10));
meta = struct("nrn", 12, "nan", 10);
p_values = [1.5, sqrt(3), 2.5, sqrt(8)];
expected_p2 = [2.25, 3, 6.25, 8];
axis_meta = struct( ...
    "nrn", 12, "nan", 10, "Fs", 60e6, ...
    "R0", 1000, "C", 3e8, "tnrn", zeros(12, 1));

for idx = 1:numel(p_values)
    p = p_values(idx);
    S_up = V4Core.twoDimUpsample(S, p, p);
    verifySize(test_case, S_up, [round(p * 12), round(p * 10)]);

    U = V4Core.buildSplitRTThreshold(S_up, 0.6);
    verifySize(test_case, U, size(S_up));
    S1 = V4Core.quantizeWithThreshold(S_up, U);
    verifySize(test_case, S1, size(S_up));
    verifyTrue(test_case, ...
        all(ismember(real(S1(:)), [-1, 1])) && ...
        all(ismember(imag(S1(:)), [-1, 1])));

    S_down = V4Core.twoDimDownsample(S_up, p, p, meta);
    verifySize(test_case, S_down, size(S));

    p2 = p ^ 2;
    if abs(p2 - round(p2)) < 1e-12
        p2 = round(p2);
    end
    verifyEqual(test_case, p2, expected_p2(idx), "AbsTol", 1e-12);

    [tnrn_up, Fs_up] = V4Core.rangeAxis( ...
        size(S_up, 1), p, axis_meta);
    verifySize(test_case, tnrn_up, [round(p * 12), 1]);
    verifyEqual(test_case, Fs_up, p * axis_meta.Fs, ...
        "RelTol", 1e-12);
end
end
