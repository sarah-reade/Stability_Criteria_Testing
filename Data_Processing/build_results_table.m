function outputTable = build_results_table(rootDir,detachSeverity)
% Builds dataset + provides filtering + aggregation utilities
if nargin < 2
    detachSeverity = "Motion";
end

if nargin < 1
    rootDir = fullfile(pwd, 'Force_Sensor_Data');
end

files = dir(fullfile(rootDir, '*', 'metaData.txt'));

% =========================
% STORAGE
% =========================
layout = {};
angle = {};
em = {};
surface = {};
lt = {};

true_positive = [];
detached_count = [];
true_positive_count = [];
fz_count = [];
tip_count = [];
fric_count = [];

w_margin = [];
w_margin_std = [];

% =========================
% PARSE FILES
% =========================
for i = 1:numel(files)

    filePath = fullfile(files(i).folder, files(i).name);
    txt = fileread(filePath);

    c = extractValue(txt,'Configuration');
    a = extractValue(txt,'Angle from Gravity');
    e = extractValue(txt,'EM Configuration');
    s = extractValue(txt,'Surface');
    loop_time = extractValue(txt,'Average Loop Time');


    if detachSeverity == "Motion"
        subheading = '---- Any Motion ----';
    else
        subheading = '---- Full Detachment ----';
        detachSeverity = "Detachment";
    end

    dc = extractNumeric(txt, sprintf('Number of %s Events', detachSeverity));
    tp = extractNumeric(txt,'True Positive Rate',subheading);
    tpc = extractNumeric(txt,'True Positive Events',subheading);

    fz_c = extractNumeric(txt,'Fz Count',subheading);
    tip_c = extractNumeric(txt,'Tip Count',subheading);
    fric_c = extractNumeric(txt,'Fric Count',subheading);

    wm = extractNumeric(txt,'Mean W Margin',subheading);
    wms = extractNumeric(txt,'W Margin STDDEV',subheading);


    if isempty(c) || isempty(a) || isempty(e)
        continue
    end


    layout{end+1,1} = c;
    angle{end+1,1} = a;       % keep raw angle
    em{end+1,1} = e;          % keep raw EM
    surface{end+1,1} = s;  
    lt{end+1,1} = loop_time;


    true_positive(end+1,1) = tp;
    detached_count(end+1,1) = dc;
    true_positive_count(end+1,1) = tpc;
    fz_count(end+1,1) = fz_c;
    tip_count(end+1,1) = tip_c;
    fric_count(end+1,1) = fric_c;

    w_margin(end+1,1) = wm;
    w_margin_std(end+1,1) = wms;
end

% =========================
% RAW TABLE
% =========================
rawTable = table(layout, angle, em, surface, true_positive,detached_count,true_positive_count,w_margin, w_margin_std, lt, ...
    fz_count,tip_count,fric_count,...
    'VariableNames', {'Configuration','Angle','EM_Config', 'Surface', ...
                      'TruePositiveRate','DetachmentCount','TruePositiveCount','WrenchMargin','WrenchMarginStd','LoopTime_ms',...
                      'FzCount','TipCount','FricCount'});

% =========================
% AGGREGATE
% =========================
outputTable = aggregateGroups(rawTable);

% =========================
% CLEAN UP OUTPUT TABLE
% =========================
outputTable = cleanTable(outputTable);

end


function outputTable = aggregateGroups(rawTable)

    % change all on-on to on and off-off to off
    rawTable.EM_Config(strcmp(rawTable.EM_Config, 'on-on')) = {'on'};
    rawTable.EM_Config(strcmp(rawTable.EM_Config, 'off-off')) = {'off'};

    %% generate list of different configs
    layouts = getUnique(rawTable.Configuration);
    angles  = getUnique(rawTable.Angle);
    em      = getUnique(rawTable.EM_Config);
    surface = getUnique(rawTable.Surface);

    %% create all combinations
    [S, E, A, L] = ndgrid(surface, em, angles, layouts);

    outputTable = table(L(:), A(:), E(:), S(:), ...
                        'VariableNames', {'Configuration','Angle','EM_Config','Surface'});
    outputTableData = table('Size',[0 9], ...
    'VariableTypes',{'double','double','double','double','double','double','double','double','double'}, ...
    'VariableNames',{'TruePositiveRate','DetachmentCount','TruePositiveCount',...
                     'WrenchMargin','WrenchMarginStd','LoopTime_ms',...
                      'FzCount','TipCount','FricCount'});

    %% loop all raw data and aggregate information
    for i = 1:size(outputTable,1)
        % config is all the check if em are all, then check if 
        mask = getMask(rawTable,outputTable.Configuration(i),outputTable.Angle(i),outputTable.EM_Config(i),outputTable.Surface(i));
        outputTableData(i,:) = combineResults(rawTable,mask);
    end

    outputTable = [outputTable,outputTableData];

end

function output = getUnique(input)
    values = string(unique(input));

    if numel(values) > 1
        output = ["all"; values];
    else
        output = values;
    end
end

function mask = getMask(data,layout,angle,em_config,surface)
    mask = true(height(data),1);

    if layout ~= "all"
        mask = mask & data.Configuration == layout;
    end

    if angle ~= "all"
        mask = mask & data.Angle == angle;
    end

    if em_config ~= "all"
        mask = mask & data.EM_Config == em_config;
    end

    if surface ~= "all"
        mask = mask & data.Surface == surface;
    end

end

function output = combineResults(data,mask)

    if nargin < 2 || any(isnan(mask))
        mask = ones(length(data));
    end

    mask = mask & ~isnan(data.DetachmentCount) & data.DetachmentCount ~= 0;

    if all(mask == 0)
        output = table(NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
                    'VariableNames', {'TruePositiveRate','DetachmentCount','TruePositiveCount','WrenchMargin','WrenchMarginStd','LoopTime_ms',...
                      'FzCount','TipCount','FricCount'});
        return;
    end

    % mask data
    data = data(mask,:);

    % calculate the results
    detach_count = sum(data.DetachmentCount);
    true_positive_count = sum(data.TruePositiveCount);
    if detach_count ~= 0
        true_positive_rate = 100*true_positive_count/detach_count;
        fz_percent = 100*sum(data.FzCount)/true_positive_count;
        tip_percent = 100*sum(data.TipCount)/true_positive_count;
        fric_percent = 100*sum(data.FricCount)/true_positive_count;
    else
        true_positive_rate = NaN;
        fz_percent =  NaN;
        tip_percent =  NaN;
        fric_percent =  NaN;
    end



    w_margin_sum = 0;
    w_margin_std_sum = 0;
    for i = 1:height(data)
        w_margin_sum = w_margin_sum + data.WrenchMargin(i)*(data.DetachmentCount(i)-1);
        w_margin_std_sum = w_margin_std_sum + (data.WrenchMarginStd(i)^2)*(data.DetachmentCount(i)-2);
    end

    if detach_count-height(data) ~= 0
        w_margin = w_margin_sum/(detach_count-height(data));
        if detach_count-2*height(data) ~= 0
            w_margin_std = sqrt(w_margin_std_sum/(detach_count-2*height(data)));
        else
            w_margin_std = NaN;
        end
    else
        w_margin = NaN;
        w_margin_std = NaN;
    end

    loop_time = sum(str2double(erase(string(data.LoopTime_ms), " ms")))/height(data);
    

    output = table(true_positive_rate, detach_count, true_positive_count, w_margin, w_margin_std, loop_time, ...
                    fz_percent, tip_percent, fric_percent, ...
                    'VariableNames', {'TruePositiveRate','DetachmentCount','TruePositiveCount','WrenchMargin','WrenchMarginStd','LoopTime_ms',...
                      'FzCount','TipCount','FricCount'});
    

end

% =========================================================
% PARSERS
% =========================================================
function val = extractValue(txt, key)
expr = [key '\s*:\s*([^\n\r%]+)'];
tok = regexp(txt, expr, 'tokens', 'once');
if isempty(tok)
    val = '';
else
    val = strtrim(tok{1});
end
end

function num = extractNumeric(txt, key, subheading)
if nargin < 3
    expr = [regexptranslate('escape', key) ...
            '\s*:\s*([-+]?\d*\.?\d+|NaN)'];
else
    expr = [regexptranslate('escape', subheading) ...
            '.*?' ...
            regexptranslate('escape', key) ...
            '\s*:\s*([-+]?\d*\.?\d+|NaN)'];
end

tok = regexp(txt, expr, 'tokens', 'once', 'dotall');

if isempty(tok)
    num = NaN;
else
    num = str2double(tok{1});
end
end

function table = cleanTable(inputTable)
    table = rmmissing(inputTable, 'DataVariables', ...
    {'TruePositiveRate', 'DetachmentCount', 'TruePositiveCount', ...
     'WrenchMargin', 'WrenchMarginStd', 'LoopTime_ms',...
     'FzCount','TipCount','FricCount'});

end