function [fig, axs] = makeCombinedFigure(time, gamma, wrench, imuData, ...
                                          variables, all_beta, nc, ...
                                          fscsvFilename)
%MAKECOMBINEDFIGURE Plot sensor data, reconstructed contact variables,
% adhesion criteria, and all beta constraints.
%
% Inputs:
%   time            - Time vector for force/torque/contact data
%   gamma           - Adhesion criteria vector
%   wrench          - Force sensor wrench [Fx Fy Fz Tx Ty Tz]
%   imuData         - Structure/table containing:
%                       Time, linX, linY, linZ
%                       gyrX, gyrY, gyrZ
%   variables       - Reconstructed contact variables:
%                       [Fx Fy Fz Tx Ty Tz] for each contact
%   all_beta        - Beta constraints, size:
%                       [N x 3 x nc]
%   nc              - Number of contacts
%   fscsvFilename   - Force sensor filename, used for figure title
%
% Outputs:
%   fig             - Figure handle
%   axs             - Array of axes handles

    axs = [];

    % -------------------------------------------------------------
    % Figure / layout
    % -------------------------------------------------------------

    % Number of plots:
    %   1 gamma
    %   1 force sensor
    %   1 moment sensor
    %   1 linear acceleration
    %   1 gyroscope
    %   2 plots per contact
    %   1 all beta
    fontSize = 10;

    nTiles = 6 + 2*nc;

    fig = figure( ...
        'Color', 'w');

    tiles = tiledlayout(fig, nTiles, 1, ...
        'TileSpacing', 'compact', ...
        'Padding', 'none');



    % =============================================================
    % 1. Adhesion Criteria
    % =============================================================

    ax = nexttile;

    hold(ax, 'on');
    grid(ax, 'on');

    plot(ax, time, gamma, 'LineWidth', 1.5);

    setupXAx(ax, time);

    ylabel(ax, 'Adhesion Criteria (N)', 'FontSize', fontSize);
    title(ax, 'Adhesion Criteria', 'Interpreter', 'none');

    legend(ax, {'\gamma'}, ...
        'Location', 'northwest', 'FontSize', fontSize);

    axs = [axs, ax];


    % =============================================================
    % 2. Force Sensor Data
    % =============================================================

    ax = nexttile;

    plot(ax, time, wrench(:,1:3), ...
        'LineWidth', 1.5);

    grid(ax, 'on');

    setupXAx(ax, time);

    ylabel(ax, 'Force (N)', 'FontSize', fontSize);
    title(ax, 'Force Sensor Data', ...
        'Interpreter', 'none');

    legend(ax, ...
        {'F_x', 'F_y', 'F_z'}, ...
        'Location', 'northwest', 'FontSize', fontSize);

    axs = [axs, ax];


    % =============================================================
    % 3. Moment Sensor Data
    % =============================================================

    ax = nexttile;

    plot(ax, time, wrench(:,4:6), ...
        'LineWidth', 1.5);

    grid(ax, 'on');

    setupXAx(ax, time);

    ylabel(ax, 'Moment (Nm)', 'FontSize', fontSize);
    title(ax, 'Moment Sensor Data', ...
        'Interpreter', 'none');

    legend(ax, ...
        {'T_x', 'T_y', 'T_z'}, ...
        'Location', 'northwest', 'FontSize', fontSize);

    axs = [axs, ax];


    % =============================================================
    % 4. Linear Acceleration
    % =============================================================

    ax = nexttile;

    plot(ax, imuData.Time, ...
        [imuData.linX imuData.linY imuData.linZ], ...
        'LineWidth', 1.5);

    grid(ax, 'on');

    setupXAx(ax, time);

    ylabel(ax, 'Acceleration', 'FontSize', fontSize);
    title(ax, ...
        'Averaged Linear Acceleration (Sensor 1 & 2)', ...
        'Interpreter', 'none');

    legend(ax, ...
        {'LinX', 'LinY', 'LinZ'}, ...
        'Location', 'northwest', 'FontSize', fontSize);

    axs = [axs, ax];


    % =============================================================
    % 5. Gyroscope
    % =============================================================

    ax = nexttile;

    plot(ax, imuData.Time, ...
        [imuData.gyrX imuData.gyrY imuData.gyrZ], ...
        'LineWidth', 1.5);

    grid(ax, 'on');

    setupXAx(ax, time);

    ylabel(ax, 'Gyroscope', 'FontSize', fontSize);
    title(ax, ...
        'Averaged Gyroscope (Sensor 1 & 2)', ...
        'Interpreter', 'none');

    legend(ax, ...
        {'GyrX', 'GyrY', 'GyrZ'}, ...
        'Location', 'northwest', 'FontSize', fontSize);

    axs = [axs, ax];


    % =============================================================
    % 6+. Contact Forces and Moments
    % =============================================================

    for i = 1:nc

        % ---------------------------------------------------------
        % Contact variable columns
        % ---------------------------------------------------------

        cols = (6*(i-1)+1):(6*i);

        F = variables(:, cols(1:3));
        T = variables(:, cols(4:6));


        % ---------------------------------------------------------
        % Contact Force
        % ---------------------------------------------------------

        ax = nexttile;

        plot(ax, time, F, ...
            'LineWidth', 1.5);

        grid(ax, 'on');

        setupXAx(ax, time);

        ylabel(ax, 'Force (N)', 'FontSize', fontSize);
        title(ax, ...
            sprintf('Force Contact %d', i), ...
            'Interpreter', 'none');

        legend(ax, ...
            {'F_x', 'F_y', 'F_z'}, ...
            'Location', 'northwest', 'FontSize', fontSize);

        axs = [axs, ax];


        % ---------------------------------------------------------
        % Contact Moment
        % ---------------------------------------------------------

        ax = nexttile;

        plot(ax, time, T, ...
            'LineWidth', 1.5);

        grid(ax, 'on');

        setupXAx(ax, time);

        ylabel(ax, 'Moment (Nm)', 'FontSize', fontSize);
        title(ax, ...
            sprintf('Moment Contact %d', i), ...
            'Interpreter', 'none');

        legend(ax, ...
            {'T_x', 'T_y', 'T_z'}, ...
            'Location', 'northwest', 'FontSize', fontSize);

        axs = [axs, ax];

    end


    % =============================================================
    % Last tile: All Beta
    % =============================================================

    ax = nexttile;

    hold(ax, 'on');
    grid(ax, 'on');

    setupXAx(ax, time);

    ylabel(ax, 'Distance to Limit (N)', 'FontSize', fontSize);
    title(ax, ...
        'All Contact Constraints', ...
        'Interpreter', 'none');


    % -------------------------------------------------------------
    % Plot beta for every contact
    %
    % all_beta(:,1,i) = f_z constraint
    % all_beta(:,2,i) = tipping constraint
    % all_beta(:,3,i) = friction cone constraint
    % -------------------------------------------------------------

    names = strings(1, 3*nc);

    for i = 1:nc

        base = (i-1)*3;

        plot(ax, time, all_beta(:,1,i), ...
            'LineWidth', 1.5);

        plot(ax, time, all_beta(:,2,i), ...
            'LineWidth', 1.5);

        plot(ax, time, all_beta(:,3,i), ...
            'LineWidth', 1.5);

        names(base + 1) = ...
            sprintf('f_z_%d constraint', i);

        names(base + 2) = ...
            sprintf('tipping_%d constraint', i);

        names(base + 3) = ...
            sprintf('friction cone_%d', i);
    end

    legend(ax, names, ...
        'Location', 'northoutside', ...
        'NumColumns', min(3*nc, 6), ...
        'Interpreter', 'none', 'FontSize', fontSize);
    xlabel(ax, 'Time (s)', 'FontSize', fontSize);

    axs = [axs, ax];

end


% =================================================================
% X-axis setup
% =================================================================

function setupXAx(ax, time)


    xlim(ax, [time(1), time(end)]);

    % 5 second tick spacing
    xticks(ax, time(1):5:time(end));

end