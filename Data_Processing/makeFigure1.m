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
    setupXAx(ax, imuData)
    ylabel(ax, 'Force (N)');
    title(ax, 'Force Components', 'Interpreter', 'none');
    legend(ax, {'F_x', 'F_y', 'F_z'}, 'Location', 'northwest');
    hold(ax, 'on');

    axs = [axs,ax];
    
    ax = nexttile;
    plot(ax, time, wrench(:,4:6), 'LineWidth', 1.5);
    grid(ax, 'on');
    setupXAx(ax, imuData)
    ylabel(ax, 'Torque (Nm)');
    title(ax, 'Torque Components', 'Interpreter', 'none');
    legend(ax, {'T_x', 'T_y', 'T_z'}, 'Location', 'northwest');
    hold(ax, 'on');

    axs = [axs,ax];

    ax = nexttile;
    plot(imuData.Time, [imuData.linX imuData.linY imuData.linZ], 'LineWidth', 1.5);
    grid on;
    setupXAx(ax, imuData)
    ylabel('Linear Acceleration');
    title('Averaged Linear Acceleration (Sensor 1 & 2)');
    legend('LinX','LinY','LinZ', 'Location', 'northwest');

    axs = [axs,ax];

    ax = nexttile;
    plot(imuData.Time, [imuData.gyrX imuData.gyrY imuData.gyrZ], 'LineWidth', 1.5);
    grid on;
    setupXAx(ax, imuData)
    ylabel('Gyroscope');
    title('Averaged Gyroscope (Sensor 1 & 2)');
    legend('GyrX','GyrY','GyrZ', 'Location', 'northwest');

    axs = [axs,ax];

    ax = nexttile;
    hold(ax,"on");
    grid(ax, 'on');
    
    % plot(ax, time, gamma_cnstr, 'LineWidth', 1.5);
    plot(ax, time, gamma, 'LineWidth', 1.5);
    setupXAx(ax, imuData)
    ylabel(ax, 'Adhesion Criteria (N)');
    title(ax, 'Adhesion Crietria', 'Interpreter', 'none');
    legend(ax, {'gamma'}, 'Location', 'southwest');

    axs = [axs,ax];
end

function setupXAx(ax, imuData)
    xlabel(ax, 'Time (s)');
    xlim(ax,[imuData.Time(1) imuData.Time(end)]);
    xticks(ax, imuData.Time(1):5:imuData.Time(end));
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