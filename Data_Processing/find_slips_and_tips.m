function [params,timestamps] = find_slips_and_tips(imuData,wrench,reff,method)

    % Build a binary motion mask using either component-wise or magnitude thresholds.

    params.linThreshold = [1.0,4.0] ;
    params.gyrThreshold = [0.06,1.0];
    params.refractoryPeriod = 0.8;
    params.wrenchThreshold = 10;


    linThreshold = params.linThreshold(1);
    s_linThreshold = params.linThreshold(2);
    gyrThreshold = params.gyrThreshold(1);
    s_gyrThreshold = params.gyrThreshold(2);
    refractoryPeriod = params.refractoryPeriod;   % seconds
    wrenchThreshold = params.wrenchThreshold;

    wrench(:,4:6) = wrench(:,4:6) ./ reff;
    W_mag = vecnorm(wrench,2,2);

    W_mag_mask = W_mag > wrenchThreshold;

    
    %% User thresholds
    [mask.start,mask.end] = getMasks(linThreshold,gyrThreshold,imuData,W_mag_mask,method);
    [s_mask.start,s_mask.end] = getMasks(s_linThreshold,s_gyrThreshold,imuData,W_mag_mask,method);

    timestamps.movementTimestamps = getTimepoints(mask,refractoryPeriod);
    timestamps.detachTimestamps = getTimepoints(s_mask,refractoryPeriod);
end

function timestamps = getTimepoints(mask,refractoryPeriod)

    % Start and end masks
    motionStart = any(mask.start{:,2:end}, 2);
    motionEnd = any(mask.end{:,2:end}, 2);

    keep = false(height(mask.start),1);
    endTimeLog = -inf(height(mask.start),1);

    inMotion = false;
    startMotionIndex = 0;
    endMotionTime = -inf;

    for maskIdx = 1:height(mask.start)

        t = mask.start.Time(maskIdx);

        %% Enter motion (high threshold)
        if ~inMotion && motionStart(maskIdx)
            inMotion = true;
            startMotionIndex = maskIdx;
            endMotionTime = -inf;
            continue
        end

        %% While in motion
        if inMotion

            % Still above end threshold -> continue motion
            if motionEnd(maskIdx)
                endMotionTime = -inf;
                continue
            end

            % Dropped below end threshold -> start refractory timer
            if endMotionTime == -inf
                endMotionTime = t;
                continue
            end

            % Confirm motion has ended
            if (t - endMotionTime) >= refractoryPeriod

                keep(startMotionIndex) = true;
                endTimeLog(startMotionIndex) = endMotionTime;

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
    timestamps = mask.start(keep,:);
    timestamps.EndTime = endTimeLog(keep);

end

function [mask_start,mask_end] = getMasks(linThreshold,gyrThreshold,imuData,W_mask,method,scalar)
    if nargin < 6
        scalar = 4;
    end
    
    if strcmp(method,'ind')
        mask_start = getIndMask(linThreshold,gyrThreshold,imuData,W_mask);
        W_mask = ones(height(W_mask));
        mask_end = getIndMask(linThreshold/scalar,gyrThreshold/scalar,imuData,W_mask);
    elseif strcmp(method,'mag')
        mask_start = getMagMask(linThreshold,gyrThreshold,imuData,W_mask);
        W_mask = ones(height(W_mask));
        mask_end = getMagMask(linThreshold/scalar,gyrThreshold/scalar,imuData,W_mask);
    end

end

function mask = getIndMask(linThreshold,gyrThreshold,imuData,W_mask)

    mask = table();

    mask.Time = imuData.Time;

    mask.LinX = abs(imuData.linX) > linThreshold & W_mask;
    mask.LinY = abs(imuData.linY) > linThreshold & W_mask;
    mask.LinZ = abs(imuData.linZ) > linThreshold & W_mask;

    mask.GyrX = abs(imuData.gyrX) > gyrThreshold & W_mask;
    mask.GyrY = abs(imuData.gyrY) > gyrThreshold & W_mask;
    mask.GyrZ = abs(imuData.gyrZ) > gyrThreshold & W_mask;
end

function mask = getMagMask(linThreshold,gyrThreshold,imuData,W_mask)

    mask = table();

    mask.Time = imuData.Time;

    mask.Lin = imuData.linX.^2+imuData.linY.^2+imuData.linZ.^2 > linThreshold^2 & W_mask;
    mask.Gyr = imuData.gyrX.^2+imuData.gyrY.^2+imuData.gyrZ.^2 > gyrThreshold^2 & W_mask;

    mask.LinX = mask.Lin;
    mask.LinY = mask.Lin;
    mask.LinZ = mask.Lin;

    mask.GyrX = mask.Gyr;
    mask.GyrY = mask.Gyr;
    mask.GyrZ = mask.Gyr;

end