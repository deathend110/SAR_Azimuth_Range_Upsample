function Range_Com_tr_ta=Range_Compress(echo,fc,tnrn,gama,R0,c,Fs,Tp) %#ok<INUSD>
[nrn,nan]=size(echo);
x=(echo);%.*(exp(-1i*2*pi*fc*tnrn).*ones(1,nan));
Hr=zeros(nrn,nan);

% 显式构造整数居中索引，兼容奇数脉冲采样点并避免半整数冒号索引。
pulse_sample_count=fix(Tp*Fs);
center_idx=floor(nrn/2)+1;
start_idx=center_idx-floor(pulse_sample_count/2);
end_idx=start_idx+pulse_sample_count-1;
assert(numel(tnrn)==nrn,"距离时间轴长度与回波距离向尺寸不一致。");
assert(pulse_sample_count>=1 && start_idx>=1 && end_idx<=nrn, ...
    "距离压缩脉冲窗口超出回波范围。");

pulse_time=tnrn(start_idx:end_idx);
pulse_time=pulse_time(:);
Hrr=exp(1i*pi*gama*(pulse_time-2*R0/c).^2)*ones(1,nan);
assert(size(Hrr,1)==pulse_sample_count,"距离压缩脉冲长度不一致。");
Hr(start_idx:end_idx,:)=Hrr;
Comp_fr_ta=fftshift(fft(fftshift(x,1),[],1),1).*conj(fftshift(fft(fftshift(Hr,1),[],1),1));
Range_Com_tr_ta=fftshift(ifft(fftshift(Comp_fr_ta,1),[],1),1);
