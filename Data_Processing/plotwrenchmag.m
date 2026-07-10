clear; clc; close all;

% Load data
data = readtable('data.csv');

% Effective radius for torque normalisation
reff = 0.077; % metres

% Time
t = data.time;

% Extract wrench components
Fx = data.Fx;
Fy = data.Fy;
Fz = data.Fz;

Taux = data.Taux;
Tauy = data.Tauy;
Tauz = data.Tauz;

%% Standardise torque to equivalent force
Tx_eq = Taux / reff;
Ty_eq = Tauy / reff;
Tz_eq = Tauz / reff;

%% Calculate wrench magnitude
Wmag = sqrt(Fx.^2 + Fy.^2 + Fz.^2 + ...
            Tx_eq.^2 + Ty_eq.^2 + Tz_eq.^2);

%% Plot
figure;

% --- Wrench magnitude ---
subplot(3,1,1)
plot(t, Wmag, 'LineWidth', 1.5)
grid on
ylabel('|W| (N)')
title('Standardised Wrench Magnitude')

% --- Force components ---
subplot(3,1,2)
plot(t, Fx, 'LineWidth', 1.2)
hold on
plot(t, Fy, 'LineWidth', 1.2)
plot(t, Fz, 'LineWidth', 1.2)
grid on
ylabel('Force (N)')
title('Force Components')
legend('F_x','F_y','F_z','Location','best')

% --- Torque components ---
subplot(3,1,3)
plot(t, Taux, 'LineWidth', 1.2)
hold on
plot(t, Tauy, 'LineWidth', 1.2)
plot(t, Tauz, 'LineWidth', 1.2)
grid on
ylabel('Torque (Nm)')
xlabel('Time')
title('Torque Components')
legend('\tau_x','\tau_y','\tau_z','Location','best')

%% Optional: mark attached state
if ismember('attached', data.Properties.VariableNames)
    attached = data.attached == 1;

    for i = 1:3
        subplot(3,1,i)
        hold on
        xline(t(find(attached,1)), '--');
    end
end