%% Build results table
all_results = build_results_table;

%% Common configurations
configs = [
    "1 Contact" + char(160) + char(160)
    "2 Planar Contacts" + repmat(char(160),1,17)
    "2 Non-Planar Contacts" + repmat(char(160),1,8)
];

% Rename configurations in all_results
all_results.Configuration(ismember(all_results.Configuration,"single")) = configs(1);
all_results.Configuration(ismember(all_results.Configuration,"flat"))   = configs(2);
all_results.Configuration(ismember(all_results.Configuration,"RA"))     = configs(3);


%% Custom colours
barColours = [
    0.6863 0.7961 0.7843   % #afcbc8
    0.7020 0.3373 0.0275   % #b35607
    0.8549 0.7412 0.7451   % #dabdbe
    0.4314 0.1804 0.2353   % #6e2e3c
    0.9216 0.8902 0.8941   % #ebe3e4
    0.4784 0.5647 0.6314   % #7a90a1
    0.9255 0.7608 0.4627   % #ecc276
    0.8157 0.6314 0.6392   % #d0a1a3
    0.8549 0.8353 0.8627   % #dad5dc
    0.4431 0.3451 0.3451   % #715858
    0.4314 0.6078 0.5529   % #6e9b8d (muted teal-green)
    0.6784 0.5765 0.7608   % #ad93c2 (muted purple)
];




%% ============================================================
% 1. True Positive Rate vs Angle
% =============================================================

plot_TPR_comparison( ...
    all_results, ...
    configs, ...
    barColours, ...
    "Angle", ...
    struct("EM_Config","all","Surface","all"));


%% ============================================================
% 2. True Positive Rate vs EM Configuration
% =============================================================

plot_TPR_comparison( ...
    all_results, ...
    configs, ...
    barColours(5:end,:), ...
    "EM_Config", ...
    struct("Angle","all","Surface","all"));


%% ============================================================
% 3. True Positive Rate vs Surface
% =============================================================

plot_TPR_comparison( ...
    all_results, ...
    configs, ...
    barColours(7:end,:), ...
    "Surface", ...
    struct("Angle","all","EM_Config","all"));


%% ============================================================
% 4. Full comparison: Configuration only
% =============================================================

plot_TPR_configuration( ...
    all_results, ...
    configs, ...
    barColours(10:end,:));

%% ============================================================
% Save all figures as .fig and .svg
% ============================================================

outDir = uigetdir(pwd, 'Select folder to save figures');

if outDir ~= 0

    figs = findall(0, 'Type', 'figure');

    for i = 1:numel(figs)

        fig = figs(i);

        % Generate filename
        filename = "Figure_" + string(i);
        
        % Set size
        set(fig, 'Units', 'normalized', 'OuterPosition', [0 0 0.85 1]);

        % Use your saveFigure function
        print(fig, fullfile(outDir, filename + ".svg"), "-dsvg");

    end

    disp('All figures saved successfully.')

else
    disp('Figure saving cancelled.')

end

%% ============================================================
% Local functions
% ============================================================

function plot_TPR_comparison(all_results, configs, barColours, ...
                             compareVar, fixedFilters)

% ===========================
% Plot settings
% ===========================

fontSize = 20;
fontName = 'Times New Roman';


% ===========================
% Select required data
% ===========================

idx = ismember(all_results.Configuration, configs);

% Apply fixed filters
fields = fieldnames(fixedFilters);

for i = 1:numel(fields)
    idx = idx & strcmp(all_results.(fields{i}), fixedFilters.(fields{i}));
end

% Remove "all" values from comparison variable
idx = idx & ~strcmp(all_results.(compareVar),"all");

t = all_results(idx,:);


% ===========================
% Convert comparison variable into columns
% ===========================

T = unstack(t(:, ...
    {'Configuration', char(compareVar), 'TruePositiveRate'}), ...
    'TruePositiveRate', char(compareVar));


% Preserve configuration order
T.Configuration = categorical(T.Configuration, configs, 'Ordinal', true);


% ===========================
% Plot
% ===========================

figure

b = bar(T.Configuration, ...
        T{:,2:end}, ...
        'grouped', ...
        'BarWidth', 0.9);


% Colours
for k = 1:min(numel(b),size(barColours,1))
    b(k).FaceColor = barColours(k,:);
end


% ===========================
% Add values / missing markers
% ===========================

hold on

for i = 1:numel(b)

    x = b(i).XEndPoints;
    y = b(i).YEndPoints;

    for j = 1:numel(y)

        if isnan(y(j)) || y(j) == 0

            % Marker line just above axis
            plot(x(j), 0.2, 'k_', ...
                'MarkerSize', 40, ...
                'LineWidth', 2.0)

            if isnan(y(j))
                label = 'N/A';
            else
                label = '0.0%';
            end

            text(x(j), 5, label, ...
                'HorizontalAlignment','center', ...
                'FontSize',fontSize, ...
                'FontName',fontName)

        else

            % Value label
            text(x(j), y(j)+0.5, ...
                sprintf('%.1f%%', y(j)), ...
                'HorizontalAlignment','center', ...
                'VerticalAlignment','bottom', ...
                'FontSize',fontSize, ...
                'FontName',fontName)

        end

    end
end


% ===========================
% Formatting
% ===========================

xlabel('Configuration', ...
       'FontSize',fontSize*1.5, ...
       'FontName',fontName, ...
       'FontWeight','bold')

ylabel('True Positive Rate (%)', ...
       'FontSize',fontSize*1.5, ...
       'FontName',fontName, ...
       'FontWeight','bold')


legend(categories(categorical(t.(compareVar))), ...
       'Location','northeast', ...
       'FontSize',fontSize, ...
       'FontName',fontName)


ylim([0 105])

grid on


ax = gca;
ax.FontSize = fontSize;
ax.FontName = fontName;

hold off

end





function plot_TPR_configuration(all_results, configs, barColours)


% ===========================
% Plot settings
% ===========================

fontSize = 20;
fontName = 'Times New Roman';


% ===========================
% Select data
% ===========================

t = all_results( ...
    ismember(all_results.Configuration, configs) & ...
    strcmp(all_results.Surface,"all") & ...
    strcmp(all_results.EM_Config,"all") & ...
    ~strcmp(all_results.Angle,"all"), :);

% Average TPR over angles
T = groupsummary(t, ...
    'Configuration', ...
    'mean', ...
    {'TruePositiveRate','FzPercent','TipPercent','FricPercent'});


% Preserve configuration order
T.Configuration = categorical(T.Configuration, configs, 'Ordinal', true);

% Convert percentage split into stacked bar heights
Y = [
    T.mean_TruePositiveRate .* T.mean_FzPercent  / 100, ...
    T.mean_TruePositiveRate .* T.mean_TipPercent / 100, ...
    T.mean_TruePositiveRate .* T.mean_FricPercent/ 100
];


% ===========================
% Plot
% ===========================

figure

b = bar(T.Configuration, Y, ...
    'stacked', ...
    'BarWidth', 0.9);

hold on

% Colours for each mechanism
b(1).FaceColor = barColours(1,:);
b(2).FaceColor = barColours(2,:);
b(3).FaceColor = barColours(3,:);

legend({'Fz','Tipping','Friction'}, ...
    'Location','northeast');

ylabel('True Positive Rate (%)')

% ===========================
% Add labels
% ===========================

% Total height of each bar (= TPR)
barTotal = sum(Y,2);

% Original percentages
splitPct = [ ...
    T.mean_FzPercent, ...
    T.mean_TipPercent, ...
    T.mean_FricPercent];

for k = 1:height(T)

    % x-location of this bar
    x = b(1).XEndPoints(k);

    %----------------------------------
    % Percent labels inside each segment
    %----------------------------------
    yBottom = 0;

    for s = 1:3

        h = Y(k,s);

        if h > 0

            text(x, ...
                yBottom + h/2, ...
                sprintf('%.0f%%', splitPct(k,s)), ...
                'HorizontalAlignment','center', ...
                'VerticalAlignment','middle', ...
                'FontSize',fontSize-1, ...
                'FontName',fontName);

        end

        yBottom = yBottom + h;

    end

    %----------------------------------
    % Overall TPR label / missing marker
    %----------------------------------
    if barTotal(k) == 0

        % Missing marker
        plot(x,0.75,'k_', ...
            'MarkerSize',20, ...
            'LineWidth',1.5);

        text(x,5,'0.0', ...
            'HorizontalAlignment','center', ...
            'FontSize',fontSize, ...
            'FontName',fontName);

    else

        text(x, ...
            barTotal(k)+0.5, ...
            sprintf('%.1f%%',T.mean_TruePositiveRate(k)), ...
            'HorizontalAlignment','center', ...
            'VerticalAlignment','bottom', ...
            'FontSize',fontSize, ...
            'FontName',fontName);

    end

end


% ===========================
% Formatting
% ===========================

xlabel('Configuration', ...
       'FontSize',fontSize*1.5, ...
       'FontName',fontName, ...
       'FontWeight','bold')

ylabel('True Positive Rate (%)', ...
       'FontSize',fontSize*1.5, ...
       'FontName',fontName, ...
       'FontWeight','bold')


ylim([0 105])

grid on


ax = gca;
ax.FontSize = fontSize;
ax.FontName = fontName;
hold off

end