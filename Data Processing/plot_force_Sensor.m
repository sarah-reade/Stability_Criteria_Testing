function plot_force_Sensor()
%PLOT_FORCE_SENSOR Select a registered force sensor dataset and plot it.

% Resolve data paths relative to this script so the function is portable.
scriptDir = fileparts(mfilename('fullpath'));
dataDir = fullfile(scriptDir, '..', '..', 'VirtualBox VMs', 'shared', 'Force_Sensor_Data');
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

requiredCols = {'ID', 'Filename', 'Configuration', 'Angle from Gravity', 'EM Config'};
missingCols = requiredCols(~ismember(requiredCols, dataReg.Properties.VariableNames));
if ~isempty(missingCols)
    errordlg(sprintf('The following required columns are missing:\n\n%s', strjoin(missingCols, ', ')), 'Invalid Registration File');
    return;
end

% Keep only rows that can be mapped to a dataset and have EM config present.
validRows = ~ismissing(dataReg.ID) & ~ismissing(dataReg.Filename) & strlength(dataReg.Filename) > 0 & ~ismissing(dataReg.('EM Config')) & strlength(dataReg.('EM Config')) > 0;
dataReg = dataReg(validRows, :);

if height(dataReg) == 0
    errordlg('No valid entries exist in Data_Reg.csv.', 'No Data Available');
    return;
end

displayItems = buildDisplayItems(dataReg);
selectedIdx = runSelectionDialog(displayItems);

if isempty(selectedIdx)
    return;
end

selectedRecord = dataReg(selectedIdx, :);
csvFilename = string(selectedRecord.Filename) + ".csv";
csvPath = fullfile(dataDir, csvFilename);

if ~isfile(csvPath)
    errordlg(sprintf('The selected CSV file does not exist:\n\n%s', csvFilename), 'Missing CSV File');
    return;
end

try
    % Parse sample rate, sensor channels, and metadata from selected CSV.
    [sampleRate, sensorData, csvMeta] = readSensorCsv(csvPath);
catch ME
    errordlg(sprintf('Failed to load CSV:\n\n%s', ME.message), 'CSV Read Error');
    return;
end

time = (0:height(sensorData)-1)' / sampleRate;

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
fx_ds = fx_s(idx);
fy_ds = fy_s(idx);
fz_ds = fz_s(idx);
tx_ds = tx_s(idx);
ty_ds = ty_s(idx);
tz_ds = tz_s(idx);

% Effective sample rate after decimation (used for derivative scaling).
sampleRate = sampleRate / decFactor;

force = [fx_ds, fy_ds, fz_ds];
torque = [tx_ds, ty_ds, tz_ds];
forceMag = vecnorm(force, 2, 2);
torqueMag = vecnorm(torque, 2, 2);

infoText = buildInfoBoxString(selectedRecord, csvMeta, sampleRate, height(sensorData));

% Layout: info panel, force components, torque components, derivative panel.
figure('Color', 'w', 'Name', sprintf('Force/Torque Plot - %s', csvFilename));
tiledlayout(4, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

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

ax = nexttile;
plot(ax, time, force, 'LineWidth', 1.5);
grid(ax, 'on');
xlabel(ax, 'Time (s)');
ylabel(ax, 'Force (N)');
title(ax, 'Force Components', 'Interpreter', 'none');
legend(ax, {'F_x', 'F_y', 'F_z'}, 'Location', 'best');

ax = nexttile;
plot(ax, time, torque, 'LineWidth', 1.5);
grid(ax, 'on');
xlabel(ax, 'Time (s)');
ylabel(ax, 'Torque (Nm)');
title(ax, 'Torque Components', 'Interpreter', 'none');
legend(ax, {'T_x', 'T_y', 'T_z'}, 'Location', 'best');

ax = nexttile;
% Plot Something Useful
tol = 1e-12;
maskValid = forceMag > tol;

% --- Estimate best-fit linear mapping A using global least squares ---
A = force(maskValid, :) \ torque(maskValid, :);  % 3x3 mapping

% --- Reconstruct predicted torque ---
torquePred = force * A;

% --- Residual magnitude (key signal) ---
residual = vecnorm(torque - torquePred, 2, 2);

% Normalize (optional but helps interpretability)
residualNorm = residual ./ (forceMag + tol);

plot(ax, time, residualNorm, 'LineWidth', 1.5, 'Color', [0.1 0.6 0.2]);
grid(ax, 'on');
xlabel(ax, 'Time (s)');
ylabel(ax, 'Normalized Residual');
title(ax, 'Force-Torque Consistency Residual (Slip Indicator)', 'Interpreter', 'none');
legend(ax, {'Residual'}, 'Location', 'best');

sgtitle(sprintf('Sensor data: %s', csvFilename), 'Interpreter', 'none');
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

function selectedIdx = runSelectionDialog(displayItems)
% Show GUI selector and return chosen row index (or [] on cancel).
selectedIdx = [];

selectionFig = uifigure('Name', 'Force Sensor Dataset Selection', 'Position', [500 400 900 170]);
selectionFig.UserData = [];
selectionFig.CloseRequestFcn = @cancelSelection;

uilabel(selectionFig, 'Position', [20 110 200 22], 'Text', 'Select Dataset');

dropdown = uidropdown( ...
    selectionFig, ...
    'Position', [20 85 860 26], ...
    'Items', cellstr(displayItems), ...
    'ItemsData', 1:numel(displayItems), ...
    'Value', 1);

uibutton(selectionFig, 'Text', 'Load Dataset', 'Position', [340 28 220 34], ...
    'ButtonPushedFcn', @loadSelection);

uibutton(selectionFig, 'Text', 'Cancel', 'Position', [580 28 120 34], ...
    'ButtonPushedFcn', @cancelSelection);

uiwait(selectionFig);

if isvalid(selectionFig)
    selectedIdx = selectionFig.UserData;
    delete(selectionFig);
end

    function loadSelection(~, ~)
        selectionFig.UserData = dropdown.Value;
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

function [sampleRate, data, meta] = readSensorCsv(csvPath)
% Read ATI-style CSV: metadata header followed by numeric data rows.
fileText = fileread(csvPath);
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
    error('Could not locate the data header in %s.', csvPath);
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
end

data = table(status, rdtSequence, ftSequence, fx, fy, fz, tx, ty, tz, ...
    'VariableNames', {'Status', 'RDTSequence', 'FTSequence', 'Fx', 'Fy', 'Fz', 'Tx', 'Ty', 'Tz'});
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