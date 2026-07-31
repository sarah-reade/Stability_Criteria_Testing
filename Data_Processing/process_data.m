function process_data()
%PLOT_FORCE_SENSOR Select a registered force sensor dataset and plot it.

% Resolve data paths relative to this script so the function is portable.
scriptDir = fileparts(mfilename('fullpath'));
dataDir = fullfile(scriptDir, '..', 'Force_Sensor_Data');
dataRegPath = fullfile(dataDir, 'Data_Reg.csv');

dataReg = getDataReg(dataRegPath);

[processDataParams,selectedIdxs] = runSelectionUi(dataReg);
 overwrite = processDataParams.overwrite;
 clearPlots = processDataParams.clearPlots;
 detachSeverity = processDataParams.detachSeverity;
 calculationMethod = processDataParams.calculationMethod;

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
        targetRate = 10; % desired display rate (Hz)
        [sampleRate, wrenchData, csvMeta] = readFilterSensorCsv(fscsvPath,targetRate);
    catch ME
        msg = sprintf(['Failed to load Force Sensor CSV:\n\n%s\n\n' ...
                    'Function: %s\nLine: %d'], ...
                    ME.message, ME.stack(1).name, ME.stack(1).line);
        errordlg(msg, 'CSV Read Error');
        continue;
    end
    
    force = [wrenchData.fx_ds, wrenchData.fy_ds, wrenchData.fz_ds];
    torque = [wrenchData.tx_ds, wrenchData.ty_ds, wrenchData.tz_ds];
    time = wrenchData.time;

    % % Force normalization (remove initial offset)
    % force0 = force(1,:);              % [fx0 fy0 fz0]
    % force = force - force0;
    % 
    % % Torque normalization
    % torque0 = torque(1,:);            % [tx0 ty0 tz0]
    % torque = torque - torque0;

    try
        % Parse sample rate, sensor channels, and metadata from selected CSV.
        [imuData,imuRawData] = readFilterIMUCsv(imucsvPath,time);
        start = imuData.Time(1);
        imuData.Time = imuData.Time - start;
        time = time - start;
    catch ME
        msg = sprintf(['Failed to load IMU CSV:\n\n%s\n\n' ...
                    'Function: %s\nLine: %d'], ...
                    ME.message, ME.stack(1).name, ME.stack(1).line);
        errordlg(msg, 'CSV Read Error');
        continue;
    end

    parameters = getParams(selectedRecord.('Configuration'),string(selectedRecord.('Angle from Gravity')),selectedRecord.('EM Config'),selectedRecord.('Surface'));

    wrench = [force,torque];

    try 
        [scriptParameters,motionTimepoints] = find_slips_and_tips(imuData,wrench,parameters.reff,'roll');
        scriptParameters.hz = targetRate;
    catch ME
        msg = sprintf(['Failed to detect slips and trips:\n\n%s\n\n' ...
                    'Function: %s\nLine: %d'], ...
                    ME.message, ME.stack(1).name, ME.stack(1).line);
        errordlg(msg, 'Processing Error');
        continue;
    end



    gamma_cnstr = zeros(height(wrench),1);
    nc = numel(parameters.c);
    variables = zeros(height(wrench),nc*6 + 1);
    beta = zeros(height(wrench),1);
    all_beta = zeros(height(wrench),3,nc);
    loop_time = zeros(height(wrench),1);

    try 

        for sampleIdx = 1:height(wrench)
            tStart = tic;
            [variables(sampleIdx,:),gamma_cnstr(sampleIdx),beta(sampleIdx),all_beta(sampleIdx,:,:)] = obtainAdhesionCriteria(parameters,wrench(sampleIdx,:)',calculationMethod);
            loop_time(sampleIdx) = toc(tStart);
        end
        
    catch ME
        msg = sprintf(['Failed to obtain adhesion criteria:\n\n%s\n\n' ...
                    'Function: %s\nLine: %d'], ...
                    ME.message, ME.stack(1).name, ME.stack(1).line);
        errordlg(msg, 'Adhesion Calculation Error');
        continue;
    end
    
    
    gamma_out = beta;
    
    try 
        outDir = saveData(csvMeta,overwrite,time,wrench,imuData,variables,gamma_out,all_beta,motionTimepoints,loop_time,parameters,selectedRecord,scriptParameters);

    catch ME
        msg = sprintf(['Failed to save data:\n\n%s\n\n' ...
                    'Function: %s\nLine: %d'], ...
                    ME.message, ME.stack(1).name, ME.stack(1).line);
        errordlg(msg, 'Saving Error');
        continue;
    end
    
    margin = 0;
    
    try 
        negTimeSegments = getNegSegments(time,gamma_out,margin);
        [fig1,axs1] = makeFigure1(selectedRecord, csvMeta, sampleRate,time,wrench,fscsvFilename,imuData,gamma_out);
        plotOverlay(axs1,motionTimepoints,negTimeSegments);
        [fig2,axs2] = plotOptimVariables(time, variables, nc, all_beta, negTimeSegments, motionTimepoints);
        plotOverlay(axs2,motionTimepoints,negTimeSegments);
    
    catch ME
        msg = sprintf(['Failed to generate plots:\n\n%s\n\n' ...
                    'Function: %s\nLine: %d'], ...
                    ME.message, ME.stack(1).name, ME.stack(1).line);
        errordlg(msg, 'Plotting Error');
        continue;
    end
    
    try
        saveFigure(fig1, outDir, "fig1", fscsvFilename, imucsvFilename);
        saveFigure(fig2, outDir, "fig2", fscsvFilename, imucsvFilename);

    catch ME
        msg = sprintf(['Failed to save plots:\n\n%s\n\n' ...
                    'Function: %s\nLine: %d'], ...
                    ME.message, ME.stack(1).name, ME.stack(1).line);
        errordlg(msg, 'Saving Plots Error');
        continue;
    end
        
    
    if ~clearPlots
        close all;
    else
        drawnow;
    end
    
end

results = build_results_table(dataDir,detachSeverity);
displayTableAndSaveCSV(results,detachSeverity);

end