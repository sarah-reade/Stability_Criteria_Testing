function [imuData,imuRawData,params,motionTimepoints] = readFilterIMUCsv(imucsvPath, time)
    imuRawData = readtable(imucsvPath, 'Delimiter', ',', 'TextType', 'string');
    imuData = average_sensor_data(imuRawData, time);
    [params,motionTimepoints] = find_slips_and_tips(imuData, 'mag');
end



function [imuData] = average_sensor_data(rawData, time)
    %PLOT_TWO_SENSOR_AVERAGE Align two IMU sensors by timestamp and average signals.

    if ischar(rawData) || isstring(rawData)
        rawData = readtable(rawData, 'Delimiter', ',');
    end

    % --- Ensure time is numeric vector (NOT graphics object) ---
    time = time(:);
    if ~isnumeric(time)
        error('Input "time" must be a numeric vector in seconds.');
    end

    % --- Parse timestamp -> seconds ---
    t = duration(string(rawData.Time_ms), 'InputFormat', 'hh:mm:ss.SSS');
    tSec = seconds(t) + 0.2;

    rawData.TimeSec = round(tSec, 3);

    % --- Split sensors ---
    s1 = rawData(rawData.SensorID == 1, :);
    s2 = rawData(rawData.SensorID == 2, :);

    % --- Aggregate ---
    s1 = groupsummary(s1, "TimeSec", "mean");
    s2 = groupsummary(s2, "TimeSec", "mean");

    % --- Rename variables ---
    s1.Properties.VariableNames(2:end) = strcat(s1.Properties.VariableNames(2:end), "_s1");
    s2.Properties.VariableNames(2:end) = strcat(s2.Properties.VariableNames(2:end), "_s2");

    % --- Align ---
    T = outerjoin(s1, s2, "Keys", "TimeSec", "MergeKeys", true);
    T = sortrows(T, "TimeSec");

    tData = T.TimeSec(:);

    % --- Build averaged signals safely ---
    linX = mean([T.mean_LinX_s1, T.mean_LinX_s2], 2, 'omitnan');
    linY = mean([T.mean_LinY_s1, T.mean_LinY_s2], 2, 'omitnan');
    linZ = mean([T.mean_LinZ_s1, T.mean_LinZ_s2], 2, 'omitnan');

    gyrX = mean([T.mean_GyrX_s1, T.mean_GyrX_s2], 2, 'omitnan');
    gyrY = mean([T.mean_GyrY_s1, T.mean_GyrY_s2], 2, 'omitnan');
    gyrZ = mean([T.mean_GyrZ_s1, T.mean_GyrZ_s2], 2, 'omitnan');

    % --- Ensure numeric for interp1 ---
    tData = double(tData);
    time  = double(time);

    % --- Interpolate onto provided time vector ---
    linX = interp1(tData, linX, time, 'linear', 'extrap');
    linY = interp1(tData, linY, time, 'linear', 'extrap');
    linZ = interp1(tData, linZ, time, 'linear', 'extrap');

    gyrX = interp1(tData, gyrX, time, 'linear', 'extrap');
    gyrY = interp1(tData, gyrY, time, 'linear', 'extrap');
    gyrZ = interp1(tData, gyrZ, time, 'linear', 'extrap');


    imuData = table(time, linX, linY, linZ, gyrX, gyrY, gyrZ, ...
        'VariableNames', {'Time', 'linX', 'linY', 'linZ', 'gyrX', 'gyrY', 'gyrZ'});
end

function [params,timestamps] = find_slips_and_tips(imuData,method)

    % Build a binary motion mask using either component-wise or magnitude thresholds.

    mask = table();
    params.linThreshold = 1.0;
    params.gyrThreshold = 0.06;
    params.refractoryPeriod = 0.8;

    if strcmp(method,'ind')
        %% User thresholds
        linThreshold = params.linThreshold;
        gyrThreshold = params.gyrThreshold;
        refractoryPeriod = params.refractoryPeriod;   % seconds

        mask.Time = imuData.Time;

        mask.LinX = abs(imuData.linX) > linThreshold;
        mask.LinY = abs(imuData.linY) > linThreshold;
        mask.LinZ = abs(imuData.linZ) > linThreshold;

        mask.GyrX = abs(imuData.gyrX) > gyrThreshold;
        mask.GyrY = abs(imuData.gyrY) > gyrThreshold;
        mask.GyrZ = abs(imuData.gyrZ) > gyrThreshold;

    elseif strcmp(method,'mag')

        %% User thresholds
        linThreshold = 0.9;
        gyrThreshold = 0.08;
        refractoryPeriod = 0.8;   % seconds

        mask.Time = imuData.Time;
        mask.Lin = imuData.linX.^2+imuData.linY.^2+imuData.linZ.^2 > linThreshold^2;
        mask.Gyr = imuData.gyrX.^2+imuData.gyrY.^2+imuData.gyrZ.^2 > gyrThreshold^2;

        mask.LinX = mask.Lin;
        mask.LinY = mask.Lin;
        mask.LinZ = mask.Lin;

        mask.GyrX = mask.Gyr;
        mask.GyrY = mask.Gyr;
        mask.GyrZ = mask.Gyr;
    end

    % Find the start of each motion segment and keep the first sample only.
    motion = any(mask{:,2:end}, 2);

    keep = false(height(mask),1);
    endTimeLog = -inf(height(mask),1);

    inMotion = false;
    startMotionIndex = 0;
    endMotionTime = -inf;

    for maskIdx = 1:height(mask)

        t = mask.Time(maskIdx);

        %% ---------------------------
        %% Enter motion
        %% ---------------------------
        if ~inMotion && motion(maskIdx)
            inMotion = true;
            startMotionIndex = maskIdx;
            endMotionTime = -inf;
            continue
        end

        %% ---------------------------
        %% While in motion
        %% ---------------------------
        if inMotion

            % still moving → reset stationary timer
            if motion(maskIdx)
                endMotionTime = -inf;
                continue
            end

            % motion dropped → start stationary timer
            if endMotionTime == -inf
                endMotionTime = t;
                continue
            end

            % check stationary duration
            if (t - endMotionTime) >= refractoryPeriod

                keep(startMotionIndex) = true;

                endTimeLog(startMotionIndex) = endMotionTime;

                % reset state
                inMotion = false;
                startMotionIndex = 0;
                endMotionTime = -inf;
            end
        end
    end

    %% Capture case where motion ends at dataset end
    if inMotion && startMotionIndex > 0
        keep(startMotionIndex) = true;
        endTimeLog(startMotionIndex) = endMotionTime;
    end

    %% Final output
    timestamps = mask(keep,:);
    timestamps.EndTime = endTimeLog(keep);

end