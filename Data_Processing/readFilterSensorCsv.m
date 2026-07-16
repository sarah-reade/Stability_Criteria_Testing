function [sampleRate, data, meta] = readFilterSensorCsv(fscsvPath,targetRate)
    
    [sampleRate, rawData, meta] = readSensorCsv(fscsvPath);
    
    t = duration(string(rawData.Time), ...
        'InputFormat', 'hh:mm:ss.SSS');
    
    time = seconds(t);
    
    % Apply rolling-average smoothing and downsample to approximately 10 Hz.
    decFactor = max(1, round(sampleRate / targetRate));
    
    % Smooth then downsample each component. Use movmean if available,
    % otherwise use a convolution fallback for older MATLAB versions.
    win = decFactor;
    useMovmean = exist('movmean', 'file') == 2;
    
    if useMovmean
        fx_s = movmean(rawData.Fx, win);
        fy_s = movmean(rawData.Fy, win);
        fz_s = movmean(rawData.Fz, win);
        tx_s = movmean(rawData.Tx, win);
        ty_s = movmean(rawData.Ty, win);
        tz_s = movmean(rawData.Tz, win);
    else
        kernel = ones(win,1) / win;
        fx_s = conv(rawData.Fx, kernel, 'same');
        fy_s = conv(rawData.Fy, kernel, 'same');
        fz_s = conv(rawData.Fz, kernel, 'same');
        tx_s = conv(rawData.Tx, kernel, 'same');
        ty_s = conv(rawData.Ty, kernel, 'same');
        tz_s = conv(rawData.Tz, kernel, 'same');
    end
    
    idx = 1:decFactor:height(rawData);
    data.time = time(idx);
    nZero = 10;
    data.fx_ds = fx_s(idx)-mean(fx_s(1:nZero));
    data.fy_ds = (fy_s(idx))-mean(fy_s(1:nZero));
    data.fz_ds = -((fz_s(idx))-mean(fz_s(1:nZero)));
    data.tx_ds = tx_s(idx)-mean(tx_s(1:nZero));
    data.ty_ds = ty_s(idx)-mean(ty_s(1:nZero));
    data.tz_ds = -(tz_s(idx)-mean(tz_s(1:nZero)));

    
    % Effective sample rate after decimation (used for derivative scaling).
    sampleRate = sampleRate / decFactor;
end

function [sampleRate, data, meta] = readSensorCsv(fscsvPath)
    % Read ATI-style CSV: metadata header followed by numeric data rows.
    fileText = fileread(fscsvPath);
    fileLines = splitlines(string(fileText));

    sampleRate = 1;
    meta = struct('startTime', "Unknown", 'forceUnits', "Unknown", 'forceCountsPerUnit', "Unknown", 'torqueUnits', "Unknown", 'torqueCountsPerUnit', "Unknown");

    rateLineIndex = find(contains(fileLines, 'RDT Sample Rate'), 1, 'first');
    if ~isempty(rateLineIndex)
        rateMatch = regexp(fileLines(rateLineIndex), 'RDT Sample Rate:\s*([0-9.]+)', 'tokens', 'once');
        if ~isempty(rateMatch)
            sampleRate = str2double(rateMatch{1});
        end
    end

    % Pull key metadata fields from header.
    meta.startTime = extractHeaderValue(fileLines, 'Start Time:');
    meta.forceUnits = extractHeaderValue(fileLines, 'Force Units:');
    meta.forceCountsPerUnit = extractHeaderValue(fileLines, 'Counts per Unit Force:');
    meta.torqueUnits = extractHeaderValue(fileLines, 'Torque Units:');
    meta.torqueCountsPerUnit = extractHeaderValue(fileLines, 'Counts per Unit Torque:');

    headerLineIndex = find(contains(fileLines, 'Status (hex)'), 1, 'first');
    if isempty(headerLineIndex)
        error('Could not locate the data header in %s.', fscsvPath);
    end

    dataLines = fileLines(headerLineIndex + 1:end);
    dataLines = dataLines(strlength(strtrim(dataLines)) > 0);

    status = strings(0, 1);
    rdtSequence = zeros(0, 1);
    ftSequence = zeros(0, 1);
    fx = zeros(0, 1);
    fy = zeros(0, 1);
    fz = zeros(0, 1);
    tx = zeros(0, 1);
    ty = zeros(0, 1);
    tz = zeros(0, 1);
    Time = strings(0, 1);

    for i = 1:numel(dataLines)
        % Data rows are comma-separated and may include trailing empty tokens.
        parts = strtrim(split(dataLines(i), ','));
        parts = parts(strlength(parts) > 0);

        if numel(parts) < 10
            continue;
        end

        status(end + 1, 1) = parts(1); %#ok<AGROW>
        rdtSequence(end + 1, 1) = str2double(parts(2)); %#ok<AGROW>
        ftSequence(end + 1, 1) = str2double(parts(3)); %#ok<AGROW>
        fx(end + 1, 1) = str2double(parts(4)); %#ok<AGROW>
        fy(end + 1, 1) = str2double(parts(5)); %#ok<AGROW>
        fz(end + 1, 1) = str2double(parts(6)); %#ok<AGROW>
        tx(end + 1, 1) = str2double(parts(7)); %#ok<AGROW>
        ty(end + 1, 1) = str2double(parts(8)); %#ok<AGROW>
        tz(end + 1, 1) = str2double(parts(9)); %#ok<AGROW>
        Time(end + 1, 1) = parts(10); %#ok<AGROW>
    end

    data = table(status, rdtSequence, ftSequence, fx, fy, fz, tx, ty, tz, Time, ...
        'VariableNames', {'Status', 'RDTSequence', 'FTSequence', 'Fx', 'Fy', 'Fz', 'Tx', 'Ty', 'Tz', 'Time'});
        
end

function valueText = extractHeaderValue(fileLines, prefixText)
% Return header value text after `prefixText`, or "Unknown" when missing.
lineIndex = find(startsWith(fileLines, prefixText), 1, 'first');
if isempty(lineIndex)
    valueText = "Unknown";
else
    valueText = strtrim(extractAfter(fileLines(lineIndex), prefixText));
end
end