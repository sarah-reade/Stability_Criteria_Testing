function parameters = getParams(config,angle,emconfig,surface)
    % Set contact variables that define the optimisation problem.
    % these are different for each configuration and angle to gravity, but include:
    % g The gravity vector relative to the force sensor
    % Gg Transformation matrix from gravity wrench to sensor wrench
    % m mass of the system
    % Fd,i Nominal magnetic adhesion force.
    % si ∈ [0, 1] Surface magnetic permeability coefficient.
    % ci ∈ [0, 1] Contact confidence coefficient.
    % Gi Transformation matrix from contact wrench to sensor wrench.
    % µi Coefficient of friction.
    % ri Contact support radius.
    % reff,i Effective frictional-torque radius.
    
    persistent CACHE

    key = sprintf('%s_%s_%s_%s', config, string(angle), string(emconfig), string(surface));

    if isempty(CACHE)
        CACHE = containers.Map;
    end

    if isKey(CACHE, key)
        parameters = CACHE(key);
        return;
    end

    % disp('--- Debug Inputs ---');

    % fprintf('config: %s | class: %s | size: %s\n', ...
    %     string(config), class(config), mat2str(size(config)));

    % fprintf('angle: %s | class: %s | size: %s\n', ...
    %     string(angle), class(angle), mat2str(size(angle)));

    % fprintf('emconfig: %s | class: %s | size: %s\n', ...
    %     string(emconfig), class(emconfig), mat2str(size(emconfig)));
    
    if ~ismember(config, {'flat','RA','single'})
        error('Invalid config "%s". Must be one of: flat, RA, single.', config);
    end

    parameters.mu = 1.0;
    r = 0.077;
    parameters.r_x = r/2;
    parameters.r_y = r/2;
    parameters.reff = r/2;%*10;

    m_em = 0.4;
    m_pm = 0.002*19;
    m_force = 0.09;
    m_EM_plate = 0.275;
    m_EM_Interface_Single = 0.275;
    m_EM_Interface_Long = 0.166;
    m_Flat_Plate = 0.197;
    m_RA_Plate = 0.272;

    Gg = zeros(6,6);

    c = 1.0;
    p_magnet = 450;
    em_magnet = 1400;

    mag_s = 0.0;
    if ismember(surface, {'steelbeam'})
        mag_s = 0.9;
    elseif ismember(surface, {'shelf'})
        mag_s = 0.1;
    end

    if ismember(config, {'flat','RA'})
        % Contact confidence
        parameters.c = [c,c]; % Account for lack of coverage

        % Calculate Adhesion Force
        mask = parseOnOff(emconfig);
        parameters.Fd = [p_magnet,p_magnet] + mask'.*[em_magnet,em_magnet];
    end
    
    if strcmp(config,'single')
        % Contact confidence
        parameters.c = [c]; % Account for lack of coverage

        % Calculate Adhesion Force
        mask = double(emconfig == "on");
        parameters.Fd = p_magnet + mask * 1400;
        
        % Set surface magnetic permeability
        if ~strcmp(angle,'0')
            parameters.s = [mag_s];
        else
            parameters.s = zeros(1,1);
        end 

        % Calculate G_i Wrench Transormation Matrix
        parameters.G = cell(1,1);
        trans = [0 0 70.533]*0.001;
        rot = eye(3);
        parameters.G{1} = getGMatrix(trans,rot);

        % Calculate mass
        parameters.m = m_EM_Interface_Single + m_EM_plate + m_force + m_pm + m_em;

        % CoM to Sensor Wrench Transormation Matrix
        trans = [0.0 0.0 47.0220]*0.001;
        rot = eye(3);
        Gg = getGMatrix(trans,rot);
        
    
    elseif strcmp(config,'flat')
        % Set surface magnetic permeability
        if ~strcmp(angle,'0')
            parameters.s = [mag_s,mag_s];
        else
            parameters.s = zeros(2,1);
        end 

        % Calculate G_i Wrench Transormation Matrix
        parameters.G = cell(2,1);

        trans = [77.1820; -63.8840; 69.0410]*0.001;
        rot = [0.6428  -0.7660  0.0000;
            0.7660   0.6428  0.0000;
            0.0000   0.0000  1.0000];

        parameters.G{1} = getGMatrix(trans, rot);

        trans = [-271.0299; 220.6576; 68.5300]*0.001;
        rot = [0.6428  -0.7660  0.0000;
            0.7660   0.6428  0.0000;
            0.0000   0.0000  1.0000];

        parameters.G{2} = getGMatrix(trans, rot);

        % Calculate mass
        parameters.m = m_EM_Interface_Long*2 + m_Flat_Plate + m_EM_plate + m_force + m_pm + m_em;

        % CoM to Sensor Wrench Transormation Matrix
        trans = [-97.8237 82.0855 68.5300]*0.001;
        rot = eye(3);
        Gg = getGMatrix(trans,rot);

    elseif strcmp(config,'RA')
        % Set surface magnetic permeability
        if ~strcmp(angle,'0')
            parameters.s = [mag_s,mag_s];
        else
            parameters.s = [0.0,mag_s];
        end 
        
        % Calculate G_i Wrench Transormation Matrix
        parameters.G = cell(2,1);

        trans = [77.1820; -63.8840; 69.0410]*0.001;
        rot = [0.6428  -0.7660  0.0000;
            0.7660   0.6428  0.0000;
            0.0000   0.0000  1.0000];

        parameters.G{1} = getGMatrix(trans, rot);

        trans = [-165.2400; 138.6500; -246.4600]*0.001;
        rot = [0.6428  0.0000  -0.7660;
            0.7660  0.0000  0.6428;
            0.0000  -1.0000  0.0000];

        parameters.G{2} = getGMatrix(trans, rot);

        % Calculate mass
        parameters.m = m_EM_Interface_Long*2 + m_RA_Plate + m_EM_plate + m_force + m_pm + m_em;

        % CoM to Sensor Wrench Transormation Matrix
        trans = [-44.0290 37.3830 -88.7095]*0.001;
        rot = eye(3);
        Gg = getGMatrix(trans,rot);
    end
    
    g_base = [0.0,0.0,-9.81];
        

    if strcmp(angle,'0')
        g = rotateVector(g_base,pi,'x');
    elseif strcmp(angle,'90')
        g = rotateVector(g_base,pi/2,'x');
        g = rotateVector(g,deg2rad(-40),'z'); % rotate to match sensor frame in x and y
    elseif strcmp(angle,'90V')
        g = rotateVector(g_base,pi/2,'x');
        g = rotateVector(g,deg2rad(-130),'z'); % rotate to match sensor frame in x and y
    else
        g = reshape(g_base,3,1);
    end 
    
    % Append the rotational components expected by the wrench transform.
    g = [g', 0, 0, 0];

    parameters.gravity = Gg*g.';

    %print_parameters(parameters);
    parameters.m = parameters.m*1.5;
    
end


function v_rot = rotateVector(vector, angle, axis)
%ROTATEVECTOR Rotate a 3D vector about principal axes (x, y, z)
%
% Inputs:
%   vector - 3x1 or 1x3 vector
%   angle  - rotation angle in radians
%   axis   - 'x', 'y', or 'z' (case-insensitive)
%
% Output:
%   v_rot  - rotated 3x1 vector

v = vector(:);

axis = lower(axis);

switch axis
    case 'x'
        R = [1 0 0;
             0 cos(angle) -sin(angle);
             0 sin(angle)  cos(angle)];

    case 'y'
        R = [ cos(angle) 0 sin(angle);
              0          1 0;
             -sin(angle) 0 cos(angle)];

    case 'z'
        R = [cos(angle) -sin(angle) 0;
             sin(angle)  cos(angle) 0;
             0           0          1];

    otherwise
        error('Axis must be ''x'', ''y'', or ''z''.');
end

v_rot = R * v;

end

function GMatrix = getGMatrix(trans,rotMat)
    % Ensure correct shapes
    trans = trans(:);

    % Skew-symmetric matrix of translation vector
    p_hat = [    0      -trans(3)  trans(2);
            trans(3)    0       -trans(1);
            -trans(2)  trans(1)     0     ];

    % Wrench transformation matrix (force-moment transformation)
    GMatrix = [rotMat, zeros(3,3);
            p_hat * rotMat, rotMat];
end

function out = parseOnOff(s)
    parts = split(string(s), "-");
    out = double(parts == "on");
end