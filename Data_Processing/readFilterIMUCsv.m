function [imuData,imuRawData] = readFilterIMUCsv(imucsvPath, time)
    imuRawData = readtable(imucsvPath, 'Delimiter', ',', 'TextType', 'string');
    imuData = average_sensor_data(imuRawData, time);
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

