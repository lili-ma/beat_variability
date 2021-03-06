function [OriginalDataStruct, SynthDataStruct] = kspace_sim_LM(slow_factor, numlines, randFlag)

% Purpose: this script is based on a modified version of Alex Barker's
% kspace_sim.m script. It simulates the k-space of magnitude and phase
% values obtained from 2D through plane MRI dicoms. The motivation is to
% determine the impact of an anomalous beat during an ECG-gated PCMRI
% acquisition. For proof of concept, the first effort looks at a pulsatile
% phantom during peak flow and simulates an anomalous beat by scaling the
% phase data by a 'slow_factor' and uses the synthetic kspace lines from
% this slow data to fill the central kspace of the original data. The
% number of central lines filled with this slow data is determined by
% 'numlines'.

% Inputs:
%  slow_factor          - array of numbers for scaling velocity/phase
%                         during anomalous beat
%  numlines             - array of number of lines changed (consider making
%                         this input based on views per segment and number
%                         of anomalous beats
%  randFlag             - bool for randomizing anomalous beats (defautl:
%                         false).

%                         
% Outputs:
%  OriginalDataStruct          - Struct with Original Data flow and mean
%                                velocity values 
%  OriginalDataStruct          - Struct with Synthetic Data flow and mean
%                                velocity values as well as error. 
%
% Dependencies:
%  - ifftMultiDim.m
%  - fftMultiDim.m

% Liliana Ma, Northwestern University 20171205

% Notes:
% - The first figure is scaled weirdly, because changing the subplots to a
% single figure also changes the eclipse ROI slightly, which I didn't want
% to do yet for the sake of consistency. The values only change slightly,
% but need to investigate further because the shape of the error curves
% changes.



% TODO:
% - Cycle through k space based on 1/10 anomalous
% - Make the ROI interactive when we start using other data 
% - detemine error interval during acquisition, ie what is the chance that
%   central kspace is filled. What is the 95% confidence interval for any
%   one acquisition (assuming numlines and slow factor are constant).
% - make sure code is flexible to use experimentally determined values



%% read data & set up variables

close all
% DICOM INFO
bitdepth    = 2^12; % dicoms are encoded 12 bit

%% end of : set default values

[magMx, flowMx, venc, voxelSize] = local_sort_filenames;
OriginalDataStruct = []; 
bitrange = bitdepth./2;

phase = (flowMx-bitrange)./bitrange; %result is +/- 1 
phase = pi().*phase;
[sy, sx, nTime] = size(phase); 
%% plot magnitude/phase along with reconstructed real/imaginary

% create imaginary and complex from magnitude and phase

mag = magMx; 
z     = mag.*exp(1i*phase);   % complex


OriginalDataStruct.mag = mag; 
OriginalDataStruct.phase = phase; 
OriginalDataStruct.venc = venc; 
OriginalDataStruct.voxelSize = voxelSize; 
kspace_z = fftMultiDim(z); 

%% create 'slow' flow phantom images
% make region in tube some% of velocity values and then create synthetic
% k-space, ie kspace_slow
% 

% plot process of ROI and computation of 'slow flow'. Overlay on first
% timepoint 
hfig = figure('position',[20   380   1019   586]);
hax1 = subplot(3,3,1); %This is to keep the same location as Alex used for these initial comparisons. This can be changed when we use different ROIs
him1 = imagesc(phase(:,:,1));
title('phase_{norm} [-pi pi]')


% get roi and compute masks
roi_tube   = imellipse(gca,[88.6878751204264 69.4691651891066 15.4136815720394 16.1123707399367]);
axis image

mask       = createMask(roi_tube,him1);
colormap(hfig,gray)
caxis([-pi() pi()]); xlim([75 115]); ylim([60 100]);
%LiliMa: consider making the ROI interactive 

mask = repmat(mask, [1 1 nTime]); % make mask same size as imported data
mask_norm  = mask.*phase;             % masked phase (for 'flow' computation)


%Calculate flow and velocity in the ROI for original data
vel_mean = velMean_TimeResolved(phase, mask, venc); %compute mean phase shift across ROI
flow_ROI = Flow_TimeResolved(phase, mask, venc, voxelSize); 
OriginalDataStruct.meanVelROI = vel_mean; 
OriginalDataStruct.flowROI = flow_ROI; 




%% create 'slow' flow phantom images
% create synthetic k space, convert to image space, and quantify parameters
% and measure percent error

mask_kChange = false([size(numlines, 2) size(kspace_z)]);

for k = 1:size(slow_factor,2)
    for j = 1:size(numlines,2)
        mask_slow  = mask_norm.*slow_factor(k);  % masked slow phase (for 'flow' computation)
        phase_slow = phase;                   % seed with original data
        phase_slow(mask) = mask_slow(mask);
        
        % compute complex slow data
        z_slow = mag.*exp(1i*phase_slow); % complex data for slow phase/mag data
        
        
        % perform FFT on complex data (and phase to test if this is the same)
        kspace_z_slow     = fftMultiDim(z_slow);
%         kspace_phase_slow = fftMultiDim(phase_slow); % won't play with this for now, doesn't seem worth it
%         vel_slow_mean = velMean_TimeResolved(phase_slow, mask, venc); %compute mean phase shift across ROI
%         
        
        % make mask for synthetic line changes 
        if k == 1  % Use the same mask for all slow factors (changes with number of lines) 
            numLinesToChange = numlines(j); %assuming even number of lines
            if randFlag
                indStart = randi([1 sy], [numLinesToChange/2 1]);
                mask_kChange(j, indStart, :,:,:) = 1;
                mask_kChange(j, indStart+1, :,:,:) = 1;
            else
                if mod(sy,2)== 0 %find center;
                    mask_kChange(j,(sy/2-numLinesToChange/2+1):(sy/2+numLinesToChange/2),:,:) = 1;
                else %if odd number of lines, make sure number of center lines to change is odd
                    mask_kChange(j,(sy/2-numLinesToChange/2+0.5):(sy/2+numLinesToChange/2+0.5),:,:) = 1;
                end
            end
        end
        
        %create synthetic kspace with center containing slow data
        kspace_z_syn = kspace_z;
        mask_numLines = squeeze(mask_kChange(j, :,:,:,:)); 
        kspace_z_syn(mask_numLines(:)) = kspace_z_slow(mask_numLines(:));
        
        %convert to image data
        z_syn     = ifftMultiDim(kspace_z_syn);
        mag_syn   = abs(z_syn);
        phase_syn = angle(z_syn);
        
        vel_syn_mean = velMean_TimeResolved(phase_syn, mask, venc);
        flow_ROI_syn = Flow_TimeResolved(phase_syn, mask, venc, voxelSize);
        
        %put data into struct 
        SynthDataStruct(k).SlowData(j).mag = mag_syn;
        SynthDataStruct(k).SlowData(j).phase = phase_syn;
        SynthDataStruct(k).SlowData(j).kSpace = kspace_z_syn;
        SynthDataStruct(k).SlowData(j).slowFactor = slow_factor(k);
        SynthDataStruct(k).SlowData(j).meanVelROI = vel_syn_mean;
        SynthDataStruct(k).SlowData(j).flowROI = flow_ROI_syn;
        SynthDataStruct(k).SlowData(j).meanVelErrorROI = abs((vel_syn_mean - OriginalDataStruct.meanVelROI)./OriginalDataStruct.meanVelROI);
        SynthDataStruct(k).SlowData(j).flowErrorROI = abs((flow_ROI_syn - OriginalDataStruct.flowROI)./OriginalDataStruct.flowROI);
              
        
    end 
end


%% Plot data
hfigMasks = figure;
hfig1_plot = figure;
for k = 1:size(slow_factor,2)
    legendNames = cell(size(numlines,2)+1,1);
    set(0,'CurrentFigure',hfig1_plot)

    for j = 1:size(numlines,2)
        if k == 1  % Use the same mask for all slow factors (changes with number of lines) 
            set(0,'CurrentFigure',hfigMasks)
            subplot(ceil(size(numlines,2)/2), 2,j)
            imagesc(squeeze(mask_kChange(j,:,:,1))); colormap gray; axis image;
            titleStr = ['Mask used for ', num2str(numlines(j)),' lines changed'];
            title(titleStr);
        end
        
        
        legendNames{j} = [num2str(numlines(j)),' center lines changed'];
        set(0,'CurrentFigure',hfig1_plot)
        currentAxis = subplot(ceil(size(slow_factor,2)/2), 2,k);
        hold on
        plot(SynthDataStruct(k).SlowData(j).flowROI);
        
        
    end
    legendNames{size(numlines,2)+1} = 'Original Data';
    plot(OriginalDataStruct.flowROI,'-xk');
    title(['Flow Curves for slow factor = ', num2str(slow_factor(k))]);
    xlabel('Time point')
    ylabel('Flow (cm^3/s)')
    legend(legendNames);
    hold off
    
    hfig2 = figure('position',[1 1 1164 1051]);
    hfig3 = figure('position',[1 1 1164 1051]);
    
    for n = 1: nTime
        set(0,'CurrentFigure',hfig2)     
        subplot(ceil(nTime/3), 3, n);
        lineError = arrayfun(@(x) x.meanVelErrorROI(n), SynthDataStruct(k).SlowData);
        lineData = arrayfun(@(x) x.meanVelROI(n), SynthDataStruct(k).SlowData);
        lineData_original = OriginalDataStruct.meanVelROI(n);
        yyaxis right
        b = plot(numlines,lineError*100,'-o');
        ylabel('% Velocity Error')

        yyaxis left
        hold on
        p = plot(numlines,lineData,'-x');
        o = plot(0, lineData_original, 'xk'); 
        ylabel('Mean Velocity (cm/s)')
       % p.LineWidth = 2; 
        xlabel('Number of  Center Lines Changed')
        titleStr = ['Slow Factor = ', num2str(slow_factor(k)), ', Time point ', num2str(n), '/', num2str(nTime)];
        title(titleStr);
        hold off
        
        
        set(0,'CurrentFigure',hfig3)
        subplot(ceil(nTime/3), 3, n);
        line1 = arrayfun(@(x) x.flowErrorROI(n), SynthDataStruct(k).SlowData);
        line2 = arrayfun(@(x) x.flowROI(n), SynthDataStruct(k).SlowData);
        line_original = OriginalDataStruct.flowROI(n); 
        yyaxis right % plot flow error on left axis
        l1 = plot(numlines,line1*100, 'o');
        ylabel('% Flow Error')
        %         ylim([0 90]);
        yyaxis left %plot flow on right axis 
        hold on
        l2 = plot(numlines,line2, '-x');
        l3 = plot(0, line_original, 'kx'); 
        ylabel('Flow (cm^3/s)')
        xlabel('Number of  Center Lines Changed')
        %         ylim([-0.4 40]);
        titleStr = ['Slow Factor = ', num2str(slow_factor(k)), ', Time point ', num2str(n), '/', num2str(nTime)];
        title(titleStr);
        
        
        hold off
    end
end

end



    function [magMx, flowMx, venc, voxelVol] = local_sort_filenames
        dirStrMag = uigetdir(pwd,'Select ''mag'' Data Directory');
        extensionStr = 'ima';
        [fileNamesMagMx, dirStrMag]  = local_get_filelist(dirStrMag,extensionStr);
        
        %% continue if at least one file was chosen
        if ~isempty(fileNamesMagMx)
            %% automatically choose flow files in directory "flow"
            
            pathstr = fileparts(dirStrMag);
            dirStrFlow   = fullfile(pathstr,'flow');
            [fileNamesFlowMx, ~]  = local_get_filelist(dirStrFlow,extensionStr);
            %% end of: automatically choose flow files in directory "flow"
            
            %% continue if there are files with flow information
            if ~isempty(fileNamesFlowMx)
                %% calculate number of flow to encode
                numOfFilesMag  = size(fileNamesMagMx,1);
                numOfFilesFlow = size(fileNamesFlowMx,1);
                
                headerStr  = full_filename(dirStrFlow,fileNamesFlowMx(1,:));
                
                %% get information from dicom header
                dataInfoStruct = dicominfo(headerStr,'UseDictionaryVR', true);
                
                voxelVol = [dataInfoStruct.PixelSpacing' dataInfoStruct.SliceThickness]; 
                if isfield(dataInfoStruct,'Private_0051_1014') && ~isempty(dataInfoStruct.Private_0051_1014)
                    venc = str2double(regexp(dataInfoStruct.Private_0051_1014, '\d*', 'match')); %get the venc;
                end
                
                magMx = zeros(dataInfoStruct.Rows, dataInfoStruct.Columns, numOfFilesMag);
                flowMx = zeros(dataInfoStruct.Rows, dataInfoStruct.Columns, numOfFilesMag);
                for k = 1:numOfFilesMag
                    filePathStrMAG  = full_filename(dirStrMag,fileNamesMagMx(k,:));
                    magMx(:,:,k)= dicomread(filePathStrMAG);
                end
                
                for k = 1:numOfFilesFlow
                    filePathStrFLOW  = full_filename(dirStrFlow,fileNamesFlowMx(k,:));
                    flowMx(:,:,k)= dicomread(filePathStrFLOW);
                end
            end
        end
    end

    function [fileNamesMx, dirStr] = local_get_filelist(dirStr,extensionStr)
        
        %%% default settings
        fileListStruct = [];
        fileNamesMx    = [];
        %%% End of: default settings
        
        %%% get file list
        if isempty(extensionStr)
            askStr = full_filename(dirStr,'*');
        else
            tmpStr = sprintf('*.%s',extensionStr);
            askStr = full_filename(dirStr,tmpStr);
        end
        dirStruct    = dir(askStr);
        noOfEntries  = size(dirStruct,1);
        %%% End of: get file list
        
        %%% create fileListStruct
        fileCount = 1;
        for k=1:noOfEntries
            fileStr = dirStruct(k).name;
            
            if dirStruct(k).isdir==0 && strcmp(fileStr,'..')==0 &&  strcmp(fileStr,'.')==0
                fileListStruct(fileCount).name = fileStr;
                fileCount = fileCount+1;
            end
        end
        %%% End of: create fileListStruct
        
        %%% convert fileListStruct to matrix of file names
        if any(size(fileListStruct))
            fileNamesMx = sortrows(char(fileListStruct.name));
        end
        %%% End of: convert fileListStruct to matrix of file names
    end

    function vel_mean = velMean_TimeResolved(dataMx, maskMx, venc)
        [ny, nx, nTimePts] = size(dataMx); 
        vel_mean = zeros(nTimePts, 1); 
        
        for n = 1: nTimePts
            dataTemp = dataMx(:,:,n);
            maskTemp = maskMx(:,:,n);
            vel_mean(n) = mean(dataTemp(maskTemp(:)))*venc/pi;
        end
    end
    
    
    function ROI_flow = Flow_TimeResolved(dataMx, maskMx, venc, voxelSize)
        [ny, nx, nTimePts] = size(dataMx);
        ROI_flow = zeros(nTimePts, 1);
        
        for n = 1: nTimePts
            dataTemp = dataMx(:,:,n);
            maskTemp = maskMx(:,:,n);
            data = dataTemp(maskTemp(:));
            ROI_flow(n) = sum(data * voxelSize(1) * voxelSize(2)*10^-2)*venc/pi; % convert voxel area from mm^2 to cm^ 
        end
    end