function plot_force_Sensor()
%PLOT_FORCE_SENSOR Select a registered force sensor dataset and plot it.

% Resolve data paths relative to this script so the function is portable.
scriptDir = fileparts(mfilename('fullpath'));
dataDir = fullfile(scriptDir, '..', 'Force_Sensor_Data');
dataRegPath = fullfile(dataDir, 'Data_Reg.csv');

if ~isfile(dataRegPath)
    errordlg(sprintf('Could not find registration file:\n%s', dataRegPath), 'Registration File Missing');
    return;
end

try
    % Preserve original CSV column names (including spaces) for direct access.
    dataReg = readtable(dataRegPath, 'TextType', 'string', 'PreserveVariableNames', true);
catch ME
    errordlg(sprintf('Failed to read Data_Reg.csv\n\n%s', ME.message), 'File Read Error');
    return;
end

requiredCols = {'ID', 'Force Sensor Filename', 'IMU Filename', 'Configuration', 'Angle from Gravity', 'EM Config'};
missingCols = requiredCols(~ismember(requiredCols, dataReg.Properties.VariableNames));
if ~isempty(missingCols)
    errordlg(sprintf('The following required columns are missing:\n\n%s', strjoin(missingCols, ', ')), 'Invalid Registration File');
    return;
end

% Keep only rows that can be mapped to a dataset and have EM config present.
validRows = ~ismissing(dataReg.ID) & ~ismissing(dataReg.('Force Sensor Filename')) & strlength(dataReg.('Force Sensor Filename')) > 0 & ~ismissing(dataReg.('IMU Filename')) & strlength(dataReg.('IMU Filename')) > 0 & ~ismissing(dataReg.('EM Config')) & strlength(dataReg.('EM Config')) > 0;
dataReg = dataReg(validRows, :);

if height(dataReg) == 0
    errordlg('No valid entries exist in Data_Reg.csv.', 'No Data Available');
    return;
end

displayItems = buildDisplayItems(dataReg);
infoItems = buildInfoItems(dataReg);
selectedIdxs = runSelectionDialog(displayItems, infoItems);

if isempty(selectedIdxs)
    return;
end

for k = 1:numel(selectedIdxs)

    selectedIdx = selectedIdxs(k);   % force scalar index
    selectedRecord = dataReg(selectedIdx, :);
    fscsvFilename = string(selectedRecord.('Force Sensor Filename')) + ".csv";
    fscsvPath = fullfile(dataDir, fscsvFilename);
    imucsvFilename = string(selectedRecord.('IMU Filename')) + ".csv";
    imucsvPath = fullfile(dataDir, imucsvFilename);
    
    if ~isfile(fscsvPath)
        errordlg(sprintf('The selected CSV file does not exist:\n\n%s', fscsvFilename), 'Missing CSV File');
        return;
    elseif ~isfile(imucsvPath)
        errordlg(sprintf('The selected CSV file does not exist:\n\n%s', imucsvFilename), 'Missing CSV File');
        return;
    end
    
    try
        % Parse sample rate, sensor channels, and metadata from selected CSV.
        [sampleRate, sensorData, csvMeta] = readSensorCsv(fscsvPath);
    catch ME
        errordlg(sprintf('Failed to load CSV:\n\n%s', ME.message), 'CSV Read Error');
        return;
    end
    
    t = duration(string(sensorData.Time), ...
        'InputFormat', 'hh:mm:ss.SSS');
    
    time = seconds(t);
    
    % Apply rolling-average smoothing and downsample to approximately 10 Hz.
    targetRate = 10; % desired display rate (Hz)
    decFactor = max(1, round(sampleRate / targetRate));
    
    % Smooth then downsample each component. Use movmean if available,
    % otherwise use a convolution fallback for older MATLAB versions.
    win = decFactor;
    useMovmean = exist('movmean', 'file') == 2;
    
    if useMovmean
        fx_s = movmean(sensorData.Fx, win);
        fy_s = movmean(sensorData.Fy, win);
        fz_s = movmean(sensorData.Fz, win);
        tx_s = movmean(sensorData.Tx, win);
        ty_s = movmean(sensorData.Ty, win);
        tz_s = movmean(sensorData.Tz, win);
    else
        k = ones(win,1) / win;
        fx_s = conv(sensorData.Fx, k, 'same');
        fy_s = conv(sensorData.Fy, k, 'same');
        fz_s = conv(sensorData.Fz, k, 'same');
        tx_s = conv(sensorData.Tx, k, 'same');
        ty_s = conv(sensorData.Ty, k, 'same');
        tz_s = conv(sensorData.Tz, k, 'same');
    end
    
    idx = 1:decFactor:height(sensorData);
    time = time(idx);
    fx_ds = (fx_s(idx))-fx_s(2);
    fy_ds = (fy_s(idx))-fy_s(2);
    fz_ds = -((fz_s(idx))-fz_s(2));
    tx_ds = tx_s(idx)-tx_s(2);
    ty_ds = ty_s(idx)-ty_s(2);
    tz_ds = -(tz_s(idx)-tz_s(2));
    
    % Effective sample rate after decimation (used for derivative scaling).
    sampleRate = sampleRate / decFactor;
    
    force = [fx_ds, fy_ds, fz_ds];
    torque = [tx_ds, ty_ds, tz_ds];
    
    % % Force normalization (remove initial offset)
    % force0 = force(1,:);              % [fx0 fy0 fz0]
    % force = force - force0;
    % 
    % % Torque normalization
    % torque0 = torque(1,:);            % [tx0 ty0 tz0]
    % torque = torque - torque0;
    
    infoText = buildInfoBoxString(selectedRecord, csvMeta, sampleRate, height(sensorData));
    
    % Layout: info panel, force components, torque components, derivative panel.
    fig = figure('Color', 'w', 'Name', sprintf('Force/Torque Plot - %s', fscsvFilename));
    tl = tiledlayout(fig, 6, 1, ...
        'TileSpacing', 'compact', ...
        'Padding', 'compact');
    
    infoAx = nexttile;
    axis(infoAx, 'off');
    text(infoAx, 0.01, 0.5, infoText, ...
        'Units', 'normalized', ...
        'Interpreter', 'none', ...
        'FontName', 'Consolas', ...
        'FontSize', 10, ...
        'VerticalAlignment', 'middle', ...
        'BackgroundColor', [0.96 0.98 1.0], ...
        'EdgeColor', [0.55 0.65 0.8], ...
        'Margin', 10);
    
    imuRawData = readtable(imucsvPath, 'Delimiter', ',', 'TextType', 'string');
    imuData = plot_two_sensor_average(imuRawData, time);
    [params,motionTimepoints] = find_slips_and_tips(imuData, 'mag');
    
    scriptParameters = params;
    scriptParameters.hz = targetRate;
    
    wrenchData = table(fx_ds, fy_ds, fz_ds, tx_ds, ty_ds, tz_ds, time, ...
        'VariableNames', {'Fx', 'Fy', 'Fz', 'Tx', 'Ty', 'Tz', 'Time'});
    wrenchTimepoints = find_wrench(motionTimepoints,wrenchData);
    
    
    ax = nexttile;
    plot(ax, time, force, 'LineWidth', 1.5);
    grid(ax, 'on');
    xlabel(ax, 'Time (s)');
    ylabel(ax, 'Force (N)');
    title(ax, 'Force Components', 'Interpreter', 'none');
    legend(ax, {'F_x', 'F_y', 'F_z'}, 'Location', 'best');
    hold(ax, 'on');
    
    ax = nexttile;
    plot(ax, time, torque, 'LineWidth', 1.5);
    grid(ax, 'on');
    xlabel(ax, 'Time (s)');
    ylabel(ax, 'Torque (Nm)');
    title(ax, 'Torque Components', 'Interpreter', 'none');
    legend(ax, {'T_x', 'T_y', 'T_z'}, 'Location', 'best');
    hold(ax, 'on');
    
    axs = findall(gcf, 'Type', 'axes');
    
    parameters = get_params(selectedRecord.('Configuration'),string(selectedRecord.('Angle from Gravity')),selectedRecord.('EM Config'));
    
    wrench = [force,torque];
    gamma_cnstr = zeros(height(wrench),1);
    nc = numel(parameters.c);
    variables = zeros(height(wrench),nc*6 + 1);
    beta = zeros(height(wrench),1);
    all_beta = zeros(height(wrench),4,nc);
    loop_time = zeros(height(wrench),1);
    for k = 1:height(wrench)
        tStart = tic;
        [variables(k,:),gamma_cnstr(k)] = obtain_gamma_cnstr(parameters,wrench(k,:)');
        [beta(k),all_beta(k,:,:)] = get_beta(variables(k,:),parameters);
        loop_time(k) = toc(tStart);
    end
    
    datetime_string = csvMeta.startTime;
    datetime_string = replace(datetime_string, [" ", "/", ":"], "_");
    outDir = make_directory(datetime_string);
    
    
    export_sensor_dataset_csv( outDir, ...
       time,wrenchData,imuData,variables,beta,motionTimepoints,loop_time);
    
    save_meta_data(outDir, 'metaData.txt', selectedRecord,parameters,scriptParameters)
    
    
    isNeg = beta < 50;
    
    % Find rising/falling edges
    d = diff([false; isNeg; false]);
    startIdx = find(d == 1)-1;
    endIdx   = find(d == -1);
    
    negSegments = [startIdx, endIdx];
    negTimeSegments = [time(negSegments(:,1)), time(negSegments(:,2))];
    
    ax = nexttile;
    hold(ax,"on");
    grid(ax, 'on');
    
    % plot(ax, time, gamma_cnstr, 'LineWidth', 1.5);
    plot(ax, time, beta, 'LineWidth', 1.5);
    xlabel(ax, 'Time (s)');
    ylabel(ax, 'value');
    title(ax, 'gamma_cnstr', 'Interpreter', 'none');
    plot_background(ax,negTimeSegments);
    % legend(ax, {'gamma', 'beta'}, 'Location', 'best');
    
        
    plotMotionPoints(ax,motionTimepoints);
    
    for k = 1:numel(axs)
        if axs(k) == infoAx
            continue
        end
        
        plotMotionPoints(axs(k),motionTimepoints);
        plot_background(axs(k),negTimeSegments);
    end
        
    
    fig2 = plotOptimVariables(time, variables, nc, all_beta, negTimeSegments,motionTimepoints);
    
    % Make figure 1 full screen
    set(fig, 'Units', 'normalized', 'OuterPosition', [0 0 1 1]);
    drawnow;
    
    savefig(fig, fullfile(outDir, "fig1.fig"));
    print(fig, fullfile(outDir, "fig1.svg"), "-dsvg");
    
    % Make figure 2 full screen
    set(fig2, 'Units', 'normalized', 'OuterPosition', [0 0 1 1]);
    drawnow;
    
    savefig(fig2, fullfile(outDir, "fig2.fig"));
    print(fig2, fullfile(outDir, "fig2.svg"), "-dsvg");
    
    sgtitle(sprintf('Sensor data: %s | %s', fscsvFilename, imucsvFilename), 'Interpreter', 'none');
end
end

function plot_background(ax,negTimeSegments)
    yl = ylim(ax);
    
    hold(ax, 'on');
    
    for i = 1:size(negTimeSegments,1)
        x1 = negTimeSegments(i,1);
        x2 = negTimeSegments(i,2);
    
        patch(ax, ...
            [x1 x2 x2 x1], ...
            [yl(1) yl(1) yl(2) yl(2)], ...
            'r', ...
            'FaceAlpha', 0.15, ...
            'EdgeColor', 'none', ...
            'HandleVisibility', 'off');
    end
    
    uistack(ax.Children, 'bottom'); % keep shading behind lines
end

function displayItems = buildDisplayItems(dataReg)
% Build human-readable dropdown labels for each registration row.
displayItems = strings(height(dataReg), 1);

for k = 1:height(dataReg)
    idText = string(dataReg.ID(k));
    configText = string(dataReg.Configuration(k));
    angleText = string(dataReg.('Angle from Gravity')(k));
    emText = string(dataReg.('EM Config')(k));

    displayItems(k) = sprintf('ID: %s | Configuration: %s | Angle: %s | EM: %s', idText, configText, angleText, emText);
end
end

function infoItems = buildInfoItems(dataReg)
% Build auxiliary info (date + notes) aligned with displayItems indexing.

infoItems = strings(height(dataReg), 1);

for k = 1:height(dataReg)

    % Extract date-like prefix from Force Sensor Filename
    forceFile = string(dataReg.('Force Sensor Filename')(k));

    % Assumes format: YYYY-MM-DD_HH-MM-SS_...
    dateToken = extractBefore(forceFile, "_");

    % Convert to datetime and reformat
    dt = datetime(dateToken, 'InputFormat', 'yyyy-MM-dd');
    dateText = "Date: " + string(dt, 'dd/MM/yyyy');

    % Notes
    notesText = string(dataReg.Notes(k));
    if strlength(strtrim(notesText)) == 0
        notesText = "Notes: (none)";
    else
        notesText = "Notes: " + notesText;
    end

    infoItems(k) = dateText + " | " + notesText;
end

end

function selectedIdx = runSelectionDialog(displayItems, infoItems)
% Multi-selection GUI selector (returns vector of indices or [])

selectedIdx = [];

width = 900;
height = 520;

selectionFig = uifigure('Name', 'Force Sensor Dataset Selection', ...
    'Position', [500 400 width height]);

selectionFig.UserData = [];

selectionFig.CloseRequestFcn = @cancelSelection;

uilabel(selectionFig, ...
    'Position', [20 height-40 300 30], ...
    'Text', 'Select Dataset(s):', ...
    'FontSize', 14);

infoLabel = uilabel(selectionFig, ...
    'Position', [220 height-40 660 30], ...
    'Text', infoItems(1), ...
    'FontSize', 12, ...
    'HorizontalAlignment', 'right');

% --- MULTI-SELECT TABLE (replaces dropdown) ---
tbl = uitable(selectionFig, ...
    'Position', [20 80 width-40 height-140], ...
    'Data', displayItems(:), ...
    'ColumnName', {'Dataset'}, ...
    'ColumnEditable', false, ...
    'CellSelectionCallback', @updateSelection);

selectedRows = [];

uibutton(selectionFig, 'Text', 'Load Dataset(s)', ...
    'Position', [340 25 220 34], ...
    'ButtonPushedFcn', @loadSelection);

uibutton(selectionFig, 'Text', 'Cancel', ...
    'Position', [580 25 120 34], ...
    'ButtonPushedFcn', @cancelSelection);

uiwait(selectionFig);

if isvalid(selectionFig)
    selectedIdx = selectionFig.UserData;
    delete(selectionFig);
end

    function updateSelection(~, event)
        if isempty(event.Indices)
            return;
        end
        selectedRows = unique(event.Indices(:,1));
        idx = selectedRows(1);
        infoLabel.Text = infoItems(idx);
    end

    function loadSelection(~, ~)
        selectionFig.UserData = selectedRows;
        uiresume(selectionFig);
    end

    function cancelSelection(~, ~)
        selectionFig.UserData = [];
        uiresume(selectionFig);
    end
end

function infoText = buildInfoBoxString(regRow, csvMeta, sampleRate, sampleCount)
% Compose metadata shown in the top information panel.
if ismember('EM Config', regRow.Properties.VariableNames)
    emText = char(string(regRow.('EM Config')));
else
    emText = 'Not provided';
end

infoText = sprintf([ ...
    'Configuration: %s\n' ...
    'Angle from Gravity: %s\n' ...
    'EM Config: %s\n' ...
    'Start Time: %s\n' ...
    'Sample Rate: %.0f Hz\n' ...
    'Samples: %d\n' ...
    'Force Units: %s | Torque Units: %s\n' ...
    'Force Counts/Unit: %s | Torque Counts/Unit: %s'], ...
    char(string(regRow.Configuration)), ...
    char(string(regRow.('Angle from Gravity'))), ...
    emText, ...
    char(csvMeta.startTime), ...
    sampleRate, ...
    sampleCount, ...
    char(csvMeta.forceUnits), ...
    char(csvMeta.torqueUnits), ...
    char(csvMeta.forceCountsPerUnit), ...
    char(csvMeta.torqueCountsPerUnit));
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

    if numel(parts) < 9
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

function [imuData] = plot_two_sensor_average(rawData, time)


%PLOT_TWO_SENSOR_AVERAGE Align two sensors by timestamp and average signals

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
tSec = seconds(t);

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

% --- Plot ---
nexttile;
plot(time, [linX linY linZ], 'LineWidth', 1.5);
grid on;
xlabel('Time (s)');
ylabel('Linear Acceleration');
title('Averaged Linear Acceleration (Sensor 1 & 2)');
legend('LinX','LinY','LinZ', 'Location', 'best');

nexttile;
plot(time, [gyrX gyrY gyrZ], 'LineWidth', 1.5);
grid on;
xlabel('Time (s)');
ylabel('Gyroscope');
title('Averaged Gyroscope (Sensor 1 & 2)');
legend('GyrX','GyrY','GyrZ', 'Location', 'best');

end

function [params,timestamps] = find_slips_and_tips(imuData,method)

    %% Build binary mask

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

    %% Find start of motion
    motion = any(mask{:,2:end}, 2);

    keep = false(height(mask),1);
    endTimeLog = -inf(height(mask),1);

    inMotion = false;
    startMotionIndex = 0;
    endMotionTime = -inf;

    for k = 1:height(mask)

        t = mask.Time(k);

        %% ---------------------------
        %% Enter motion
        %% ---------------------------
        if ~inMotion && motion(k)
            inMotion = true;
            startMotionIndex = k;
            endMotionTime = -inf;
            continue
        end

        %% ---------------------------
        %% While in motion
        %% ---------------------------
        if inMotion

            % still moving → reset stationary timer
            if motion(k)
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

    


    % %% ================= DEBUG VISUALISATION =================

    % figure('Color','w','Name','IMU Event Mask Debug');

    % tiledlayout(3,1,'TileSpacing','compact','Padding','compact');

    % %% -------------------------------------------------------
    % %% 1. Raw signals + thresholds
    % %% -------------------------------------------------------
    % nexttile;
    % linMag = sqrt(imuData.linX.^2+imuData.linY.^2+imuData.linZ.^2);
    % gyrMag = sqrt(imuData.gyrX.^2+imuData.gyrY.^2+imuData.gyrZ.^2);
    % plot(imuData.Time, linMag, 'b'); hold on;
    % plot(imuData.Time, gyrMag, 'r'); hold on;
    % % plot(imuData.Time, imuData.linX, 'b'); hold on;
    % % plot(imuData.Time, imuData.linY, 'b--');
    % % plot(imuData.Time, imuData.linZ, 'b:');

    % % plot(imuData.Time, imuData.gyrX, 'r');
    % % plot(imuData.Time, imuData.gyrY, 'r--');
    % % plot(imuData.Time, imuData.gyrZ, 'r:');

    % yline(linThreshold,'b','LineWidth',1);
    % yline(-linThreshold,'b','LineWidth',1);

    % yline(gyrThreshold,'r','LineWidth',1);
    % yline(-gyrThreshold,'r','LineWidth',1);

    % grid on;
    % title('Raw IMU Signals + Thresholds');
    % xlabel('Time (s)');
    % ylabel('Signal');

    % %legend({'LinX','LinY','LinZ','GyrX','GyrY','GyrZ'},'Location','bestoutside');
    % legend({'LinMag','GyrMag'},'Location','bestoutside');

    % %% -------------------------------------------------------
    % %% 2. Binary mask evolution
    % %% -------------------------------------------------------
    % nexttile;

    % maskMat = table2array(mask(:,2:end));

    % imagesc(imuData.Time, 1:6, maskMat');
    % colormap(gray);
    % clim([0 1]);

    % yticks(1:6);
    % yticklabels({'LinX','LinY','LinZ','GyrX','GyrY','GyrZ'});

    % xlabel('Time (s)');
    % ylabel('Channel');
    % title('Binary Threshold Mask (1 = exceeded)');

    % %% -------------------------------------------------------
    % %% 3. After refractory filtering
    % %% -------------------------------------------------------
    % nexttile;

    % hold on;

    % % show all detected events lightly
    % scatter(mask.Time, ones(height(mask),1), 10, [0.7 0.7 0.7], 'filled');

    % % show accepted events strongly
    % scatter(timestamps.Time, ones(height(timestamps),1), 40, 'r', 'filled');

    % yticks([]);
    % xlabel('Time (s)');
    % title('Refractory Filtering Result (grey = rejected, red = kept)');
    % grid on;

end

function wrenchTimestamps = find_wrench(stTimestamps, wrenchData)

    n = height(stTimestamps);

    wrenchTimestamps = table();

    wrenchTimestamps.Time = stTimestamps.Time;

    wrenchTimestamps.Fx = zeros(n,1);
    wrenchTimestamps.Fy = zeros(n,1);
    wrenchTimestamps.Fz = zeros(n,1);
    wrenchTimestamps.Tx = zeros(n,1);
    wrenchTimestamps.Ty = zeros(n,1);
    wrenchTimestamps.Tz = zeros(n,1);

    for k = 1:n

        t = stTimestamps.Time(k);

        % nearest time match
        [~, idx] = min(abs(wrenchData.Time - t));

        wrenchTimestamps.Fx(k) = wrenchData.Fx(idx);
        wrenchTimestamps.Fy(k) = wrenchData.Fy(idx);
        wrenchTimestamps.Fz(k) = wrenchData.Fz(idx);

        wrenchTimestamps.Tx(k) = wrenchData.Tx(idx);
        wrenchTimestamps.Ty(k) = wrenchData.Ty(idx);
        wrenchTimestamps.Tz(k) = wrenchData.Tz(idx);

    end

    % figure('Color','w');

    % tiledlayout(2,1,'TileSpacing','compact','Padding','compact');

    % %% --- Forces ---
    % nexttile;
    % hold on;

    % scatter(wrenchTimestamps.Time, wrenchTimestamps.Fx, 25, 'filled');
    % scatter(wrenchTimestamps.Time, wrenchTimestamps.Fy, 25, 'filled');
    % scatter(wrenchTimestamps.Time, wrenchTimestamps.Fz, 25, 'filled');

    % grid on;
    % xlabel('Time (s)');
    % ylabel('Force (N)');
    % title('Force at Motion Events');

    % legend({'Fx','Fy','Fz'}, 'Location','best');

    % %% --- Torques ---
    % nexttile;
    % hold on;

    % scatter(wrenchTimestamps.Time, wrenchTimestamps.Tx, 25, 'filled');
    % scatter(wrenchTimestamps.Time, wrenchTimestamps.Ty, 25, 'filled');
    % scatter(wrenchTimestamps.Time, wrenchTimestamps.Tz, 25, 'filled');

    % grid on;
    % xlabel('Time (s)');
    % ylabel('Torque (Nm)');
    % title('Torque at Motion Events');

    % legend({'Tx','Ty','Tz'}, 'Location','best');

end

function out = parseOnOff(s)
    parts = split(string(s), "-");
    out = double(parts == "on");
end

function GMatrix = getGMatrix(trans,rotMat)
    % Ensure correct shapes
    trans = trans(:);

    % Skew-symmetric matrix of translation vector
    p_hat = [    0      -trans(3)  trans(2);
            trans(3)    0       -trans(1);
            -trans(2)  trans(1)     0     ];

    % Wrench transformation matrix (force-moment transformation)
    GMatrix = [rotMat, zeros(3,3);
            p_hat * rotMat, rotMat];
end

function parameters = get_params(config,angle,emconfig)
    %% Set Contact Variables
    % these are different for each configuration and angle to gravity, but include:
    % g The gravity vector relative to the force sensor
    % Gg Transformation matrix from gravity wrench to sensor wrench
    % m mass of the system
    % Fd,i Nominal magnetic adhesion force.
    % si ∈ [0, 1] Surface magnetic permeability coefficient.
    % ci ∈ [0, 1] Contact confidence coefficient.
    % Gi Transformation matrix from contact wrench to sensor wrench.
    % µi Coefficient of friction.
    % ri Contact support radius.
    % reff,i Effective frictional-torque radius.
    
    persistent CACHE

    key = sprintf('%s_%s_%s', config, angle, string(emconfig));

    if isempty(CACHE)
        CACHE = containers.Map;
    end

    if isKey(CACHE, key)
        parameters = CACHE(key);
        return;
    end

    % disp('--- Debug Inputs ---');

    % fprintf('config: %s | class: %s | size: %s\n', ...
    %     string(config), class(config), mat2str(size(config)));

    % fprintf('angle: %s | class: %s | size: %s\n', ...
    %     string(angle), class(angle), mat2str(size(angle)));

    % fprintf('emconfig: %s | class: %s | size: %s\n', ...
    %     string(emconfig), class(emconfig), mat2str(size(emconfig)));
    
    if ~ismember(config, {'flat','RA','single'})
        error('Invalid config "%s". Must be one of: flat, RA, single.', config);
    end

    parameters.mu = 1.0;
    r = 0.077;
    parameters.r_x = r/6;
    parameters.r_y = r/18;
    parameters.reff = r;

    m_em = 0.4;
    m_pm = 0.002*19;
    m_force = 0.09;
    m_EM_plate = 0.275;
    m_EM_Interface_Single = 0.275;
    m_EM_Interface_Long = 0.166;
    m_Flat_Plate = 0.197;
    m_RA_Plate = 0.272;

    Gg = zeros(6,6);

    c = 1.0;
    p_magnet = 450;
    em_magnet = 1400;
    steel_s = 1.0;
    floor_s = 0.0;

    if ismember(config, {'flat','RA'})
        % Contact confidence
        parameters.c = [c,c]; % Account for lack of coverage

        % Calculate Adhesion Force
        mask = parseOnOff(emconfig);
        parameters.Fd = [p_magnet,p_magnet] + mask'.*[em_magnet,em_magnet];
    end
    
    if strcmp(config,'single')
        % Contact confidence
        parameters.c = [c]; % Account for lack of coverage

        % Calculate Adhesion Force
        mask = double(emconfig == "on");
        parameters.Fd = [p_magnet] + mask*[1400];
        
        % Set surface magnetic permeability
        if ~strcmp(angle,'0')
            parameters.s = [steel_s];
        else
            parameters.s = zeros(1,1);
        end 

        % Calculate G_i Wrench Transormation Matrix
        parameters.G = cell(1,1);
        trans = [0 0 70.533]*0.001;
        rot = eye(3);
        parameters.G{1} = getGMatrix(trans,rot);

        % Calculate mass
        parameters.m = m_EM_Interface_Single + m_EM_plate + m_force + m_pm + m_em;

        % CoM to Sensor Wrench Transormation Matrix
        trans = [0.0 0.0 47.0220]*0.001;
        rot = eye(3);
        Gg = getGMatrix(trans,rot);
        
    
    elseif strcmp(config,'flat')
        % Set surface magnetic permeability
        if ~strcmp(angle,'0')
            parameters.s = [steel_s,steel_s];
        else
            parameters.s = zeros(2,1);
        end 

        % Calculate G_i Wrench Transormation Matrix
        parameters.G = cell(2,1);

        trans = [77.1820; -63.8840; 69.0410]*0.001;
        rot = [0.6428  -0.7660  0.0000;
            0.7660   0.6428  0.0000;
            0.0000   0.0000  1.0000];

        parameters.G{1} = getGMatrix(trans, rot);

        trans = [-271.0299; 220.6576; 68.5300]*0.001;
        rot = [0.6428  -0.7660  0.0000;
            0.7660   0.6428  0.0000;
            0.0000   0.0000  1.0000];

        parameters.G{2} = getGMatrix(trans, rot);

        % Calculate mass
        parameters.m = m_EM_Interface_Long*2 + m_Flat_Plate + m_EM_plate + m_force + m_pm + m_em;

        % CoM to Sensor Wrench Transormation Matrix
        trans = [-97.8237 82.0855 68.5300]*0.001;
        rot = eye(3);
        Gg = getGMatrix(trans,rot);

    elseif strcmp(config,'RA')
        % Set surface magnetic permeability
        if ~strcmp(angle,'0')
            parameters.s = [steel_s,steel_s];
        else
            parameters.s = [0.0,steel_s];
        end 
        
        % Calculate G_i Wrench Transormation Matrix
        parameters.G = cell(2,1);

        trans = [77.1820; -63.8840; 69.0410]*0.001;
        rot = [0.6428  -0.7660  0.0000;
            0.7660   0.6428  0.0000;
            0.0000   0.0000  1.0000];

        parameters.G{1} = getGMatrix(trans, rot);

        trans = [-165.2400; 138.6500; -246.4600]*0.001;
        rot = [0.6428  0.0000  -0.7660;
            0.7660  0.0000  0.6428;
            0.0000  -1.0000  0.0000];

        parameters.G{2} = getGMatrix(trans, rot);

        % Calculate mass
        parameters.m = m_EM_Interface_Long*2 + m_RA_Plate + m_EM_plate + m_force + m_pm + m_em;

        % CoM to Sensor Wrench Transormation Matrix
        trans = [-44.0290 37.3830 -88.7095]*0.001;
        rot = eye(3);
        Gg = getGMatrix(trans,rot);
    end
    
    g_base = [0.0,0.0,-9.81];
        

    if strcmp(angle,'0')
        g = rotateVector(g_base,pi,'x');
    elseif strcmp(angle,'90')
        g = rotateVector(g_base,pi/2,'x');
        g = rotateVector(g,deg2rad(-40),'z'); % rotate to match sensor frame in x and y
    elseif strcmp(angle,'90V')
        g = rotateVector(g_base,pi/2,'x');
        g = rotateVector(g,deg2rad(-130),'z'); % rotate to match sensor frame in x and y
    else
        g = g_base;
    end 
    
    g = [g',0,0,0]

    parameters.gravity = Gg*g.';

    %print_parameters(parameters);
    
    
end

function print_parameters(p)
%% PRINT_PARAMETERS Pretty-print parameters struct

    fprintf('\n================ PARAMETERS ================\n');

    % --- Scalars ---
    print_field('mu', p.mu);
    print_field('r_x', p.r_x);
    print_field('r_y', p.r_y);
    print_field('reff', p.reff);
    print_field('m', p.m);

    % --- Vectors ---
    if isfield(p, 'c')
        fprintf('c:\n');
        disp(p.c);
    end

    if isfield(p, 'Fd')
        fprintf('Fd:\n');
        disp(p.Fd);
    end

    if isfield(p, 's')
        fprintf('s:\n');
        disp(p.s);
    end

    % --- Gravity ---
    if isfield(p, 'gravity')
        fprintf('gravity (sensor frame wrench):\n');
        disp(p.gravity);
    end

    % --- Transformation matrices ---
    if isfield(p, 'G')
        fprintf('G (contact wrench transforms):\n');
        for i = 1:numel(p.G)
            fprintf('  G{%d}:\n', i);
            disp(p.G{i});
        end
    end

    fprintf('===========================================\n\n');

end

%% Helper for scalar printing
function print_field(name, value)
    if isnumeric(value)
        if isscalar(value)
            fprintf('%s: %.6f\n', name, value);
        else
            fprintf('%s:\n', name);
            disp(value);
        end
    else
        fprintf('%s:\n', name);
        disp(value);
    end
end

function [x,beta] = obtain_gamma_cnstr(parameters,wrench)
    
    %% Add Gravity 
    sensor_wrench = wrench + parameters.gravity;
    %%sensor_wrench = wrench;

    %% Solve optimisation problem
    [x,beta] = solveSOCP(parameters,sensor_wrench);


end


function [x,beta] = solveSOCP(parameters, wrench)
    % SOLVESOCP
    % Robust contact-wrench SOCP using coneprog
    
    % -----------------------------
    % Extract parameters
    % -----------------------------
    nc   = numel(parameters.c);     % number of contacts
    mu   = parameters.mu;
    r_x    = parameters.r_x;
    r_y    = parameters.r_y;
    reff = parameters.reff;
    c    = parameters.c;
    G    = parameters.G;
    Fa   = parameters.s.*parameters.Fd;
    
    % -----------------------------
    % Setup x and objective function
    % -----------------------------
    % f = ones(6*nc+1,1);
    % f(end) = -1;
    % 
    % for i = 1:nc
    %     f((i-1)*6+3) = -1; % maximise normal forces
    % end
    f = zeros(6*nc+1,1);
    f(end) = -1;
    
    % -----------------------------
    % Linear equality
    % -----------------------------
    Aeq = zeros(6, 6*nc + 1);
    
    for i = 1:nc
        cols = (6*(i-1)+1):(6*i);
        c_mat = ones(6,1).*c(i);
        c_mat(3,1) = 1;
        Aeq(:, cols) = c(i) * G{i};
    end

    beq = wrench;

    % -----------------------------
    % Linear inequality
    % -----------------------------

    nrow = 4 * nc;
    ncol = 6 * nc + 1;
    
    A = zeros(nrow, ncol);
    
    b = [];

    for i = 1:nc
        cols = (6*(i-1)+1):(6*i);
        rows = (4*(i-1)+1):(4*i);
    
        % z component (always 1)
        A(rows, cols(3)) = -1;
    
        % angular x/y contributions
        A(rows(1:2), cols(4)) = [ 2/r_x; -2/r_x ];
        A(rows(3:4), cols(5)) = [ 2/r_y; -2/r_y ];
    
        % last column = 1
        A(rows, end) = 1;

        b = [b; Fa(i) * ones(4,1)];
    end

    % -----------------------------
    % SOC inequalities
    % -----------------------------
    for i = 1:nc
        Asoc = zeros(3, ncol);

        startCol = 6*(i-1) + 1;

        Asoc(1, startCol)     = 1;
        Asoc(2, startCol + 1) = 1;
        Asoc(3, startCol + 5) = 1/reff;

        bsoc = zeros(3,1);

        dsoc = zeros(ncol, 1);
        dsoc(startCol + 2,1) = mu;
        dsoc(end,1) = -1;

        gamma = mu*Fa(i);
        
        socConstraints(nc+1-i) = secondordercone(Asoc,bsoc,dsoc,gamma);
    end



    % -----------------------------
    % Solve
    % -----------------------------
    lb = ones(1,6*nc+1)*-Inf;
    ub = ones(1,6*nc+1)*Inf;
    [x,beta] = coneprog(f,socConstraints,A,b,Aeq,beq,lb,ub);
    beta = -beta;

    %displaySOCPConstraints(x, parameters, wrench);
end

function v_rot = rotateVector(vector, angle, axis)
%ROTATEVECTOR Rotate a 3D vector about principal axes (x, y, z)
%
% Inputs:
%   vector - 3x1 or 1x3 vector
%   angle  - rotation angle in radians
%   axis   - 'x', 'y', or 'z' (case-insensitive)
%
% Output:
%   v_rot  - rotated 3x1 vector

v = vector(:);

axis = lower(axis);

switch axis
    case 'x'
        R = [1 0 0;
             0 cos(angle) -sin(angle);
             0 sin(angle)  cos(angle)];

    case 'y'
        R = [ cos(angle) 0 sin(angle);
              0          1 0;
             -sin(angle) 0 cos(angle)];

    case 'z'
        R = [cos(angle) -sin(angle) 0;
             sin(angle)  cos(angle) 0;
             0           0          1];

    otherwise
        error('Axis must be ''x'', ''y'', or ''z''.');
end

v_rot = R * v;

end

function fig = plotOptimVariables(time, variables, nc, beta, negTimeSegments,motionTimepoints)

N = size(variables,1);

% ----------------------------
% Extract gamma
% ----------------------------
beta_copy = beta;
gamma = min(min(beta_copy, [], 2), [], 3);

% ----------------------------
% Create figure + tiles
% ----------------------------
fig = figure('Color', 'w', 'Name', sprintf('Optimised Variables'));
tl = tiledlayout(fig, nc*2+2, 1, ...
    'TileSpacing', 'compact', ...
    'Padding', 'compact');

% ============================
% Plot each contact wrench
% ============================
for i = 1:nc

    cols = (6*(i-1)+1):(6*i);

    F = variables(:, cols(1:3));
    T = variables(:, cols(4:6));

    % --- Force ---
    ax1 = nexttile;
    plot(ax1, time, F, 'LineWidth', 1.5);
    grid(ax1, 'on');
    xlabel(ax1, 'Time (s)');
    ylabel(ax1, sprintf('Force_%d', i));
    title(ax1, sprintf('Force_%d', i), 'Interpreter', 'none');
    hold(ax1, 'on');

    
    plotMotionPoints(ax1,motionTimepoints);
    plot_background(ax1,negTimeSegments);
    

    % --- Torque ---
    ax2 = nexttile;
    plot(ax2, time, T, 'LineWidth', 1.5);
    grid(ax2, 'on');
    xlabel(ax2, 'Time (s)');
    ylabel(ax2, sprintf('Torque_%d', i));
    title(ax2, sprintf('Torque_%d', i), 'Interpreter', 'none');
    hold(ax2, 'on');
    
    
    plotMotionPoints(ax2,motionTimepoints)
    plot_background(ax2,negTimeSegments);
    

    legend(ax1, {'F_x', 'F_y', 'F_z'}, 'Location', 'best');
    legend(ax2, {'T_x', 'T_y', 'T_z'}, 'Location', 'best');
end

% ============================
% Plot gamma (last tile)
% ============================
axg = nexttile;

plot(axg, time, gamma, 'LineWidth', 1.5);
grid(axg, 'on');
xlabel(axg, 'Time (s)');
ylabel(axg, 'gamma\_cnstr');
title(axg, 'gamma_cnstr', 'Interpreter', 'none');
hold(axg, 'on');


plotMotionPoints(axg,motionTimepoints);
plot_background(axg,negTimeSegments);

% ============================
% Plot beta (contact-wise + envelope)
% ============================
axb = nexttile;

hold(axb, 'on');
grid(axb, 'on');    
grid on;
title(sprintf('Contact %d', i));
xlabel('Time (s)');
ylabel('\beta');

names = strings(1, 4*nc);

for i = 1:nc
    base = (i-1)*4;

    plot(time, beta(:,1,i), 'LineWidth', 1.5);
    plot(time, beta(:,2,i), 'LineWidth', 1.5);
    plot(time, beta(:,3,i), 'LineWidth', 1.5);
    plot(time, beta(:,4,i), 'LineWidth', 1.5);

    names(base + 1) = sprintf('f_z_%d constraint', i);
    names(base + 2) = sprintf('tau_x_%d constraint', i);
    names(base + 3) = sprintf('tau_y_%d constraint', i);
    names(base + 4) = sprintf('friction cone_%d', i);
    
end


legend(names, 'Location','best');


% time markers (same style as others)
plotMotionPoints(axb,motionTimepoints);
plot_background(axb,negTimeSegments);
end

function plotMotionPoints(ax,motionTimepoints)
    if ~isempty(motionTimepoints)
        xl = xline(ax, motionTimepoints.Time, '--r', 'LineWidth', 1);
        xe = xline(ax, motionTimepoints.EndTime, '--b', 'LineWidth', 1);
        set(xl, 'HandleVisibility', 'off');
        set(xe, 'HandleVisibility', 'off');
    end
end

function displaySOCPConstraints(x, parameters, wrench)

    nc   = numel(parameters.c);
    mu   = parameters.mu;
    r_x    = parameters.r_x;
    r_y    = parameters.r_y;
    reff = parameters.reff;
    c    = parameters.c;
    G    = parameters.G;
    Fa   = parameters.s .* parameters.Fd;
    beta = x(end);

    fprintf('\n=========================================\n');
    fprintf('SUBSTITUTED SOCP VARIABLES\n');
    fprintf('=========================================\n');

    fprintf('\nnc   = %d\n', nc);
    fprintf('mu   = %.6f\n', mu);
    fprintf('r_x    = %.6f\n', r_x);
    fprintf('r_y    = %.6f\n', r_y);
    fprintf('reff = %.6f\n', reff);

    fprintf('\nc:\n');
    disp(c(:)');

    fprintf('Fa:\n');
    disp(Fa(:)');

    fprintf('\n-----------------------------------------\n');
    fprintf('DECISION VECTOR x VALUES\n');
    fprintf('-----------------------------------------\n');

    for i = 1:nc
        idx = 6*(i-1)+(1:6);

        fx = x(idx(1));
        fy = x(idx(2));
        fz = x(idx(3));
        mx = x(idx(4));
        my = x(idx(5));
        mz = x(idx(6));

        fprintf('\nContact %d:\n', i);
        fprintf('  fx = %.6f\n', fx);
        fprintf('  fy = %.6f\n', fy);
        fprintf('  fz = %.6f\n', fz);
        fprintf('  mx = %.6f\n', mx);
        fprintf('  my = %.6f\n', my);
        fprintf('  mz = %.6f\n', mz);

        fprintf('\n  LINEAR INEQUALITIES (SUBSTITUTED)\n');

        fprintf('    beta - %.6f + ( 2/%.6f)*%.6f  <= %.6f\n', ...
            fz, r_x, mx, Fa(i));
        fprintf('    beta <= %.6f\n', ...
            Fa(i) + fz - (2/r_x)*mx);

        fprintf('    beta - %.6f + ( 2/%.6f)*%.6f  <= %.6f\n', ...
            fz, r_x, mx, Fa(i));
        fprintf('    beta <= %.6f\n', ...
            Fa(i) + fz + (2/r_x)*mx);

        fprintf('    beta - %.6f + ( 2/%.6f)*%.6f  <= %.6f\n', ...
            fz, r_y, my, Fa(i));
        fprintf('    beta <= %.6f\n', ...
            Fa(i) + fz - (2/r_y)*my);

        fprintf('    beta - %.6f + ( 2/%.6f)*%.6f  <= %.6f\n', ...
            fz, r_y, my, Fa(i));
        fprintf('    beta <= %.6f\n', ...
            Fa(i) + fz + (2/r_y)*my);

        fprintf('\n  SOC INEQUALITIES (SUBSTITUTED)\n');

        fprintf('   ||[(%.6f); (%.6f); (%.6f/%.6f)]|| <= %.6f*(%.6f + %.6f) - beta\n', ...
        fx, fy, mz, reff, mu, fz, Fa(i));
            fprintf('    beta <= %.6f\n', ...
        mu*(fz + Fa(i)) - sqrt(fx^2 + fy^2 + (mz/reff)^2));
        

     end

    fprintf('\n-----------------------------------------\n');
    fprintf('BETA\n');
    fprintf('-----------------------------------------\n');
    fprintf('beta = %.6f\n', x(end));

    fprintf('\n-----------------------------------------\n');
    fprintf('WRENCH\n');
    fprintf('-----------------------------------------\n');
    disp(wrench);

end

function [beta, all_beta] = get_beta(x, parameters)

    nc   = numel(parameters.c);
    mu   = parameters.mu;
    r_x    = parameters.r_x;
    r_y    = parameters.r_y;
    reff = parameters.reff;
    c    = parameters.c;
    Fa   = parameters.s .* parameters.Fd;

    beta_vals = [];
    all_beta = [];

    for i = 1:nc

        cols = (6*(i-1)+1):(6*i);

        fx = x(cols(1));
        fy = x(cols(2));
        fz = x(cols(3));
        mx = x(cols(4));
        my = x(cols(5));
        mz = x(cols(6));

        % -------------------------
        % Linear inequality bounds
        % -------------------------
        b1 = Fa(i) + fz;
        b2 = Fa(i) + fz - (2/r_x)*abs(mx);
        b3 = Fa(i) + fz - (2/r_y)*abs(my);


        % -------------------------
        % SOC bound
        % -------------------------
        b4 = mu*(fz + Fa(i)) - sqrt(fx^2 + fy^2 + (mz/reff)^2);

        % -------------------------
        % Contact beta
        % -------------------------
        beta_i = min([b1 b2 b3 b4]);

        beta_vals = [beta_vals; beta_i];
        all_beta(:,i) = [b1 b2 b3 b4];

    end

    % global beta is most restrictive contact
    beta = min(beta_vals);
end

function outDir = make_directory(datetime_string)

    scriptDir = fileparts(mfilename('fullpath'));
    outDir = fullfile(scriptDir, '..', 'Force_Sensor_Data', datetime_string);
    baseDir = outDir;
    i = 1;
    
    while exist(outDir, 'dir') 
        outDir = sprintf("%s__(%s)", baseDir, string(i)); 
        i = i + 1; 
    end
    
    mkdir(outDir);

end


function export_sensor_dataset_csv( outDir, ...
    time,wrenchData,imuData,optimised_variables,gamma,motionTimepoints,loop_time)


%=========================================================
% BUILD OUTPUT TABLE
%=========================================================
N = length(time);

T = table();

T.time = time;

% Wrench data
T.Fx   = wrenchData.Fx;
T.Fy   = wrenchData.Fy;
T.Fz   = wrenchData.Fz;
T.Taux = wrenchData.Tx;
T.Tauy = wrenchData.Ty;
T.Tauz = wrenchData.Tz;

% IMU data
height(T)
height(imuData)
T.LinX = imuData.linX;
T.LinY = imuData.linY;
T.LinZ = imuData.linZ;

T.GyrX = imuData.gyrX;
T.GyrY = imuData.gyrY;
T.GyrZ = imuData.gyrZ;

T.loopTime = loop_time;

% Optimisation Variables
nc = (size(optimised_variables,2) - 1) / 6;


nc = (size(optimised_variables,2)) / 6;

for i = 1:nc
    k = i-1;

    T.(sprintf('Fx_%d', i))   = optimised_variables(:,k*6+1);
    T.(sprintf('Fy_%d', i))   = optimised_variables(:,k*6+2);
    T.(sprintf('Fz_%d', i))   = optimised_variables(:,k*6+3);
    T.(sprintf('Taux_%d', i)) = optimised_variables(:,k*6+4);
    T.(sprintf('Tauy_%d', i)) = optimised_variables(:,k*6+5);
    T.(sprintf('Tauz_%d', i)) = optimised_variables(:,k*6+6);
end

T.gamma = gamma;

N = numel(time);
M = numel(motionTimepoints.Time);

T.attached = ones(N,1);   % default = 1 (outside motion)

for j = 1:M
    inInterval = (time >= motionTimepoints.Time(j)) & ...
                 (time <= motionTimepoints.EndTime(j));

    T.attached(inInterval) = 0;
end


%=========================================================
% WRITE CSV
%=========================================================

outName = 'data.csv';
outPath = fullfile(outDir, outName);

writetable(T, outPath);

fprintf('Dataset exported:\n%s\n', outPath);

end

function save_meta_data(folder, filename, selectedRecord,parameters, scriptParameters)

% ===================== BASIC INFO =====================
ID = selectedRecord.ID;                          % int
nc = length(parameters.c);                          % number of contacts (int)

Configuration = string(selectedRecord.Configuration);      % string
EM_Configuration = string(selectedRecord.('EM Config'));   % string
GravityAngle = string(selectedRecord.('Angle from Gravity'));

ProcessedTime = datetime("now");    % or string if preferred
Notes = selectedRecord.('Notes');     % string

forceSensorFile = string(selectedRecord.('Force Sensor Filename')) + ".csv";
imuFile = string(selectedRecord.('IMU Filename')) + ".csv";

% ==================== SCRIPT PARAMETERS ===================
hz = scriptParameters.hz;
imu_linThresh = scriptParameters.linThreshold;
imu_gyrThresh = scriptParameters.gyrThreshold;
imu_refPer = scriptParameters.refractoryPeriod;

% ===================== MODEL PARAMETERS =====================
mu    = parameters.mu;
r_x   = parameters.r_x;
r_y   = parameters.r_y;
r_eff = parameters.reff;
mass  = parameters.m;

% ===================== PER-CONTACT VARIABLES =====================
% Each indexed by contact i = 1...nc

f_d     = parameters.Fd;      % size nc
s       = parameters.s;   % size nc
gravity = parameters.gravity;   % size nc
c       = parameters.c;    % size nc

% ===================== ADJOINT MATRICES =====================
% 6x6xnc tensor
A = parameters.G;    

% ===== Build full file path =====
fullpath = fullfile(folder, filename);

% ===== Open file for writing =====
fid = fopen(fullpath, 'w');
if fid == -1
    error('Failed to create output file: %s', fullpath);
end

% ===== Optional: format datetime =====
if isdatetime(ProcessedTime)
    StartTimeStr = char(ProcessedTime, 'dd/MM/yyyy HH:mm:ss');
else
    StartTimeStr = ProcessedTime;
end

% ===== Header =====
fprintf(fid, '==================== SYSTEM REPORT ====================\n\n');

fprintf(fid, 'ID: %d\n', ID);
fprintf(fid, 'Number of Contacts: %d\n', nc);
fprintf(fid, 'Configuration: %s\n', Configuration);
fprintf(fid, 'EM Configuration: %s\n', EM_Configuration);
fprintf(fid, 'Angle from Gravity: %s\n', GravityAngle);
fprintf(fid, 'Processed Time: %s\n', StartTimeStr);
fprintf(fid, 'Notes: %s\n\n', Notes);
fprintf(fid, 'Force Sensor Filename: %s\n\n', forceSensorFile);
fprintf(fid, 'IMU Filename: %s\n\n', imuFile);

% ===== Script Parameters =====
fprintf(fid, '---------------- SCRIPT PARAMETERS -----------------\n');
fprintf(fid, 'hz    : %.6f\n', hz);
fprintf(fid, '---------- IMU Thresholds:\n');
fprintf(fid, 'linThreshold      : %.10f\n', imu_linThresh);
fprintf(fid, 'gyrThreshold      : %.10f\n', imu_gyrThresh);
fprintf(fid, 'refractoryPeriod  : %.10f\n', imu_refPer);

% ===== Global Parameters =====
fprintf(fid, '-------------- OPTIMISATION PARAMETERS ------------\n');
fprintf(fid, 'mu     : %.6f\n', mu);
fprintf(fid, 'r_x    : %.6f\n', r_x);
fprintf(fid, 'r_y    : %.6f\n', r_y);
fprintf(fid, 'r_eff  : %.6f\n', r_eff);
fprintf(fid, 'mass   : %.6f\n\n', mass);

% ===== Contact Data =====
fprintf(fid, '-------------------- CONTACT DATA --------------------\n\n');

for i = 1:nc
    fprintf(fid, 'CONTACT %d\n', i);
    fprintf(fid, '-----------------------------------------------------\n');
    fprintf(fid, 'f_d     : %.6f\n', f_d(i));
    fprintf(fid, 's       : %.6f\n', s(i));
    fprintf(fid, 'gravity : %.6f\n', gravity(i));
    fprintf(fid, 'c       : %.6f\n\n', c(i));

    fprintf(fid, 'Adjoint Matrix (6x6):\n');
    
    A_i = A{i};

    for r = 1:6
        fprintf(fid, '  % .6f  % .6f  % .6f  % .6f  % .6f  % .6f\n', A_i(r,:));
    end

    fprintf(fid, '\n');
end

% ===== Footer =====
fprintf(fid, '==================== END OF REPORT ====================\n');

% ===== Close file =====
fclose(fid);

% ===== Optional confirmation =====
fprintf('Report written to: %s\n', fullpath);
end
