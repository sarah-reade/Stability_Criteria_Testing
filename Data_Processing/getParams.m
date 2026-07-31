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

    parameters.mu = 0.9;
    r = 0.077;
    parameters.r_x = r;
    parameters.r_y = r;
    parameters.reff = r;%*10;
    parameters.r = r;

    m_em = 1.0;
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
    em_magnet = 290;

    mag_s = 0.0;
    if ismember(surface, {'steelbeam'})
        mag_s = 0.15;
    elseif ismember(surface, {'shelf'})
        mag_s = 0.05;
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
        parameters.Fd = p_magnet + mask * em_magnet;
        
        % Set surface magnetic permeability
        if ~strcmp(angle,'0')
            parameters.s = [mag_s];
        else
            parameters.s = zeros(1,1);
        end 

        % Calculate G_i Wrench Transormation Matrix
        parameters.G = cell(1,1);
        parameters.trans = cell(1,1);
        trans = [0 0 70.533]*0.001;
        rot = eye(3);
        parameters.G{1} = getGMatrix(trans,rot);
        parameters.trans{1} = trans;

        % Calculate mass
        parameters.m = m_EM_Interface_Long + m_EM_plate + m_force + m_pm + m_em;
        parameters.m = parameters.m;

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
        parameters.trans = cell(2,1);

        trans = [77.1820; -63.8840; 69.0410]*0.001;
        rot = [0.6428  -0.7660  0.0000;
            0.7660   0.6428  0.0000;
            0.0000   0.0000  1.0000];

        parameters.G{1} = getGMatrix(trans, rot);
        parameters.trans{1} = trans;

        trans = [-271.0299; 220.6576; 68.5300]*0.001;
        rot = [0.6428  -0.7660  0.0000;
            0.7660   0.6428  0.0000;
            0.0000   0.0000  1.0000];

        parameters.G{2} = getGMatrix(trans, rot);
        parameters.trans{2} = trans;

        % Calculate mass
        parameters.m = m_EM_Interface_Long*2 + m_Flat_Plate + m_EM_plate*2 + m_force + m_pm*2 + m_em*2;

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
        parameters.trans = cell(2,1);

        trans = [77.1820; -63.8840; 69.0410]*0.001;
        rot = [0.6428  -0.7660  0.0000;
            0.7660   0.6428  0.0000;
            0.0000   0.0000  1.0000];

        parameters.G{1} = getGMatrix(trans, rot);
        parameters.trans{1} = trans;

        trans = [-165.2400; 138.6500; -246.4600]*0.001;
        rot = [0.6428  0.0000  -0.7660;
            0.7660  0.0000  0.6428;
            0.0000  -1.0000  0.0000];

        parameters.G{2} = getGMatrix(trans, rot);
        parameters.trans{2} = trans;

        % Calculate mass
        parameters.m = m_EM_Interface_Long*2 + m_RA_Plate + m_EM_plate*2 + m_force + m_pm*2 + m_em*2;

        % CoM to Sensor Wrench Transormation Matrix
        trans = [-44.0290 37.3830 -88.7095]*0.001;
        rot = eye(3);
        Gg = getGMatrix(trans,rot);

        if strcmp(angle,'180')
            angle = '90V';
        end
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
    % plotConfigTFs(parameters);
    % drawnow;
    % keyboard;
    
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



function plotConfigTFs(parameters)
% plotConfigTFs Plot sensor and contact transformation frames
%
% Input:
%   parameters - output from getParams()

    figure;
    hold on;
    grid on;
    axis equal;

    xlabel('X (m)')
    ylabel('Y (m)')
    zlabel('Z (m)')
    title('Configuration Transformation Frames')

    % Plot sensor frame
    plotFrame(eye(3), [0 0 0], 'Sensor');

    colours = lines(length(parameters.G));

    % Plot contact frames
    for i = 1:length(parameters.G)

        G = parameters.G{i};

        % Extract rotation
        R = G(1:3,1:3);

        % Recover translation from G matrix
        p_skew = G(4:6,1:3) * R';

        p = [
            p_skew(3,2)
            p_skew(1,3)
            p_skew(2,1)
        ];

        plotFrame(R, p, sprintf('Contact %d',i), colours(i,:));

        % Draw line from sensor to contact
        plot3([0 p(1)], ...
              [0 p(2)], ...
              [0 p(3)], ...
              '--', ...
              'Color', colours(i,:));
    end

    % Plot gravity vector
    if isfield(parameters,'gravity')

        g = parameters.gravity(1:3);

        quiver3(0,0,0,...
            g(1),g(2),g(3),...
            0.05,...
            'k',...
            'LineWidth',2,...
            'DisplayName','Gravity');

    end


    view(3);
    legend('Location','best');

end


function plotFrame(R,p,label,c)

    if nargin < 4
        c = 'k';
    end

    scale = 0.05;

    quiver3(p(1),p(2),p(3),...
        R(1,1)*scale,...
        R(2,1)*scale,...
        R(3,1)*scale,...
        0,...
        'Color','r',...
        'LineWidth',2);

    quiver3(p(1),p(2),p(3),...
        R(1,2)*scale,...
        R(2,2)*scale,...
        R(3,2)*scale,...
        0,...
        'Color','g',...
        'LineWidth',2);

    quiver3(p(1),p(2),p(3),...
        R(1,3)*scale,...
        R(2,3)*scale,...
        R(3,3)*scale,...
        0,...
        'Color','b',...
        'LineWidth',2);


    text(p(1),p(2),p(3),['  ' label],...
        'Color',c,...
        'FontSize',10);

end