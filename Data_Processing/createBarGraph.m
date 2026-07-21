%% Build results table
all_results = build_results_table;


%% Custom colours
barColours = [
    0.6863 0.7961 0.7843   % #afcbc8
    0.4784 0.5647 0.6314   % #7a90a1
    0.7020 0.3373 0.0275   % #b35607
    0.8549 0.7412 0.7451   % #dabdbe
];


%% Common configurations
configs = ["flat","RA","single"];


%% ============================================================
% 1. True Positive Rate vs Angle
% =============================================================

t_angle = all_results( ...
    ismember(all_results.Configuration, configs) & ...
    strcmp(all_results.EM_Config,"all") & ...
    strcmp(all_results.Surface,"all") & ...
    ~strcmp(all_results.Angle,"all"), :);


T_angle = unstack(t_angle(:, ...
    {'Configuration','Angle','TruePositiveRate'}), ...
    'TruePositiveRate','Angle');


figure
b = bar(categorical(T_angle.Configuration), ...
        T_angle{:,2:end}, ...
        'grouped');

for k = 1:min(numel(b),size(barColours,1))
    b(k).FaceColor = barColours(k,:);
end

xlabel('Configuration')
ylabel('True Positive Rate (%)')
title('True Positive Rate vs Angle')
legend(categories(categorical(t_angle.Angle)), 'Location','best')
ylim([0 110])
grid on



%% ============================================================
% 2. True Positive Rate vs EM Configuration
% =============================================================

t_em_config = all_results( ...
    ismember(all_results.Configuration, configs) & ...
    strcmp(all_results.Angle,"all") & ...
    strcmp(all_results.Surface,"all") & ...
    ~strcmp(all_results.EM_Config,"all"), :);


T_em = unstack(t_em_config(:, ...
    {'Configuration','EM_Config','TruePositiveRate'}), ...
    'TruePositiveRate','EM_Config');


figure
b = bar(categorical(T_em.Configuration), ...
        T_em{:,2:end}, ...
        'grouped');

for k = 1:min(numel(b),size(barColours,1))
    b(k).FaceColor = barColours(k,:);
end

xlabel('Configuration')
ylabel('True Positive Rate (%)')
title('True Positive Rate vs EM Configuration')
legend(categories(categorical(t_em_config.EM_Config)), 'Location','best')
ylim([0 110])
grid on



%% ============================================================
% 3. True Positive Rate vs Surface
% =============================================================

t_surface = all_results( ...
    ismember(all_results.Configuration, configs) & ...
    strcmp(all_results.Angle,"all") & ...
    strcmp(all_results.EM_Config,"all") & ...
    ~strcmp(all_results.Surface,"all"), :);


T_surface = unstack(t_surface(:, ...
    {'Configuration','Surface','TruePositiveRate'}), ...
    'TruePositiveRate','Surface');


figure
b = bar(categorical(T_surface.Configuration), ...
        T_surface{:,2:end}, ...
        'grouped');

for k = 1:min(numel(b),size(barColours,1))
    b(k).FaceColor = barColours(k,:);
end

xlabel('Configuration')
ylabel('True Positive Rate (%)')
title('True Positive Rate vs Surface')
legend(categories(categorical(t_surface.Surface)), 'Location','best')
ylim([0 110])
grid on



%% ============================================================
% 4. Full comparison: Angle (excluding all)
% =============================================================

t_all = all_results( ...
    ismember(all_results.Configuration, configs) & ...
    strcmp(all_results.Surface,"all") & ...
    strcmp(all_results.EM_Config,"all") & ...
    ~strcmp(all_results.Angle,"all"), :);


T_all = unstack(t_all(:, ...
    {'Configuration','Angle','TruePositiveRate'}), ...
    'TruePositiveRate','Angle');


figure
b = bar(categorical(T_all.Configuration), ...
        T_all{:,2:end}, ...
        'grouped');

for k = 1:min(numel(b),size(barColours,1))
    b(k).FaceColor = barColours(k,:);
end

xlabel('Configuration')
ylabel('True Positive Rate (%)')
title('True Positive Rate vs Configuration and Angle')
legend(categories(categorical(t_all.Angle)), 'Location','best')
ylim([0 110])
grid on