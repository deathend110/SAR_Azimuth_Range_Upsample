function V5_NoiseEvaluation()
% V5高斯噪声实验：同一noisy重建同时评价clean GT与同噪声noisy GT。

cfg=V5Core.config(); addpath(cfg.repo_root,cfg.experiment_dir);
output_dir=fullfile(cfg.output_root,"NoiseEvaluation"); V5Core.ensureDir(output_dir);
S60=load(cfg.parameter_file);
defs=V5Core.noiseGroupDefinitions();
fast_context=V5Core.buildNoiseFastContext(S60,defs);
[cache,manifest]=V5Core.buildNoiseSampleCache(cfg,S60);
n_groups=numel(defs); n_snr=numel(cfg.SNR_dB_list);
n_samples=numel(cache); n_repeats=cfg.noise_repeats;
[is_enl,enl_top,enl_left,~,roi_manifest]= ...
    V5Core.buildENLRegions(cache,manifest,cfg);
writetable(roi_manifest,fullfile(output_dir,"V5_Noise_ENL_ROI_Manifest.csv"));

psnr_clean=nan(n_groups,n_snr,n_samples,n_repeats);
ssim_clean=nan(n_groups,n_snr,n_samples,n_repeats);
psnr_noisy=nan(n_groups,n_snr,n_samples,n_repeats);
ssim_noisy=nan(n_groups,n_snr,n_samples,n_repeats);
enl_all=nan(n_groups,n_snr,n_samples,n_repeats);
actual_snr=nan(n_snr,n_samples,n_repeats);
clean_psnr=nan(n_groups,n_samples); clean_ssim=nan(n_groups,n_samples);
clean_enl=nan(n_groups,n_samples); baseline_completed=false(n_samples,1);
completed=false(n_samples,n_repeats);
signature=buildSignature(cfg,defs,manifest,roi_manifest);
checkpoint_name=sprintf("V5_Noise_Checkpoint_R%d_%s_%s.mat", ...
    n_repeats,cfg.noise_seed_protocol,cfg.noise_compute_version);
checkpoint_path=fullfile(output_dir,checkpoint_name);
if isfile(checkpoint_path)
    cp=load(checkpoint_path);
    if ~isfield(cp,"signature") || ~isequaln(cp.signature,signature)
        error("现有V5噪声实验checkpoint签名不匹配。");
    end
    psnr_clean=cp.psnr_clean; ssim_clean=cp.ssim_clean;
    psnr_noisy=cp.psnr_noisy; ssim_noisy=cp.ssim_noisy;
    enl_all=cp.enl_all; actual_snr=cp.actual_snr; completed=cp.completed;
    clean_psnr=cp.clean_psnr; clean_ssim=cp.clean_ssim;
    clean_enl=cp.clean_enl; baseline_completed=cp.baseline_completed;
    fprintf("恢复V5噪声checkpoint：%d/%d个样本-重复单元已完成。\n", ...
        nnz(completed),numel(completed));
else
    save(checkpoint_path,"signature","psnr_clean","ssim_clean", ...
        "psnr_noisy","ssim_noisy","enl_all","actual_snr", ...
        "clean_psnr","clean_ssim","clean_enl","baseline_completed", ...
        "completed","-v7.3");
end
checkpoint=matfile(checkpoint_path,"Writable",true);
[use_parallel,max_workers,created_pool,parallel_mode]=configureParallel(cfg);
if ~isempty(created_pool)
    pool_cleanup=onCleanup(@() closeCreatedPool(created_pool));
end

fprintf(["=== V5噪声实验CPU快路径：%d SNR × %d样本 × %d重复 × " ...
    "%d分配；%s，最多%d worker ===\n"],n_snr,n_samples,n_repeats, ...
    n_groups,parallel_mode,max_workers);
for dataset_idx=1:numel(cfg.dataset_names)
    [sample_ids,signals]=V5Core.loadNoiseDatasetSignals(cache,dataset_idx,S60);
    for local_idx=1:numel(sample_ids)
        sample_idx=sample_ids(local_idx);
        pending_repeats=find(~completed(sample_idx,:));
        if isempty(pending_repeats) && baseline_completed(sample_idx)
            continue;
        end
        clean_signal=signals{local_idx};
        clean_gt=cache(sample_idx).img_gt;
        clean_complex_roi=cache(sample_idx).complex_gt_roi;
        sample_is_enl=is_enl(sample_idx);
        sample_enl_top=enl_top(sample_idx);
        sample_enl_left=enl_left(sample_idx);
        clean_up=cell(n_groups,1);
        for group_idx=1:n_groups
            clean_up{group_idx}=V5Core.twoDimUpsample(clean_signal, ...
                defs(group_idx).Azimuth_q,defs(group_idx).Range_q);
        end

        if ~baseline_completed(sample_idx)
            [clean_psnr(:,sample_idx),clean_ssim(:,sample_idx), ...
                clean_enl(:,sample_idx)]=evaluateCleanBaseline( ...
                clean_up,clean_gt,defs,cfg,fast_context,sample_is_enl, ...
                sample_enl_top,sample_enl_left,sample_idx);
            checkpoint.clean_psnr(:,sample_idx)=clean_psnr(:,sample_idx);
            checkpoint.clean_ssim(:,sample_idx)=clean_ssim(:,sample_idx);
            checkpoint.clean_enl(:,sample_idx)=clean_enl(:,sample_idx);
            baseline_completed(sample_idx)=true;
            checkpoint.baseline_completed(sample_idx,1)=true;
        end

        for batch_start=1:max_workers:numel(pending_repeats)
            batch_repeats=pending_repeats(batch_start: ...
                min(batch_start+max_workers-1,numel(pending_repeats)));
            batch_results=cell(numel(batch_repeats),1);
            if use_parallel && numel(batch_repeats)>1
                parfor (task_idx=1:numel(batch_repeats),max_workers)
                    batch_results{task_idx}=evaluateNoiseRepeat( ...
                        batch_repeats(task_idx),sample_idx,clean_signal, ...
                        clean_complex_roi,clean_gt,clean_up,fast_context, ...
                        defs,cfg,sample_is_enl,sample_enl_top,sample_enl_left);
                end
            else
                for task_idx=1:numel(batch_repeats)
                    batch_results{task_idx}=evaluateNoiseRepeat( ...
                        batch_repeats(task_idx),sample_idx,clean_signal, ...
                        clean_complex_roi,clean_gt,clean_up,fast_context, ...
                        defs,cfg,sample_is_enl,sample_enl_top,sample_enl_left);
                end
            end
            for task_idx=1:numel(batch_repeats)
                repeat_idx=batch_repeats(task_idx); result=batch_results{task_idx};
                psnr_clean(:,:,sample_idx,repeat_idx)=result.psnr_clean;
                ssim_clean(:,:,sample_idx,repeat_idx)=result.ssim_clean;
                psnr_noisy(:,:,sample_idx,repeat_idx)=result.psnr_noisy;
                ssim_noisy(:,:,sample_idx,repeat_idx)=result.ssim_noisy;
                enl_all(:,:,sample_idx,repeat_idx)=result.enl;
                actual_snr(:,sample_idx,repeat_idx)=result.actual_snr;
                % 先写完整切片，最后更新完成标记，避免恢复半成品任务。
                checkpoint.psnr_clean(:,:,sample_idx,repeat_idx)=result.psnr_clean;
                checkpoint.ssim_clean(:,:,sample_idx,repeat_idx)=result.ssim_clean;
                checkpoint.psnr_noisy(:,:,sample_idx,repeat_idx)=result.psnr_noisy;
                checkpoint.ssim_noisy(:,:,sample_idx,repeat_idx)=result.ssim_noisy;
                checkpoint.enl_all(:,:,sample_idx,repeat_idx)=result.enl;
                checkpoint.actual_snr(:,sample_idx,repeat_idx)=result.actual_snr;
                completed(sample_idx,repeat_idx)=true;
                checkpoint.completed(sample_idx,repeat_idx)=true;
            end
        end
        fprintf("样本%d/%d完成。\n",sample_idx,n_samples);
        clear clean_up clean_signal;
    end
    clear signals;
end

psnr_clean_sample=mean(psnr_clean,4); ssim_clean_sample=mean(ssim_clean,4);
psnr_noisy_sample=mean(psnr_noisy,4); ssim_noisy_sample=mean(ssim_noisy,4);
enl_sample=mean(enl_all,4,"omitnan");

raw_detail=buildRawDetail(defs,cfg.SNR_dB_list,manifest,actual_snr, ...
    psnr_clean,ssim_clean,psnr_noisy,ssim_noisy,enl_all);
sample_means=buildSampleMeans(defs,cfg.SNR_dB_list,manifest, ...
    psnr_clean_sample,ssim_clean_sample,psnr_noisy_sample,ssim_noisy_sample, ...
    enl_sample);
summary=buildSummary(defs,cfg.SNR_dB_list,psnr_clean_sample, ...
    ssim_clean_sample,psnr_noisy_sample,ssim_noisy_sample,enl_sample,n_repeats);
paired_tests=buildPairedTests(defs,cfg.SNR_dB_list,psnr_clean_sample, ...
    ssim_clean_sample,psnr_noisy_sample,ssim_noisy_sample);
snr_audit=buildSNRAudit(cfg.SNR_dB_list,manifest,actual_snr);
clean_baseline=buildCleanTable(defs,clean_psnr,clean_ssim,clean_enl);

writetable(raw_detail,fullfile(output_dir,"V5_Noise_RawDetail.csv"));
writetable(sample_means,fullfile(output_dir,"V5_Noise_SampleMeans.csv"));
writetable(summary,fullfile(output_dir,"V5_Noise_Summary.csv"));
writetable(paired_tests,fullfile(output_dir,"V5_Noise_PairedTests.csv"));
writetable(snr_audit,fullfile(output_dir,"V5_Noise_ActualSNR.csv"));
writetable(clean_baseline,fullfile(output_dir,"V5_Noise_CleanBaseline.csv"));
save(fullfile(output_dir,"V5_Noise_Data.mat"),"cfg","defs","manifest", ...
    "roi_manifest","psnr_clean","ssim_clean","psnr_noisy","ssim_noisy", ...
    "enl_all","actual_snr","clean_psnr","clean_ssim","clean_enl", ...
    "summary","paired_tests","-v7.3");
exportCurves(defs,cfg.SNR_dB_list,summary,clean_baseline,output_dir);
writeMetadata(cfg,defs,n_samples,sum(is_enl),checkpoint_name,parallel_mode, ...
    max_workers,output_dir);
fprintf("V5噪声实验完成：%s\n",output_dir);
end

function signature=buildSignature(cfg,defs,manifest,roi_manifest)
signature=struct("Experiment","V5_NoiseEvaluation", ...
    "ComputeVersion",cfg.noise_compute_version, ...
    "SNRdBList",cfg.SNR_dB_list,"Repeats",cfg.noise_repeats, ...
    "As",cfg.As,"NoiseSeed",cfg.noise_seed,"RTSeed",cfg.seed, ...
    "SeedProtocol",cfg.noise_seed_protocol, ...
    "GroupNames",string({defs.GroupName}),"RangeQ",[defs.Range_q], ...
    "AzimuthQ",[defs.Azimuth_q],"SampleID",manifest.SampleID, ...
    "Dataset",manifest.Dataset,"File",manifest.File,"CStart",manifest.CStart, ...
    "ENLSampleID",roi_manifest.SampleID,"ENLROITop",roi_manifest.ROITop, ...
    "ENLROILeft",roi_manifest.ROILeft,"ENLROIHeight",roi_manifest.ROIHeight, ...
    "ENLROIWidth",roi_manifest.ROIWidth,"ENLStride",cfg.enl_stride, ...
    "ENLDatasets",cfg.enl_dataset_names, ...
    "ENLProtocol","clean GT fixed ROI; intensity=normalized amplitude squared", ...
    "NoiseProtocol","shared centered base Gaussian; linear scaling across SNR", ...
    "GTProtocols",["clean_gt","same_noise_gt"]);
end

function [clean_psnr,clean_ssim,clean_enl]=evaluateCleanBaseline( ...
        clean_up,clean_gt,defs,cfg,context,is_enl,enl_top,enl_left,sample_idx)
n_groups=numel(defs); clean_psnr=nan(n_groups,1);
clean_ssim=nan(n_groups,1); clean_enl=nan(n_groups,1);
for group_idx=1:n_groups
    img=V5Core.buildNoiseFastImageFromUpsampled(clean_up{group_idx},context, ...
        defs(group_idx).Range_q,defs(group_idx).Azimuth_q,cfg.As, ...
        V5Core.rtSeed(cfg,0,group_idx,sample_idx,1), ...
        cfg.noise_quant_block_cols);
    clean_psnr(group_idx)=psnr(img,clean_gt);
    clean_ssim(group_idx)=ssim(img,clean_gt);
    if is_enl
        clean_enl(group_idx)=V5Core.enl(img,enl_top,enl_left, ...
            cfg.enl_window_size);
    end
end
end

function result=evaluateNoiseRepeat(repeat_idx,sample_idx,clean_signal, ...
        clean_complex_roi,clean_gt,clean_up,context,defs,cfg,is_enl, ...
        enl_top,enl_left)
% 单个重复内部共享基础噪声、noisy GT和三组上采样结果。
n_groups=numel(defs); n_snr=numel(cfg.SNR_dB_list);
[base_noise,noise_stats]=V5Core.buildSharedNoiseBase(clean_signal, ...
    V5Core.noiseSeed(cfg,sample_idx,repeat_idx));
noise_complex_roi=V5Core.fastFocusComplexROI(base_noise,context,1,1);
scales=sqrt(noise_stats.SignalPower ./ ...
    (10 .^ (cfg.SNR_dB_list / 10))) / sqrt(2);
actual_snr=10*log10(noise_stats.SignalPower ./ ...
    (scales.^2*noise_stats.BaseNoisePower));
noisy_gt=cell(n_snr,1);
for snr_idx=1:n_snr
    noisy_gt{snr_idx}=normalize_image(abs( ...
        clean_complex_roi+scales(snr_idx)*noise_complex_roi));
end
result=struct("psnr_clean",nan(n_groups,n_snr), ...
    "ssim_clean",nan(n_groups,n_snr),"psnr_noisy",nan(n_groups,n_snr), ...
    "ssim_noisy",nan(n_groups,n_snr),"enl",nan(n_groups,n_snr), ...
    "actual_snr",actual_snr(:));
for group_idx=1:n_groups
    noise_up=V5Core.twoDimUpsample(base_noise, ...
        defs(group_idx).Azimuth_q,defs(group_idx).Range_q);
    for snr_idx=1:n_snr
        signal_up=clean_up{group_idx}+scales(snr_idx)*noise_up;
        img=V5Core.buildNoiseFastImageFromUpsampled(signal_up,context, ...
            defs(group_idx).Range_q,defs(group_idx).Azimuth_q,cfg.As, ...
            V5Core.rtSeed(cfg,snr_idx,group_idx,sample_idx,repeat_idx), ...
            cfg.noise_quant_block_cols);
        result.psnr_clean(group_idx,snr_idx)=psnr(img,clean_gt);
        result.ssim_clean(group_idx,snr_idx)=ssim(img,clean_gt);
        result.psnr_noisy(group_idx,snr_idx)=psnr(img,noisy_gt{snr_idx});
        result.ssim_noisy(group_idx,snr_idx)=ssim(img,noisy_gt{snr_idx});
        if is_enl
            result.enl(group_idx,snr_idx)=V5Core.enl(img,enl_top,enl_left, ...
                cfg.enl_window_size);
        end
    end
end
end

function [use_parallel,max_workers,created_pool,parallel_mode]=configureParallel(cfg)
use_parallel=false; max_workers=1; created_pool=[]; parallel_mode="serial";
if ~license("test","Distrib_Computing_Toolbox") || cfg.noise_num_workers<=1
    return;
end
try
    pool=gcp("nocreate");
    if isempty(pool)
        pool=parpool("Threads",cfg.noise_num_workers);
        created_pool=pool;
    end
    max_workers=min(cfg.noise_num_workers,pool.NumWorkers);
    use_parallel=max_workers>1;
    parallel_mode=string(class(pool));
catch exception
    warning("V5:NoiseParallelFallback", ...
        "CPU并行池不可用，将串行运行：%s",exception.message);
end
end

function closeCreatedPool(pool)
if ~isempty(pool) && isvalid(pool)
    delete(pool);
end
end

function T=buildRawDetail(defs,snr_list,manifest,actual_snr,pc,sc,pn,sn,enl)
n_groups=numel(defs); n_snr=numel(snr_list); n_samples=height(manifest); n_rep=size(pc,4);
n=n_groups*n_snr*n_samples*n_rep; SNR_dB=zeros(n,1); ActualSNR_dB=zeros(n,1);
GroupName=strings(n,1); Range_q=zeros(n,1); Azimuth_q=zeros(n,1);
SampleID=zeros(n,1); Dataset=strings(n,1); File=strings(n,1); CStart=zeros(n,1);
Repeat=zeros(n,1); PSNR_CleanGT=zeros(n,1); SSIM_CleanGT=zeros(n,1);
PSNR_NoisyGT=zeros(n,1); SSIM_NoisyGT=zeros(n,1); ptr=0;
ENL=nan(n,1);
for g=1:n_groups
 for z=1:n_snr
  for r=1:n_rep
   rows=ptr+(1:n_samples); ptr=ptr+n_samples;
   SNR_dB(rows)=snr_list(z); ActualSNR_dB(rows)=reshape(actual_snr(z,:,r),[],1);
   GroupName(rows)=defs(g).GroupName; Range_q(rows)=defs(g).Range_q;
   Azimuth_q(rows)=defs(g).Azimuth_q; SampleID(rows)=manifest.SampleID;
   Dataset(rows)=manifest.Dataset; File(rows)=manifest.File; CStart(rows)=manifest.CStart;
   Repeat(rows)=r; PSNR_CleanGT(rows)=reshape(pc(g,z,:,r),[],1);
   SSIM_CleanGT(rows)=reshape(sc(g,z,:,r),[],1);
   PSNR_NoisyGT(rows)=reshape(pn(g,z,:,r),[],1);
   SSIM_NoisyGT(rows)=reshape(sn(g,z,:,r),[],1);
   ENL(rows)=reshape(enl(g,z,:,r),[],1);
  end
 end
end
T=table(SNR_dB,ActualSNR_dB,GroupName,Range_q,Azimuth_q,SampleID, ...
    Dataset,File,CStart,Repeat,PSNR_CleanGT,SSIM_CleanGT,PSNR_NoisyGT, ...
    SSIM_NoisyGT,ENL);
end

function T=buildSampleMeans(defs,snr_list,manifest,pc,sc,pn,sn,enl)
n_groups=numel(defs); n_snr=numel(snr_list); n_samples=height(manifest); n=n_groups*n_snr*n_samples;
SNR_dB=zeros(n,1); GroupName=strings(n,1); Range_q=zeros(n,1); Azimuth_q=zeros(n,1);
SampleID=zeros(n,1); Dataset=strings(n,1); File=strings(n,1); CStart=zeros(n,1);
PSNR_CleanGT=zeros(n,1); SSIM_CleanGT=zeros(n,1); PSNR_NoisyGT=zeros(n,1); SSIM_NoisyGT=zeros(n,1);
ENL=nan(n,1);
ptr=0;
for g=1:n_groups
 for z=1:n_snr
  rows=ptr+(1:n_samples); ptr=ptr+n_samples; SNR_dB(rows)=snr_list(z);
  GroupName(rows)=defs(g).GroupName; Range_q(rows)=defs(g).Range_q;
  Azimuth_q(rows)=defs(g).Azimuth_q; SampleID(rows)=manifest.SampleID;
  Dataset(rows)=manifest.Dataset; File(rows)=manifest.File; CStart(rows)=manifest.CStart;
  PSNR_CleanGT(rows)=reshape(pc(g,z,:),[],1);
  SSIM_CleanGT(rows)=reshape(sc(g,z,:),[],1);
  PSNR_NoisyGT(rows)=reshape(pn(g,z,:),[],1);
  SSIM_NoisyGT(rows)=reshape(sn(g,z,:),[],1);
  ENL(rows)=reshape(enl(g,z,:),[],1);
 end
end
T=table(SNR_dB,GroupName,Range_q,Azimuth_q,SampleID,Dataset,File,CStart, ...
    PSNR_CleanGT,SSIM_CleanGT,PSNR_NoisyGT,SSIM_NoisyGT,ENL);
end

function T=buildSummary(defs,snr_list,pc,sc,pn,sn,enl,n_repeats)
n_groups=numel(defs); n_snr=numel(snr_list); n=n_groups*n_snr;
SNR_dB=zeros(n,1); GroupName=strings(n,1); Range_q=zeros(n,1); Azimuth_q=zeros(n,1);
SampleCount=repmat(size(pc,3),n,1); Repeats=repmat(n_repeats,n,1);
ENLSampleCount=zeros(n,1); ENL_Mean=zeros(n,1); ENL_Std=zeros(n,1);
PSNR_CleanGT_Mean=zeros(n,1); PSNR_CleanGT_Std=zeros(n,1);
SSIM_CleanGT_Mean=zeros(n,1); SSIM_CleanGT_Std=zeros(n,1);
PSNR_NoisyGT_Mean=zeros(n,1); PSNR_NoisyGT_Std=zeros(n,1);
SSIM_NoisyGT_Mean=zeros(n,1); SSIM_NoisyGT_Std=zeros(n,1); ptr=0;
for g=1:n_groups
 for z=1:n_snr
  ptr=ptr+1; SNR_dB(ptr)=snr_list(z); GroupName(ptr)=defs(g).GroupName;
  Range_q(ptr)=defs(g).Range_q; Azimuth_q(ptr)=defs(g).Azimuth_q;
  values={squeeze(pc(g,z,:)),squeeze(sc(g,z,:)),squeeze(pn(g,z,:)),squeeze(sn(g,z,:))};
  PSNR_CleanGT_Mean(ptr)=mean(values{1}); PSNR_CleanGT_Std(ptr)=std(values{1});
  SSIM_CleanGT_Mean(ptr)=mean(values{2}); SSIM_CleanGT_Std(ptr)=std(values{2});
  PSNR_NoisyGT_Mean(ptr)=mean(values{3}); PSNR_NoisyGT_Std(ptr)=std(values{3});
  SSIM_NoisyGT_Mean(ptr)=mean(values{4}); SSIM_NoisyGT_Std(ptr)=std(values{4});
  enl_values=squeeze(enl(g,z,:)); enl_values=enl_values(isfinite(enl_values));
  ENLSampleCount(ptr)=numel(enl_values);
  ENL_Mean(ptr)=mean(enl_values); ENL_Std(ptr)=std(enl_values);
 end
end
T=table(SNR_dB,GroupName,Range_q,Azimuth_q,SampleCount,ENLSampleCount,Repeats, ...
    PSNR_CleanGT_Mean,PSNR_CleanGT_Std,SSIM_CleanGT_Mean,SSIM_CleanGT_Std, ...
    PSNR_NoisyGT_Mean,PSNR_NoisyGT_Std,SSIM_NoisyGT_Mean,SSIM_NoisyGT_Std, ...
    ENL_Mean,ENL_Std);
end

function T=buildPairedTests(defs,snr_list,pc,sc,pn,sn)
comparators=[1,2]; n=numel(snr_list)*2*numel(comparators); SNR_dB=zeros(n,1);
ReferenceType=strings(n,1); Bidirectional=repmat("R2A2",n,1);
Comparator=strings(n,1); DeltaPSNR=zeros(n,1); DeltaSSIM=zeros(n,1);
P_PSNR=zeros(n,1); P_SSIM=zeros(n,1); ptr=0; bi=find(string({defs.GroupName})=="R2A2",1);
for z=1:numel(snr_list)
 for ref=1:2
  if ref==1, p=pc; s=sc; ref_name="clean_gt"; else, p=pn; s=sn; ref_name="same_noise_gt"; end
  for comparator=comparators
   ptr=ptr+1; SNR_dB(ptr)=snr_list(z); ReferenceType(ptr)=ref_name;
   Comparator(ptr)=defs(comparator).GroupName; bp=squeeze(p(bi,z,:)); up=squeeze(p(comparator,z,:));
   bs=squeeze(s(bi,z,:)); us=squeeze(s(comparator,z,:));
   DeltaPSNR(ptr)=mean(bp-up); DeltaSSIM(ptr)=mean(bs-us);
   P_PSNR(ptr)=signrank(bp,up); P_SSIM(ptr)=signrank(bs,us);
  end
 end
end
T=table(SNR_dB,ReferenceType,Bidirectional,Comparator,DeltaPSNR,DeltaSSIM,P_PSNR,P_SSIM);
end

function T=buildSNRAudit(snr_list,manifest,actual)
n_snr=numel(snr_list); n_samples=height(manifest); n_rep=size(actual,3); n=n_snr*n_samples*n_rep;
TargetSNR_dB=zeros(n,1); ActualSNR_dB=zeros(n,1); SampleID=zeros(n,1);
Dataset=strings(n,1); Repeat=zeros(n,1); ptr=0;
for z=1:n_snr
 for r=1:n_rep
  rows=ptr+(1:n_samples); ptr=ptr+n_samples; TargetSNR_dB(rows)=snr_list(z);
   ActualSNR_dB(rows)=reshape(actual(z,:,r),[],1); SampleID(rows)=manifest.SampleID;
  Dataset(rows)=manifest.Dataset; Repeat(rows)=r;
 end
end
T=table(TargetSNR_dB,ActualSNR_dB,SampleID,Dataset,Repeat);
end

function T=buildCleanTable(defs,p,s,enl)
n=numel(defs); GroupName=string({defs.GroupName}).'; Range_q=[defs.Range_q].';
Azimuth_q=[defs.Azimuth_q].'; SampleCount=repmat(size(p,2),n,1);
PSNR_Mean=mean(p,2); PSNR_Std=std(p,0,2); SSIM_Mean=mean(s,2); SSIM_Std=std(s,0,2);
ENLSampleCount=sum(isfinite(enl),2); ENL_Mean=mean(enl,2,"omitnan");
ENL_Std=std(enl,0,2,"omitnan");
T=table(GroupName,Range_q,Azimuth_q,SampleCount,ENLSampleCount, ...
    PSNR_Mean,PSNR_Std,SSIM_Mean,SSIM_Std,ENL_Mean,ENL_Std);
end

function exportCurves(defs,snr_list,summary,baseline,output_dir)
% clean GT与同噪声GT分别绘制，统一坐标范围便于直接比较。
colors=lines(numel(defs));
common_ylimits={[20 26.5],[0.45 0.85]};
exportReferenceFigure(defs,snr_list,summary,baseline,colors, ...
    ["PSNR_CleanGT_Mean","SSIM_CleanGT_Mean"], ...
    "Noise Robustness of 1-Bit SAR Reconstruction (Clean-GT Reference)", ...
    fullfile(output_dir,"V5_Noise_CleanGT_Curves.png"), ...
    fullfile(output_dir,"V5_Noise_CleanGT_Curves.pdf"),common_ylimits);
exportReferenceFigure(defs,snr_list,summary,baseline,colors, ...
    ["PSNR_NoisyGT_Mean","SSIM_NoisyGT_Mean"], ...
    "Noise Robustness of 1-Bit SAR Reconstruction (Same-Noise-GT Reference)", ...
    fullfile(output_dir,"V5_Noise_NoisyGT_Curves.png"), ...
    fullfile(output_dir,"V5_Noise_NoisyGT_Curves.pdf"),common_ylimits);
% 自动纵轴版本用于突出同噪声GT曲线的细微非单调变化。
exportReferenceFigure(defs,snr_list,summary,baseline,colors, ...
    ["PSNR_NoisyGT_Mean","SSIM_NoisyGT_Mean"], ...
    "Noise Robustness of 1-Bit SAR Reconstruction (Same-Noise-GT, Auto-Scaled)", ...
    fullfile(output_dir,"V5_Noise_NoisyGT_AutoScale_Curves.png"), ...
    fullfile(output_dir,"V5_Noise_NoisyGT_AutoScale_Curves.pdf"),[]);
exportFocusedNoisyGTFigure(defs,snr_list,summary,baseline,colors, ...
    fullfile(output_dir,"V5_Noise_NoisyGT_FocusCurves.png"), ...
    fullfile(output_dir,"V5_Noise_NoisyGT_FocusCurves.pdf"));
end

function exportReferenceFigure(defs,snr_list,summary,baseline,colors,specs, ...
    title_text,png_path,pdf_path,ylimits)
% 最右侧独立端点表示无外加高斯噪声，不与有限SNR曲线连接。
fig=figure("Visible","on","Color","w","Units","centimeters", ...
    "Position",[2 2 20 8]);
layout=tiledlayout(fig,1,2,"Padding","compact","TileSpacing","compact");
title(layout,title_text,"FontName","Times New Roman","FontSize",11, ...
    "FontWeight","bold");
labels=string({defs.GroupName});
clean_x=max(snr_list)+2;
finite_ticks=min(snr_list):2:max(snr_list);
tick_labels=[compose("%g",finite_ticks),"\infty"];
ylabels=["PSNR (dB)","SSIM"];
for panel=1:2
    ax=nexttile(layout); hold(ax,"on"); grid(ax,"on"); box(ax,"on");
    handles=gobjects(numel(defs),1);
    for g=1:numel(defs)
        rows=summary.GroupName==defs(g).GroupName;
        y=summary.(specs(panel))(rows);
        handles(g)=plot(ax,snr_list,y,"-o","Color",colors(g,:), ...
            "LineWidth",1.3,"MarkerSize",3);
        if panel==1
            base=baseline.PSNR_Mean(g);
        else
            base=baseline.SSIM_Mean(g);
        end
        plot(ax,clean_x,base,"d","Color",colors(g,:), ...
            "MarkerFaceColor",colors(g,:),"MarkerSize",5, ...
            "HandleVisibility","off");
    end
    xlim(ax,[min(snr_list),clean_x+0.3]);
    if ~isempty(ylimits)
        ylim(ax,ylimits{panel});
    end
    xticks(ax,[finite_ticks,clean_x]); xticklabels(ax,tick_labels);
    xlabel(ax,"Added Gaussian-Noise SNR (dB; \infty = no added noise)");
    ylabel(ax,ylabels(panel));
    set(ax,"FontName","Times New Roman","FontSize",8, ...
        "TickLabelInterpreter","tex");
    legend(ax,handles,labels,"Location","best");
end
exportgraphics(fig,png_path,"Resolution",300);
exportgraphics(fig,pdf_path,"ContentType","vector");
end

function exportFocusedNoisyGTFigure(defs,snr_list,summary,baseline,colors, ...
    png_path,pdf_path)
% 面向论文单栏排版：自动纵轴、共享横轴标题，并仅保留一次图例。
fig=figure("Visible","on","Color","w","Units","centimeters", ...
    "Position",[2 2 9 5.6]);
layout=tiledlayout(fig,1,2,"Padding","compact","TileSpacing","compact");
labels=string({defs.GroupName});
clean_x=max(snr_list)+2;
finite_ticks=unique([min(snr_list):4:max(snr_list),max(snr_list)]);
tick_labels=[compose("%g",finite_ticks),"\infty"];
specs=["PSNR_NoisyGT_Mean","SSIM_NoisyGT_Mean"];
ylabels=["PSNR (dB)","SSIM"];
for panel=1:2
    ax=nexttile(layout); hold(ax,"on"); grid(ax,"on"); box(ax,"on");
    handles=gobjects(numel(defs),1);
    for g=1:numel(defs)
        rows=summary.GroupName==defs(g).GroupName;
        handles(g)=plot(ax,snr_list,summary.(specs(panel))(rows),"-o", ...
            "Color",colors(g,:),"LineWidth",1.3,"MarkerSize",2.8);
        if panel==1
            base=baseline.PSNR_Mean(g);
        else
            base=baseline.SSIM_Mean(g);
        end
        plot(ax,clean_x,base,"d","Color",colors(g,:), ...
            "MarkerFaceColor",colors(g,:),"MarkerSize",4, ...
            "HandleVisibility","off");
    end
    xlim(ax,[min(snr_list),clean_x+0.3]);
    xticks(ax,[finite_ticks,clean_x]); xticklabels(ax,tick_labels);
    ylabel(ax,ylabels(panel));
    set(ax,"FontName","Times New Roman","FontSize",7, ...
        "TickLabelInterpreter","tex");
    if panel==2
        legend(ax,handles,labels,"Location","best","FontSize",6);
    end
end
xlabel(layout,"Added Gaussian-Noise SNR (dB)", ...
    "FontName","Times New Roman","FontSize",7);
set(findall(fig,"-property","FontName"),"FontName","Times New Roman");
exportgraphics(fig,png_path,"Resolution",300);
% 固定论文单栏物理尺寸，并保持PDF为矢量输出。
set(fig,"PaperUnits","centimeters","PaperPosition",[0 0 9 5.6], ...
    "PaperSize",[9 5.6]);
print(fig,pdf_path,"-dpdf","-vector");
end

function writeMetadata(cfg,defs,n_samples,n_enl,checkpoint_name,parallel_mode, ...
        max_workers,output_dir)
fid=fopen(fullfile(output_dir,"V5_Noise_Metadata.txt"),"w");
cleanup=onCleanup(@() fclose(fid));
fprintf(fid,"SNRdBList=%s\nRepeats=%d\nAs=%.16g\n", ...
    mat2str(cfg.SNR_dB_list),cfg.noise_repeats,cfg.As);
fprintf(fid,"Groups=%s\nSampleCount=%d\nNoiseSeed=%d\nRTSeed=%d\n", ...
    strjoin(string({defs.GroupName}),","),n_samples,cfg.noise_seed,cfg.seed);
fprintf(fid,"SeedProtocol=%s\nCheckpoint=%s\n", ...
    cfg.noise_seed_protocol,checkpoint_name);
fprintf(fid,"ComputeVersion=%s\nParallelMode=%s\nMaxWorkers=%d\n", ...
    cfg.noise_compute_version,parallel_mode,max_workers);
fprintf(fid,"QuantizationBlockColumns=%d\nGPU=false\n", ...
    cfg.noise_quant_block_cols);
fprintf(fid,"References=clean_gt,same_noise_gt\nRepeatAggregation=mean within sample\n");
fprintf(fid,"NoiseSharedAcrossGroups=true\nBaseNoiseSharedAcrossSNR=true\n");
fprintf(fid,"ENLSampleCount=%d\nENLDatasets=%s\nENLWindow=%d\nENLStride=%d\n", ...
    n_enl,strjoin(cfg.enl_dataset_names,","),cfg.enl_window_size,cfg.enl_stride);
fprintf(fid,"ENLIntensity=normalized amplitude squared\nENLFormula=mean(I)^2/var(I)\n");
fprintf(fid,"ENLROISelection=clean GT; mean intensity percentile 20-80; minimum var(I)/mean(I)^2\n");
end
