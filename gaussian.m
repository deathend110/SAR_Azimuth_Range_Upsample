function Noise = gaussian(signal, SNR_dB)
    % 以1-bit量化前原始复回波的平均功率定义输入信噪比
    signal_power = mean(abs(signal(:)) .^ 2);
    target_noise_power = signal_power / (10 ^ (SNR_dB / 10));
    target_noise_std = sqrt(target_noise_power);

    % 生成与原流程一致的零均值复高斯白噪声
    [rows, cols] = size(signal);
    scale_factor = target_noise_std / sqrt(2);

    Noise = scale_factor * (randn(rows, cols) + 1j * randn(rows, cols));
    Noise = Noise - mean(Noise, "all");

    % 输出有限样本下的实际噪声统计量，便于核验实验配置
    actual_noise_power = mean(abs(Noise(:)) .^ 2);
    actual_SNR_dB = 10 * log10(signal_power / actual_noise_power);
    disp(['目标SNR(dB): ', num2str(SNR_dB)]);
    disp(['实际SNR(dB): ', num2str(actual_SNR_dB)]);
    disp(['噪声均值: ', num2str(mean(Noise(:)))]);
    disp(['噪声目标标准差: ', num2str(target_noise_std)]);
    disp(['噪声实际标准差: ', num2str(std(Noise(:)))]);
end
