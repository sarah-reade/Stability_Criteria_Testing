clear; clc; close all;

%% Rotation helper
rotz = @(th) [cosd(th) -sind(th) 0;
              sind(th)  cosd(th) 0;
              0         0       1];

%% Configuration definitions

configs = {};

%% Config 1
cfg.mag(1).p = [0;0;70.533];
cfg.mag(1).R = [1 0 0;
                0 1 0;
                0 0 1];

cfg.sensor.p = 2.*cfg.mag(1).p./3;
configs{1} = cfg;

%% Config 2
t = 50;
ct = cosd(t);
st = sind(t);

R1 = [ct -st 0;
      st  ct 0;
      0   0 1];

cfg = [];
cfg.mag(1).p = [-86.61;-37.04;68.53];
cfg.mag(1).p = rotateVector(cfg.mag(1).p,2*pi/3,'z');
cfg.mag(1).R = R1;

cfg.mag(2).p = [326.61;124.39;68.53];
cfg.mag(2).p = rotateVector(cfg.mag(2).p,2*pi/3,'z');
cfg.mag(2).R = R1;

% Sensor CoM
cfg.sensor.p = (cfg.mag(1).p + cfg.mag(2).p)./2;
configs{2} = cfg;

%% Config 3
t = 50;
ct = cosd(t);
st = sind(t);

R1 = [ct -st 0;
      st  ct 0;
      0   0 1];

Rflip = [ 1  0 0;
          0 0  1;
         0  -1  0];

cfg = [];
cfg.mag(1).p = [77.182;-63.884;69.041];
cfg.mag(1).R = R1;

cfg.mag(2).p = [-165.24;138.65;-246.46];
cfg.mag(2).R = R1*Rflip;

% Sensor CoM
cfg.sensor.p = (cfg.mag(1).p + cfg.mag(2).p)./2;
configs{3} = cfg;
printConfigs(configs);

%% Plot
figure('Color','w','Position',[100 100 1400 450]);

axisLength = 60;

for k = 1:3

    subplot(1,3,k);
    hold on;
    grid on;
    axis equal;
    view(3);

    title(sprintf('Configuration %d',k));

    %% Sensor frame at origin
    drawFrame([0;0;0], eye(3), axisLength, 'Sensor');

    mags = configs{k}.mag;

    %% Magnets
    for i = 1:length(mags)

        p = mags(i).p;
        R = mags(i).R;

        % position marker
        plot3(p(1),p(2),p(3), ...
            'ko','MarkerFaceColor','y','MarkerSize',8);

        % line from sensor to magnet
        plot3([0 p(1)], [0 p(2)], [0 p(3)], ...
            'k--','LineWidth',1);

        % magnet frame
        drawFrame(p,R,axisLength,...
            sprintf('M%d',i));
    end

    com = configs{k}.sensor;

    %% Sensor CoM
    p = com.p;

    % position marker
    plot3(p(1),p(2),p(3), ...
        'ko','MarkerFaceColor','c','MarkerSize',8);

    % line from origin to sensor
    plot3([0 p(1)], [0 p(2)], [0 p(3)], ...
        'b--','LineWidth',1);

    % label
    text(p(1),p(2),p(3),'  CoM', ...
        'FontWeight','bold');

    xlabel('X');
    ylabel('Y');
    zlabel('Z');

    axis vis3d;
end

%% ===== Local function =====
function drawFrame(origin,R,L,labeltxt)

xAxis = R(:,1);
yAxis = R(:,2);
zAxis = R(:,3);

quiver3(origin(1),origin(2),origin(3), ...
    L*xAxis(1),L*xAxis(2),L*xAxis(3), ...
    0,'r','LineWidth',2,'MaxHeadSize',0.3);

quiver3(origin(1),origin(2),origin(3), ...
    L*yAxis(1),L*yAxis(2),L*yAxis(3), ...
    0,'g','LineWidth',2,'MaxHeadSize',0.3);

quiver3(origin(1),origin(2),origin(3), ...
    L*zAxis(1),L*zAxis(2),L*zAxis(3), ...
    0,'b','LineWidth',2,'MaxHeadSize',0.3);

text(origin(1),origin(2),origin(3), ...
    ['  ' labeltxt], ...
    'FontWeight','bold','FontSize',10);

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

function printConfigs(configs)

for i = 1:length(configs)
    fprintf('\n========================\n');
    fprintf('Configuration %d\n', i);
    fprintf('========================\n');

    cfg = configs{i};

    for m = 1:length(cfg.mag)
        fprintf('\n--- Magnet %d ---\n', m);

        % Position
        p = cfg.mag(m).p;
        fprintf('p = [%.4f; %.4f; %.4f]\n', p(1), p(2), p(3));

        % Rotation matrix
        R = cfg.mag(m).R;
        fprintf('R = \n');
        fprintf('[%.4f  %.4f  %.4f]\n', R(1,1), R(1,2), R(1,3));
        fprintf('[%.4f  %.4f  %.4f]\n', R(2,1), R(2,2), R(2,3));
        fprintf('[%.4f  %.4f  %.4f]\n', R(3,1), R(3,2), R(3,3));
    end
    p = cfg.sensor.p;
    fprintf('\n--- CoM ---\n');
    fprintf('p = [%.4f; %.4f; %.4f]\n', p(1), p(2), p(3));


end

end