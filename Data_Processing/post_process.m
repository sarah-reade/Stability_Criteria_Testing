function ppdata = post_process(data, margin)

    %% ---------------- Defaults ----------------
    if nargin < 2 || isempty(margin)
        margin = 0;
    end

    % If input is filepath, load as table
    if ischar(data) || isstring(data)
        data = readtable(data);
    end

    n = height(data);

    %% ---------------- Init outputs ----------------
    ppdata.true_positive = 0;
    ppdata.false_positive = 0;
    ppdata.detached_count = 0;
    ppdata.true_positive_count = 0;
    ppdata.attached_duration = 0;
    ppdata.false_positive_duration = 0;
    ppdata.average_loop_speed = 0;

    %% ---------------- Extract signals ----------------
    t = data.time;
    attached = data.attached;
    gamma = data.gamma;

    %% ---------------- State transition tracking ----------------
    detached_start = [];
    detached_end = [];

    for i = 2:n
        % 1 -> 0 : entering detached state
        if attached(i-1) == 1 && attached(i) == 0
            detached_start(end+1) = t(i);
            
        if any(gamma(max(1,i-3):min(n,i+3)) <= margin)
            ppdata.true_positive_count = ppdata.true_positive_count + 1;
        end
        
        % 0 -> 1 : exiting detached state
        elseif attached(i-1) == 0 && attached(i) == 1
            detached_end(end+1) = t(i);
        end
    end

    % Ensure pairing integrity
    num_segments = min(length(detached_start), length(detached_end));
    ppdata.detached_count = num_segments;

    %% ---------------- True positive logic ----------------

    if ppdata.detached_count > 0
        ppdata.true_positive = 100 * ppdata.true_positive_count / ppdata.detached_count;
    else
        ppdata.true_positive = NaN;
    end

    %% ---------------- Duration calculations ----------------

    % Attached duration: sum time differences when attached == 1
    dt = diff(t);
    ppdata.attached_duration = sum(dt(attached(1:end-1) == 1));

    % False positive duration:
    % ASSUMPTION: gamma <= margin while ATTACHED (bad signal during attachment)
    fp_mask = (attached == 1) & (gamma <= margin);
    ppdata.false_positive_duration = sum(dt(fp_mask(1:end-1)));

    if ppdata.attached_duration > 0
        ppdata.false_positive = ...
            100* ppdata.false_positive_duration / ppdata.attached_duration;
    else
        ppdata.false_positive = NaN;
    end

    %% ---------------- Average loop speed ----------------
    % ASSUMPTION: loop speed = inverse of loopTime
    if ismember('loopTime', data.Properties.VariableNames)
        valid = data.loopTime > 0;
        ppdata.average_loop_speed = mean(1 ./ data.loopTime(valid));
    else
        ppdata.average_loop_speed = NaN;
    end

end