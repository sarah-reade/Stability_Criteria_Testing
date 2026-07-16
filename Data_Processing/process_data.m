function process_data()
%PLOT_FORCE_SENSOR Select a registered force sensor dataset and plot it.

% Resolve data paths relative to this script so the function is portable.
scriptDir = fileparts(mfilename('fullpath'));
dataDir = fullfile(scriptDir, '..', 'Force_Sensor_Data');
dataRegPath = fullfile(dataDir, 'Data_Reg.csv');
overwrite = false;

if ~isfile(dataRegPath)
    errordlg(sprintf('Could not find registration file:\n%s', dataRegPath), 'Registration File Missing');
    return;
end

try
    % Preserve original CSV column names (including spaces) for direct access.

    opts = detectImportOptions(dataRegPath, ...
    'TextType', 'string', ...
    'VariableNamingRule', 'preserve');

    opts = setvartype(opts, 'Angle from Gravity', 'string');
    opts = setvartype(opts, 'Notes', 'string');
    opts = setvaropts(opts, 'Notes', 'TreatAsMissing', {''});

    dataReg = readtable(dataRegPath, opts);
    dataReg.Notes(ismissing(dataReg.Notes)) = "";

    summary(dataReg)
catch ME
    errordlg(sprintf('Failed to read Data_Reg.csv\n\n%s', ME.message), 'File Read Error');
    return;
end

requiredCols = {'ID', 'Force Sensor Filename', 'IMU Filename', 'Configuration', 'Angle from Gravity', 'EM Config'};
missingCols = requiredCols(~ismember(requiredCols, dataReg.Properties.VariableNames));
disp(dataReg.Properties.VariableNames')
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
[overwrite,plots,selectedIdxs] = runSelectionDialog(displayItems, infoItems, dataReg);

if isempty(selectedIdxs)
    return;
end


for selectionIdx = 1:numel(selectedIdxs)

    selectedIdx = selectedIdxs(selectionIdx);   % force scalar index
    selectedRecord = dataReg(selectedIdx, :);
    fscsvFilename = string(selectedRecord.('Force Sensor Filename')) + ".csv";
    fscsvPath = fullfile(dataDir, fscsvFilename);
    imucsvFilename = string(selectedRecord.('IMU Filename')) + ".csv";
    imucsvPath = fullfile(dataDir, imucsvFilename);
    
    if ~isfile(fscsvPath)
        errordlg(sprintf('The selected CSV file does not exist:\n\n%s', fscsvFilename), 'Missing CSV File');
        continue;
    elseif ~isfile(imucsvPath)
        errordlg(sprintf('The selected CSV file does not exist:\n\n%s', imucsvFilename), 'Missing CSV File');
        continue;
    end
    
    try
        % Parse sample rate, sensor channels, and metadata from selected CSV.
        [sampleRate, sensorData, csvMeta] = readSensorCsv(fscsvPath);
    catch ME
        errordlg(sprintf('Failed to load CSV:\n\n%s', ME.message), 'CSV Read Error');
        continue;
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
        kernel = ones(win,1) / win;
        fx_s = conv(sensorData.Fx, kernel, 'same');
        fy_s = conv(sensorData.Fy, kernel, 'same');
        fz_s = conv(sensorData.Fz, kernel, 'same');
        tx_s = conv(sensorData.Tx, kernel, 'same');
        ty_s = conv(sensorData.Ty, kernel, 'same');
        tz_s = conv(sensorData.Tz, kernel, 'same');
    end
    
    idx = 1:decFactor:height(sensorData);
    time = time(idx);
    nZero = 10;
    fx_ds = fx_s(idx)-mean(fx_s(1:nZero));
    fy_ds = (fy_s(idx))-mean(fy_s(1:nZero));
    fz_ds = -((fz_s(idx))-mean(fz_s(1:nZero)));
    tx_ds = tx_s(idx)-mean(tx_s(1:nZero));
    ty_ds = ty_s(idx)-mean(ty_s(1:nZero));
    tz_ds = -(tz_s(idx)-mean(tz_s(1:nZero)));

    
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
    tiledlayout(fig, 6, 1, ...
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
    
    axs = findall(fig, 'Type', 'axes');
    
    parameters = get_params(selectedRecord.('Configuration'),string(selectedRecord.('Angle from Gravity')),selectedRecord.('EM Config'));
    
    wrench = [force,torque];
    gamma_cnstr = zeros(height(wrench),1);
    nc = numel(parameters.c);
    variables = zeros(height(wrench),nc*6 + 1);
    beta = zeros(height(wrench),1);
    all_beta = zeros(height(wrench),4,nc);
    loop_time = zeros(height(wrench),1);
    for sampleIdx = 1:height(wrench)
        tStart = tic;
        [variables(sampleIdx,:),gamma_cnstr(sampleIdx)] = obtain_gamma_cnstr(parameters,wrench(sampleIdx,:)');
        [beta(sampleIdx),all_beta(sampleIdx,:,:)] = get_beta(variables(sampleIdx,:),parameters);
        loop_time(sampleIdx) = toc(tStart);
    end
    
    datetime_string = csvMeta.startTime;
    datetime_string = replace(datetime_string, [" ", "/", ":"], "_");
    outDir = make_directory(datetime_string,overwrite);
    
    gamma_out = beta;
    margin = 0;
    isNeg = gamma_out < margin;
    
    export_sensor_dataset_csv( outDir, ...
       time,wrenchData,imuData,variables,gamma_out,motionTimepoints,loop_time);
    
    ppdata = post_process(outDir+"/data.csv",parameters.reff,10,10);

    save_meta_data(outDir, 'metaData.txt', selectedRecord,parameters,scriptParameters,ppdata)
    
    
    % Find rising/falling edges
    d = diff([false; isNeg; false]);
    startIdx = find(d == 1)-1;
    endIdx   = find(d == -1);
    
    negSegments = [startIdx, endIdx];
    if ~isempty(negSegments) && all(negSegments(:) >= 1)
        negTimeSegments = [time(negSegments(:,1)), time(negSegments(:,2))];
    else
        negTimeSegments = [];
    end
    
    ax = nexttile;
    hold(ax,"on");
    grid(ax, 'on');
    
    % plot(ax, time, gamma_cnstr, 'LineWidth', 1.5);
    plot(ax, time, beta, 'LineWidth', 1.5);
    xlabel(ax, 'Time (s)');
    ylabel(ax, 'value');
    title(ax, 'gamma', 'Interpreter', 'none');
    plot_background(ax,negTimeSegments);
    % legend(ax, {'gamma', 'beta'}, 'Location', 'best');
    
        
    plotMotionPoints(ax,motionTimepoints);
    
    for axisIdx = 1:numel(axs)
        if axs(axisIdx) == infoAx
            continue
        end
        
        plotMotionPoints(axs(axisIdx),motionTimepoints);
        plot_background(axs(axisIdx),negTimeSegments);
    end
        
    
    fig2 = plotOptimVariables(time, variables, nc, all_beta, negTimeSegments, motionTimepoints);

    sgtitle(fig, sprintf('Sensor data: %s | %s', fscsvFilename, imucsvFilename), 'Interpreter', 'none');
    sgtitle(fig2, sprintf('Sensor data: %s | %s', fscsvFilename, imucsvFilename), 'Interpreter', 'none');
    
    % Maximise the exported figures so saved images match the on-screen view.
    set(fig, 'Units', 'normalized', 'OuterPosition', [0 0 1 1]);
    drawnow;
    
    savefig(fig, fullfile(outDir, "fig1.fig"));
    print(fig, fullfile(outDir, "fig1.svg"), "-dsvg");
    
    set(fig2, 'Units', 'normalized', 'OuterPosition', [0 0 1 1]);
    drawnow;
    
    savefig(fig2, fullfile(outDir, "fig2.fig"));
    print(fig2, fullfile(outDir, "fig2.svg"), "-dsvg");
    
    if ~plots
        close all;
    end
    
end

results = build_results_table(dataDir);
displayTableAndSaveCSV(results);

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
% Build human-readable labels for the dataset picker.
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
% Build auxiliary info (date + notes) aligned with the dataset picker rows.

infoItems = strings(height(dataReg), 1);

for rowIdx = 1:height(dataReg)

    % Extract date-like prefix from Force Sensor Filename
    forceFile = string(dataReg.('Force Sensor Filename')(rowIdx));

    % Assumes format: YYYY-MM-DD_HH-MM-SS_...
    dateToken = extractBefore(forceFile, "_");

    % Convert to datetime and reformat
    dt = datetime(dateToken, 'InputFormat', 'yyyy-MM-dd');
    dateText = "Date: " + string(dt, 'dd/MM/yyyy');

    % Notes
    notesText = string(dataReg.Notes(rowIdx));
    if strlength(strtrim(notesText)) == 0
        notesText = "Notes: (none)";
    else
        notesText = "Notes: " + notesText;
    end

    infoItems(rowIdx) = dateText + " | " + notesText;
end

end

function [overwrite,plots,selectedIdx] = runSelectionDialog(displayItems, infoItems, dataReg)
% Single-figure selector with persistent manual and rule-based selection.

selectedIdx = [];
overwrite = false;
rowCount = height(dataReg);
selectedMask = false(rowCount, 1);
selectionConfirmed = false;

filterState = struct( ...
    'Configuration', "All", ...
    'Angle', "All", ...
    'EMConfig', "All");

isUpdatingFilters = false;

selectionFig = uifigure('Name', 'Force Sensor Dataset Selection', ...
    'Position', [500 250 1180 760]);

drawnow;
selectionFig.CloseRequestFcn = @cancelSelection;

mainGrid = uigridlayout(selectionFig, [4 1]);
mainGrid.Padding = [10 10 10 10];
mainGrid.RowSpacing = 6;
mainGrid.RowHeight = {120, 60, '1x', 80};
controlPanel = uipanel(mainGrid, 'Title', 'Controls');
controlPanel.Layout.Row = [1 2];

mainGridLayout = uigridlayout(controlPanel, [2 1]);
mainGridLayout.RowHeight = {90, 40};
mainGridLayout.Padding = [8 8 8 8];
mainGridLayout.RowSpacing = 10;

%% ---------------- ACTIONS (bottom row) ----------------
actionsGrid = uigridlayout(mainGridLayout, [1 4]);
actionsGrid.Layout.Row = 1;

actionsGrid.ColumnWidth = {'1x','1x','1x','1x'};

uibutton(actionsGrid, 'Text', 'Select Matching', 'ButtonPushedFcn', @applySelectMatching);
uibutton(actionsGrid, 'Text', 'Deselect Matching', 'ButtonPushedFcn', @applyDeselectMatching);
uibutton(actionsGrid, 'Text', 'Clear Selection', 'ButtonPushedFcn', @clearSelection);
uibutton(actionsGrid, 'Text', 'Select All', 'ButtonPushedFcn', @selectAllRows);

%% ---------------- FILTERS (top row) ----------------
filterGrid = uigridlayout(mainGridLayout, [1 10]);
filterGrid.Layout.Row = 2;

filterGrid.ColumnWidth = {100, '1x', 100, '1x', 100, '1x',150, 40, 40,40};
filterGrid.RowHeight = {24};

uilabel(filterGrid, 'Text', 'Configuration');
configurationDropDown = uidropdown(filterGrid, ...
    'Items', {'All', 'flat', 'RA', 'single'}, ...
    'Value', 'All', ...
    'ValueChangedFcn', @onFilterChange);

uilabel(filterGrid, 'Text', 'AngleFromGravity');
angleDropDown = uidropdown(filterGrid, ...
    'Items', {'All', '0', '90', '180', '90V'}, ...
    'Value', 'All', ...
    'ValueChangedFcn', @onFilterChange);

uilabel(filterGrid, 'Text', 'EM Config');
emDropDown = uidropdown(filterGrid, ...
    'Items', {'All', 'off', 'on', 'off-off', 'on-on', 'off-on', 'on-off'}, ...
    'Value', 'All', ...
    'ValueChangedFcn', @onFilterChange);

uilabel(filterGrid, ...
    'Text', sprintf('Overwrite Existing Files'));
overwriteCheckbox = uicheckbox(filterGrid, ...
    'Text', '', ...
    'Value', true);

uilabel(filterGrid, ...
    'Text', sprintf('Plot?'));
plotsCheckbox = uicheckbox(filterGrid, ...
    'Text', '', ...
    'Value', false);

tablePanel = uipanel(mainGrid, 'Title', 'Datasets');
tablePanel.Layout.Row = 3;
tableGrid = uigridlayout(tablePanel, [1 1]);
tableGrid.Padding = [0 0 0 0];

selectionTable = uitable(tableGrid, ...
    'Data', buildSelectionTableData(), ...
    'ColumnEditable', false(1, 7), ...
    'CellSelectionCallback', @onTableSelectionChanged);%, ...
    %'ColumnWidth', {'1x', '1x', '1x', '1x', '1x', '1x', '1x'});
selectionTable.Layout.Row = 1;
selectionTable.Layout.Column = 1;

% statusLabel = uilabel(mainGrid, ...
%     'Text', '', ...
%     'FontWeight', 'bold');
% statusLabel.Layout.Row = 4;

footerPanel = uipanel(mainGrid, 'BorderType', 'none');
footerPanel.Layout.Row = 4;
footerGrid = uigridlayout(footerPanel, [1 3]);
footerGrid.ColumnWidth = {'1x','1x','1x'};


statusLabel = uilabel(footerGrid, ...
    'Text', '', ...
    'FontWeight', 'bold');

uibutton(footerGrid, ...
    'Text', 'Select', ...
    'ButtonPushedFcn', @confirmSelection);

uibutton(footerGrid, ...
    'Text', 'Cancel', ...
    'ButtonPushedFcn', @cancelSelection);

syncFilterOptions();
refreshTableHighlight();

drawnow;
uiwait(selectionFig);

if isvalid(selectionFig)
    if selectionConfirmed && isempty(selectedIdx)
        selectedIdx = find(selectedMask);
    end
    overwrite = overwriteCheckbox.Value;
    plots = plotsCheckbox.Value;
    delete(selectionFig);
end

    function onFilterChange(~, ~)
        if isUpdatingFilters
            return;
        end

        filterState.Configuration = string(configurationDropDown.Value);
        filterState.Angle = string(angleDropDown.Value);
        filterState.EMConfig = string(emDropDown.Value);

        syncFilterOptions();
        refreshStatusText();
    end

    function syncFilterOptions()
        isUpdatingFilters = true;

        configValue = string(configurationDropDown.Value);
        angleItems = buildAngleItems(configValue);
        emItems = buildEmItems(configValue);

        configurationDropDown.Items = {'All', 'flat', 'RA', 'single'};
        angleDropDown.Items = cellstr(angleItems);
        emDropDown.Items = cellstr(emItems);

        configurationDropDown.Value = char(keepOrResetValue(string(configurationDropDown.Value), string(configurationDropDown.Items)));
        angleDropDown.Value = char(keepOrResetValue(string(angleDropDown.Value), angleItems));
        emDropDown.Value = char(keepOrResetValue(string(emDropDown.Value), emItems));

        filterState.Configuration = string(configurationDropDown.Value);
        filterState.Angle = string(angleDropDown.Value);
        filterState.EMConfig = string(emDropDown.Value);

        isUpdatingFilters = false;
    end

    function value = keepOrResetValue(currentValue, validItems)
        validItems = string(validItems);

        if ismember(currentValue, validItems)
            value = currentValue;
        else
            value = validItems(1);
        end
    end

    function applySelectMatching(~, ~)
        matchingMask = computeMatchingMask();
        selectedMask(matchingMask) = true;
        refreshTableHighlight();
    end

    function applyDeselectMatching(~, ~)
        matchingMask = computeMatchingMask();
        selectedMask(matchingMask) = false;
        refreshTableHighlight();
    end

    function clearSelection(~, ~)
        selectedMask(:) = false;
        refreshTableHighlight();
    end

    function selectAllRows(~, ~)
        selectedMask(:) = true;
        refreshTableHighlight();
    end

    function onTableSelectionChanged(~, event)
        if isempty(event.Indices)
            return;
        end

        rows = unique(event.Indices(:,1));
        rows = rows(rows >= 1 & rows <= rowCount);
        if isempty(rows)
            return;
        end

        selectedMask(rows) = ~selectedMask(rows);
        refreshTableHighlight();
    end

    function refreshTableHighlight()
        selectionTable.Data = buildSelectionTableData();
        refreshStatusText();
    end

    function refreshStatusText()
        matchingMask = computeMatchingMask();
        statusLabel.Text = sprintf('%d of %d rows selected | %d rows match current filters', ...
            nnz(selectedMask), rowCount, nnz(matchingMask));
    end

    function matchingMask = computeMatchingMask()
        matchingMask = false(rowCount, 1);

        for rowIdx = 1:rowCount
            matchingMask(rowIdx) = matchesFilter(dataReg(rowIdx, :), filterState);
        end
    end

    function selectionTableData = buildSelectionTableData()
        selectionTableData = table();
        selectionTableData.Selected = selectedMask;
        selectionTableData.ID = getRowValue(dataReg, 'ID');
        selectionTableData.Dataset = displayItems(:);
        selectionTableData.Info = infoItems(:);
        selectionTableData.Configuration = normalizeRowText(getRowValue(dataReg, {'Configuration'}));
        selectionTableData.AngleFromGravity = normalizeAngleColumn(getRowValue(dataReg, {'Angle from Gravity', 'AngleFromGravity'}));
        selectionTableData.EMConfig = normalizeRowText(getRowValue(dataReg, {'EM Config', 'EMConfig'}));
    end

    function valueColumn = getRowValue(sourceTable, candidateNames)
        valueColumn = strings(rowCount, 1);

        if ischar(candidateNames) || isstring(candidateNames)
            candidateNames = cellstr(candidateNames);
        end

        matchedName = '';
        sourceNames = sourceTable.Properties.VariableNames;
        for candidateIdx = 1:numel(candidateNames)
            matchIdx = find(strcmpi(sourceNames, candidateNames{candidateIdx}), 1, 'first');
            if ~isempty(matchIdx)
                matchedName = sourceNames{matchIdx};
                break;
            end
        end

        if isempty(matchedName)
            return;
        end

        rawValue = sourceTable.(matchedName);
        if istable(rawValue)
            rawValue = table2array(rawValue);
        end

        for rowIdx = 1:rowCount
            valueColumn(rowIdx) = string(rawValue(rowIdx));
        end
    end

    function textValue = normalizeRowText(textValue)
        textValue = strip(string(textValue));
    end

    function angleValue = normalizeAngleColumn(angleColumn)
        angleValue = strip(string(angleColumn));
        angleValue(lower(angleValue) == "90v") = "90V";
    end

    function tf = matchesFilter(row, filters)
        tf = true;

        rowConfig = lower(normalizeRowText(getSingleRowValue(row, {'Configuration'})));
        rowAngle = normalizeAngleText(getSingleRowValue(row, {'Angle from Gravity', 'AngleFromGravity'}), rowConfig);
        rowEm = lower(normalizeRowText(getSingleRowValue(row, {'EM Config', 'EMConfig'})));

        if filters.Configuration ~= "All"
            tf = tf && rowConfig == lower(filters.Configuration);
        end

        if filters.Angle ~= "All"
            tf = tf && angleMatches(rowAngle, rowConfig, filters.Angle);
        end

        if filters.EMConfig ~= "All"
            tf = tf && emMatches(rowEm, filters.EMConfig);
        end
    end

    function rowValue = getSingleRowValue(row, candidateNames)
        rowValue = "";
        sourceNames = row.Properties.VariableNames;
        if ischar(candidateNames) || isstring(candidateNames)
            candidateNames = cellstr(candidateNames);
        end

        for candidateIdx = 1:numel(candidateNames)
            matchIdx = find(strcmpi(sourceNames, candidateNames{candidateIdx}), 1, 'first');
            if ~isempty(matchIdx)
                rowValue = string(row.(sourceNames{matchIdx}));
                return;
            end
        end
    end

    function angleValue = normalizeAngleText(rawAngle, rowConfig)
        angleValue = upper(strip(string(rawAngle)));

        if angleValue == "90V"
            return;
        end

        if isnan(str2double(angleValue))
            angleValue = "";
            return;
        end

        angleValue = string(str2double(angleValue));

        if rowConfig == "flat" && angleValue == "90"
            angleValue = "90";
        end
    end

    function tf = angleMatches(rowAngle, rowConfig, filterAngle)
        filterAngle = string(filterAngle);
        if filterAngle == "90V"
            tf = rowConfig == "flat" && rowAngle == "90V";
        else
            tf = rowAngle == filterAngle;
        end
    end

    function angleItems = buildAngleItems(configValue)
        configValue = lower(string(configValue));
        if configValue == "flat"
            angleItems = {'All', '0', '90', '180', '90V'};
        else
            angleItems = {'All', '0', '90', '180'};
        end
    end

    function emItems = buildEmItems(configValue)
        configValue = lower(string(configValue));
        if configValue == "single"
            emItems = {'All', 'off', 'on'};
        else
            emItems = {'All', 'off', 'on', 'off-on', 'on-off'};
        end
    end
    
    function confirmSelection(~, ~)
        selectionConfirmed = true;
        selectedIdx = find(selectedMask);
        uiresume(selectionFig);
    end

    function cancelSelection(~, ~)
        selectionConfirmed = false;
        selectedIdx = [];
        uiresume(selectionFig);
    end

    function tf = emMatches(rowEm, filterEm)

        rowEm = lower(string(rowEm));
        filterEm = lower(string(filterEm));

        switch filterEm
            case "on"
                tf = ismember(rowEm, ["on", "on-on"]);

            case "off"
                tf = ismember(rowEm, ["off", "off-off"]);

            otherwise
                tf = rowEm == filterEm;
        end
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

function [imuData] = plot_two_sensor_average(rawData, time)
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
    % Set contact variables that define the optimisation problem.
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
    parameters.r_x = r;%/8;
    parameters.r_y = r;%/8;
    parameters.reff = r;%*10;

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
    steel_s = 0.1;
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
        parameters.Fd = p_magnet + mask * 1400;
        
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
        g = reshape(g_base,3,1);
    end 
    
    % Append the rotational components expected by the wrench transform.
    g = [g', 0, 0, 0];

    parameters.gravity = Gg*g.';

    %print_parameters(parameters);
    parameters.m = parameters.m*1.5;
    
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
    % f = ones(6*nc+1,1);
    for i = 1:nc
        f((i-1)*6+3) = -1;
    end
    % f(end) = -1;
    
    % -----------------------------
    % Linear equality
    % -----------------------------
    Aeq = zeros(6, 6*nc + 1);
    
    for i = 1:nc
        cols = (6*(i-1)+1):(6*i);
        Aeq(:, cols) = c(i) * G{i};
    end

    beq = wrench;

    % -----------------------------
    % Linear inequality
    % -----------------------------

    nrow = 5 * nc;
    ncol = 6 * nc + 1;
    
    A = zeros(nrow, ncol);
    b = zeros(nrow,1);
    
    % b = [];

    % for i = 1:nc
    %     cols = (6*(i-1)+1):(6*i);
    %     rows = (5*(i-1)+1):(5*i);
    
    %     % z component (always 1)
    %     A(rows, cols(3)) = -1;
    
    %     % angular x/y contributions
    %     A(rows(1:2), cols(4)) = [ 2/r_x; -2/r_x ];
    %     A(rows(3:4), cols(5)) = [ 2/r_y; -2/r_y ];

    %     % last column = 1
    %     A(rows, end) = 1;

    %     b = [b; Fa(i) * ones(5,1)];
    % end
    
    % -----------------------------
    % SOC inequalities
    % -----------------------------
    for i = 1:nc
        % -------- friction ---------%
        Asoc = zeros(3, ncol);

        startCol = 6*(i-1) + 1;

        Asoc(1, startCol)     = 1;
        Asoc(2, startCol + 1) = 1;
        Asoc(3, startCol + 5) = 1/reff;

        bsoc = zeros(3,1);

        dsoc = zeros(ncol, 1);
        dsoc(startCol + 2,1) = mu;
        dsoc(end,1) = -1;

        gamma = -mu*Fa(i);
        
        socConstraints(nc+1-i) = secondordercone(Asoc,bsoc,dsoc,gamma);


        % -------- tipping ---------%
        nrows = 2;
        Asoc = zeros(nrows, ncol);

        startCol = 6*(i-1) + 4;

        Asoc(1, startCol)     = 2/r_x;
        Asoc(2, startCol + 1) = 2/r_y;

        bsoc = zeros(nrows,1);

        dsoc = zeros(ncol, 1);
        dsoc(startCol + 2,1) = 1;
        dsoc(end,1) = -1;

        gamma = -Fa(i);
        
        socConstraints(2*nc+1-i) = secondordercone(Asoc,bsoc,dsoc,gamma);
    end



    % -----------------------------
    % Solve
    % -----------------------------
    lb = ones(1,6*nc+1)*-10000;
    ub = ones(1,6*nc+1)*10000;
    opts = optimoptions('coneprog', ...
        'ConstraintTolerance', 1e-6, ...
        'Display', 'final', ...
        'LinearSolver', 'auto', ...
        'MaxIterations', 500, ...
        'MaxTime', Inf, ...
        'OptimalityTolerance', 1e-6);

    %% Display coneprog inputs
    % disp('========== coneprog INPUTS ==========');

    % disp('f =');
    % disp(f);

    % disp('socConstraints =');
    % disp(socConstraints);

    % disp('A =');
    % disp(A);

    % disp('b =');
    % disp(b);

    % disp('Aeq =');
    % disp(Aeq);

    % disp('beq =');
    % disp(beq);

    % disp('lb =');
    % disp(lb);

    % disp('ub =');
    % disp(ub);

    % disp('opts =');
    % disp(opts);

    % disp('=====================================');

    [x,beta] = coneprog(f,socConstraints,A,b,Aeq,beq,lb,ub,opts);
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

%PLOTOPTIMVARIABLES Plot the reconstructed contact variables and beta terms.

% Extract the envelope used for the final constraint plot.
beta_copy = beta;
gamma = min(min(beta_copy, [], 2), [], 3);

fig = figure('Color', 'w', 'Name', sprintf('Optimised Variables'));
tiledlayout(fig, nc*2+2, 1, ...
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
title(axb, 'Beta Constraints', 'Interpreter', 'none');
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

function [beta, all_beta] = get_beta(x, parameters)

    nc   = numel(parameters.c);
    mu   = parameters.mu;
    r_x    = parameters.r_x;
    r_y    = parameters.r_y;
    reff = parameters.reff;
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

function outDir = make_directory(datetime_string,overwrite)

    scriptDir = fileparts(mfilename('fullpath'));
    outDir = fullfile(scriptDir, '..', 'Force_Sensor_Data', datetime_string);
    baseDir = outDir;
    i = 1;
    
    if exist(outDir, 'dir') && overwrite
        return
    end

    while exist(outDir, 'dir')
        outDir = sprintf("%s__(%s)", baseDir, string(i)); 
        i = i + 1; 
    end
    
    mkdir(outDir);

end


function export_sensor_dataset_csv( outDir, ...
    time,wrenchData,imuData,optimised_variables,gamma,motionTimepoints,loop_time)


% Build a flat CSV that preserves the processed signals and optimisation output.

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
T.LinX = imuData.linX;
T.LinY = imuData.linY;
T.LinZ = imuData.linZ;

T.GyrX = imuData.gyrX;
T.GyrY = imuData.gyrY;
T.GyrZ = imuData.gyrZ;

T.loopTime = loop_time;

% Optimisation variables are stored as one 6-column block per contact.
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

T.attached = ones(N,1);   % Default to 1 outside motion intervals.

for j = 1:M
    inInterval = (time >= motionTimepoints.Time(j)) & ...
                 (time <= motionTimepoints.EndTime(j));

    T.attached(inInterval) = 0;
end

T = T(21:end-20, :);

outName = 'data.csv';
outPath = fullfile(outDir, outName);

writetable(T, outPath);

fprintf('Dataset exported:\n%s\n', outPath);

end

function save_meta_data(folder, filename, selectedRecord,parameters, scriptParameters,ppdata)

% Record the dataset metadata that was used to produce the export.
ID = selectedRecord.ID;
nc = length(parameters.c);

Configuration = string(selectedRecord.Configuration);      % string
EM_Configuration = string(selectedRecord.('EM Config'));   % string
GravityAngle = string(selectedRecord.('Angle from Gravity'));

ProcessedTime = datetime("now");
Notes = selectedRecord.('Notes');

forceSensorFile = string(selectedRecord.('Force Sensor Filename')) + ".csv";
imuFile = string(selectedRecord.('IMU Filename')) + ".csv";

% Script parameters used for event detection.
hz = scriptParameters.hz;
imu_linThresh = scriptParameters.linThreshold;
imu_gyrThresh = scriptParameters.gyrThreshold;
imu_refPer = scriptParameters.refractoryPeriod;

% Model parameters used by the SOCP.
mu    = parameters.mu;
r_x   = parameters.r_x;
r_y   = parameters.r_y;
r_eff = parameters.reff;
mass  = parameters.m;

% Per-contact variables, indexed by contact i = 1...nc.
f_d     = parameters.Fd;
s       = parameters.s;
gravity = parameters.gravity;
c       = parameters.c;

% Adjoint transforms stored as a 6x6 cell array.
A = parameters.G;    

fullpath = fullfile(folder, filename);

fid = fopen(fullpath, 'w');
if fid == -1
    error('Failed to create output file: %s', fullpath);
end

if isdatetime(ProcessedTime)
    StartTimeStr = char(ProcessedTime, 'dd/MM/yyyy HH:mm:ss');
else
    StartTimeStr = ProcessedTime;
end

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

% ===== Post Processing Results =====
fprintf(fid, '--------------- POST PROCESSING RESULTS ---------------\n');
fprintf(fid, 'Number of Detachment Events      : %d\n', ppdata.detached_count);
fprintf(fid, '\n');
fprintf(fid, 'True Positive Events             : %d\n', ppdata.true_positive_count);
fprintf(fid, 'True Positive Rate               : %.2f %%\n', ppdata.true_positive);
fprintf(fid, '\n');

fprintf(fid, 'Mean W Margin                   : %.6f\n', ppdata.w_margin);
fprintf(fid, 'W Margin STDDEV                 : ');
fprintf(fid, '%.6f %%\n', ppdata.w_margin_std);
fprintf(fid, '\n');

fprintf(fid, 'Average Optimisation Frequency   : %.2f Hz\n', ...
    ppdata.average_loop_speed);
fprintf(fid, 'Average Loop Time                : %.3f ms\n', ...
    1000 / ppdata.average_loop_speed);
fprintf(fid, '\n');

% ===== Footer =====
fprintf(fid, '==================== END OF REPORT ====================\n');

% ===== Close file =====
fclose(fid);

% ===== Optional confirmation =====
fprintf('Report written to: %s\n', fullpath);
end


function displayTableAndSaveCSV(inputTable)

    % Create UI window
    fig = uifigure('Name', 'Table Viewer', ...
                   'Position', [100 100 800 500]);

    % Display table
    uit = uitable(fig, ...
                  'Data', inputTable, ...
                  'Position', [20 70 760 400]);

    % Add save button
    btn = uibutton(fig, ...
                   'Text', 'Save CSV', ...
                   'Position', [20 20 100 30], ...
                   'ButtonPushedFcn', @(src,event) saveCSV(inputTable));

end


function saveCSV(inputTable)

    % Ask user where to save
    [file, path] = uiputfile('*.csv', 'Save Table As');

    % User cancelled
    if isequal(file,0)
        return
    end

    % Save table
    writetable(inputTable, fullfile(path,file));

    % Confirmation
    uialert(gcf, 'Table saved successfully.', 'Saved');

end