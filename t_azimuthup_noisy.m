clear;clc;close all;

%% 单次Ax上采样噪声实验代码，验证方位向的噪声上采样成像策略
%% ==================== 参数加载 ====================
S60 = load("FS60_params.mat");
seed = 42;
rng(seed);

Azimuth_q_m     = 2;       % 与R2A2实验保持一致的方位向倍率
Range_q_m       = 2;       % 与R2A2实验保持一致的距离向倍率
q               = Azimuth_q_m * Range_q_m;
Azimuth_q       = q;       % R1A4：全部预算用于方位向上采样
As_rt           = 0.6;     % RT阈值系数
SNR_dB          = 2.59;    % 1-bit量化前原始复回波的高斯噪声信噪比

%% 加载回波数据和成像参数
data_figure = "SAR_Dataset_city2_histeq";
data_folder = replace("G:\MATLAB-G\SAR Full PSF\temp\", "temp", data_figure);
data_name = "rstart 301.mat";
data = load(data_folder + data_name).channel_1;
c_start = 6500;
channel_1 = data(:, c_start:c_start + S60.nrn - 1);
signal60_input = channel_1(1:3:end, :);

%% GT
RC_gt   = Range_Compress(signal60_input, S60.fc, S60.tnrn, S60.gama, S60.R0, S60.C, S60.Fs, S60.Tp);
RCMC_gt = RCMC(RC_gt, S60.lambda, S60.fnrn, S60.fnan, S60.R0, S60.C, S60.v);
IMG_gt  = SAR_Imaging(RCMC_gt, S60.lambda, S60.Fs, S60.R0, S60.C, S60.v, S60.tnan, S60.Ta, S60.prf);
roi_gt = abs(IMG_gt(S60.nrn/2-S60.R_total/2+1:S60.nrn/2+S60.R_total/2, ...
    S60.nan/2-S60.A_num/2:S60.nan/2+S60.A_num/2-1));
img_gt = normalize_image(roi_gt);
subplot(221);imagesc(img_gt);axis image;colorbar;title("GT As: " + num2str(As_rt));

%% Azimuth Upsample
% 方位向上采样，并在上采样后的信号上生成方位向RT阈值
signal60_patch_high = azimuth_upsample_fft(signal60_input, Azimuth_q);
[U_master_patch, ~, ~] = Azimuth_Build_RT(signal60_patch_high, As_rt);

% RT阈值1-bit量化
channel_1bit_high = quantize_1bit_with_U(signal60_patch_high, U_master_patch);

% 距离向未上采样，因此距离压缩仍使用原始快时间参数
RC_high = Range_Compress(channel_1bit_high, S60.fc, S60.tnrn, S60.gama, S60.R0, S60.C, S60.Fs, S60.Tp);

% 与BRAU/V4主实验保持一致：RC后先裁剪回原方位宽度，再继续RCMC
RC_crop = crop_azimuth_doppler_to_width(RC_high, S60.nan);
RCMC_crop = RCMC(RC_crop, S60.lambda, S60.fnrn, S60.fnan, S60.R0, S60.C, S60.v);

IMG_high = SAR_Imaging(RCMC_crop, S60.lambda, S60.Fs, S60.R0, S60.C, S60.v, S60.tnan, S60.Ta, S60.prf);
roi_crop = abs(IMG_high(S60.nrn/2-S60.R_total/2+1:S60.nrn/2+S60.R_total/2, ...
    S60.nan/2-S60.A_num/2:S60.nan/2+S60.A_num/2-1));
Azimuth_Upsample = normalize_image(roi_crop);

Azimuth_title = [
    "Azimuth Upsample q" + num2str(Azimuth_q) + " 1bit";
    "SSIM: " + num2str(ssim(Azimuth_Upsample, img_gt)) + ...
    "   PSNR: " + num2str(psnr(Azimuth_Upsample, img_gt))
];
subplot(223);imagesc(Azimuth_Upsample);axis image;colorbar;title(Azimuth_title);

%% Azimuth Upsample noisy
% 同一份带噪回波同时用于1-bit成像和带噪GT成像
noisy = gaussian(signal60_input, SNR_dB);
signal60_input_noisy = signal60_input + noisy;

% 先加噪、再上采样，并在带噪上采样信号上重新计算RT阈值
signal60_patch_high_noisy = azimuth_upsample_fft(signal60_input_noisy, Azimuth_q);
[U_master_patch, ~, ~] = Azimuth_Build_RT(signal60_patch_high_noisy, As_rt);

channel_1bit_high = quantize_1bit_with_U(signal60_patch_high_noisy, U_master_patch);
RC_high = Range_Compress(channel_1bit_high, S60.fc, S60.tnrn, S60.gama, S60.R0, S60.C, S60.Fs, S60.Tp);
RC_crop = crop_azimuth_doppler_to_width(RC_high, S60.nan);
RCMC_crop = RCMC(RC_crop, S60.lambda, S60.fnrn, S60.fnan, S60.R0, S60.C, S60.v);

IMG_high = SAR_Imaging(RCMC_crop, S60.lambda, S60.Fs, S60.R0, S60.C, S60.v, S60.tnan, S60.Ta, S60.prf);
roi_crop = abs(IMG_high(S60.nrn/2-S60.R_total/2+1:S60.nrn/2+S60.R_total/2, ...
    S60.nan/2-S60.A_num/2:S60.nan/2+S60.A_num/2-1));
Azimuth_Upsample_noisy = normalize_image(roi_crop);

%% GT noisy
RC_gt = Range_Compress(signal60_input_noisy, S60.fc, S60.tnrn, S60.gama, S60.R0, S60.C, S60.Fs, S60.Tp);
RCMC_gt = RCMC(RC_gt, S60.lambda, S60.fnrn, S60.fnan, S60.R0, S60.C, S60.v);
IMG_gt = SAR_Imaging(RCMC_gt, S60.lambda, S60.Fs, S60.R0, S60.C, S60.v, S60.tnan, S60.Ta, S60.prf);
roi_gt = abs(IMG_gt(S60.nrn/2-S60.R_total/2+1:S60.nrn/2+S60.R_total/2, ...
    S60.nan/2-S60.A_num/2:S60.nan/2+S60.A_num/2-1));
img_gt_noisy = normalize_image(roi_gt);

subplot(222);imagesc(img_gt_noisy);axis image;colorbar;title("GT noisy As: " + num2str(As_rt));

Azimuth_title = [
    "Azimuth Upsample noisy q" + num2str(Azimuth_q) + " 1bit";
    "SSIM: " + num2str(ssim(Azimuth_Upsample_noisy, img_gt_noisy)) + ...
    "   PSNR: " + num2str(psnr(Azimuth_Upsample_noisy, img_gt_noisy))
];
subplot(224);imagesc(Azimuth_Upsample_noisy);axis image;colorbar;title(Azimuth_title);

%% =========================================================
%% =================== assistant function ==================
%% =========================================================
% 根据已经完成方位上采样的信号生成方位向全局RT阈值
function [U, sigma, A_rt] = Azimuth_Build_RT(signal_up, As)
    sigma = sqrt(2 / pi) * mean(abs(signal_up(:)));
    A_rt = As * sigma;

    phi = 2 * pi * rand(1, size(signal_up, 2));
    U = A_rt * exp(1i * phi);
end

% 附带RT阈值的1-bit量化
function S1 = quantize_1bit_with_U(S, U)
    re = ones(size(S), 'like', real(S));
    im = ones(size(S), 'like', real(S));

    re(real(S) + real(U) < 0) = -1;
    im(imag(S) + imag(U) < 0) = -1;

    S1 = complex(re, im);
end

% 方位向FFT零填充上采样
function S_up = azimuth_upsample_fft(S, q)
    [Nr, Na] = size(S);
    Na_up = q * Na;

    Sf = fftshift(fft(S, [], 2), 2);

    pad_total = Na_up - Na;
    pad_left = floor(pad_total / 2);
    pad_right = pad_total - pad_left;

    Sf_up = [zeros(Nr, pad_left, 'like', Sf), ...
             Sf, ...
             zeros(Nr, pad_right, 'like', Sf)];

    S_up = ifft(ifftshift(Sf_up, 2), [], 2) * q;
end

% 方位多普勒域裁剪到原始宽度
function X_crop = crop_azimuth_doppler_to_width(X, target_width)
    [~, Na_up] = size(X);
    if target_width > Na_up
        error('target_width cannot be larger than current width.');
    end

    Xf = fftshift(fft(X, [], 2), 2);

    c = floor(Na_up / 2) + 1;
    h = floor(target_width / 2);

    if mod(target_width, 2) == 0
        idx = (c-h):(c+h-1);
    else
        idx = (c-h):(c+h);
    end

    Xf_crop = Xf(:, idx);
    X_crop = ifft(ifftshift(Xf_crop, 2), [], 2);
end
