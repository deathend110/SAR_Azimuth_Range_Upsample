classdef V4Core
    % V4实验共享核心：统一样本、成像链、指标和ROI协议。

    methods (Static)
        function cfg = config()
            this_file = mfilename("fullpath");
            experiment_dir = fileparts(this_file);
            repo_root = fileparts(experiment_dir);

            cfg = struct();
            cfg.repo_root = repo_root;
            cfg.experiment_dir = experiment_dir;
            cfg.output_root = fullfile(repo_root, "V4_Experiments_Output");
            cfg.data_root = "G:\MATLAB-G\SAR Full PSF";
            cfg.parameter_file = fullfile(repo_root, "FS60_params.mat");
            cfg.seed = 2026;
            cfg.As = 0.6;
            cfg.Q_list = [4, 6, 8, 9, 10];
            cfg.table_Q_list = [4, 6, 8];
            cfg.num_samples_per_dataset = 10;
            cfg.dataset_names = { ...
                "SAR_Dataset_Bangkok_1", ...
                "SAR_Dataset_city1_histeq", ...
                "SAR_Dataset_city2_histeq", ...
                "SAR_Dataset_SAR_figure", ...
                "SAR_Dataset_filed", ...
                "SAR_Dataset_port", ...
                "SAR_Dataset_suburb" ...
            };
            cfg.enl_dataset_names = ["SAR_Dataset_filed", "SAR_Dataset_port"];
            cfg.enl_window_size = 64;
            cfg.enl_stride = 16;
            cfg.entropy_num_bins = 256;

            cfg.rt_figure = fullfile(repo_root, "assert", "RT_SSIM_bestAs_curve.png");
            cfg.rsft_figure = fullfile(repo_root, ...
                "Exp5_RSFT_ParameterMap_Output", "Exp5_RSFT_ParameterMap.png");
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
            num_datasets = numel(cfg.dataset_names);
            total_samples = num_datasets * cfg.num_samples_per_dataset;
            sample_cache = repmat(struct( ...
                "sample_id", 0, ...
                "dataset_idx", 0, ...
                "sample_idx", 0, ...
                "dataset_name", "", ...
                "filename", "", ...
                "filepath", "", ...
                "c_start", 0, ...
                "signal60_input", [], ...
                "img_gt", []), total_samples, 1);

            fprintf("=== V4统一样本清单：%d个样本 ===\n", total_samples);
            sample_id = 0;
            for ds_idx = 1:num_datasets
                ds_name = cfg.dataset_names{ds_idx};
                ds_folder = fullfile(cfg.data_root, ds_name);
                mat_files = dir(fullfile(ds_folder, "rstart*.mat"));
                mat_names = sort({mat_files.name});
                if isempty(mat_names)
                    error("数据集 %s 中未找到 rstart*.mat。", ds_name);
                end

                pick_idx = mod(cfg.seed, numel(mat_names)) + 1;
                picked_name = mat_names{pick_idx};
                mat_path = fullfile(ds_folder, picked_name);
                loaded_data = load(mat_path);
                var_names = fieldnames(loaded_data);
                raw_data = loaded_data.(var_names{1});
                starts = V4Core.stratifiedStarts( ...
                    size(raw_data, 2), S60.nrn, cfg.num_samples_per_dataset);

                fprintf("  [%d/%d] %s -> %s\n", ...
                    ds_idx, num_datasets, ds_name, picked_name);
                for local_idx = 1:cfg.num_samples_per_dataset
                    sample_id = sample_id + 1;
                    c_start = starts(local_idx);
                    block = raw_data(:, c_start:c_start + S60.nrn - 1);
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
                    sample_cache(sample_id).img_gt = ...
                        V4Core.buildGTImage(signal60, S60);
                end
                clear raw_data loaded_data;
            end

            sample_manifest = table( ...
                [sample_cache.sample_id].', ...
                [sample_cache.dataset_idx].', ...
                [sample_cache.sample_idx].', ...
                string({sample_cache.dataset_name}).', ...
                string({sample_cache.filename}).', ...
                [sample_cache.c_start].', ...
                'VariableNames', { ...
                'SampleID', 'DatasetIdx', 'LocalSampleIdx', ...
                'Dataset', 'File', 'CStart'});
        end

        function starts = stratifiedStarts(raw_width, window_width, num_samples)
            max_start = raw_width - window_width + 1;
            if max_start < 1
                error("原始序列宽度不足以裁出完整窗口。");
            end
            starts = zeros(num_samples, 1);
            for idx = 1:num_samples
                center_pos = round((idx - 0.5) / num_samples * max_start);
                starts(idx) = min(max(center_pos, 1), max_start);
            end
        end

        function group_defs = buildGroupDefinitions(Q_list)
            total_groups = 1;
            for Q = Q_list
                total_groups = total_groups + size(V4Core.factorPairs(Q), 1);
            end
            empty_group = struct( ...
                "Q", 0, "Range_q", 0, "Azimuth_q", 0, ...
                "GroupName", "", "GroupType", "", "Description", "");
            group_defs = repmat(empty_group, total_groups, 1);
            group_idx = 1;

            group_defs(group_idx) = struct( ...
                "Q", 1, "Range_q", 1, "Azimuth_q", 1, ...
                "GroupName", "R1A1_NoUp", ...
                "GroupType", "no_upsample", ...
                "Description", "无上采样SplitRT基线");

            for Q = Q_list
                pairs = V4Core.factorPairs(Q);
                for idx = 1:size(pairs, 1)
                    range_q = pairs(idx, 1);
                    azimuth_q = pairs(idx, 2);
                    [group_type, description] = ...
                        V4Core.describeGroup(range_q, azimuth_q, Q);
                    group_idx = group_idx + 1;
                    group_defs(group_idx) = struct( ...
                        "Q", Q, ...
                        "Range_q", range_q, ...
                        "Azimuth_q", azimuth_q, ...
                        "GroupName", sprintf("R%dA%d", range_q, azimuth_q), ...
                        "GroupType", group_type, ...
                        "Description", description);
                end
            end
        end

        function pairs = factorPairs(Q)
            if Q < 1 || Q ~= round(Q)
                error("Q必须是正整数。");
            end
            divisors = find(mod(Q, 1:Q) == 0);
            pairs = zeros(numel(divisors), 2);
            pair_idx = 0;
            for range_q = 1:Q
                if mod(Q, range_q) == 0
                    pair_idx = pair_idx + 1;
                    pairs(pair_idx, :) = [range_q, Q / range_q];
                end
            end
        end

        function [group_type, description] = describeGroup(range_q, azimuth_q, Q)
            if range_q == 1 && azimuth_q == Q
                group_type = "azimuth_only";
                description = "方位向单方向上采样";
            elseif azimuth_q == 1 && range_q == Q
                group_type = "range_only";
                description = "距离向单方向上采样";
            elseif range_q == azimuth_q
                group_type = "balanced";
                description = "双向均衡上采样";
            else
                group_type = "mixed";
                description = "双向非均衡上采样";
            end
        end

        function img_gt = buildGTImage(signal60, S60)
            RC = Range_Compress( ...
                signal60, S60.fc, S60.tnrn, S60.gama, ...
                S60.R0, S60.C, S60.Fs, S60.Tp);
            RCMC_out = RCMC( ...
                RC, S60.lambda, S60.fnrn, S60.fnan, ...
                S60.R0, S60.C, S60.v);
            IMG = SAR_Imaging( ...
                RCMC_out, S60.lambda, S60.Fs, S60.R0, ...
                S60.C, S60.v, S60.tnan, S60.Ta, S60.prf);
            img_gt = normalize_image(V4Core.extractROI(IMG, S60));
        end

        function img_out = buildSplitRTImage( ...
                signal60, S60, range_q, azimuth_q, As)
            signal_up = V4Core.twoDimUpsample(signal60, azimuth_q, range_q);
            U = V4Core.buildSplitRTThreshold(signal_up, As);
            channel_1bit = V4Core.quantizeWithThreshold(signal_up, U);
            img_out = V4Core.focusUpsampledChannel( ...
                channel_1bit, S60, range_q, azimuth_q);
        end

        function [nodes, reference_rc_crop] = buildMechanismNodes( ...
                signal60, S60, range_q, azimuth_q, As)
            signal_up = V4Core.twoDimUpsample(signal60, azimuth_q, range_q);
            U = V4Core.buildSplitRTThreshold(signal_up, As);
            channel_1bit = V4Core.quantizeWithThreshold(signal_up, U);
            [tnrn_up, Fs_up] = V4Core.rangeAxis( ...
                size(signal_up, 1), range_q, S60);
            RC_raw = Range_Compress( ...
                channel_1bit, S60.fc, tnrn_up, S60.gama, ...
                S60.R0, S60.C, Fs_up, S60.Tp);
            RC_crop = V4Core.twoDimDownsample( ...
                RC_raw, azimuth_q, range_q, S60);
            RCMC_out = RCMC( ...
                RC_crop, S60.lambda, S60.fnrn, S60.fnan, ...
                S60.R0, S60.C, S60.v);
            IMG = SAR_Imaging( ...
                RCMC_out, S60.lambda, S60.Fs, S60.R0, ...
                S60.C, S60.v, S60.tnan, S60.Ta, S60.prf);

            reference_rc_raw = Range_Compress( ...
                signal_up, S60.fc, tnrn_up, S60.gama, ...
                S60.R0, S60.C, Fs_up, S60.Tp);
            reference_rc_crop = V4Core.twoDimDownsample( ...
                reference_rc_raw, azimuth_q, range_q, S60);

            nodes = struct();
            nodes.RC_raw = RC_raw;
            nodes.RC_crop = RC_crop;
            nodes.ROI = normalize_image(V4Core.extractROI(IMG, S60));
            nodes.ThresholdMeanAbs = mean(abs(U(:)));
        end

        function roi = extractROI(IMG, S60)
            row_idx = ...
                S60.nrn / 2 - S60.R_total / 2 + 1 : ...
                S60.nrn / 2 + S60.R_total / 2;
            col_idx = ...
                S60.nan / 2 - S60.A_num / 2 : ...
                S60.nan / 2 + S60.A_num / 2 - 1;
            roi = abs(IMG(row_idx, col_idx));
        end

        function img_out = focusUpsampledChannel( ...
                channel_1bit, S60, range_q, azimuth_q)
            [tnrn_up, Fs_up] = V4Core.rangeAxis( ...
                size(channel_1bit, 1), range_q, S60);
            RC = Range_Compress( ...
                channel_1bit, S60.fc, tnrn_up, S60.gama, ...
                S60.R0, S60.C, Fs_up, S60.Tp);
            RC_crop = V4Core.twoDimDownsample( ...
                RC, azimuth_q, range_q, S60);
            RCMC_out = RCMC( ...
                RC_crop, S60.lambda, S60.fnrn, S60.fnan, ...
                S60.R0, S60.C, S60.v);
            IMG = SAR_Imaging( ...
                RCMC_out, S60.lambda, S60.Fs, S60.R0, ...
                S60.C, S60.v, S60.tnan, S60.Ta, S60.prf);
            img_out = normalize_image(V4Core.extractROI(IMG, S60));
        end

        function [tnrn_up, Fs_up] = rangeAxis(nrn_up, range_q, S60)
            Fs_up = range_q * S60.Fs;
            if range_q == 1 && nrn_up == S60.nrn
                tnrn_up = S60.tnrn;
                return;
            end
            Tstart_up = 2 * S60.R0 / S60.C - nrn_up / 2 / Fs_up;
            tnrn_up = Tstart_up + (0:nrn_up - 1).' / Fs_up;
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
            if q_range > 1
                S_up = V4Core.rangeUpsample(S_up, q_range);
            end
            if q_azimuth > 1
                S_up = V4Core.azimuthUpsample(S_up, q_azimuth);
            end
        end

        function S_down = twoDimDownsample(S, q_azimuth, q_range, meta)
            S_down = S;
            if q_azimuth > 1
                S_down = V4Core.cropAzimuth(S_down, meta.nan);
            end
            if q_range > 1
                S_down = V4Core.cropRange(S_down, meta.nrn);
            end
        end

        function S_up = rangeUpsample(S, q)
            [Nr, Na] = size(S);
            Nr_up = round(q * Nr);
            Sf = fftshift(fft(S, [], 1), 1);
            pad_total = Nr_up - Nr;
            pad_top = floor(pad_total / 2);
            pad_bottom = pad_total - pad_top;
            Sf_up = [ ...
                zeros(pad_top, Na, "like", Sf); ...
                Sf; ...
                zeros(pad_bottom, Na, "like", Sf)];
            S_up = ifft(ifftshift(Sf_up, 1), [], 1) * q;
        end

        function S_up = azimuthUpsample(S, q)
            [Nr, Na] = size(S);
            Na_up = round(q * Na);
            Sf = fftshift(fft(S, [], 2), 2);
            pad_total = Na_up - Na;
            pad_left = floor(pad_total / 2);
            pad_right = pad_total - pad_left;
            Sf_up = [ ...
                zeros(Nr, pad_left, "like", Sf), ...
                Sf, ...
                zeros(Nr, pad_right, "like", Sf)];
            S_up = ifft(ifftshift(Sf_up, 2), [], 2) * q;
        end

        function X_crop = cropRange(X, target_height)
            Nr_up = size(X, 1);
            if target_height > Nr_up
                error("目标距离向尺寸大于当前尺寸。");
            end
            Xf = fftshift(fft(X, [], 1), 1);
            c = floor(Nr_up / 2) + 1;
            h = floor(target_height / 2);
            if mod(target_height, 2) == 0
                idx = (c - h):(c + h - 1);
            else
                idx = (c - h):(c + h);
            end
            X_crop = ifft(ifftshift(Xf(idx, :), 1), [], 1);
        end

        function X_crop = cropAzimuth(X, target_width)
            Na_up = size(X, 2);
            if target_width > Na_up
                error("目标方位向尺寸大于当前尺寸。");
            end
            Xf = fftshift(fft(X, [], 2), 2);
            c = floor(Na_up / 2) + 1;
            h = floor(target_width / 2);
            if mod(target_width, 2) == 0
                idx = (c - h):(c + h - 1);
            else
                idx = (c - h):(c + h);
            end
            X_crop = ifft(ifftshift(Xf(:, idx), 2), [], 2);
        end

        function value = imageEntropy(img, num_bins)
            values = double(img(:));
            values = min(max(values, 0), 1);
            counts = histcounts(values, linspace(0, 1, num_bins + 1));
            probabilities = counts / max(sum(counts), 1);
            probabilities = probabilities(probabilities > 0);
            value = -sum(probabilities .* log2(probabilities));
        end

        function value = enl(img, top, left, window_size)
            patch = double(img( ...
                top:top + window_size - 1, ...
                left:left + window_size - 1));
            intensity = patch .^ 2;
            mu = mean(intensity(:));
            variance = var(intensity(:), 0);
            if variance <= eps(max(mu ^ 2, 1))
                value = Inf;
            else
                value = mu ^ 2 / variance;
            end
        end

        function [top, left, score] = selectUniformROI( ...
                img_gt, window_size, stride)
            [height, width] = size(img_gt);
            if height < window_size || width < window_size
                error("图像尺寸小于ENL窗口。");
            end

            tops = 1:stride:(height - window_size + 1);
            lefts = 1:stride:(width - window_size + 1);
            num_candidates = numel(tops) * numel(lefts);
            means = zeros(num_candidates, 1);
            scores = inf(num_candidates, 1);
            top_values = zeros(num_candidates, 1);
            left_values = zeros(num_candidates, 1);

            ptr = 0;
            intensity = double(img_gt) .^ 2;
            for row = tops
                for col = lefts
                    ptr = ptr + 1;
                    patch = intensity( ...
                        row:row + window_size - 1, ...
                        col:col + window_size - 1);
                    mu = mean(patch(:));
                    means(ptr) = mu;
                    scores(ptr) = var(patch(:), 0) / (mu ^ 2 + eps);
                    top_values(ptr) = row;
                    left_values(ptr) = col;
                end
            end

            lower = V4Core.percentile(means, 20);
            upper = V4Core.percentile(means, 80);
            valid = means >= lower & means <= upper & means > eps;
            if ~any(valid)
                valid = means > eps;
            end
            valid_indices = find(valid);
            [score, local_idx] = min(scores(valid_indices));
            best_idx = valid_indices(local_idx);
            top = top_values(best_idx);
            left = left_values(best_idx);
        end

        function [off_ratio, range_ratio, azimuth_ratio] = ...
                leakageMetrics(X, reference_matrix, threshold_ratio)
            ref_spec = abs(fftshift(fft2(reference_matrix)));
            support_mask = ref_spec >= threshold_ratio * max(ref_spec(:));
            spec = abs(fftshift(fft2(X))) .^ 2;
            total_energy = sum(spec(:)) + eps;
            off_ratio = sum(spec(~support_mask), "all") / total_energy;

            range_profile = sum(spec, 2);
            azimuth_profile = sum(spec, 1).';
            range_mask = any(support_mask, 2);
            azimuth_mask = any(support_mask, 1).';
            range_ratio = sum(range_profile(~range_mask)) / ...
                (sum(range_profile) + eps);
            azimuth_ratio = sum(azimuth_profile(~azimuth_mask)) / ...
                (sum(azimuth_profile) + eps);
        end

        function value = percentile(values, p)
            values = sort(values(~isnan(values)));
            if isempty(values)
                value = NaN;
                return;
            end
            pos = 1 + (numel(values) - 1) * p / 100;
            lo = floor(pos);
            hi = ceil(pos);
            if lo == hi
                value = values(lo);
            else
                value = values(lo) + ...
                    (values(hi) - values(lo)) * (pos - lo);
            end
        end
    end
end
