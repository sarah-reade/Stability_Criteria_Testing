function outDir = saveData(csvMeta,overwrite,time,wrench,imuData,variables,gamma_out,motionTimepoints,loop_time,parameters,selectedRecord,scriptParameters)
    datetime_string = csvMeta.startTime;
    datetime_string = replace(datetime_string, [" ", "/", ":"], "_");
    outDir = make_directory(datetime_string,overwrite);
    
    
    export_sensor_dataset_csv( outDir, ...
       time,wrench,imuData,variables,gamma_out,motionTimepoints,loop_time);
    
    ppdata = post_process(outDir+"/data.csv",parameters.reff,10,10);

    save_meta_data(outDir, 'metaData.txt', selectedRecord,parameters,scriptParameters,ppdata)
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
    T.Fx   = wrenchData(:,1);
    T.Fy   = wrenchData(:,2);
    T.Fz   = wrenchData(:,3);
    T.Taux = wrenchData(:,4);
    T.Tauy = wrenchData(:,5);
    T.Tauz = wrenchData(:,6);

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
    Surface = string(selectedRecord.('Surface'));   % string
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
    fprintf(fid, 'Surface: %s\n', Surface);
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