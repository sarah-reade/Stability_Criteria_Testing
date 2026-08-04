function displayTableAndSaveCSV(inputTable,detachSeverity,calculationMethod,autosave)
    
    if autosave
        saveCSV(inputTable,detachSeverity,calculationMethod,true)
        return
    end

    % Create UI window
    fig = uifigure('Name', sprintf('Table Viewer - Detach Severity: %s',detachSeverity), ...
                   'Position', [100 100 800 500]);

    % Display table
    uit = uitable(fig, ...
                  'Data', inputTable, ...
                  'Position', [20 70 760 400]);

    % Add save button
    btn = uibutton(fig, ...
                   'Text', 'Save CSV', ...
                   'Position', [20 20 100 30], ...
                   'ButtonPushedFcn', @(src,event) saveCSV(inputTable,detachSeverity,calculationMethod));

end


function saveCSV(inputTable,detachSeverity,calculationMethod,autosave)

    % Default filename
    defaultName = sprintf('%s_%s.csv', calculationMethod, detachSeverity);

    if autosave

        resultsFolder = fullfile(pwd, 'Results');

        if ~exist(resultsFolder, 'dir')
            mkdir(resultsFolder);
        end

        writetable(inputTable, fullfile(resultsFolder, defaultName));

        return
    end

    % Ask user where to save
    [file, path] = uiputfile('*.csv', 'Save Table As', defaultName);

    % User cancelled
    if isequal(file,0)
        return
    end

    % Save table
    writetable(inputTable, fullfile(path,file));

    % Confirmation
    uialert(gcf, 'Table saved successfully.', 'Saved');

end