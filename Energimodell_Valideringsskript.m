%% ============================================================
%  VISUALISERING/VALIDERING AV ENERGIMODELL - ENDELIG 
%    Figur 1: Predikert vs observert energiproxy (scatter)
%    Figur 2: Tidsserie — modell vs observert energiproxy
%    Figur 3: Fold-vis R^2 (kross-validering)
%% ============================================================

clear; clc; close all;

%% 1) Last data
modelDataFile = 'MergedData_NEW.csv';

V2 = readtable(modelDataFile, 'Delimiter', ',', 'VariableNamingRule', 'preserve');
V2.timestamp = datetime(string(V2.timestamp), ...
    'InputFormat', 'yyyy-MM-dd HH:mm:ssXXX', 'TimeZone', 'UTC');
V2.timestamp.TimeZone = '';
V2 = sortrows(V2, 'timestamp');
[~, ia] = unique(V2.timestamp, 'stable');
V2 = V2(ia, :);
V2 = fillmissing(V2, 'previous');

N = height(V2);
timeVec = V2.timestamp;

% Energy proxy
energy_proxy = V2.mainoutput_comprhigh + V2.mainoutput_comprlow + V2.mainoutput_fans;
energy_proxy = fillmissing(energy_proxy, 'constant', 0);

% Prediktorer
dv_halltemp = V2.hall_temp;
valve_sp    = V2.valve_two_setvalue;
pump_freq   = V2.flowpump_freqout;
dv_glycol_dT = V2.glycol_in - V2.glycol_out;

X_all = [ones(N,1), valve_sp, pump_freq, dv_halltemp, dv_glycol_dT];
y_all = energy_proxy;

%% 2) 5-fold kross-validering for å få "ærlige" prediksjoner for hele datasettet
K = 5;
rng(42);
perm_cv = randperm(N); % For å randomisere datapunkter
fold_size = floor(N / K);
cv_indices = zeros(N, 1);
for k = 1:K
    if k < K
        idx_fold = perm_cv((k-1)*fold_size+1 : k*fold_size);
    else
        idx_fold = perm_cv((k-1)*fold_size+1 : end);
    end
    cv_indices(idx_fold) = k;
end

% Få prediksjoner for hver datapunkt (men trent uten det punktet)
y_pred_cv = zeros(N, 1);
R2_folds  = zeros(K, 1);
RMSE_folds = zeros(K, 1);

for k = 1:K
    test_mask  = (cv_indices == k);
    train_mask = ~test_mask;

    beta_cv = X_all(train_mask,:) \ y_all(train_mask);
    y_pred_cv(test_mask) = X_all(test_mask,:) * beta_cv;

    y_actual = y_all(test_mask);
    y_pred   = y_pred_cv(test_mask);
    R2_folds(k)   = 1 - sum((y_actual - y_pred).^2) / sum((y_actual - mean(y_actual)).^2);
    RMSE_folds(k) = sqrt(mean((y_actual - y_pred).^2));
end

R2_mean  = mean(R2_folds);
R2_std   = std(R2_folds);
RMSE_mean = mean(RMSE_folds);

% Også en "full modell" trent på alle data (det MPC-en bruker)
beta_full = X_all \ y_all;
y_pred_full = X_all * beta_full;
R2_full = 1 - sum((y_all - y_pred_full).^2) / sum((y_all - mean(y_all)).^2);

fprintf('5-fold CV: R² = %.4f ± %.4f, RMSE = %.2f\n', R2_mean, R2_std, RMSE_mean);
fprintf('Full modell (hele datasett): R² = %.4f\n\n', R2_full);

%% 3) Fargevalg (enhetlig med MPC-koden)
c_mpc    = [0.00 0.45 0.74];   % blå (modell)
c_actual = [0.40 0.40 0.40];   % mørkegrå (observert proxy)
c_good   = [0.47 0.67 0.19];   % grønn (identitetslinje)
c_accent = [0.85 0.33 0.10];   % rød/oransje (framheving)

%% ============================================================
%  FIGUR 1: PREDIKERT vs OBSERVERT ENERGIPROXY (SCATTER)
%  Viser modellens prediksjoner direkte mot observert energiproxy.
%  Perfekt modell = alle punkter på den grønne linjen.
%% ============================================================
figure('Name','Energimodell — Predikert vs observert', ...
       'Position',[100 100 700 650], 'Color', 'w');

% Beregn grenser for plottet
lims = [min([y_all; y_pred_cv])-5, max([y_all; y_pred_cv])+5];

% Identitetslinjen (perfekt prediksjon)
plot(lims, lims, '--', 'Color', c_good, 'LineWidth', 2, ...
     'DisplayName', 'Perfekt prediksjon'); hold on;

% Scatter av CV-prediksjoner
scatter(y_all, y_pred_cv, 14, c_mpc, 'filled', ...
    'MarkerFaceAlpha', 0.25, 'MarkerEdgeColor', 'none', ...
    'DisplayName', 'Modellprediksjon');

xlabel('Observert energiproxy [% total kapasitet]', 'FontSize', 12);
ylabel('Predikert energiproxy [% total kapasitet]', 'FontSize', 12);
title({'Energimodell: predikert vs observert'; ...
       sprintf('5-fold kryssvalidering: R^2 = %.3f \\pm %.3f, RMSE = %.2f', ...
       R2_mean, R2_std, RMSE_mean)}, 'FontSize', 13);
legend('Location', 'northwest', 'FontSize', 11);
grid on;
axis equal;
xlim(lims); ylim(lims);
set(gca, 'FontSize', 11);

%% ============================================================
%  FIGUR 2: TIDSSERIE — MODELL vs OBSERVERT ENERGIPROXY
%  Viser hvordan modellen følger observert energiproxy over tid.
%  Her ser vi også hvor modellen fanger trendene og hvor den bommer.
%% ============================================================
figure('Name','Energimodell — Tidsserie', ...
       'Position',[100 100 1400 500], 'Color', 'w');

t_hr = hours(timeVec - timeVec(1));

plot(t_hr, y_all, '-', 'Color', c_actual, 'LineWidth', 0.8, ...
     'DisplayName', 'Energiproxy'); hold on;
plot(t_hr, y_pred_cv, '-', 'Color', c_mpc, 'LineWidth', 1.2, ...
     'DisplayName', sprintf('Modellprediksjon (R^2 = %.3f)', R2_mean));

xlabel('Tid [timer]', 'FontSize', 12);
ylabel('Energiproxy [% total kapasitet]', 'FontSize', 12);
title('Energimodell: prediksjon vs observert energiproxy fra data', 'FontSize', 13);
legend('Location', 'best', 'FontSize', 11);
grid on;
xlim([0, t_hr(end)]);
set(gca, 'FontSize', 11);

%% ============================================================
%  FIGUR 3: FOLD-VIS R² (ROBUSTHET)
%  Lite spredning = mer stabil modell.
%% ============================================================
figure('Name','Energimodell — Robusthet', ...
       'Position',[100 100 700 500], 'Color', 'w');

b = bar(1:K, R2_folds, 0.6, 'FaceColor', c_mpc, 'EdgeColor', 'none'); hold on;

% Linje for gjennomsnittet
yline(R2_mean, '-', 'Color', c_accent, 'LineWidth', 2, ...
    'Label', sprintf('Snitt: R^2 = %.3f', R2_mean), ...
    'LabelHorizontalAlignment', 'right', 'FontSize', 11);

% Skyggelagt område for +-1 standardavvik
fill([0.3, K+0.7, K+0.7, 0.3], ...
     [R2_mean-R2_std, R2_mean-R2_std, R2_mean+R2_std, R2_mean+R2_std], ...
     c_accent, 'FaceAlpha', 0.1, 'EdgeColor', 'none', ...
     'HandleVisibility', 'off');

% Verdietikett over hver søyle
for k = 1:K
    text(k, R2_folds(k)+0.015, sprintf('%.3f', R2_folds(k)), ...
        'HorizontalAlignment', 'center', 'FontSize', 10, 'FontWeight', 'bold');
end

xlabel('Fold', 'FontSize', 12);
ylabel('R^2 på testsett', 'FontSize', 12);
title({'Modellrobusthet: R^2 per fold i 5-fold kryssvalidering'; ...
       sprintf('Snitt %.3f \\pm %.3f', ...
       R2_mean, R2_std)}, 'FontSize', 13);
set(gca, 'XTick', 1:K, 'XTickLabel', ...
    arrayfun(@(x) sprintf('Fold %d', x), 1:K, 'UniformOutput', false), ...
    'FontSize', 11);
ylim([0, max(R2_folds)*1.2]);
grid on;

fprintf('Figurer generert. Lagre dem ved å høyreklikke i hver figur\n');
fprintf('(eller bruk "Save As" i menyen) for å eksportere til rapporten.\n');
