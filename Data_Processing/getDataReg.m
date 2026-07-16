function dataReg = getDataReg(dataRegPath)
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

    requiredCols = {'ID', 'Force Sensor Filename', 'IMU Filename', 'Configuration', 'Angle from Gravity','EM Config','Surface'};
    missingCols = requiredCols(~ismember(requiredCols, dataReg.Properties.VariableNames));
    if ~isempty(missingCols)
        errordlg(sprintf('The following required columns are missing:\n\n%s', strjoin(missingCols, ', ')), 'Invalid Registration File');
        return;
    end

    % Keep only rows that can be mapped to a dataset and have EM config present.
    validRows = ~ismissing(dataReg.ID) & ~ismissing(dataReg.('Force Sensor Filename')) & strlength(dataReg.('Force Sensor Filename')) > 0 & ~ismissing(dataReg.('IMU Filename')) & strlength(dataReg.('IMU Filename')) > 0 & ~ismissing(dataReg.('EM Config')) & strlength(dataReg.('EM Config')) > 0 & ~ismissing(dataReg.('Surface')) & strlength(dataReg.('Surface')) > 0;
    dataReg = dataReg(validRows, :);

end