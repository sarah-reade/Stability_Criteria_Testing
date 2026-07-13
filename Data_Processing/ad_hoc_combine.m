
function acm = saveppdata(acm,ppdata,selectedRecord)
    if isempty(acm) 
        acm = table( ...
        strings(0,1), ...   % layout
        strings(0,1), ...     % angle_from_gravity
        strings(0,1), ...   % em_config
        zeros(0,1), ...     % true_positive
        zeros(0,1), ...     % detached_count
        zeros(0,1), ...     % true_positive_count
        zeros(0,1), ...     % w_margin
        zeros(0,1), ...     % w_margin_std
        'VariableNames', { ...
            'layout', ...
            'angle_from_gravity', ...
            'em_config', ...
            'true_positive', ...
            'detached_count', ...
            'true_positive_count', ...
            'w_margin', ...
            'w_margin_std' ...
        });
    end

    layout = string(selectedRecord.Configuration);      % string
    em_config = string(selectedRecord.('EM Config'));   % string
    angle_from_gravity = string(selectedRecord.('Angle from Gravity')); % string

    % Post-processing results
    true_positive      = ppdata.true_positive;
    detached_count     = ppdata.detached_count;
    true_positive_count = ppdata.true_positive_count;
    w_margin           = ppdata.w_margin;
    w_margin_std       = ppdata.w_margin_std;

    acm = [acm;
        table(layout, angle_from_gravity, em_config, ...
              true_positive, detached_count, ...
              true_positive_count, w_margin, w_margin_std)];
end 


function acm_out = combineppdata(acm)

    % Storage
    acm_out = table();

    %----------------------------------------------------------
    % 1) Exact configuration groups
    %    Keep 90 and 90V separate
    %----------------------------------------------------------
    exact = aggregate_groups(acm, ...
        {'layout','angle_from_gravity','em_config'}, ...
        "exact");

    acm_out = [acm_out; exact];


    %----------------------------------------------------------
    % 2) Layout + EM configuration groups
    %    Ignore angle
    %----------------------------------------------------------
    layout_em = aggregate_groups(acm, ...
        {'layout','em_config'}, ...
        "layout_em");

    % Fill missing angle column
    layout_em.angle_from_gravity(:) = "any";

    acm_out = [acm_out; layout_em];


    %----------------------------------------------------------
    % 3) Any group
    %----------------------------------------------------------
    any_group = aggregate_groups(acm, {}, "any");

    any_group.layout(:) = "any";
    any_group.angle_from_gravity(:) = "any";
    any_group.em_config(:) = "any";

    acm_out = [acm_out; any_group];

end



function out = aggregate_groups(acm, group_vars, group_type)

    % Find groups
    if isempty(group_vars)

        G = ones(height(acm),1);

        layout = "any";
        angle = "any";
        em = "any";

    else

        [G, vals] = findgroups(acm(:,group_vars));

        % Extract group labels
        layout = strings(max(G),1);
        angle  = strings(max(G),1);
        em     = strings(max(G),1);

        for i = 1:max(G)

            row = vals(i,:);

            if ismember("layout", group_vars)
                layout(i) = string(row.layout);
            else
                layout(i) = "any";
            end

            if ismember("angle_from_gravity", group_vars)
                angle(i) = string(row.angle_from_gravity);
            else
                angle(i) = "any";
            end

            if ismember("em_config", group_vars)
                em(i) = string(row.em_config);
            else
                em(i) = "any";
            end

        end
    end


    ng = max(G);


    % Output table
    out = table();
    out.layout = layout;
    out.angle_from_gravity = angle;
    out.em_config = em;

    out.true_positive = zeros(ng,1);
    out.detached_count = zeros(ng,1);
    out.true_positive_count = zeros(ng,1);
    out.w_margin = zeros(ng,1);
    out.w_margin_std = zeros(ng,1);

    out.group_type = repmat(string(group_type),ng,1);



    for i = 1:ng

        rows = acm(G==i,:);


        % Counts
        total_detached = sum(rows.detached_count);
        total_tp = sum(rows.true_positive_count);

        out.detached_count(i) = total_detached;
        out.true_positive_count(i) = total_tp;

        out.true_positive(i) = total_tp / total_detached;



        % Weighted mean w_margin
        n = rows.detached_count - 1;

        total_n = sum(n);

        if total_n > 0
            mu = sum(n .* rows.w_margin) / total_n;
        else
            mu = mean(rows.w_margin);
        end

        out.w_margin(i) = mu;



        % Pooled standard deviation
        if total_n > 1

            within = sum((n-1).*rows.w_margin_std.^2);

            between = sum(n .* (rows.w_margin - mu).^2);

            out.w_margin_std(i) = sqrt( ...
                (within + between) / (total_n-1));

        else
            out.w_margin_std(i) = NaN;
        end

    end

end
    