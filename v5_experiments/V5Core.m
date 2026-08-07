classdef V5Core
    % V5 RT-only实验共享核心：统一样本、成像链、指标和随机协议。

    methods (Static)
        function cfg = config()
            experiment_dir = fileparts(mfilename("fullpath"));
            repo_root = fileparts(experiment_dir);
            cfg = struct();
            cfg.repo_root = repo_root;
            cfg.experiment_dir = experiment_dir;
            cfg.output_root = fullfile(repo_root, "V5_Experiments_Output");
            cfg.data_root = "G:\MATLAB-G\SAR Full PSF";
            cfg.parameter_file = fullfile(repo_root, "FS60_params.mat");
            cfg.seed = 2026;
            cfg.noise_seed = 20260804;
            cfg.noise_seed_protocol = "decimal_v2_r50";
            cfg.As = 0.6;
            cfg.Q_list = [4, 6, 8, 9, 10];
            cfg.table_Q_list = cfg.Q_list;
            cfg.As_list = 0:0.1:1.5;
            cfg.SNR_dB_list = -2:0.5:12;
            cfg.noise_repeats = 50;
            % 以下参数只控制V5噪声实验的CPU执行方式，不属于实验变量。
            cfg.noise_num_workers = 4;
            cfg.noise_quant_block_cols = 256;
            cfg.noise_compute_version = "fastcpu_v1";
            cfg.num_samples_per_dataset = 10;
            cfg.dataset_names = { ...
                "SAR_Dataset_Bangkok_1", ...
                "SAR_Dataset_city1_histeq", ...
                "SAR_Dataset_city2_histeq", ...
                "SAR_Dataset_SAR_figure", ...
                "SAR_Dataset_filed", ...
                "SAR_Dataset_port", ...
                "SAR_Dataset_suburb"};
            cfg.enl_dataset_names = ["SAR_Dataset_filed", "SAR_Dataset_port"];
            cfg.enl_window_size = 64;
            cfg.enl_stride = 16;
            cfg.entropy_num_bins = 256;
        end

        function ensureDir(path_value)
            if ~exist(path_value, "dir")
                [ok, msg] = mkdir(path_value);
                if ~ok
                    error("无法创建目录 %s：%s", path_value, msg);
                end
            end
        end

        function [sample_cache, sample_manifest] = buildSampleCache(cfg, S60)
            total_samples = numel(cfg.dataset_names) * cfg.num_samples_per_dataset;
            sample_cache = repmat(struct( ...
                "sample_id", 0, "dataset_idx", 0, "sample_idx", 0, ...
                "dataset_name", "", "filename", "", "filepath", "", ...
                "c_start", 0, "signal60_input", [], "img_gt", []), ...
                total_samples, 1);
            fprintf("=== V5统一样本清单：%d个样本 ===\n", total_samples);
            sample_id = 0;
            for ds_idx = 1:numel(cfg.dataset_names)
                ds_name = cfg.dataset_names{ds_idx};
                mat_files = dir(fullfile(cfg.data_root, ds_name, "rstart*.mat"));
                mat_names = sort({mat_files.name});
                if isempty(mat_names)
                    error("数据集 %s 中未找到 rstart*.mat。", ds_name);
                end
                pick_idx = mod(cfg.seed, numel(mat_names)) + 1;
                picked_name = mat_names{pick_idx};
                mat_path = fullfile(cfg.data_root, ds_name, picked_name);
                loaded = load(mat_path);
                names = fieldnames(loaded);
                raw = loaded.(names{1});
                starts = V5Core.stratifiedStarts( ...
                    size(raw, 2), S60.nrn, cfg.num_samples_per_dataset);
                for local_idx = 1:cfg.num_samples_per_dataset
                    sample_id = sample_id + 1;
                    c_start = starts(local_idx);
                    block = raw(:, c_start:c_start + S60.nrn - 1);
                    signal60 = block(1:3:end, :);
                    assert(isequal(size(signal60), [S60.nrn, S60.nan]), ...
                        "样本尺寸与FS60参数不一致。");
                    sample_cache(sample_id).sample_id = sample_id;
                    sample_cache(sample_id).dataset_idx = ds_idx;
                    sample_cache(sample_id).sample_idx = local_idx;
                    sample_cache(sample_id).dataset_name = string(ds_name);
                    sample_cache(sample_id).filename = string(picked_name);
                    sample_cache(sample_id).filepath = string(mat_path);
                    sample_cache(sample_id).c_start = c_start;
                    sample_cache(sample_id).signal60_input = signal60;
                    sample_cache(sample_id).img_gt = V5Core.buildGTImage(signal60, S60);
                end
                clear raw loaded;
            end
            sample_manifest = table( ...
                [sample_cache.sample_id].', [sample_cache.dataset_idx].', ...
                [sample_cache.sample_idx].', string({sample_cache.dataset_name}).', ...
                string({sample_cache.filename}).', [sample_cache.c_start].', ...
                'VariableNames', {'SampleID', 'DatasetIdx', 'LocalSampleIdx', ...
                'Dataset', 'File', 'CStart'});
        end

        function [sample_cache, sample_manifest] = buildNoiseSampleCache(cfg, S60)
            % 构建噪声实验的轻量样本缓存，仅保留GT ROI而不常驻完整复回波。
            total_samples = numel(cfg.dataset_names) * cfg.num_samples_per_dataset;
            sample_cache = repmat(struct( ...
                "sample_id", 0, "dataset_idx", 0, "sample_idx", 0, ...
                "dataset_name", "", "filename", "", "filepath", "", ...
                "c_start", 0, "signal60_input", [], "img_gt", [], ...
                "complex_gt_roi", []), total_samples, 1);
            fprintf("=== V5噪声实验轻量样本清单：%d个样本 ===\n", total_samples);
            sample_id = 0;
            for ds_idx = 1:numel(cfg.dataset_names)
                ds_name = cfg.dataset_names{ds_idx};
                mat_files = dir(fullfile(cfg.data_root, ds_name, "rstart*.mat"));
                mat_names = sort({mat_files.name});
                if isempty(mat_names)
                    error("数据集 %s 中未找到 rstart*.mat。", ds_name);
                end
                pick_idx = mod(cfg.seed, numel(mat_names)) + 1;
                picked_name = mat_names{pick_idx};
                mat_path = fullfile(cfg.data_root, ds_name, picked_name);
                loaded = load(mat_path);
                names = fieldnames(loaded);
                raw = loaded.(names{1});
                starts = V5Core.stratifiedStarts( ...
                    size(raw, 2), S60.nrn, cfg.num_samples_per_dataset);
                for local_idx = 1:cfg.num_samples_per_dataset
                    sample_id = sample_id + 1;
                    c_start = starts(local_idx);
                    block = raw(:, c_start:c_start + S60.nrn - 1);
                    signal60 = block(1:3:end, :);
                    assert(isequal(size(signal60), [S60.nrn, S60.nan]), ...
                        "样本尺寸与FS60参数不一致。");
                    complex_gt_roi = V5Core.buildGTComplexROI(signal60, S60);
                    sample_cache(sample_id).sample_id = sample_id;
                    sample_cache(sample_id).dataset_idx = ds_idx;
                    sample_cache(sample_id).sample_idx = local_idx;
                    sample_cache(sample_id).dataset_name = string(ds_name);
                    sample_cache(sample_id).filename = string(picked_name);
                    sample_cache(sample_id).filepath = string(mat_path);
                    sample_cache(sample_id).c_start = c_start;
                    sample_cache(sample_id).img_gt = ...
                        normalize_image(abs(complex_gt_roi));
                    sample_cache(sample_id).complex_gt_roi = complex_gt_roi;
                end
                clear raw loaded;
            end
            sample_manifest = table( ...
                [sample_cache.sample_id].', [sample_cache.dataset_idx].', ...
                [sample_cache.sample_idx].', string({sample_cache.dataset_name}).', ...
                string({sample_cache.filename}).', [sample_cache.c_start].', ...
                'VariableNames', {'SampleID', 'DatasetIdx', 'LocalSampleIdx', ...
                'Dataset', 'File', 'CStart'});
        end

        function [sample_ids, signals] = loadNoiseDatasetSignals( ...
                sample_cache, dataset_idx, S60)
            % 每次只加载一个数据集的10个样本，避免70个完整回波长期占用内存。
            mask = [sample_cache.dataset_idx] == dataset_idx;
            entries = sample_cache(mask);
            if isempty(entries)
                sample_ids = zeros(0, 1);
                signals = cell(0, 1);
                return;
            end
            loaded = load(char(entries(1).filepath));
            names = fieldnames(loaded);
            raw = loaded.(names{1});
            sample_ids = [entries.sample_id].';
            signals = cell(numel(entries), 1);
            for idx = 1:numel(entries)
                c_start = entries(idx).c_start;
                block = raw(:, c_start:c_start + S60.nrn - 1);
                signal60 = block(1:3:end, :);
                assert(isequal(size(signal60), [S60.nrn, S60.nan]), ...
                    "样本尺寸与FS60参数不一致。");
                signals{idx} = signal60;
            end
        end

        function starts = stratifiedStarts(raw_width, window_width, num_samples)
            max_start = raw_width - window_width + 1;
            if max_start < 1
                error("原始序列宽度不足以裁出完整窗口。");
            end
            starts = zeros(num_samples, 1);
            for idx = 1:num_samples
                starts(idx) = min(max( ...
                    round((idx - 0.5) / num_samples * max_start), 1), max_start);
            end
        end

        function group_defs = buildGroupDefinitions(Q_list)
            total_groups = 1;
            for Q = Q_list
                total_groups = total_groups + size(V5Core.factorPairs(Q), 1);
            end
            empty_group = struct("Q", 0, "Range_q", 0, "Azimuth_q", 0, ...
                "GroupName", "", "GroupType", "", "Description", "");
            group_defs = repmat(empty_group, total_groups, 1);
            group_defs(1) = struct("Q", 1, "Range_q", 1, "Azimuth_q", 1, ...
                "GroupName", "R1A1_NoUp", "GroupType", "no_upsample", ...
                "Description", "无上采样SplitRT基线");
            ptr = 1;
            for Q = Q_list
                pairs = V5Core.factorPairs(Q);
                for idx = 1:size(pairs, 1)
                    range_q = pairs(idx, 1);
                    azimuth_q = pairs(idx, 2);
                    [group_type, description] = ...
                        V5Core.describeGroup(range_q, azimuth_q, Q);
                    ptr = ptr + 1;
                    group_defs(ptr) = struct("Q", Q, "Range_q", range_q, ...
                        "Azimuth_q", azimuth_q, ...
                        "GroupName", sprintf("R%dA%d", range_q, azimuth_q), ...
                        "GroupType", group_type, "Description", description);
                end
            end
        end

        function defs = noiseGroupDefinitions()
            defs = struct( ...
                "Q", {4, 4, 4}, "Range_q", {4, 1, 2}, ...
                "Azimuth_q", {1, 4, 2}, ...
                "GroupName", {"R4A1", "R1A4", "R2A2"}, ...
                "GroupType", {"range_only", "azimuth_only", "balanced"});
        end

        function pairs = factorPairs(Q)
            if Q < 1 || Q ~= round(Q)
                error("Q必须是正整数。");
            end
            pairs = zeros(sum(mod(Q, 1:Q) == 0), 2);
            ptr = 0;
            for range_q = 1:Q
                if mod(Q, range_q) == 0
                    ptr = ptr + 1;
                    pairs(ptr, :) = [range_q, Q / range_q];
                end
            end
        end

        function [group_type, description] = describeGroup(range_q, azimuth_q, Q)
            if range_q == 1 && azimuth_q == Q
                group_type = "azimuth_only"; description = "方位向单方向上采样";
            elseif azimuth_q == 1 && range_q == Q
                group_type = "range_only"; description = "距离向单方向上采样";
            elseif range_q == azimuth_q
                group_type = "balanced"; description = "双向均衡上采样";
            else
                group_type = "mixed"; description = "双向非均衡上采样";
            end
        end

        function img_gt = buildGTImage(signal60, S60)
            RC = Range_Compress(signal60, S60.fc, S60.tnrn, S60.gama, ...
                S60.R0, S60.C, S60.Fs, S60.Tp);
            RCMC_out = RCMC(RC, S60.lambda, S60.fnrn, S60.fnan, ...
                S60.R0, S60.C, S60.v);
            IMG = SAR_Imaging(RCMC_out, S60.lambda, S60.Fs, S60.R0, ...
                S60.C, S60.v, S60.tnan, S60.Ta, S60.prf);
            img_gt = normalize_image(V5Core.extractROI(IMG, S60));
        end

        function complex_roi = buildGTComplexROI(signal60, S60)
            % 保留传统全精度成像链的舍入路径，并在取幅度前返回复数ROI。
            RC = Range_Compress(signal60, S60.fc, S60.tnrn, S60.gama, ...
                S60.R0, S60.C, S60.Fs, S60.Tp);
            RCMC_out = RCMC(RC, S60.lambda, S60.fnrn, S60.fnan, ...
                S60.R0, S60.C, S60.v);
            IMG = SAR_Imaging(RCMC_out, S60.lambda, S60.Fs, S60.R0, ...
                S60.C, S60.v, S60.tnan, S60.Ta, S60.prf);
            rows = S60.nrn/2-S60.R_total/2+1:S60.nrn/2+S60.R_total/2;
            cols = S60.nan/2-S60.A_num/2:S60.nan/2+S60.A_num/2-1;
            complex_roi = IMG(rows, cols);
        end

        function img_out = buildSplitRTImage(signal60, S60, range_q, azimuth_q, As)
            signal_up = V5Core.twoDimUpsample(signal60, azimuth_q, range_q);
            U = V5Core.buildSplitRTThreshold(signal_up, As);
            channel_1bit = V5Core.quantizeWithThreshold(signal_up, U);
            img_out = V5Core.focusUpsampledChannel( ...
                channel_1bit, S60, range_q, azimuth_q);
        end

        function [nodes, reference_rc_crop] = buildMechanismNodes( ...
                signal60, S60, range_q, azimuth_q, As)
            signal_up = V5Core.twoDimUpsample(signal60, azimuth_q, range_q);
            U = V5Core.buildSplitRTThreshold(signal_up, As);
            channel_1bit = V5Core.quantizeWithThreshold(signal_up, U);
            [tnrn_up, Fs_up] = V5Core.rangeAxis(size(signal_up, 1), range_q, S60);
            RC_raw = Range_Compress(channel_1bit, S60.fc, tnrn_up, S60.gama, ...
                S60.R0, S60.C, Fs_up, S60.Tp);
            RC_crop = V5Core.twoDimDownsample(RC_raw, azimuth_q, range_q, S60);
            RCMC_out = RCMC(RC_crop, S60.lambda, S60.fnrn, S60.fnan, ...
                S60.R0, S60.C, S60.v);
            IMG = SAR_Imaging(RCMC_out, S60.lambda, S60.Fs, S60.R0, ...
                S60.C, S60.v, S60.tnan, S60.Ta, S60.prf);
            reference_rc_raw = Range_Compress(signal_up, S60.fc, tnrn_up, ...
                S60.gama, S60.R0, S60.C, Fs_up, S60.Tp);
            reference_rc_crop = V5Core.twoDimDownsample( ...
                reference_rc_raw, azimuth_q, range_q, S60);
            nodes = struct("RC_raw", RC_raw, "RC_crop", RC_crop, ...
                "ROI", normalize_image(V5Core.extractROI(IMG, S60)), ...
                "ThresholdMeanAbs", mean(abs(U(:))));
        end

        function roi = extractROI(IMG, S60)
            rows = S60.nrn/2-S60.R_total/2+1:S60.nrn/2+S60.R_total/2;
            cols = S60.nan/2-S60.A_num/2:S60.nan/2+S60.A_num/2-1;
            roi = abs(IMG(rows, cols));
        end

        function img_out = focusUpsampledChannel(channel_1bit, S60, range_q, azimuth_q)
            [tnrn_up, Fs_up] = V5Core.rangeAxis( ...
                size(channel_1bit, 1), range_q, S60);
            RC = Range_Compress(channel_1bit, S60.fc, tnrn_up, S60.gama, ...
                S60.R0, S60.C, Fs_up, S60.Tp);
            RC_crop = V5Core.twoDimDownsample(RC, azimuth_q, range_q, S60);
            RCMC_out = RCMC(RC_crop, S60.lambda, S60.fnrn, S60.fnan, ...
                S60.R0, S60.C, S60.v);
            IMG = SAR_Imaging(RCMC_out, S60.lambda, S60.Fs, S60.R0, ...
                S60.C, S60.v, S60.tnan, S60.Ta, S60.prf);
            img_out = normalize_image(V5Core.extractROI(IMG, S60));
        end

        function [tnrn_up, Fs_up] = rangeAxis(nrn_up, range_q, S60)
            Fs_up = range_q * S60.Fs;
            if range_q == 1 && nrn_up == S60.nrn
                tnrn_up = S60.tnrn;
                return;
            end
            start_time = 2 * S60.R0 / S60.C - floor(nrn_up / 2) / Fs_up;
            tnrn_up = start_time + (0:nrn_up - 1).' / Fs_up;
        end

        function U = buildSplitRTThreshold(signal_up, As)
            [Nr_up, Na_up] = size(signal_up);
            phi_r = 2 * pi * rand(Nr_up, 1);
            phi_a = 2 * pi * rand(1, Na_up);
            sigma = sqrt(2 / pi) * mean(abs(signal_up(:)));
            U = As * sigma * exp(1i * (phi_r + phi_a));
        end

        function S1 = quantizeWithThreshold(S, U)
            assert(isequal(size(S), size(U)), "信号与阈值尺寸不一致。");
            re = ones(size(S), "like", real(S));
            im = ones(size(S), "like", real(S));
            re(real(S) + real(U) < 0) = -1;
            im(imag(S) + imag(U) < 0) = -1;
            S1 = complex(re, im);
        end

        function S_up = twoDimUpsample(S, q_azimuth, q_range)
            S_up = S;
            if q_range > 1, S_up = V5Core.rangeUpsample(S_up, q_range); end
            if q_azimuth > 1, S_up = V5Core.azimuthUpsample(S_up, q_azimuth); end
        end

        function S_down = twoDimDownsample(S, q_azimuth, q_range, meta)
            S_down = S;
            if q_azimuth > 1, S_down = V5Core.cropAzimuth(S_down, meta.nan); end
            if q_range > 1, S_down = V5Core.cropRange(S_down, meta.nrn); end
        end

        function S_up = rangeUpsample(S, q)
            [Nr, Na] = size(S); Nr_up = round(q * Nr);
            Sf = fftshift(fft(S, [], 1), 1);
            pad_total = Nr_up - Nr; pad_top = floor(pad_total / 2);
            Sf_up = [zeros(pad_top, Na, "like", Sf); Sf; ...
                zeros(pad_total-pad_top, Na, "like", Sf)];
            S_up = ifft(ifftshift(Sf_up, 1), [], 1) * q;
        end

        function S_up = azimuthUpsample(S, q)
            [Nr, Na] = size(S); Na_up = round(q * Na);
            Sf = fftshift(fft(S, [], 2), 2);
            pad_total = Na_up - Na; pad_left = floor(pad_total / 2);
            Sf_up = [zeros(Nr, pad_left, "like", Sf), Sf, ...
                zeros(Nr, pad_total-pad_left, "like", Sf)];
            S_up = ifft(ifftshift(Sf_up, 2), [], 2) * q;
        end

        function X_crop = cropRange(X, target_height)
            Nr_up = size(X, 1);
            if target_height > Nr_up, error("目标距离向尺寸大于当前尺寸。"); end
            Xf = fftshift(fft(X, [], 1), 1); c = floor(Nr_up/2)+1;
            h = floor(target_height/2);
            if mod(target_height, 2) == 0, idx = c-h:c+h-1;
            else, idx = c-h:c+h; end
            X_crop = ifft(ifftshift(Xf(idx, :), 1), [], 1);
        end

        function X_crop = cropAzimuth(X, target_width)
            Na_up = size(X, 2);
            if target_width > Na_up, error("目标方位向尺寸大于当前尺寸。"); end
            Xf = fftshift(fft(X, [], 2), 2); c = floor(Na_up/2)+1;
            h = floor(target_width/2);
            if mod(target_width, 2) == 0, idx = c-h:c+h-1;
            else, idx = c-h:c+h; end
            X_crop = ifft(ifftshift(Xf(:, idx), 2), [], 2);
        end

        function context = buildNoiseFastContext(S60, defs)
            % 预计算噪声实验中与样本和随机阈值无关的成像核。
            context = struct();
            context.nrn = S60.nrn;
            context.nan = S60.nan;
            context.range_kernels = cell(1, max([1, [defs.Range_q]]));
            context.range_crop_indices = cell(size(context.range_kernels));
            context.azimuth_crop_indices = cell(1, max([1, [defs.Azimuth_q]]));

            range_factors = unique([1, [defs.Range_q]]);
            for range_q = range_factors
                nrn_up = round(range_q * S60.nrn);
                [tnrn_up, Fs_up] = V5Core.rangeAxis(nrn_up, range_q, S60);
                pulse_sample_count = fix(S60.Tp * Fs_up);
                center_idx = floor(nrn_up / 2) + 1;
                start_idx = center_idx - floor(pulse_sample_count / 2);
                end_idx = start_idx + pulse_sample_count - 1;
                assert(pulse_sample_count >= 1 && start_idx >= 1 && ...
                    end_idx <= nrn_up, "距离压缩脉冲窗口超出回波范围。");
                range_filter = zeros(nrn_up, 1);
                pulse_time = tnrn_up(start_idx:end_idx);
                range_filter(start_idx:end_idx) = exp(1i * pi * S60.gama * ...
                    (pulse_time(:) - 2 * S60.R0 / S60.C) .^ 2);
                context.range_kernels{range_q} = conj( ...
                    V5Core.centeredFFT(range_filter, 1));
                context.range_crop_indices{range_q} = ...
                    V5Core.centeredIndices(nrn_up, S60.nrn);
            end

            azimuth_factors = unique([1, [defs.Azimuth_q]]);
            for azimuth_q = azimuth_factors
                nan_up = round(azimuth_q * S60.nan);
                context.azimuth_crop_indices{azimuth_q} = ...
                    V5Core.centeredIndices(nan_up, S60.nan);
            end

            fnan_row = S60.fnan(:).';
            migration = S60.lambda ^ 2 * S60.R0 * fnan_row .^ 2 / ...
                (8 * S60.v ^ 2);
            context.rcmc_kernel = exp(1i * 2 * pi * ...
                (S60.fnrn(:) * (2 * migration / S60.C)));

            delta_range = S60.C / (2 * S60.Fs);
            range_scale = (-S60.nrn / 2:S60.nrn / 2 - 1).' * delta_range;
            azimuth_rate = -2 * S60.v ^ 2 ./ ...
                (S60.lambda * (range_scale + S60.R0));
            azimuth_filter = zeros(S60.nrn, S60.nan);
            aperture_samples = fix(S60.Ta * S60.prf);
            start_idx = -aperture_samples / 2 + S60.nan / 2 + 1;
            end_idx = aperture_samples / 2 + S60.nan / 2;
            assert(start_idx == round(start_idx) && end_idx == round(end_idx), ...
                "方位压缩窗口索引不是整数。");
            aperture_idx = round(start_idx):round(end_idx);
            azimuth_filter(:, aperture_idx) = exp(-1i * pi * azimuth_rate * ...
                (S60.tnan(aperture_idx) .^ 2));
            context.azimuth_kernel = V5Core.centeredFFT(azimuth_filter, 2);

            context.roi_rows = S60.nrn / 2 - S60.R_total / 2 + 1: ...
                S60.nrn / 2 + S60.R_total / 2;
            context.roi_cols = S60.nan / 2 - S60.A_num / 2: ...
                S60.nan / 2 + S60.A_num / 2 - 1;
        end

        function complex_roi = fastFocusComplexROI( ...
                channel, context, range_q, azimuth_q)
            % 在中心频谱上直接完成裁剪、RCMC和方位压缩，消除成对FFT/IFFT。
            expected_size = [round(range_q * context.nrn), ...
                round(azimuth_q * context.nan)];
            assert(isequal(size(channel), expected_size), ...
                "快路径输入尺寸与距离/方位倍率不一致。");
            range_spectrum = V5Core.centeredFFT(channel, 1) .* ...
                context.range_kernels{range_q};
            if range_q > 1
                range_spectrum = range_spectrum( ...
                    context.range_crop_indices{range_q}, :);
            end
            range_doppler = V5Core.centeredFFT(range_spectrum, 2);
            if azimuth_q > 1
                range_doppler = range_doppler(:, ...
                    context.azimuth_crop_indices{azimuth_q});
            end
            assert(isequal(size(range_doppler), [context.nrn, context.nan]), ...
                "频域裁剪后的尺寸与基础成像网格不一致。");
            range_azimuth = V5Core.centeredIFFT( ...
                range_doppler .* context.rcmc_kernel, 1);
            image = V5Core.centeredIFFT( ...
                range_azimuth .* context.azimuth_kernel, 2);
            complex_roi = image(context.roi_rows, context.roi_cols);
        end

        function [img_out, channel_1bit] = buildNoiseFastImageFromUpsampled( ...
                signal_up, context, range_q, azimuth_q, As, seed, block_cols)
            % 使用局部随机流和分块阈值量化，避免全尺寸阈值与相位矩阵常驻。
            stream = RandStream('mt19937ar', 'Seed', seed);
            channel_1bit = V5Core.quantizeSplitRTBlocked( ...
                signal_up, As, stream, block_cols);
            complex_roi = V5Core.fastFocusComplexROI( ...
                channel_1bit, context, range_q, azimuth_q);
            img_out = normalize_image(abs(complex_roi));
        end

        function S1 = quantizeSplitRTBlocked(S, As, stream, block_cols)
            [num_rows, num_cols] = size(S);
            phase_range = exp(1i * 2 * pi * rand(stream, num_rows, 1));
            phase_azimuth = exp(1i * 2 * pi * rand(stream, 1, num_cols));
            sigma = sqrt(2 / pi) * mean(abs(S(:)));
            amplitude = As * sigma;
            S1 = zeros(size(S), "like", S);
            for first_col = 1:block_cols:num_cols
                columns = first_col:min(first_col + block_cols - 1, num_cols);
                signal_block = S(:, columns);
                threshold = amplitude * ...
                    (phase_range * phase_azimuth(columns));
                real_values = ones(size(signal_block), "like", real(signal_block));
                imag_values = ones(size(signal_block), "like", real(signal_block));
                real_values(real(signal_block) + real(threshold) < 0) = -1;
                imag_values(imag(signal_block) + imag(threshold) < 0) = -1;
                S1(:, columns) = complex(real_values, imag_values);
            end
        end

        function [base_noise, stats] = buildSharedNoiseBase(signal, seed)
            % 每个样本/重复只生成一次零均值标准复高斯噪声，供全部SNR缩放。
            stream = RandStream('mt19937ar', 'Seed', seed);
            [num_rows, num_cols] = size(signal);
            base_noise = complex(randn(stream, num_rows, num_cols), ...
                randn(stream, num_rows, num_cols));
            base_noise = base_noise - mean(base_noise, "all");
            base_noise_power = mean(abs(base_noise(:)) .^ 2);
            if isa(signal, "single")
                % 原始SAR回波为single时及时回收double随机矩阵，降低FFT内存和耗时。
                base_noise = single(base_noise);
            end
            stats = struct( ...
                "SignalPower", mean(abs(signal(:)) .^ 2), ...
                "BaseNoisePower", base_noise_power);
        end

        function Xf = centeredFFT(X, dimension)
            Xf = fftshift(fft(fftshift(X, dimension), [], dimension), dimension);
        end

        function X = centeredIFFT(Xf, dimension)
            X = fftshift(ifft(fftshift(Xf, dimension), [], dimension), dimension);
        end

        function indices = centeredIndices(current_size, target_size)
            if target_size > current_size
                error("目标频谱尺寸大于当前尺寸。");
            end
            center = floor(current_size / 2) + 1;
            half_size = floor(target_size / 2);
            if mod(target_size, 2) == 0
                indices = center - half_size:center + half_size - 1;
            else
                indices = center - half_size:center + half_size;
            end
        end

        function value = imageEntropy(img, num_bins)
            values = min(max(double(img(:)), 0), 1);
            counts = histcounts(values, linspace(0, 1, num_bins + 1));
            probabilities = counts / max(sum(counts), 1);
            probabilities = probabilities(probabilities > 0);
            value = -sum(probabilities .* log2(probabilities));
        end

        function value = enl(img, top, left, window_size)
            patch = double(img(top:top+window_size-1, left:left+window_size-1));
            intensity = patch .^ 2; mu = mean(intensity(:));
            variance = var(intensity(:), 0);
            if variance <= eps(max(mu^2, 1)), value = Inf;
            else, value = mu^2 / variance; end
        end

        function [is_enl, tops, lefts, scores, roi_manifest] = ...
                buildENLRegions(cache, manifest, cfg)
            % 统一在clean GT上选择ENL区域，后续所有实验分支固定复用。
            n_samples = numel(cache);
            is_enl = ismember(string({cache.dataset_name}), ...
                cfg.enl_dataset_names).';
            tops = zeros(n_samples, 1);
            lefts = zeros(n_samples, 1);
            scores = nan(n_samples, 1);
            for sample_idx = find(is_enl).'
                [tops(sample_idx), lefts(sample_idx), scores(sample_idx)] = ...
                    V5Core.selectUniformROI(cache(sample_idx).img_gt, ...
                    cfg.enl_window_size, cfg.enl_stride);
            end
            roi_manifest = manifest(is_enl, :);
            roi_manifest.ROITop = tops(is_enl);
            roi_manifest.ROILeft = lefts(is_enl);
            roi_manifest.ROIHeight = repmat(cfg.enl_window_size, ...
                height(roi_manifest), 1);
            roi_manifest.ROIWidth = repmat(cfg.enl_window_size, ...
                height(roi_manifest), 1);
            roi_manifest.UniformityScore = scores(is_enl);
        end

        function [top, left, score] = selectUniformROI(img_gt, window_size, stride)
            [height, width] = size(img_gt);
            if height < window_size || width < window_size
                error("图像尺寸小于ENL窗口。");
            end
            tops = 1:stride:height-window_size+1;
            lefts = 1:stride:width-window_size+1;
            count = numel(tops)*numel(lefts);
            means = zeros(count, 1); scores = inf(count, 1);
            top_values = zeros(count, 1); left_values = zeros(count, 1);
            ptr = 0; intensity = double(img_gt).^2;
            for row = tops
                for col = lefts
                    ptr = ptr + 1;
                    patch = intensity(row:row+window_size-1, col:col+window_size-1);
                    mu = mean(patch(:)); means(ptr) = mu;
                    scores(ptr) = var(patch(:), 0)/(mu^2+eps);
                    top_values(ptr) = row; left_values(ptr) = col;
                end
            end
            valid = means >= V5Core.percentile(means, 20) & ...
                means <= V5Core.percentile(means, 80) & means > eps;
            if ~any(valid), valid = means > eps; end
            valid_idx = find(valid); [score, local_idx] = min(scores(valid_idx));
            best_idx = valid_idx(local_idx);
            top = top_values(best_idx); left = left_values(best_idx);
        end

        function [off_ratio, range_ratio, azimuth_ratio] = ...
                leakageMetrics(X, reference_matrix, threshold_ratio)
            ref_spec = abs(fftshift(fft2(reference_matrix)));
            support = ref_spec >= threshold_ratio * max(ref_spec(:));
            spec = abs(fftshift(fft2(X))).^2; total = sum(spec(:)) + eps;
            off_ratio = sum(spec(~support), "all") / total;
            range_profile = sum(spec, 2); azimuth_profile = sum(spec, 1).';
            range_mask = any(support, 2); azimuth_mask = any(support, 1).';
            range_ratio = sum(range_profile(~range_mask))/(sum(range_profile)+eps);
            azimuth_ratio = sum(azimuth_profile(~azimuth_mask))/(sum(azimuth_profile)+eps);
        end

        function value = percentile(values, p)
            values = sort(values(~isnan(values)));
            if isempty(values), value = NaN; return; end
            pos = 1 + (numel(values)-1)*p/100; lo = floor(pos); hi = ceil(pos);
            if lo == hi, value = values(lo);
            else, value = values(lo)+(values(hi)-values(lo))*(pos-lo); end
        end

        function seed = noiseSeed(cfg, sample_id, repeat_idx)
            seed = cfg.noise_seed + sample_id * 1000 + repeat_idx;
        end

        function seed = rtSeed(cfg, snr_idx, group_idx, sample_id, repeat_idx)
            seed = cfg.seed + snr_idx * 10000000 + group_idx * 100000 + ...
                sample_id * 1000 + repeat_idx;
        end
    end
end
