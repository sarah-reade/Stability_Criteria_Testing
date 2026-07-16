function [fig,axs] = makeFigure1(selectedRecord, csvMeta, sampleRate,time, wrench,fscsvFilename,imuData,gamma)
    infoText = buildInfoBoxString(selectedRecord, csvMeta, sampleRate, height(wrench));
    axs = [];
    % Layout: info panel, force components, torque components, derivative panel.
    fig = figure('Color', 'w', 'Name', sprintf('Force/Torque Plot - %s', fscsvFilename));
    tiledlayout(fig, 6, 1, ...
        'TileSpacing', 'compact', ...
        'Padding', 'compact');
    
    infoAx = nexttile;
    axis(infoAx, 'off');
    text(infoAx, 0.01, 0.5, infoText, ...
        'Units', 'normalized', ...
        'Interpreter', 'none', ...
        'FontName', 'Consolas', ...
        'FontSize', 10, ...
        'VerticalAlignment', 'middle', ...
        'BackgroundColor', [0.96 0.98 1.0], ...
        'EdgeColor', [0.55 0.65 0.8], ...
        'Margin', 10);
    
    
    ax = nexttile;
    plot(ax, time, wrench(:,1:3), 'LineWidth', 1.5);
    grid(ax, 'on');
    xlabel(ax, 'Time (s)');
    ylabel(ax, 'Force (N)');
    title(ax, 'Force Components', 'Interpreter', 'none');
    legend(ax, {'F_x', 'F_y', 'F_z'}, 'Location', 'best');
    hold(ax, 'on');

    axs = [axs,ax];
    
    ax = nexttile;
    plot(ax, time, wrench(:,4:6), 'LineWidth', 1.5);
    grid(ax, 'on');
    xlabel(ax, 'Time (s)');
    ylabel(ax, 'Torque (Nm)');
    title(ax, 'Torque Components', 'Interpreter', 'none');
    legend(ax, {'T_x', 'T_y', 'T_z'}, 'Location', 'best');
    hold(ax, 'on');

    axs = [axs,ax];

    ax = nexttile;
    plot(imuData.Time, [imuData.linX imuData.linY imuData.linZ], 'LineWidth', 1.5);
    grid on;
    xlabel('Time (s)');
    ylabel('Linear Acceleration');
    title('Averaged Linear Acceleration (Sensor 1 & 2)');
    legend('LinX','LinY','LinZ', 'Location', 'best');

    axs = [axs,ax];

    ax = nexttile;
    plot(imuData.Time, [imuData.gyrX imuData.gyrY imuData.gyrZ], 'LineWidth', 1.5);
    grid on;
    xlabel('Time (s)');
    ylabel('Gyroscope');
    title('Averaged Gyroscope (Sensor 1 & 2)');
    legend('GyrX','GyrY','GyrZ', 'Location', 'best');

    axs = [axs,ax];

    ax = nexttile;
    hold(ax,"on");
    grid(ax, 'on');
    
    % plot(ax, time, gamma_cnstr, 'LineWidth', 1.5);
    plot(ax, time, gamma, 'LineWidth', 1.5);
    xlabel(ax, 'Time (s)');
    ylabel(ax, 'value');
    title(ax, 'gamma', 'Interpreter', 'none');
    % legend(ax, {'gamma', 'beta'}, 'Location', 'best');

    axs = [axs,ax];
end

function infoText = buildInfoBoxString(regRow, csvMeta, sampleRate, sampleCount)
% Compose metadata shown in the top information panel.
if ismember('EM Config', regRow.Properties.VariableNames)
    emText = char(string(regRow.('EM Config')));
else
    emText = 'Not provided';
end

infoText = sprintf([ ...
    'Configuration: %s\n' ...
    'Angle from Gravity: %s\n' ...
    'EM Config: %s\n' ...
    'Surface: %s\n' ...
    'Start Time: %s\n' ...
    'Sample Rate: %.0f Hz\n' ...
    'Samples: %d\n' ...
    'Force Units: %s | Torque Units: %s\n' ...
    'Force Counts/Unit: %s | Torque Counts/Unit: %s'], ...
    char(string(regRow.Configuration)), ...
    char(string(regRow.('Angle from Gravity'))), ...
    emText, ...
    char(string(regRow.Surface)), ...
    char(csvMeta.startTime), ...
    sampleRate, ...
    sampleCount, ...
    char(csvMeta.forceUnits), ...
    char(csvMeta.torqueUnits), ...
    char(csvMeta.forceCountsPerUnit), ...
    char(csvMeta.torqueCountsPerUnit));
end