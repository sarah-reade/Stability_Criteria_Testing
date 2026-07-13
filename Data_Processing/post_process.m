function ppdata = post_process(data, reff,g_margin,w_margin)

    %% ---------------- Defaults ----------------
    if nargin < 3 || isempty(g_margin)
        g_margin = 0;
        w_margin = 2;
    elseif nargin < 4 || isempty(w_margin)
        w_margin = 2;
    end

    % If input is filepath, load as table
    if ischar(data) || isstring(data)
        data = readtable(data);
    end

    n = height(data);

    %% ---------------- Init outputs ----------------
    ppdata.true_positive = 0;
    ppdata.detached_count = 0;
    ppdata.true_positive_count = 0;
    ppdata.w_margin = 0;

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
            
        if any(gamma(max(1,i-3):min(n,i+3)) <= g_margin)
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

    %% ---------------- Calculate required wrench margin ----------------
    
    w_margin_values = zeros(ppdata.detached_count,1);
    
    for k = 2:ppdata.detached_count-1
    
        % Find detachment index
        detach_idx = find(t == detached_start(k),1);
    
        % Find last reattachment before this detachment
        attach_idx = find(t == detached_end(k-1),1);
    
        if isempty(attach_idx)
            attach_idx = 1;
        end
    
        %% Wrench magnitude at detachment
    
        W_detach = norm([ ...
            data.Fx(detach_idx), ...
            data.Fy(detach_idx), ...
            data.Fz(detach_idx), ...
            data.Taux(detach_idx)/reff, ...
            data.Tauy(detach_idx)/reff, ...
            data.Tauz(detach_idx)/reff ]);
    
        %% Wrench history over attached interval
    
        Fx = data.Fx(attach_idx:detach_idx);
        Fy = data.Fy(attach_idx:detach_idx);
        Fz = data.Fz(attach_idx:detach_idx);
    
        Tx = data.Taux(attach_idx:detach_idx);
        Ty = data.Tauy(attach_idx:detach_idx);
        Tz = data.Tauz(attach_idx:detach_idx);
    
        F = vecnorm([Fx Fy Fz],2,2);
        T = vecnorm([Tx Ty Tz],2,2) / reff;
    
        W = sqrt(F.^2 + T.^2);
    
        gamma_seg = gamma(attach_idx:detach_idx);
    
        %% Identify false-positive region
    
        false_positive_samples = gamma_seg <= g_margin;
    
        if any(false_positive_samples)
    
            % Highest wrench that would still be incorrectly classified
            W_fp_max = max(W(false_positive_samples));
    
            % Margin needed to exclude all false positives
            w_margin_values(k) = W_fp_max - W_detach;
    
        else
            % No false positives, no margin required
            w_margin_values(k) = 0;
        end
    
    end
    
    %% Average required margin
    ppdata.w_margin = mean(w_margin_values);
    ppdata.w_margin_std = std(w_margin_values);


    %% ---------------- Average loop speed ----------------
    % ASSUMPTION: loop speed = inverse of loopTime
    if ismember('loopTime', data.Properties.VariableNames)
        valid = data.loopTime > 0;
        ppdata.average_loop_speed = mean(1 ./ data.loopTime(valid));
    else
        ppdata.average_loop_speed = NaN;
    end

end
