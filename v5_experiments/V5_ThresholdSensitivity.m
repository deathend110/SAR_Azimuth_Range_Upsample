function V5_ThresholdSensitivity()
% V5 RT阈值幅度敏感性：仅评价正文使用的三个双向分配。

cfg = V5Core.config();
addpath(cfg.repo_root, cfg.experiment_dir);
output_dir = fullfile(cfg.output_root, "ThresholdSensitivity");
V5Core.ensureDir(output_dir);
S60 = load(cfg.parameter_file);
[sample_cache, sample_manifest] = V5Core.buildSampleCache(cfg, S60);
defs = struct("Q", {4,6,9}, "Range_q", {2,2,3}, ...
    "Azimuth_q", {2,3,3}, "GroupName", {"R2A2","R2A3","R3A3"});
n_groups = numel(defs); n_as = numel(cfg.As_list); n_samples = numel(sample_cache);
psnr_all = nan(n_groups,n_as,n_samples); ssim_all = nan(n_groups,n_as,n_samples);
completed = false(n_groups,n_as);
signature = struct("Experiment","V5_ThresholdSensitivity", ...
    "Seed",cfg.seed,"AsList",cfg.As_list,"GroupNames",string({defs.GroupName}), ...
    "SampleID",sample_manifest.SampleID,"CStart",sample_manifest.CStart);
checkpoint_path = fullfile(output_dir,"V5_Threshold_Checkpoint.mat");
if isfile(checkpoint_path)
    cp=load(checkpoint_path);
    if ~isfield(cp,"signature") || ~isequaln(cp.signature,signature)
        error("现有RT敏感性checkpoint签名不匹配。");
    end
    psnr_all=cp.psnr_all; ssim_all=cp.ssim_all; completed=cp.completed;
end

for group_idx=1:n_groups
    for as_idx=1:n_as
        if completed(group_idx,as_idx), continue; end
        As=cfg.As_list(as_idx);
        fprintf("RT敏感性 %s As=%.1f\n",defs(group_idx).GroupName,As);
        % 随机相位属于RT阈值本身，每个配置和As使用可复现的独立序列。
        rng(cfg.seed+group_idx*1000+as_idx*10);
        for sample_idx=1:n_samples
            img=V5Core.buildSplitRTImage(sample_cache(sample_idx).signal60_input, ...
                S60,defs(group_idx).Range_q,defs(group_idx).Azimuth_q,As);
            gt=sample_cache(sample_idx).img_gt;
            psnr_all(group_idx,as_idx,sample_idx)=psnr(img,gt);
            ssim_all(group_idx,as_idx,sample_idx)=ssim(img,gt);
        end
        completed(group_idx,as_idx)=true;
        save(checkpoint_path,"signature","psnr_all","ssim_all","completed","-v7.3");
    end
end

summary=buildSummary(defs,cfg.As_list,psnr_all,ssim_all);
detail=buildDetail(defs,cfg.As_list,sample_manifest,psnr_all,ssim_all);
writetable(summary,fullfile(output_dir,"V5_RT_As_Summary.csv"));
writetable(detail,fullfile(output_dir,"V5_RT_As_Detail.csv"));
save(fullfile(output_dir,"V5_RT_As_Data.mat"),"cfg","defs", ...
    "sample_manifest","psnr_all","ssim_all","summary","-v7.3");
exportCurve(defs,cfg.As_list,ssim_all, ...
    fullfile(output_dir,"V5_RT_SSIM_AsCurve.png"));
writeMetadata(cfg,defs,n_samples,output_dir);
fprintf("V5 RT敏感性实验完成：%s\n",output_dir);
end

function T=buildSummary(defs,As_list,psnr_all,ssim_all)
n_groups=numel(defs); n_as=numel(As_list); n=n_groups*n_as;
Q=zeros(n,1); GroupName=strings(n,1); Range_q=zeros(n,1); Azimuth_q=zeros(n,1);
As=zeros(n,1); SampleCount=repmat(size(psnr_all,3),n,1);
PSNR_Mean=zeros(n,1); PSNR_Std=zeros(n,1); SSIM_Mean=zeros(n,1); SSIM_Std=zeros(n,1);
ptr=0;
for g=1:n_groups
    for a=1:n_as
        ptr=ptr+1; Q(ptr)=defs(g).Q; GroupName(ptr)=defs(g).GroupName;
        Range_q(ptr)=defs(g).Range_q; Azimuth_q(ptr)=defs(g).Azimuth_q; As(ptr)=As_list(a);
        p=squeeze(psnr_all(g,a,:)); s=squeeze(ssim_all(g,a,:));
        PSNR_Mean(ptr)=mean(p); PSNR_Std(ptr)=std(p);
        SSIM_Mean(ptr)=mean(s); SSIM_Std(ptr)=std(s);
    end
end
T=table(Q,GroupName,Range_q,Azimuth_q,As,SampleCount, ...
    PSNR_Mean,PSNR_Std,SSIM_Mean,SSIM_Std);
end

function T=buildDetail(defs,As_list,manifest,psnr_all,ssim_all)
n_groups=numel(defs); n_as=numel(As_list); n_samples=height(manifest);
n=n_groups*n_as*n_samples; Q=zeros(n,1); GroupName=strings(n,1);
Range_q=zeros(n,1); Azimuth_q=zeros(n,1); As=zeros(n,1); SampleID=zeros(n,1);
Dataset=strings(n,1); File=strings(n,1); CStart=zeros(n,1); PSNR=zeros(n,1); SSIM=zeros(n,1);
ptr=0;
for g=1:n_groups
    for a=1:n_as
        rows=ptr+(1:n_samples); ptr=ptr+n_samples;
        Q(rows)=defs(g).Q; GroupName(rows)=defs(g).GroupName;
        Range_q(rows)=defs(g).Range_q; Azimuth_q(rows)=defs(g).Azimuth_q;
        As(rows)=As_list(a); SampleID(rows)=manifest.SampleID;
        Dataset(rows)=manifest.Dataset; File(rows)=manifest.File; CStart(rows)=manifest.CStart;
        PSNR(rows)=reshape(psnr_all(g,a,:),[],1);
        SSIM(rows)=reshape(ssim_all(g,a,:),[],1);
    end
end
T=table(Q,GroupName,Range_q,Azimuth_q,As,SampleID,Dataset,File,CStart,PSNR,SSIM);
end

function exportCurve(defs,As_list,ssim_all,save_path)
mean_ssim=mean(ssim_all,3); std_ssim=std(ssim_all,0,3);
fig=figure("Visible","off","Color","w","Units","centimeters", ...
    "Position",[2 2 13 8]); ax=axes(fig); hold(ax,"on"); grid(ax,"on"); box(ax,"on");
colors=lines(numel(defs)); handles=gobjects(numel(defs),1); labels=strings(numel(defs),1);
for g=1:numel(defs)
    handles(g)=errorbar(ax,As_list,mean_ssim(g,:),std_ssim(g,:),"-o", ...
        "Color",colors(g,:),"LineWidth",1.4,"MarkerSize",4,"CapSize",5);
    [best,best_idx]=max(mean_ssim(g,:));
    plot(ax,As_list(best_idx),best,"p","Color",colors(g,:), ...
        "MarkerFaceColor",colors(g,:),"MarkerSize",9,"HandleVisibility","off");
    labels(g)=sprintf("%s, Q=%d",defs(g).GroupName,defs(g).Q);
end
xlabel(ax,"A_s"); ylabel(ax,"SSIM"); legend(ax,handles,labels,"Location","best");
set(ax,"FontName","Times New Roman","FontSize",9);
exportgraphics(fig,save_path,"Resolution",300); close(fig);
end

function writeMetadata(cfg,defs,n_samples,output_dir)
fid=fopen(fullfile(output_dir,"V5_RT_As_Metadata.txt"),"w");
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,"Seed=%d\nAsList=%s\nGroups=%s\nSampleCount=%d\n", ...
    cfg.seed,mat2str(cfg.As_list),strjoin(string({defs.GroupName}),","),n_samples);
fprintf(fid,"RTPhaseProtocol=independent deterministic sequence per group and As\n");
end
