clear; clc; close all;

%% Sampling time
Ts = 10*60;   % 10 min [s]

%% Import CSV
RawData = readtable('MergedData_NEW_V2.csv', ...
    'Delimiter', ',', ...
    'VariableNamingRule', 'preserve');
RawData.timestamp = datetime(string(RawData.timestamp), ...
    'InputFormat', 'yyyy-MM-dd HH:mm:ssXXX', ...
    'TimeZone', 'UTC');
RawData.timestamp.TimeZone = '';
TT = table2timetable(RawData, 'RowTimes', 'timestamp');

%% Output signal
TT.IceLane2Temp = mean([TT.lanetwo_pt2, TT.lanetwo_pt3], 2, 'omitnan');

%% Inputs og output (rå)
u = [TT.valve_two_setvalue, ...
     TT.hall_temp, ...
     TT.flowpump_freqout];
y = TT.IceLane2Temp;

%% Tidsvektor
t = (0:height(TT)-1)' * Ts;

%% =========================================================
%  Z-score normalisering med normalize()
%  Returnerer også mu og sigma for back-transform
%% =========================================================
[u_norm, mu_u, sig_u] = normalize(u);
[y_norm, mu_y, sig_y] = normalize(y);

fprintf('===== NORMALISERINGSPARAMETRE =====\n');
fprintf('  mu_u  = [%.4f, %.4f, %.4f]\n', mu_u);
fprintf('  sig_u = [%.4f, %.4f, %.4f]\n', sig_u);
fprintf('  mu_y  = %.4f\n', mu_y);
fprintf('  sig_y = %.4f\n\n', sig_y);

%% =========================================================
%  Korrekt skalerte forsterkninger
%  G_norm = G_phys * sig_u(i) / sig_y
%% =========================================================
Gsp_n = tf(1.02   * sig_u(1)/sig_y, [2000 1], 'InputDelay', 0);
Gh_n  = tf(0.04   * sig_u(2)/sig_y, [2000 1], 'InputDelay', 600);
Gf_n  = tf(-0.004 * sig_u(3)/sig_y, [5000 1], 'InputDelay', 1200);

G_norm = [Gsp_n Gh_n Gf_n];

%% Simuler i normalisert domene
y_sim_norm = lsim(G_norm, u_norm, t);

%% =========================================================
%  Back-transform til fysiske verdier (°C)
%% =========================================================
y_sim_phys = y_sim_norm * sig_y + mu_y;

%% Ytelsesmål
valid_idx   = isfinite(y) & isfinite(y_sim_phys);
y_valid     = y(valid_idx);
y_sim_valid = y_sim_phys(valid_idx);

R     = corrcoef(y_valid, y_sim_valid);
R2    = R(1,2)^2;
RMSE  = sqrt(mean((y_valid - y_sim_valid).^2));
NRMSE = RMSE / std(y_valid);

fprintf('===== MODEL FIT =====\n');
fprintf('R^2   = %.4f\n', R2);
fprintf('RMSE  = %.4f °C\n', RMSE);
fprintf('NRMSE = %.4f\n\n', NRMSE);

%% Plot 1 — Fysiske verdier
figure;
plot(t/3600, y,          'y',   'DisplayName', 'Measured'); hold on;
plot(t/3600, y_sim_phys, 'r--', 'LineWidth', 1.5, ...
     'DisplayName', 'Hand tuned');
title(sprintf('Hand-tuned TF fit   R^2 = %.3f   NRMSE = %.3f', R2, NRMSE));
xlabel('Time [hours]');
ylabel('Ice temp [°C]');
legend('Location', 'best');
grid on;
set(gca, 'FontSize', 14);

%% Plot 2 — Normalisert domene
figure;
plot(t/3600, y_norm,     'y',   'DisplayName', 'Measured (norm)'); hold on;
plot(t/3600, y_sim_norm, 'r--', 'LineWidth', 1.5, ...
     'DisplayName', 'Simulated (norm)');
title('Normalisert domene');
xlabel('Time [hours]');
ylabel('y\_norm [-]');
legend('Location', 'best');
grid on;
set(gca, 'FontSize', 14);

%% Plot 3 — Stegsvar
figure;
tiledlayout(3,1)

nexttile
step(Gsp_n)
title('Valve setpoint (Gsp\_n)')

nexttile
step(Gh_n)
title('Hall temperature (Gh\_n)')

nexttile
step(Gf_n)
title('Pump frequency (Gf\_n)')

%% Save normalized model and normalization parameters for MPC
sys_tf = G_norm;

save('plant_model_lane2_3input.mat', ...
    'sys_tf', 'mu_u', 'sig_u', 'mu_y', 'sig_y', 'Ts');

fprintf('Normalisert modell lagret til plant_model_lane2_3input.mat\n');
fprintf('sys_tf er nå G_norm: u_norm -> y_norm\n');