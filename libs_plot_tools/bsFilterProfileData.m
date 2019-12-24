function profileData = bsFilterProfileData(profileData, showFiltCoef)
    [sampNum, ~] = size(profileData);
    
    % filter data along with horizon
    if showFiltCoef > 0 && showFiltCoef < 1
        [b, a] = butter(10, showFiltCoef, 'low');
        try
            for i = 1 : sampNum
                if mod(i, 10000) == 0
                    fprintf('Filtering data progress information: %d/%d...\n', i, sampNum);
                end  
                profileData(i, :) = filtfilt(b, a, profileData(i, :));
%                 profileData(i, :) = bsButtLowPassFilter(profileData(i, :), showFiltCoef);
            end
        catch
        end
    end
end