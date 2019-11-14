function [invResults, horizonTimes] = bsPostInvTrueMultiTraces(GPostInvParam, inIds, crossIds, timeLine, methods)
%% inverse multiple traces
% Programmed by: Bin She (Email: bin.stepbystep@gmail.com)
% Programming dates: Nov 2019
% -------------------------------------------------------------------------
%
% Input 
% GPostInvParam     all information of the inverse task
% inIds      	inline ids to be inverted
% crossIds      crossline ids to be inverted
% timeLine      horizon information
% methods       the methods to solve the inverse task
% 
% Output
% invVals       inverted results
% model         the data including d, G, m, m_0 of the inverse task
% outputs       outputs of the iteration process including some intermediate
% results
% -------------------------------------------------------------------------
    
    assert(length(inIds) == length(crossIds), 'The length of inline ids and crossline ids must be the same.');
    nTrace = length(inIds);
    nMethod = size(methods, 1);
    sampNum = GPostInvParam.upNum + GPostInvParam.downNum;
    % save the inverted results
    rangeIn = [min(inIds), max(inIds)];
    rangeCross = [min(crossIds), max(crossIds)];
    
    % horion of the whole volume
    usedTimeLine = timeLine{GPostInvParam.usedTimeLineId};
    % create folder to save the intermediate results
    try
        mkdir([GPostInvParam.modelSavePath,'/models/']);
        mkdir([GPostInvParam.modelSavePath,'/mat_results/']);
        mkdir([GPostInvParam.modelSavePath,'/sgy_results/']);
    catch
    end
    
    invResults = cell(1, nMethod);
    % horizon of given traces
    horizonTimes = bsCalcHorizonTime(usedTimeLine, inIds, crossIds);
                
    for i = 1 : nMethod
        method = methods{i};
        methodName = method.name;
        matFileName = bsGetFileName('mat');
        
        if isfield(method, 'load')
            loadInfo = method.load;
            switch loadInfo.mode
                % load results directly
                case 'mat'
                    % from mat file
                    if isfield(loadInfo, 'fileName') && ~isempty(loadInfo.fileName)
                        load(GPostInvParam.load.fileName);
                    else
                        load(matFileName);
                    end
                    
                    res.source = 'mat';
                case 'segy'
                    % from sgy file
                    poses = bsCalcT0Pos(GPostInvParam, loadInfo.segyInfo, horizonTimes);
                    [data, loadInfo.segyInfo, ~] = bsReadTracesByIds(...
                        loadInfo.fileName, ...
                        loadInfo.segyInfo, ...
                        inIds, crossIds, poses, sampNum);
                    
                    res.source = 'segy';
                    
                otherwise
                    data = bsCallInvFcn();
                    res.source = 'compution';
            end
        else
            data = bsCallInvFcn();
            res.source = 'compution';
        end
        
        res.data = data;
        res.inIds = inIds;
        res.crossIds = crossIds;
        res.horizon = horizonTimes;
        res.name = method.name;
        
        if isfield(method, 'type')
            res.type = method.type;
        else
            res.type = 'IP';
        end
        
        if isfield(method, 'showFiltCoef')
            res.showFiltCoef = method.showFiltCoef;
        else
            res.showFiltCoef = 0;
        end
        
        invResults{i} = res;
        
        % save mat file
        save(matFileName, 'data', 'horizonTimes', 'inIds', 'crossIds', 'GPostInvParam');
        fprintf('Write mat file:%s\n', matFileName);
        
        % save sgy file
        if isfield(method, 'isSaveSegy') && method.isSaveSegy
            segyFileName = bsGetFileName('segy');
            bsWriteInvResultIntoSegyFile(res, ...
                GPostInvParam.postSeisData.segyFileName, ...
                GPostInvParam.postSeisData.segyInfo, ...
                segyFileName, ...
                GPostInvParam.upNum, ...
                GPostInvParam.dt);
            fprintf('Write mat file:%s\n', segyFileName);
        end
    end
    
    function fileName = bsGetFileName(type)
        switch type
            case 'mat'
                fileName = sprintf('%s/mat_results/Ip_%s_inline_[%d_%d]_crossline_[%d_%d].mat', ...
                    GPostInvParam.modelSavePath, methodName, rangeIn(1), rangeIn(2), rangeCross(1), rangeCross(2));
            case 'segy'
                fileName = sprintf('%s/sgy_results/Ip_%s_inline_[%d_%d]_crossline_[%d_%d].sgy', ...
                    GPostInvParam.modelSavePath, methodName, rangeIn(1), rangeIn(2), rangeCross(1), rangeCross(2));
        end
        
    end

    function data = bsCallInvFcn()
        data = zeros(sampNum, nTrace);
        
        % obtain an initial model avoid calculating matrix G again and again.
        % see line 20 of function bsPostPrepareModel for details
        preModel = bsPostPrepareModel(GPostInvParam, inIds(1), crossIds(1), horizonTimes(1), [], []);
            
        if GPostInvParam.isParallel
            % parallel computing
            parfor iTrace = 1 : nTrace

                data(:, iTrace) = bsPostInvOneTrace(GPostInvParam, horizonTimes(iTrace), method, inIds(iTrace), crossIds(iTrace), preModel);
            end
        else
            % non-parallel computing 
            for iTrace = 1 : nTrace
                data(:, iTrace) = bsPostInvOneTrace(GPostInvParam, horizonTimes(iTrace), method, inIds(iTrace), crossIds(iTrace), preModel);
                
                if GPostInvParam.showITraceResult
                    bsShowITrace(model, data(:, iTrace));
                end
            end
        end
    end

    
end

function fileName = bsGetModelFileName(modelSavePath, inId, crossId)

    fileName = sprintf('%s/models/model_inline_%d_crossline_%d.mat', ...
        modelSavePath, inId, crossId);

end

function [idata] = bsPostInvOneTrace(GPostInvParam, horizonTime, method, inId, crossId, preModel)
    fprintf('Solving the trace of inline=%d and crossline=%d by using method %s...\n', ...
        inId, crossId, method.name);


    % create model data
    if GPostInvParam.isReadMode
        % in read mode, model is loaded from local file
        modelFileName = bsGetModelFileName(GPostInvParam.modelSavePath, inId, crossId);
        parLoad(matFileName);
    else
        model = bsPostPrepareModel(GPostInvParam, inId, crossId, horizonTime, [], preModel);
        if GPostInvParam.isSaveMode
            % in save mode, mode should be saved as local file
            modelFileName = bsGetModelFileName(GPostInvParam.modelSavePath, inId, crossId);
            parSave(modelFileName, model);
        end
    end

    [xOut, ~, ~, ~] = bsPostInv1DTrace(model.d, model.G, model.initX, model.Lb, model.Ub, method);                       

    idata = exp(xOut);
end

function [horizonTimes] = bsCalcHorizonTime(usedTimeLine, inIds, crossIds)
    nTrace = length(inIds);
    horizonTimes = zeros(1, nTrace);
    
    for i = 1 : nTrace
        [~, ~, horizonTimes(i)] = bsCalcWellBaseInfo(usedTimeLine, ...
            inIds(i), crossIds(i), 1, 2, 1, 2, 3);
    end
end

function bsShowITrace(model, imp)
    figure(10000);
    subplot(1, 2, 1);
    plot(1:length(model.d), model.d, 'r', 'linewidth', 2);
    set(gca, 'ydir', 'reverse');
    title('Seismic');
    bsSetDefaultPlotSet(bsGetDefaultPlotSet());
    subplot(1, 2, 2);
    plot(1:length(model.initLog), model.initLog, 'g', 'linewidth', 2);
    plot(1:length(imp), imp, 'r', 'linewidth', 2);
    set(gca, 'ydir', 'reverse');
    title('Impedance');
    bsSetDefaultPlotSet(bsGetDefaultPlotSet());
end