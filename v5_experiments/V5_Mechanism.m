function V5_Mechanism()
% V5机制实验：RC频谱泄漏、共享色标频谱图和场景图。

cfg=V5Core.config(); addpath(cfg.repo_root,cfg.experiment_dir);
output_dir=fullfile(cfg.output_root,"Mechanism"); V5Core.ensureDir(output_dir);
S60=load(cfg.parameter_file); seed=42; As=cfg.As;
dataset_name="SAR_Dataset_city2_histeq"; file_name="rstart 301.mat"; c_start=6500;
loaded=load(fullfile(cfg.data_root,dataset_name,file_name)); names=fieldnames(loaded);
raw=loaded.(names{1}); block=raw(:,c_start:c_start+S60.nrn-1); signal60=block(1:3:end,:);
defs=struct("Name",{"R1A1","R4A1","R1A4","R2A2"}, ...
    "Range_q",{1,4,1,2},"Azimuth_q",{1,1,4,2});
results=repmat(struct("Name","","Range_q",0,"Azimuth_q",0, ...
    "RC_raw",[],"RC_crop",[],"ROI",[],"ReferenceRC",[], ...
    "ThresholdMeanAbs",NaN),numel(defs),1);
for idx=1:numel(defs)
    rng(seed+idx);
    [nodes,reference_rc]=V5Core.buildMechanismNodes(signal60,S60, ...
        defs(idx).Range_q,defs(idx).Azimuth_q,As);
    results(idx).Name=defs(idx).Name; results(idx).Range_q=defs(idx).Range_q;
    results(idx).Azimuth_q=defs(idx).Azimuth_q; results(idx).RC_raw=nodes.RC_raw;
    results(idx).RC_crop=nodes.RC_crop; results(idx).ROI=nodes.ROI;
    results(idx).ReferenceRC=reference_rc;
    results(idx).ThresholdMeanAbs=nodes.ThresholdMeanAbs;
end

metrics=buildMetrics(results);
img_gt=V5Core.buildGTImage(signal60,S60);
scene_rois=cat(3,img_gt,results(2).ROI,results(3).ROI,results(4).ROI);
scene_metrics=buildSceneMetrics(scene_rois);
writetable(metrics,fullfile(output_dir,"V5_Mechanism_Metrics.csv"));
writetable(scene_metrics,fullfile(output_dir,"V5_Scene_Metrics.csv"));
exportSpectrum(results,S60,fullfile(output_dir,"V5_Mechanism_Common4x4.png"));
exportScenes(scene_rois,scene_metrics,fullfile(output_dir,"V5_Scene_SharedColorbar.png"));
save(fullfile(output_dir,"V5_Mechanism_Data.mat"),"seed","As","dataset_name", ...
    "file_name","c_start","defs","metrics","scene_rois","scene_metrics","-v7.3");
writeMetadata(seed,As,dataset_name,file_name,c_start,output_dir);
fprintf("V5机制实验完成：%s\n",output_dir);
end

function T=buildMetrics(results)
n=numel(results); Allocation=strings(n,1); Range_q=zeros(n,1); Azimuth_q=zeros(n,1);
OffSupport=zeros(n,1); RangeLeakage=zeros(n,1); AzimuthLeakage=zeros(n,1);
ThresholdMeanAbs=zeros(n,1);
for idx=1:n
    [OffSupport(idx),RangeLeakage(idx),AzimuthLeakage(idx)]= ...
        V5Core.leakageMetrics(results(idx).RC_crop,results(idx).ReferenceRC,0.35);
    Allocation(idx)=results(idx).Name; Range_q(idx)=results(idx).Range_q;
    Azimuth_q(idx)=results(idx).Azimuth_q;
    ThresholdMeanAbs(idx)=results(idx).ThresholdMeanAbs;
end
T=table(Allocation,Range_q,Azimuth_q,OffSupport,RangeLeakage, ...
    AzimuthLeakage,ThresholdMeanAbs);
end

function T=buildSceneMetrics(rois)
Allocation=["GT";"R4A1";"R1A4";"R2A2"]; PSNR=zeros(4,1); SSIM=zeros(4,1);
gt=rois(:,:,1);
for idx=1:4, PSNR(idx)=psnr(rois(:,:,idx),gt); SSIM(idx)=ssim(rois(:,:,idx),gt); end
T=table(Allocation,PSNR,SSIM);
end

function exportSpectrum(results,S60,save_path)
n=numel(results); specs=cell(n,1); samples=[];
for idx=1:n
    specs{idx}=log1p(abs(fftshift(fft2(results(idx).RC_raw))));
    step=max(1,floor(numel(specs{idx})/200000));
    values=specs{idx}(1:step:end); samples=[samples;values(:)]; %#ok<AGROW>
end
limits=[V5Core.percentile(samples,1),V5Core.percentile(samples,99.5)];
fig=figure("Visible","off","Color","w","Units","centimeters","Position",[2 2 12.5 10]);
layout=tiledlayout(fig,2,2,"Padding","compact","TileSpacing","compact");
labels=["(a)","(b)","(c)","(d)"];
for idx=1:n
    ax=nexttile(layout); x=((0:size(specs{idx},2)-1)-floor(size(specs{idx},2)/2))/S60.nan;
    y=((0:size(specs{idx},1)-1)-floor(size(specs{idx},1)/2))/S60.nrn;
    imagesc(ax,x,y,specs{idx}); set(ax,"YDir","normal","FontName","Times New Roman", ...
        "FontSize",7,"Box","on"); axis(ax,"image"); xlim(ax,[-2 2]); ylim(ax,[-2 2]);
    clim(ax,limits); xlabel(ax,"Azimuth frequency"); ylabel(ax,"Range frequency");
    title(ax,sprintf("%s %s",labels(idx),results(idx).Name),"FontWeight","normal");
end
colormap(fig,turbo(256)); cb=colorbar; cb.Layout.Tile="east";
ylabel(cb,"log(1 + |FFT|)"); exportgraphics(fig,save_path,"Resolution",300); close(fig);
end

function exportScenes(rois,metrics,save_path)
fig=figure("Visible","off","Color","w","Units","centimeters","Position",[2 2 12.5 10]);
layout=tiledlayout(fig,2,2,"Padding","compact","TileSpacing","compact");
labels=["(a)","(b)","(c)","(d)"];
for idx=1:4
    ax=nexttile(layout); imagesc(ax,rois(:,:,idx),[0 1]); axis(ax,"image","off");
    if isinf(metrics.PSNR(idx)), p="Inf"; else, p=sprintf("%.2f",metrics.PSNR(idx)); end
    title(ax,{sprintf("%s %s",labels(idx),metrics.Allocation(idx)), ...
        sprintf("PSNR = %s dB; SSIM = %.4f",p,metrics.SSIM(idx))}, ...
        "FontName","Times New Roman","FontSize",8,"FontWeight","normal");
end
colormap(fig,parula); cb=colorbar; cb.Layout.Tile="east"; ylabel(cb,"Normalized amplitude");
exportgraphics(fig,save_path,"Resolution",300); close(fig);
end

function writeMetadata(seed,As,dataset,file,c_start,output_dir)
fid=fopen(fullfile(output_dir,"V5_Mechanism_Metadata.txt"),"w");
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,"Seed=%d\nAs=%.16g\nDataset=%s\nFile=%s\nCStart=%d\n", ...
    seed,As,dataset,file,c_start);
fprintf(fid,"SupportThreshold=0.35\nSpectrumLimits=[-2,2]x[-2,2]\n");
end
