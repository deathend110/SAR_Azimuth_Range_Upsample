clear; close all;

%% ==================== 用户参数 ====================
% 距离向上采样
q_list = 2:5;              % q=1到q=10
% q_list = [2, 2.3, 2.7, 3, 3.4, 3.8, 4, 4.2, 4.6];
num_A = 11;                 % NCT 幅度扫描点数（分位数）
p_min = 5;
p_max = 95;

num_k = 11;                 % RT 幅度扫描点数（sigma_ref倍数）
k_min = 0.1;
k_max = 1.5;
n_repeat_rt = 5;            % RT 每个A重复次数，取均值更稳
rng_seed = 20260414;

show_best_images = true;    % 是否展示每个方法全局最佳图像

%% ==================== 读取基础数据 ====================
load("Generate_SAR.mat");

% load("FS60_params.mat");
% data_figure = "SAR_Dataset_city2_histeq";
% data_root = "G:\MATLAB-G\SAR Full PSF";
% data_folder = fullfile(data_root, data_figure);
% data_name = "rstart 2401.mat";
% data_path = fullfile(data_folder, data_name);
% data = load(data_path).channel_1;
% c_start = 2200;
% channel_1 = data(:, c_start:c_start+nrn-1);
% channel_1 = channel_1(1:3:end, :);

%% ==================== Accurate 参考图 ====================
RC_acc   = Range_Compress(channel_1, fc, tnrn, gama, R0, C, Fs, Tp);
RCMC_acc = RCMC(RC_acc, lambda, fnrn, fnan, R0, C, v);
IMG_acc  = SAR_Imaging(RCMC_acc, lambda, Fs, R0, C, v, tnan, Ta, prf);

roi_acc = abs(IMG_acc(nrn/2-R_total/2+1:nrn/2+R_total/2, ...
                      nan/2-A_num/2:nan/2+A_num/2-1));
roi_acc = roi_acc / max(roi_acc(:) + eps);

%% ==================== 结果缓存 ====================
ssim_zt  = zeros(size(q_list));
ssim_nct = zeros(size(q_list));
ssim_rt  = zeros(size(q_list));

psnr_zt  = zeros(size(q_list));
psnr_nct = zeros(size(q_list));
psnr_rt  = zeros(size(q_list));

best_nct_A = zeros(size(q_list));
best_nct_p = zeros(size(q_list));

best_rt_A = zeros(size(q_list));
best_rt_k = zeros(size(q_list));

best_img_zt_all  = [];
best_img_nct_all = [];
best_img_rt_all  = [];
best_ssim_zt_all  = -inf;
best_ssim_nct_all = -inf;
best_ssim_rt_all  = -inf;

fprintf('开始 q 扫描：q = %s\n', mat2str(q_list));

%% ==================== 主循环：q = 1 ... 10 ====================
for iq = 1:numel(q_list)
    q = q_list(iq);
    fprintf('\n================ q = %d ================\n', q);

    %% ---------- 1) 改为距离向上采样 ----------
    channel_up = range_upsample_fft(channel_1, q);   % (q*nrn) x nan

    nrn_up = size(channel_up, 1);
    Fs_up  = q * Fs;

    Tnrn_up   = 1 / Fs_up;
    Tstart_up = 2 * R0 / C - nrn_up / 2 / Fs_up;
    Tend_up   = 2 * R0 / C + (nrn_up / 2 - 1) / Fs_up;
    tnrn_up   = (Tstart_up : Tnrn_up : Tend_up).';
    fnrn_up   = ((-nrn_up/2 : nrn_up/2-1).' * Fs_up / nrn_up);

    %% ---------- 2) ZT ----------
    channel_zt_1bit = quantize_1bit_zero(channel_up);

    RC_zt_up   = Range_Compress(channel_zt_1bit, fc, tnrn_up, gama, R0, C, Fs_up, Tp);
    RCMC_zt_up = RCMC(RC_zt_up, lambda, fnrn_up, fnan, R0, C, v);
    RCMC_zt_crop = crop_range_frequency_to_height(RCMC_zt_up, nrn);

    IMG_zt = SAR_Imaging(RCMC_zt_crop, lambda, Fs, R0, C, v, tnan, Ta, prf);

    roi_zt = abs(IMG_zt(nrn/2-R_total/2+1:nrn/2+R_total/2, ...
                        nan/2-A_num/2:nan/2+A_num/2-1));
    roi_zt = roi_zt / max(roi_zt(:) + eps);

    ssim_zt(iq) = ssim(roi_zt, roi_acc);
    psnr_zt(iq) = psnr(roi_zt, roi_acc);
    fprintf('ZT  : SSIM = %.6f, PSNR = %.6f dB\n', ssim_zt(iq), psnr_zt(iq));

    if ssim_zt(iq) > best_ssim_zt_all
        best_ssim_zt_all = ssim_zt(iq);
        best_img_zt_all = roi_zt;
    end

    %% ---------- 3) NCT：分位数搜索 ----------
    ref_mag = abs(channel_up(:));
    p_list = linspace(p_min, p_max, num_A);
    A_list_nct = prctile(ref_mag, p_list);

    [A_list_nct, uniq_idx] = unique(double(A_list_nct(:).'), 'stable');
    p_list = p_list(uniq_idx);

    best_ssim_nct_q = -inf;
    best_psnr_nct_q = -inf;
    best_A_nct_q = A_list_nct(1);
    best_p_nct_q = p_list(1);
    best_img_nct_q = [];

    for iA = 1:numel(A_list_nct)
        A_nct = A_list_nct(iA);

        channel_nct_1bit = quantize_1bit_nct(channel_up, A_nct, 0);

        RC_nct_up   = Range_Compress(channel_nct_1bit, fc, tnrn_up, gama, R0, C, Fs_up, Tp);
        RCMC_nct_up = RCMC(RC_nct_up, lambda, fnrn_up, fnan, R0, C, v);
        RCMC_nct_crop = crop_range_frequency_to_height(RCMC_nct_up, nrn);

        IMG_nct = SAR_Imaging(RCMC_nct_crop, lambda, Fs, R0, C, v, tnan, Ta, prf);

        roi_nct = abs(IMG_nct(nrn/2-R_total/2+1:nrn/2+R_total/2, ...
                              nan/2-A_num/2:nan/2+A_num/2-1));
        roi_nct = roi_nct / max(roi_nct(:) + eps);

        cur_ssim = ssim(roi_nct, roi_acc);
        cur_psnr = psnr(roi_nct, roi_acc);

        if cur_ssim > best_ssim_nct_q
            best_ssim_nct_q = cur_ssim;
            best_psnr_nct_q = cur_psnr;
            best_A_nct_q = A_nct;
            best_p_nct_q = p_list(iA);
            best_img_nct_q = roi_nct;
        end
    end

    ssim_nct(iq) = best_ssim_nct_q;
    psnr_nct(iq) = best_psnr_nct_q;
    best_nct_A(iq) = best_A_nct_q;
    best_nct_p(iq) = best_p_nct_q;

    fprintf('NCT : best SSIM = %.6f, best PSNR = %.6f dB, percentile = %.2f%%, A = %.6g\n', ...
        ssim_nct(iq), psnr_nct(iq), best_nct_p(iq), best_nct_A(iq));

    if ssim_nct(iq) > best_ssim_nct_all
        best_ssim_nct_all = ssim_nct(iq);
        best_img_nct_all = best_img_nct_q;
    end

    %% ---------- 4) RT：随机相位，幅度搜索 ----------
    sigma_ref = sqrt(2/pi) * mean(abs(channel_up(:)));
    k_scan = linspace(k_min, k_max, num_k);
    A_list_rt = k_scan * sigma_ref;

    best_ssim_rt_q = -inf;
    best_psnr_rt_q = -inf;
    best_A_rt_q = A_list_rt(1);
    best_k_rt_q = k_scan(1);
    best_img_rt_q = [];

    for iK = 1:numel(A_list_rt)
        A_rt = A_list_rt(iK);

        ssim_rep = zeros(1, n_repeat_rt);
        psnr_rep = zeros(1, n_repeat_rt);

        for r = 1:n_repeat_rt
            rng(rng_seed + iq*1000 + iK*100 + r);

            channel_rt_1bit = quantize_1bit_rt_random_phase(channel_up, A_rt);

            RC_rt_up   = Range_Compress(channel_rt_1bit, fc, tnrn_up, gama, R0, C, Fs_up, Tp);
            RCMC_rt_up = RCMC(RC_rt_up, lambda, fnrn_up, fnan, R0, C, v);
            RCMC_rt_crop = crop_range_frequency_to_height(RCMC_rt_up, nrn);

            IMG_rt = SAR_Imaging(RCMC_rt_crop, lambda, Fs, R0, C, v, tnan, Ta, prf);

            roi_rt = abs(IMG_rt(nrn/2-R_total/2+1:nrn/2+R_total/2, ...
                                nan/2-A_num/2:nan/2+A_num/2-1));
            roi_rt = roi_rt / max(roi_rt(:) + eps);

            if r == 1
                roi_rt_rep = roi_rt;
            end

            ssim_rep(r) = ssim(roi_rt, roi_acc);
            psnr_rep(r) = psnr(roi_rt, roi_acc);
        end

        cur_ssim_mean = mean(ssim_rep);
        cur_psnr_mean = mean(psnr_rep);

        if cur_ssim_mean > best_ssim_rt_q
            best_ssim_rt_q = cur_ssim_mean;
            best_psnr_rt_q = cur_psnr_mean;
            best_A_rt_q = A_rt;
            best_k_rt_q = k_scan(iK);
            best_img_rt_q = roi_rt_rep;
        end
    end

    ssim_rt(iq) = best_ssim_rt_q;
    psnr_rt(iq) = best_psnr_rt_q;
    best_rt_A(iq) = best_A_rt_q;
    best_rt_k(iq) = best_k_rt_q;

    fprintf('RT  : best mean SSIM = %.6f, best mean PSNR = %.6f dB, k = %.4f, A = %.6g\n', ...
        ssim_rt(iq), psnr_rt(iq), best_rt_k(iq), best_rt_A(iq));

    if ssim_rt(iq) > best_ssim_rt_all
        best_ssim_rt_all = ssim_rt(iq);
        best_img_rt_all = best_img_rt_q;
    end
end

%% ==================== SSIM 曲线图 ====================
figure('Color','w','Position',[120,120,1000,560]);
plot(q_list, ssim_zt,  '-o', 'LineWidth',1.8, 'MarkerSize',6); hold on;
plot(q_list, ssim_nct, '-s', 'LineWidth',1.8, 'MarkerSize',6);
plot(q_list, ssim_rt,  '-d', 'LineWidth',1.8, 'MarkerSize',6);
grid on;
xlabel('q');
ylabel('SSIM');
ylim([0.5 1.0]);
title('SSIM vs q for ZT / NCT / RT (range upsampling + range crop)');
legend('ZT','NCT(best per q)','RT(best per q)','Location','best');

% ---- 标注 NCT 每个点：最优分位数 ----
for i = 1:numel(q_list)
    text(q_list(i), ssim_nct(i) + 0.008, ...
        sprintf('%.1f%%', best_nct_p(i)), ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'bottom', ...
        'FontSize', 8);
end

% ---- 标注 RT 每个点：用了多少倍的 As ----
for i = 1:numel(q_list)
    text(q_list(i), ssim_rt(i) - 0.010, ...
        sprintf('%.2fAs', best_rt_k(i)), ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'top', ...
        'FontSize', 8);
end

%% ==================== PSNR 曲线图 ====================
figure('Color','w','Position',[140,140,1000,560]);
plot(q_list, psnr_zt,  '-o', 'LineWidth',1.8, 'MarkerSize',6); hold on;
plot(q_list, psnr_nct, '-s', 'LineWidth',1.8, 'MarkerSize',6);
plot(q_list, psnr_rt,  '-d', 'LineWidth',1.8, 'MarkerSize',6);
grid on;
xlabel('q');
ylabel('PSNR (dB)');
title('PSNR vs q for ZT / NCT / RT (range upsampling + range crop)');
legend('ZT','NCT(best per q)','RT(best per q)','Location','best');

% ---- 标注 NCT 每个点：最优分位数 ----
for i = 1:numel(q_list)
    text(q_list(i), psnr_nct(i) + 0.25, ...
        sprintf('%.1f%%', best_nct_p(i)), ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'bottom', ...
        'FontSize', 8);
end

% ---- 标注 RT 每个点：用了多少倍的 As ----
for i = 1:numel(q_list)
    text(q_list(i), psnr_rt(i) - 0.35, ...
        sprintf('%.2fAs', best_rt_k(i)), ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'top', ...
        'FontSize', 8);
end

%% ==================== 可选：显示全局最佳图像 ====================
if show_best_images
    figure('Color','w','Position',[140,140,1400,320]);
    tiledlayout(1,4,'Padding','compact','TileSpacing','compact');

    nexttile;
    imagesc(roi_acc); axis image off; colormap(gray);
    title('Accurate');

    nexttile;
    imagesc(best_img_zt_all); axis image off; colormap(gray);
    title(sprintf('Best ZT\nSSIM=%.4f', best_ssim_zt_all));

    nexttile;
    imagesc(best_img_nct_all); axis image off; colormap(gray);
    title(sprintf('Best NCT\nSSIM=%.4f', best_ssim_nct_all));

    nexttile;
    imagesc(best_img_rt_all); axis image off; colormap(gray);
    title(sprintf('Best RT\nSSIM=%.4f', best_ssim_rt_all));
end

%% ==================== 保存 ====================
save('q_sweep_range_up_zt_nct_rt.mat', ...
    'q_list', ...
    'ssim_zt', 'ssim_nct', 'ssim_rt', ...
    'psnr_zt', 'psnr_nct', 'psnr_rt', ...
    'best_nct_A', 'best_nct_p', ...
    'best_rt_A', 'best_rt_k');

%% ==================== 辅助函数 ====================

function S_up = range_upsample_fft(S, q)
    [Nr, Na] = size(S);
    Nr_up = q * Nr;

    Sf = fftshift(fft(S, [], 1), 1);

    pad_total = Nr_up - Nr;
    pad_top    = floor(pad_total / 2);
    pad_bottom = pad_total - pad_top;

    Sf_up = [zeros(pad_top, Na, 'like', Sf); ...
             Sf; ...
             zeros(pad_bottom, Na, 'like', Sf)];

    S_up = ifft(ifftshift(Sf_up, 1), [], 1) * q;
end

function X_crop = crop_range_frequency_to_height(X, target_height)
    [Nr_up, ~] = size(X);
    if target_height > Nr_up
        error('target_height cannot be larger than current height.');
    end

    Xf = fftshift(fft(X, [], 1), 1);

    c = floor(Nr_up/2) + 1;
    h = floor(target_height/2);

    if mod(target_height, 2) == 0
        idx = (c-h):(c+h-1);
    else
        idx = (c-h):(c+h);
    end

    Xf_crop = Xf(idx, :);
    X_crop = ifft(ifftshift(Xf_crop, 1), [], 1);
end

function S1 = quantize_1bit_zero(S)
    re = ones(size(S), 'like', real(S));
    im = ones(size(S), 'like', real(S));

    re(real(S) < 0) = -1;
    im(imag(S) < 0) = -1;

    S1 = complex(re, im);
end

function S1 = quantize_1bit_nct(S, A, psi)
    u = A * exp(1i * psi);
    ur = real(u);
    ui = imag(u);

    re = ones(size(S), 'like', real(S));
    im = ones(size(S), 'like', real(S));

    re(real(S) + ur < 0) = -1;
    im(imag(S) + ui < 0) = -1;

    S1 = complex(re, im);
end

function S1 = quantize_1bit_rt_random_phase(S, A)
    [nrn, nan] = size(S);

    phi = 2*pi*rand(nrn, 1);
    u = A * exp(1i * phi);
    U = repmat(u, 1, nan);

    re = ones(size(S), 'like', real(S));
    im = ones(size(S), 'like', real(S));

    re(real(S) + real(U) < 0) = -1;
    im(imag(S) + imag(U) < 0) = -1;

    S1 = complex(re, im);
end