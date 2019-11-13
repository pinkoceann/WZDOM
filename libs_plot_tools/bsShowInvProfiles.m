function bsShowInvProfiles(GPostInvParam, GShowProfileParam, profiles, wellLogs)
%% Show the inversion results
% Programmed by: Bin She (Email: bin.stepbystep@gmail.com)
% Programming dates: Nov 2019
% -------------------------------------------------------------------------
    
    nProfile = length(profiles);
    [~, traceNum] = size(profiles{1}.data);

    
    figure;
    % set the screen size
    switch nProfile
        case 1
            bsSetPosition(0.4, 0.25);
            nRow = 1;
            nCol = 1;
            
        case 2
            bsSetPosition(0.4, 0.5);
            nRow = 2;
            nCol = 1;
            
        case 3
            bsSetPosition(0.4, 0.75);
            nRow = 3;
            nCol = 1;
        case 4
            bsSetPosition(0.8, 0.5);
            nRow = 2;
            nCol = 2;
        case {5, 6}
            bsSetPosition(0.8, 0.75);
            nRow = 3;
            nCol = 2;
    end
    
    % show profiles
    for iProfile = 1 : nProfile
        
        profile = profiles{iProfile};
        
        subplot(nRow, nCol, iProfile);
        
        bsShowOneProfile(profile);
    end
    
    % show one profile
    function bsShowOneProfile(profile)
        
        profileData = profile.data;
        
        if profile.inIds(1) == profile.inIds(2)
            traceIds = profile.crossIds;
        else
            traceIds = profile.inIds;
        end
        
        [sampNum, ~] = size(profileData);
        
        % data preprocessing base on the type of profile
        switch profile.type
            case 'IP'
                
                profileData(profileData<=0) = nan;
                
                if(max(max(profileData)) > 1000)
                    profileData = profileData / 1000;
                end
                
                range = GShowProfileParam.rangeIP;
                if range(1) > 1000
                    range = range / 1000;
                end
                
                attName = 'Impedance (g/cm^3\cdotkm/s)';
                [wellPos, wellData] = bsFindWellLocation(GPostInvParam, ...
                    wellLogs, ...
                    profile.inIds, ...
                    profile.crossIds, ...
                    profile.horizon, ...
                    1, ...
                    2, ...
                    GShowProfileParam.showProfileFiltCoef);
                if ~isempty(wellData)
                    wellData = wellData / 1000;
                end
                
            case 'Seismic'
                attName = 'Seismic (Amplitude)';
                wellPos = [];
                wellData = [];
                
        end
        
        % filter data along with horizon
        profileData = bsFilterData(profileData, profile.showFiltCoef);
        
        % replace the traces that are near by well location as welllog data
        profileData = bsReplaceWellLocationData(GShowProfileParam, profileData, wellPos, wellData);
        
        % fill data by using horion information
        [newProfileData, minTime] = bsHorizonRestoreData(GPostInvParam, profileData, profile.horizon);

        % show the filled data by using imagesc
        bsShowHorizonedData(GShowProfileParam, ...
            newProfileData, ...
            profile.horizon, minTime, GPostInvParam.dt, profile.name, traceIds, range, GShowProfileParam.dataColorTbl);
        
        % set attribute name of colorbar
        ylabel(colorbar(), attName);
        bsSetDefaultPlotSet(GShowProfileParam.plotParam);
%         ylabel(colorbar('fontsize', GPlotParam.fontsize,'fontweight', GPlotParam.fontweight, 'fontname', GPlotParam.fontname), ...
%                     'Impedance (g/cm^3\cdotkm/s)', 'fontsize', GPlotParam.fontsize,'fontweight', GPlotParam.fontweight, 'fontname', GPlotParam.fontname);
    end
end

function [wellPos, wellData] = bsFindWellLocation(GPostInvParam, wellLogs, inIds, crossIds, horizon, dataIndex, timeIndex, showWellFiltCoef)
    wells = cell2mat(wellLogs);
    wellInIds = [wells.inline];
    wellCrossIds = [wells.crossline];
    sampNum = GPostInvParam.upNum + GPostInvParam.downNum;
    
    wellPos = [];
    wellData = [];
    for i = 1 : length(inIds)
        for j = 1 : length(wellInIds)
            if wellInIds(j) == inIds(i) && wellCrossIds(j) == crossIds(i)
                wellPos = [wellPos, i];
                data = wellLogs{j}.wellLog(:, dataIndex);
                data = bsButtLowPassFilter(data, showWellFiltCoef);
                
                time = wellLogs{j}.wellLog(:, timeIndex);
                dist = horizon(i) - time;
                [~, index] = min(abs(dist));
                iPos = index - GPostInvParam.upNum;
    
                tmp = zeros(sampNum, 1);
%                 t0 = horizon(i) - GPostInvParam.upNum * GPostInvParam.dt;
%                 iPos = round((wellLogs{j}.t0 - t0) / GPostInvParam.dt);
                
                if iPos < 0
                    % start time of origianl welllog data is below the
                    % start time of the profile to be shown
                    sPos = 1;
                    lsPos = abs(iPos) + 1;
                else
                    sPos = iPos + 1;
                    lsPos = 1;
                end

                if iPos + sampNum > length(data)
                    % end time of origianl welllog data is above the
                    % end time of the profile to be shown
                    ePos = length(data);
                    lePos = length(data) - iPos;
                else
                    ePos = iPos+sampNum;
                    lePos = sampNum;
                end
            
                tmp(lsPos : lePos) = data(sPos : ePos);
                tmp(1:lsPos) = data(sPos);
                tmp(lePos:end) = data(ePos);
                
                wellData = [wellData, tmp];
            end
        end
    end
end

function profileData = bsReplaceWellLocationData(GShowProfileParam, profileData, wellPos, wellData)
    [~, trNum] = size(profileData);
    
    if ~isempty(wellPos)
        % replace the data at well location by wellData
        for i = 1 : length(wellPos)
            s = wellPos(i) - GShowProfileParam.showWellOffset;
            if s < 1
                s = 1;
            end
            
            e = wellPos(i) + GShowProfileParam.showWellOffset;
            if e > trNum
                e = trNum;
            end
            
            % replace serveral traces neary by the current well as the
            % corresponding welllog data
            profileData(:, s:e) = repmat(wellData(:, i), [1, e-s+1]);
        end
    end
    
end

function profileData = bsFilterData(profileData, showFiltCoef)
    [sampNum, ~] = size(profileData);
    
    % filter data along with horizon
    if showFiltCoef > 0 && showFiltCoef < 1
        try
            for i = 1 : sampNum
                profileData(i, :) = bsButtLowPassFilter(profileData(i, :), showFiltCoef);
            end
        catch
        end
    end
end

function [newProfileData, minTime] = bsHorizonRestoreData(GPostInvParam, profileData, horizon)
    [sampNum, trNum] = size(profileData);
    
    % fill data based on horizon
    time0 = horizon - GPostInvParam.upNum * GPostInvParam.dt;
    minTime = min(time0) - 5 * GPostInvParam.dt;
    maxTime = max(time0) + sampNum * GPostInvParam.dt + 5 * GPostInvParam.dt;
    newSampNum = round((maxTime - minTime)/GPostInvParam.dt);
    
    poses = round((time0 - minTime)/GPostInvParam.dt);
    newProfileData = zeros(newSampNum, trNum);
    newProfileData(:) = nan;
    
    for i = 1 : trNum
        newProfileData(poses(i):poses(i)+sampNum-1, i) = profileData(:, i);
    end
    
end

function bsShowHorizonedData(GShowProfileParam, profileData, horizon, minTime, dt, name, traceIds, range, colorTbl)
    
    [sampNum, traceNum] = size(profileData);
%     min_val = min(min(profileData));
%     min_val = min_val - abs(min_val)*10;
%     profileData(isnan(profileData )) = min_val;
    profileData(isinf(profileData )) = nan;
    h = imagesc(profileData); hold on;
    set(gca, 'clim', range);
    set(gcf, 'colormap', colorTbl);
    set(h, 'AlphaData', ~isnan(profileData));
    colorbar;
    
    % set labels of x and y axises
    [label, data] = bsGenLabel(minTime, minTime+sampNum*dt, sampNum, GShowProfileParam.yLabelNum);
    data = floor(data / 10) / 100;
    set(gca,'Ytick', label, 'YtickLabel', data);
    
    [label, data] = bsGenLabel(traceIds(1), traceIds(end), traceNum, GShowProfileParam.xLabelNum);
    set(gca,'Xtick', label, 'XtickLabel', data);
        
    % set title
    xlabel('');
    if(~isempty(name))
        title(name); 
    end
    ylabel('Time (s)');
    
%     set(gca, 'ydir', 'reverse');
    set(gca, 'xlim', [traceIds(1), traceIds(end)]);
    
    % show horizon
    if( GShowProfileParam.isShowHorizon)
        y = 1 + round((horizon - minTime) / dt);
%         y = horizon / 1000;
        plot(1:traceNum, y, 'k-','LineWidth', GShowProfileParam.plotParam.linewidth); hold on;
    end
end