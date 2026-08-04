function createBarGraph(rootDir,outDir)

    if nargin < 1
        rootDir = "Results";
    end

    if nargin < 2
        outDir = uigetdir(pwd, 'Select folder to save figures');
    end

    [every_result, program_list] = load_results_table(rootDir);
    close all;


    %% Common configurations
    configs = [
        "1 Contact" + char(160) + char(160)
        "2 Planar Contacts" + repmat(char(160),1,17)
        "2 Non-Planar Contacts" + repmat(char(160),1,8)
    ];

    % Custom colours
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

    for i = 1:length(every_result)
        all_results = every_result{i};

        if ~istable(all_results) || isempty(all_results)
            % Not a table or empty table
            warning(sprintf('%s table not found',program_list(i)))
            continue;
        end

        % Rename configurations in all_results
        all_results.Configuration(ismember(all_results.Configuration,"single")) = configs(1);
        all_results.Configuration(ismember(all_results.Configuration,"flat"))   = configs(2);
        all_results.Configuration(ismember(all_results.Configuration,"RA"))     = configs(3);


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

        outDir_i = fullfile(outDir, program_list(i));

        save_figures(outDir_i);
        close all;


    end

    plot_TPR_programs(every_result,program_list,barColours(5:end,:));
    plot_TPR_vs_X(every_result, program_list, barColours,'LoopTime_ms');
    plot_TPR_vs_X(every_result, program_list, barColours,'FalsePositiveRate');
    
    save_figures(outDir);

    create_summary_csv(every_result, program_list, outDir);
end

function save_figures(outDir_i)

    if ~exist(outDir_i, 'dir')
        mkdir(outDir_i);
    end


    figs = findall(0, 'Type', 'figure');

    for i = 1:numel(figs)

        fig = figs(i);

        % Generate filename
        filename = "Figure_" + string(i);
        
        % Set size
        set(fig, 'Units', 'normalized', 'OuterPosition', [0 0 0.85 1]);

        % Use your saveFigure function
        print(fig, fullfile(outDir_i, filename + ".svg"), "-dsvg");

    end

    disp('All figures saved successfully.')
end

function [all_results, program_list] = load_results_table(rootDir)
% Loads all results CSV files in a specified order

    program_list = ["SOCP", "SOCPZML", "QP32", "QP16", "QP8", "QP4", "QP8ZML", "ZML"];

    all_results = cell(numel(program_list),1);

    for i = 1:numel(program_list)
        filename = fullfile(rootDir, program_list(i) + "_Motion.csv");

        if isfile(filename)

            opts = detectImportOptions(filename);

            % Set the first four columns to strings
            opts = setvartype(opts, ...
                {'Configuration','Angle','EM_Config','Surface'}, ...
                'string');

            % Set the remaining columns to doubles
            opts = setvartype(opts, ...
                {'TruePositiveRate','DetachmentCount','TruePositiveCount', ...
                 'WrenchMargin','WrenchMarginStd','TimeAttached', ...
                 'FalsePositiveRate','LoopTime_ms', ...
                 'FzPercent','TipPercent','FricPercent'}, ...
                'double');

            all_results{i} = readtable(filename, opts);

        else
            warning("Missing file: %s", filename);
            all_results{i} = table();
        end
    end
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
    T.mean_TruePositiveRate.*T.mean_FzPercent/100, ...
    T.mean_TruePositiveRate.*T.mean_TipPercent/100, ...
    T.mean_TruePositiveRate.*T.mean_FricPercent/100];

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


function plot_TPR_programs(every_result, program_list, barColours)

% ===========================
% Plot settings
% ===========================

fontSize = 20;
fontName = 'Times New Roman';


% ===========================
% Extract data
% ===========================

Y = zeros(numel(every_result),3);
TPR = zeros(numel(every_result),1);
splitPct = zeros(numel(every_result),3);


for i = 1:numel(every_result)

    all_results = every_result{i};

    % Skip missing data
    if ~istable(all_results) || isempty(all_results)
        continue
    end

    % Select all configurations, average over angles
    t = all_results( ...
        strcmp(all_results.Surface,"all") & ...
        strcmp(all_results.EM_Config,"all") & ...
        ~strcmp(all_results.Angle,"all"), :);


    if isempty(t)
        continue
    end


    % Average values
    T = groupsummary(t, ...
        {}, ...
        'mean', ...
        {'TruePositiveRate','FzPercent','TipPercent','FricPercent'});


    % Store values
    TPR(i) = T.mean_TruePositiveRate;

    splitPct(i,:) = [
        T.mean_TruePositiveRate * T.mean_FzPercent/100, ...
        T.mean_TruePositiveRate * T.mean_TipPercent/100, ...
        T.mean_TruePositiveRate * T.mean_FricPercent/100
    ];


    % Convert percentage split into stacked heights
    Y(i,:) = [
        T.mean_TruePositiveRate * T.mean_FzPercent  / 100, ...
        T.mean_TruePositiveRate * T.mean_TipPercent / 100, ...
        T.mean_TruePositiveRate * T.mean_FricPercent/ 100
    ];

end


% ===========================
% Plot
% ===========================

figure

program_categories = categorical(program_list, program_list, 'Ordinal', true);

b = bar(program_categories, Y, ...
    'stacked', ...
    'BarWidth',0.8);

hold on


% Colours
b(1).FaceColor = barColours(1,:);
b(2).FaceColor = barColours(2,:);
b(3).FaceColor = barColours(3,:);


legend({'Fz','Tipping','Slip'}, ...
    'Location','northeast');


ylabel('True Positive Rate (%)')


% ===========================
% Add labels
% ===========================

for k = 1:size(Y,1)

    if sum(Y(k,:)) == 0
        continue
    end

    x = b(1).XEndPoints(k);

    yBottom = 0;

    for s = 1:3

        h = Y(k,s);

        if h > 0
            text(x,...
                yBottom+h/2,...
                sprintf('%.0f%%',splitPct(k,s)),...
                'HorizontalAlignment','center',...
                'VerticalAlignment','middle',...
                'FontSize',fontSize-1,...
                'FontName',fontName);
        end

        yBottom = yBottom+h;

    end


    text(x,...
        sum(Y(k,:))+2.5,...
        sprintf('%.1f%%',TPR(k)),...
        'HorizontalAlignment','center',...
        'FontSize',fontSize,...
        'FontName',fontName);

end


% ===========================
% Formatting
% ===========================

ylim([0 105])

xlabel('Controller',...
       'FontSize',fontSize*1.5,...
       'FontName',fontName,...
       'FontWeight','bold')

ylabel('True Positive Rate (%)',...
       'FontSize',fontSize*1.5,...
       'FontName',fontName,...
       'FontWeight','bold')


grid on

ax = gca;
ax.FontSize = fontSize;
ax.FontName = fontName;

hold off

end

function plot_TPR_vs_X(every_result, program_list, markerColours, xVariable)

% ===========================
% Plot settings
% ===========================

fontSize = 20;
fontName = 'Times New Roman';


% ===========================
% Extract data
% ===========================

TPR = zeros(numel(every_result),1);
X = zeros(numel(every_result),1);


for i = 1:numel(every_result)

    all_results = every_result{i};

    if ~istable(all_results) || isempty(all_results)
        continue
    end


    % Select all configurations, average over angles
    t = all_results( ...
        strcmp(all_results.Surface,"all") & ...
        strcmp(all_results.EM_Config,"all") & ...
        ~strcmp(all_results.Angle,"all"), :);


    if isempty(t)
        continue
    end


    % Average values
    T = groupsummary(t, ...
        {}, ...
        'mean', ...
        {'TruePositiveRate','LoopTime_ms','FalsePositiveRate'});


    % Store values
    TPR(i) = T.mean_TruePositiveRate;


    switch xVariable

        case 'LoopTime_ms'
            X(i) = T.mean_LoopTime_ms;

        case 'FalsePositiveRate'
            X(i) = T.mean_FalsePositiveRate;

        otherwise
            error('Unknown xVariable. Use ''LoopTime_ms'' or ''FalsePositiveRate''.')

    end

end


% ===========================
% Plot
% ===========================

figure

n = length(program_list);
markerColours = markerColours(1:n,:);

scatter(X, TPR, 120, markerColours, 'filled');

hold on


% Labels
for i = 1:length(program_list)

    if X(i) == 0
        continue
    end

    text(X(i), ...
         TPR(i)+1, ...
         program_list{i}, ...
         'FontSize',fontSize-2,...
         'FontName',fontName);

end


% ===========================
% Formatting
% ===========================

switch xVariable

    case 'LoopTime_ms'
        xlabel('Loop Time (ms)',...
               'FontSize',fontSize*1.5,...
               'FontName',fontName,...
               'FontWeight','bold');

    case 'FalsePositiveRate'
        xlabel('False Positive Rate (%)',...
               'FontSize',fontSize*1.5,...
               'FontName',fontName,...
               'FontWeight','bold');

end


ylabel('True Positive Rate (%)',...
       'FontSize',fontSize*1.5,...
       'FontName',fontName,...
       'FontWeight','bold');


ylim([0 105])

grid on

ax = gca;
ax.FontSize = fontSize;
ax.FontName = fontName;

hold off

end

function create_summary_csv(every_result, program_list, outDir)

    % Preallocate
    summary = table( ...
        strings(numel(every_result),1), ...
        zeros(numel(every_result),1), ...
        zeros(numel(every_result),1), ...
        zeros(numel(every_result),1), ...
        'VariableNames', { ...
            'Method', ...
            'TruePositiveRate', ...
            'FalsePositiveRate', ...
            'LoopTime'});


    for i = 1:numel(every_result)

        all_results = every_result{i};

        % Store method name
        summary.Method(i) = program_list(i);


        % Skip missing tables
        if ~istable(all_results) || isempty(all_results)
            summary.TruePositiveRate(i) = NaN;
            summary.FalsePositiveRate(i) = NaN;
            summary.LoopTime(i) = NaN;
            continue
        end


        % Same filtering as your plots
        t = all_results( ...
            strcmp(all_results.Surface,"all") & ...
            strcmp(all_results.EM_Config,"all") & ...
            ~strcmp(all_results.Angle,"all"), :);


        if isempty(t)
            summary.TruePositiveRate(i) = NaN;
            summary.FalsePositiveRate(i) = NaN;
            summary.LoopTime(i) = NaN;
            continue
        end


        % Average values
        T = groupsummary(t, ...
            {}, ...
            'mean', ...
            {'TruePositiveRate','FalsePositiveRate','LoopTime_ms'});


        summary.TruePositiveRate(i) = T.mean_TruePositiveRate;
        summary.FalsePositiveRate(i) = T.mean_FalsePositiveRate;
        summary.LoopTime(i) = T.mean_LoopTime_ms;

    end


    % Save CSV
    if ~exist(outDir,'dir')
        mkdir(outDir)
    end

    filename = fullfile(outDir,'summary_results.csv');

    writetable(summary, filename);

    fprintf('Summary table saved: %s\n', filename)

end