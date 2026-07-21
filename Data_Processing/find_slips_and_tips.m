function [params,timestamps] = find_slips_and_tips(imuData,wrench,reff,method)

    % Build a binary motion mask using either component-wise or magnitude thresholds.

    params.linThreshold = [1.0,4.0] ;
    params.gyrThreshold = [0.06,0.24];
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
    N = 4;                           % Expand by 4 samples each side
    W_mag_mask = conv(double(W_mag_mask), ones(1,2*N+1), 'same') > 0;
    W_mag_mask = logical(W_mag_mask);
    
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

    linThreshold_e = linThreshold/(1+linThreshold*scalar);
    gyrThreshold_e = gyrThreshold/(1+gyrThreshold*scalar);

    if strcmp(method,'ind')
        mask_start = getIndMask(linThreshold,gyrThreshold,imuData,W_mask);
        W_mask = ones(height(W_mask));
        mask_end = getIndMask(linThreshold_e,gyrThreshold_e,imuData,W_mask);
    elseif strcmp(method,'mag')
        mask_start = getMagMask(linThreshold,gyrThreshold,imuData,W_mask);
        W_mask = ones(height(W_mask));
        mask_end = getMagMask(linThreshold_e,gyrThreshold_e,imuData,W_mask);
    elseif strcmp(method,'roll')
        mask_start = getRollMask(linThreshold,gyrThreshold,imuData,W_mask);
        mask_end = mask_start;
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

function mask = getRollMask(linThreshold,gyrThreshold,imuData,W_mask)

    mask = table();

    % Get mask where rolling average deviates
    % Get rolling average in window
    window = 5;
    rollLinThreshold = 0.04;
    rollGyrThreshold = 0.002;
    cut = 10;
    maskStartEnd = [false(cut,1); true(length(imuData.Time)-(2*cut),1);false(cut,1)];

    % Get change in rolling average
    dataLin = imuData.linX.^2+imuData.linY.^2+imuData.linZ.^2;
    dataLin = dataLin .* maskStartEnd;
    rollingAvgLin = movmean(dataLin, [0 window-1], 'Endpoints', 'discard');


    dataGyr = imuData.gyrX.^2+imuData.gyrY.^2+imuData.gyrZ.^2;
    dataGyr = dataGyr .* maskStartEnd;
    rollingAvgGyr = movmean(dataGyr, [0 window-1], 'Endpoints', 'discard');

    % create mask for when motion is detected:
    motionMaskLin = rollingAvgLin > rollLinThreshold;
    motionMaskLin = [false(window-2,1); motionMaskLin; false(window-4,1)];

    motionMaskGyr = rollingAvgGyr > rollGyrThreshold;
    motionMaskGyr = [false(window-2,1); motionMaskGyr; false(window-4,1)];

    % check each segment reaches the threshold:
    mask.Time = imuData.Time;

    mask.Lin = keepMotionPeaks(motionMaskLin,dataLin,linThreshold,W_mask);
    mask.Gyr = keepMotionPeaks(motionMaskGyr,dataGyr,gyrThreshold,W_mask);

    mask.LinX = mask.Lin;
    mask.LinY = mask.Lin;
    mask.LinZ = mask.Lin;

    mask.GyrX = mask.Gyr;
    mask.GyrY = mask.Gyr;
    mask.GyrZ = mask.Gyr;

    %% Plot linear motion detection

    % figure;

    % % Align rolling average with original data length
    % rollingAvgLinPlot = [nan(window-2,1); rollingAvgLin; nan(1,1)];

    % subplot(3,1,1)
    % plot(imuData.Time, dataLin, 'k')
    % hold on
    % yline(linThreshold, 'r--', 'Peak Threshold')
    % ylabel('Linear magnitude')
    % title('Raw linear acceleration magnitude')
    % grid on

    % subplot(3,1,2)
    % plot(imuData.Time, dataLin, 'Color', [0.7 0.7 0.7])
    % hold on
    % plot(imuData.Time, rollingAvgLinPlot, 'b', 'LineWidth', 1.5)
    % yline(rollLinThreshold, 'r--', 'Rolling Threshold')
    % ylabel('Magnitude')
    % title('Rolling average detection')
    % legend('Raw','Rolling average')
    % grid on

    % subplot(3,1,3)
    % plot(imuData.Time, motionMaskLin, 'b')
    % hold on
    % plot(imuData.Time, mask.Lin, 'r', 'LineWidth', 1.5)
    % ylabel('Mask')
    % xlabel('Time')
    % title('Motion mask before and after peak filtering')
    % legend('Initial mask','Final mask')
    % ylim([-0.1 1.1])
    % grid on

    % %% Plot gyro motion detection

    % figure;

    % rollingAvgGyrPlot = [nan(window-2,1); rollingAvgGyr; nan(1,1)];

    % subplot(3,1,1)
    % plot(imuData.Time, dataGyr, 'k')
    % hold on
    % yline(gyrThreshold, 'r--', 'Peak Threshold')
    % ylabel('Gyro magnitude')
    % title('Raw gyro magnitude')
    % grid on

    % subplot(3,1,2)
    % plot(imuData.Time, dataGyr, 'Color', [0.7 0.7 0.7])
    % hold on
    % plot(imuData.Time, rollingAvgGyrPlot, 'b', 'LineWidth', 1.5)
    % yline(rollGyrThreshold, 'r--', 'Rolling Threshold')
    % ylabel('Magnitude')
    % title('Rolling average detection')
    % legend('Raw','Rolling average')
    % grid on

    % subplot(3,1,3)
    % plot(imuData.Time, motionMaskGyr, 'b')
    % hold on
    % plot(imuData.Time, mask.Gyr, 'r', 'LineWidth', 1.5)
    % ylabel('Mask')
    % xlabel('Time')
    % title('Motion mask before and after peak filtering')
    % legend('Initial mask','Final mask')
    % ylim([-0.1 1.1])
    % grid on

    %keyboard

end

function filteredMask = keepMotionPeaks(motionMask, data, Threshold, W_mask)
% keepMotionPeaks Keeps motion regions that contain a peak above threshold
%
% Inputs:
%   motionMask : logical vector, true where motion occurs
%   data       : numeric vector containing values used for peak detection
%   Threshold  : minimum peak value required to keep a motion segment
%
% Output:
%   filteredMask : logical vector, same size as motionMask

    % Check inputs
    if ~islogical(motionMask)
        error('motionMask must be a logical array');
    end
    
    if length(motionMask) ~= length(data)
        error('motionMask and data must be the same length');
    end

    % Initialise output
    filteredMask = false(size(motionMask));

    % Find continuous true regions
    edges = diff([false; motionMask(:); false]);
    starts = find(edges == 1);
    ends = find(edges == -1) - 1;

    maskStart = W_mask(starts);

    starts = starts(maskStart);
    ends = ends(maskStart);

    % Keep regions containing a sufficient peak
    for i = 1:length(starts)
        idx = starts(i):ends(i);

        if max(data(idx)) >= Threshold
            filteredMask(idx) = true;
        end
    end
end