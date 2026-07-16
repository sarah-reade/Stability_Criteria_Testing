function [fig,axs] = plotOptimVariables(time, variables, nc, beta, negTimeSegments,motionTimepoints)

    %PLOTOPTIMVARIABLES Plot the reconstructed contact variables and beta terms.
    axs = [];
    % Extract the envelope used for the final constraint plot.
    beta_copy = beta;
    gamma = min(min(beta_copy, [], 2), [], 3);

    fig = figure('Color', 'w', 'Name', sprintf('Optimised Variables'));
    tiledlayout(fig, nc*2+2, 1, ...
        'TileSpacing', 'compact', ...
        'Padding', 'compact');

    % ============================
    % Plot each contact wrench
    % ============================
    for i = 1:nc

        cols = (6*(i-1)+1):(6*i);

        F = variables(:, cols(1:3));
        T = variables(:, cols(4:6));

        % --- Force ---
        ax1 = nexttile;
        plot(ax1, time, F, 'LineWidth', 1.5);
        grid(ax1, 'on');
        xlabel(ax1, 'Time (s)');
        ylabel(ax1, sprintf('Force_%d', i));
        title(ax1, sprintf('Force_%d', i), 'Interpreter', 'none');
        hold(ax1, 'on');

        axs = [axs,ax1];
        

        % --- Torque ---
        ax2 = nexttile;
        plot(ax2, time, T, 'LineWidth', 1.5);
        grid(ax2, 'on');
        xlabel(ax2, 'Time (s)');
        ylabel(ax2, sprintf('Torque_%d', i));
        title(ax2, sprintf('Torque_%d', i), 'Interpreter', 'none');
        hold(ax2, 'on');
    
        axs = [axs,ax2];
        

        legend(ax1, {'F_x', 'F_y', 'F_z'}, 'Location', 'best');
        legend(ax2, {'T_x', 'T_y', 'T_z'}, 'Location', 'best');
    end

    % ============================
    % Plot gamma (last tile)
    % ============================
    axg = nexttile;

    plot(axg, time, gamma, 'LineWidth', 1.5);
    grid(axg, 'on');
    xlabel(axg, 'Time (s)');
    ylabel(axg, 'gamma\_cnstr');
    title(axg, 'gamma_cnstr', 'Interpreter', 'none');
    hold(axg, 'on');


    axs = [axs,axg];
    % ============================
    % Plot beta (contact-wise + envelope)
    % ============================
    axb = nexttile;

    hold(axb, 'on');
    grid(axb, 'on');    
    grid on;
    title(axb, 'Beta Constraints', 'Interpreter', 'none');
    xlabel('Time (s)');
    ylabel('\beta');

    names = strings(1, 4*nc);

    for i = 1:nc
        base = (i-1)*4;

        plot(time, beta(:,1,i), 'LineWidth', 1.5);
        plot(time, beta(:,2,i), 'LineWidth', 1.5);
        plot(time, beta(:,3,i), 'LineWidth', 1.5);
        plot(time, beta(:,4,i), 'LineWidth', 1.5);

        names(base + 1) = sprintf('f_z_%d constraint', i);
        names(base + 2) = sprintf('tau_x_%d constraint', i);
        names(base + 3) = sprintf('tau_y_%d constraint', i);
        names(base + 4) = sprintf('friction cone_%d', i);
        
    end

    axs = [axs,axb];

    legend(names, 'Location','best');

end