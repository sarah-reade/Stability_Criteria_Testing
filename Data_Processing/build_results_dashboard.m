function dashboard = build_results_dashboard(rootDir)
% Builds dataset + provides filtering + aggregation utilities
%
% OUTPUT:
% dashboard.rawTable      -> full dataset
% dashboard.query         -> filtering function handle
% dashboard.summary       -> aggregation function handle

if nargin < 1
    rootDir = fullfile(pwd, 'Force_Sensor_Data');
end

files = dir(fullfile(rootDir, '**', 'metaData.txt'));

% =========================
% STORAGE
% =========================
cfg  = {};
ang  = {};
em   = {};

tpr  = [];
fpr  = [];
lt   = [];

% =========================
% PARSE FILES
% =========================
for i = 1:numel(files)

    filePath = fullfile(files(i).folder, files(i).name);
    txt = fileread(filePath);

    c = extractValue(txt, 'Configuration');
    a = extractValue(txt, 'Angle from Gravity');
    e = extractValue(txt, 'EM Configuration');

    tpr_i = extractNumeric(txt, 'True Positive Rate');
    fpr_i = extractNumeric(txt, 'False Positive Rate');
    lt_i  = extractNumeric(txt, 'Average Loop Time');

    if isempty(c) || isempty(a) || isempty(e)
        continue;
    end

    % Normalisation
    a = normalizeAngle(a);
    e = normalizeEM(e);

    cfg{end+1,1} = c;
    ang{end+1,1} = a;
    em{end+1,1}  = e;

    tpr(end+1,1) = tpr_i;
    fpr(end+1,1) = fpr_i;
    lt(end+1,1)  = lt_i;
end

% =========================
% RAW TABLE
% =========================
rawTable = table(cfg, ang, em, tpr, fpr, lt, ...
    'VariableNames', {'Configuration','Angle','EM_Config', ...
                      'TruePositiveRate','FalsePositiveRate','LoopTime_ms'});

% =========================
% DASHBOARD OUTPUT
% =========================
dashboard.rawTable = rawTable;
dashboard.query    = @(varargin) queryTable(rawTable, varargin{:});
dashboard.summary  = @(groupVars) summarizeTable(rawTable, groupVars);

end

% =========================================================
% QUERY ENGINE (UI FILTER STYLE)
% =========================================================
function T = queryTable(Tin, cfg, ang, em)

mask = true(height(Tin),1);

if nargin < 2 || isempty(cfg) || strcmp(cfg,'All')
else
    mask = mask & strcmp(Tin.Configuration, cfg);
end

if nargin < 3 || isempty(ang) || strcmp(ang,'All')
else
    mask = mask & strcmp(Tin.Angle, ang);
end

if nargin < 4 || isempty(em) || strcmp(em,'All')
else
    mask = mask & strcmp(Tin.EM_Config, em);
end

T = Tin(mask,:);

end

% =========================================================
% SUMMARY ENGINE (GROUPING)
% =========================================================
function S = summarizeTable(T, groupVars)

if nargin < 2
    groupVars = {'Configuration','Angle','EM_Config'};
end

S = groupsummary(T, groupVars, ...
    'mean', {'TruePositiveRate','FalsePositiveRate','LoopTime_ms'});

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

function num = extractNumeric(txt, key)
expr = [key '\s*:\s*([-+]?\d*\.?\d+|NaN)'];
tok = regexp(txt, expr, 'tokens', 'once');
if isempty(tok)
    num = NaN;
else
    num = str2double(tok{1});
end
end

% =========================================================
% NORMALISATION RULES
% =========================================================
function ang = normalizeAngle(ang)
ang = strtrim(ang);
if strcmp(ang,'90V')
    ang = '90';
end
end

function em = normalizeEM(em)
em = strtrim(em);

switch em
    case {'off-off'}
        em = 'off';
    case {'on-on'}
        em = 'on';
    case {'on-off','off-on'}
        em = 'mixed';
end
end