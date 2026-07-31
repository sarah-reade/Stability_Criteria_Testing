function [processDataParams,selectedIdxs] = runSelectionUi(dataReg)

    if height(dataReg) == 0
        errordlg('No valid entries exist in Data_Reg.csv.', 'No Data Available');
        return;
    end

    displayItems = buildDisplayItems(dataReg);
    infoItems = buildInfoItems(dataReg);
    [overwrite,plots,detachSeverity,calculationMethod,selectedIdxs] = runSelectionDialog(displayItems, infoItems, dataReg);
    
    processDataParams.overwrite = overwrite;
    processDataParams.clearPlots = plots;
    processDataParams.detachSeverity = detachSeverity;
    processDataParams.calculationMethod = calculationMethod;

end

function displayItems = buildDisplayItems(dataReg)
% Build human-readable labels for the dataset picker.
displayItems = strings(height(dataReg), 1);

for k = 1:height(dataReg)
    idText = string(dataReg.ID(k));
    configText = string(dataReg.Configuration(k));
    angleText = string(dataReg.('Angle from Gravity')(k));
    emText = string(dataReg.('EM Config')(k));
    surfaceText = string(dataReg.('Surface')(k));

    displayItems(k) = sprintf('ID: %s | Configuration: %s | Angle: %s | EM: %s | Surface: %s' , idText, configText, angleText, emText, surfaceText);
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

function [overwrite,plots,detachSeverity,calculationMethod,selectedIdx] = runSelectionDialog(displayItems, infoItems, dataReg)
% Single-figure selector with persistent manual and rule-based selection.

selectedIdx = [];
overwrite = true;
plots = false;
detachSeverity = "Motion";
calculationMethod = "SOCP";
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

mainGridLayout = uigridlayout(controlPanel, [3 1]);
mainGridLayout.RowHeight = {60, 40, 40};
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
filterGrid = uigridlayout(mainGridLayout, [1 8]);
filterGrid.Layout.Row = 2;

filterGrid.ColumnWidth = {80, '1x', 100, '1x', 60, '1x',60, '1x'};
filterGrid.RowHeight = {24};

uilabel(filterGrid, 'Text', 'Configuration', ...
    'HorizontalAlignment', 'right');
configurationDropDown = uidropdown(filterGrid, ...
    'Items', {'All', 'flat', 'RA', 'single'}, ...
    'Value', 'All', ...
    'ValueChangedFcn', @onFilterChange);

uilabel(filterGrid, 'Text', 'AngleFromGravity', ...
    'HorizontalAlignment', 'right');
angleDropDown = uidropdown(filterGrid, ...
    'Items', {'All', '0', '90', '180', '90V'}, ...
    'Value', 'All', ...
    'ValueChangedFcn', @onFilterChange);

uilabel(filterGrid, 'Text', 'EM Config', ...
    'HorizontalAlignment', 'right');
emDropDown = uidropdown(filterGrid, ...
    'Items', {'All', 'off', 'on', 'off-off', 'on-on', 'off-on', 'on-off'}, ...
    'Value', 'All', ...
    'ValueChangedFcn', @onFilterChange);

uilabel(filterGrid, 'Text', 'Surface', ...
    'HorizontalAlignment', 'right');
surfaceDropDown = uidropdown(filterGrid, ...
    'Items', {'All', 'shelf', 'floor', 'steelbeam'}, ...
    'Value', 'All', ...
    'ValueChangedFcn', @onFilterChange);


filterGrid = uigridlayout(mainGridLayout, [1 6]);
filterGrid.Layout.Row = 3;

filterGrid.ColumnWidth = {150, '1x',150, '1x',150, 40, 80,40};
filterGrid.RowHeight = {24};

uilabel(filterGrid, 'Text', 'Detachment Severity', ...
    'HorizontalAlignment', 'right');
detachmentDropDown = uidropdown(filterGrid, ...
    'Items', {'Any Motion', 'Full Detachment'}, ...
    'Value', 'Any Motion');

uilabel(filterGrid, 'Text', 'Calculation Method', ...
    'HorizontalAlignment', 'right');
calculationDropDown = uidropdown(filterGrid, ...
    'Items', {'SOCP', 'QP', 'ZML','SOCP-ZML','QP-ZML'}, ...
    'Value', 'SOCP');

uilabel(filterGrid, ...
    'Text', sprintf('Overwrite Existing Files'), ...
    'HorizontalAlignment', 'right');
overwriteCheckbox = uicheckbox(filterGrid, ...
    'Text', '', ...
    'Value', true);

uilabel(filterGrid, ...
    'Text', sprintf('Keep Plots?'), ...
    'HorizontalAlignment', 'right');
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
footerGrid.RowHeight = {60};


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
    detachSeverity = detachmentDropDown.Value;

    if strcmp(detachSeverity, 'Any Motion')
        detachSeverity = 'Motion';
    elseif strcmp(detachSeverity, 'Full Detachment')
        detachSeverity = 'Detachment';
    end


    calculationMethod = calculationDropDown.Value;
    calculationMethod = erase(calculationMethod,"-");
    
    delete(selectionFig);
end

    function onFilterChange(~, ~)
        if isUpdatingFilters
            return;
        end

        filterState.Configuration = string(configurationDropDown.Value);
        filterState.Angle = string(angleDropDown.Value);
        filterState.EMConfig = string(emDropDown.Value);
        filterState.Surface = string(surfaceDropDown.Value);

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
        surfaceDropDown.Items = {'All', 'floor', 'shelf', 'steelbeam'};

        configurationDropDown.Value = char(keepOrResetValue(string(configurationDropDown.Value), string(configurationDropDown.Items)));
        angleDropDown.Value = char(keepOrResetValue(string(angleDropDown.Value), angleItems));
        emDropDown.Value = char(keepOrResetValue(string(emDropDown.Value), emItems));
        surfaceDropDown.Value = char(keepOrResetValue(string(surfaceDropDown.Value), string(surfaceDropDown.Items)));

        filterState.Configuration = string(configurationDropDown.Value);
        filterState.Angle = string(angleDropDown.Value);
        filterState.EMConfig = string(emDropDown.Value);
        filterState.Surface = string(surfaceDropDown.Value);

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
        selectionTableData.Surface = normalizeRowText(getRowValue(dataReg, {'Surface', 'Surface'}));
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
        rowSurface = lower(normalizeRowText(getSingleRowValue(row, {'Surface'})));

        if filters.Configuration ~= "All"
            tf = tf && rowConfig == lower(filters.Configuration);
        end

        if filters.Angle ~= "All"
            tf = tf && angleMatches(rowAngle, rowConfig, filters.Angle);
        end

        if filters.EMConfig ~= "All"
            tf = tf && emMatches(rowEm, filters.EMConfig);
        end

        if filters.Surface ~= "All"
            tf = tf && emMatches(rowSurface, filters.Surface);
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