%% =================================================================
%  ECONOMIC MPC v10 — med flere 2-lane bookinger (ca. 40% for 2-lane
%  og ca. 60% for 4-lane)
%  =================================================================

clear; clc; close all;
fprintf('=========================================================\n');
fprintf('  ECONOMIC MPC — CURLINGHALL LANE 2 (3-input plantmodell)\n');
fprintf('  Halltemp som DV | dT_glycol-energimodell | AR(1) støy\n');
fprintf('==============================================================\n\n');

%% ============================================================
%  SEKSJON 1: INNSTILLINGER
%% ============================================================

% Filer:
modelFile     = 'plant_model_lane2_3input.mat';
modelDataFile = 'MergedData_NEW.csv';
bookingFile   = 'Flere_2026_simulerte_bookinger.csv';
priceFile     = 'strompris_lane2_2026.csv';

% Sampletid:
Ts = 10 * 60;   % 10 min i sekunder

% Temperaturintervaller [°C]:
T_idle_min  = -3.90;  T_idle_max  = -3.70;   % ref = -3.80
T_hobby_min = -4.30;  T_hobby_max = -4.10;   % ref = -4.20
T_elite_min = -4.50;  T_elite_max = -4.30;   % ref = -4.40

% MPC horisonter:
Np = 144;  % prediksjonshorisont: 24 timer
Nc = 24;   % kontrollhorisont:    4 timer

% VEKTER:
W_quality = 30; 
W_energy  = 3;  
R_du1 = 50;   
R_du2 = 100;   
W_slack   = 1e5;
W_terminal = 5000;

% MV1: ventilsetpunkt [°C]:
u1_min_phys  = -4.55;
u1_max_phys  = -3.65;
du1_min_phys = -0.1; 
du1_max_phys =  0.1; 

% MV2: pumpefrekvens [Hz]:
u2_min_phys  = 20.0;
u2_max_phys  = 90.0;
du2_min_phys = -2.0;
du2_max_phys =  2.0;

% Disturbance estimator:
alpha_dest = 0.3;

% Simulering:
N_sim = 6511; %6511 rader (hele datasettet)

% Warm-start:
N_warmup = 12;

%% ============================================================
%  SEKSJON 2: LAST PLANTMODELL OG DATA
%  Plantmodellen og normaliseringsparametrene lastes fra .mat-fil 
%  (laget i plantmodell-skriptet). 3 inputs: ventil (MV1), 
%  halltemp (DV), pumpe (MV2).
%% ============================================================
fprintf('=== SEKSJON 2: Laster plantmodell og data ===\n');

% Last plantmodell og normaliseringsparametre fra fil:
load(modelFile, 'sys_tf', 'mu_u', 'sig_u', 'mu_y', 'sig_y');
G = sys_tf;   % G(1)=ventil (MV1), G(2)=halltemp (DV), G(3)=pumpe (MV2)
fprintf('  Modell lastet fra %s\n', modelFile);
fprintf('  3 TF-er: G(1)=ventil (MV1), G(2)=halltemp (DV), G(3)=pumpe (MV2)\n');
fprintf('  mu_u  = [%.2f, %.2f, %.2f]\n', mu_u(1), mu_u(2), mu_u(3));
fprintf('  sig_u = [%.3f, %.3f, %.3f]\n', sig_u(1), sig_u(2), sig_u(3));

% --- Last driftsdata ---
V2 = readtable(modelDataFile, ...
    'Delimiter', ',', ...
    'VariableNamingRule', 'preserve');

V2.timestamp = datetime(string(V2.timestamp), ...
    'InputFormat', 'yyyy-MM-dd HH:mm:ssXXX', ...
    'TimeZone', 'UTC');
V2.timestamp.TimeZone = '';

V2 = sortrows(V2, 'timestamp');
[~, ia] = unique(V2.timestamp, 'stable');
V2 = V2(ia, :);
V2 = fillmissing(V2, 'previous');

V2.IceLane2 = mean([V2.lanetwo_pt2, V2.lanetwo_pt3], 2, 'omitnan');

N = min(N_sim, height(V2));
V2 = V2(1:N, :);
timeVec = V2.timestamp;

fprintf('  Data: %d samples (%s til %s)\n\n', N, ...
    datestr(timeVec(1),'dd.mm.yyyy'), datestr(timeVec(end),'dd.mm.yyyy'));

% --- Hent ut signaler ---
% 3 inputs: ventil, halltemp, pumpe (samme rekkefølge som plantmodellen)
u_sim_phys = [V2.valve_two_setvalue, V2.hall_temp, V2.flowpump_freqout];
y_sim_phys = V2.IceLane2;

% Normaliser signaler med parametrene fra .mat-filen:
u_sim_norm = (u_sim_phys - mu_u) ./ sig_u;
y_sim_norm = (y_sim_phys - mu_y) ./ sig_y;

%% ============================================================
%  SEKSJON 3: ENERGIMODELL (uendret struktur, dT_glycol prediktor)
%% ============================================================
fprintf('=== SEKSJON 3: Energimodell fra data ===\n');

energy_proxy = V2.mainoutput_comprhigh + V2.mainoutput_comprlow + V2.mainoutput_fans;
energy_proxy = fillmissing(energy_proxy, 'constant', 0);

% DV-kolonner for energimodellen:
dv_halltemp  = V2.hall_temp;
dv_glycol_dT = V2.glycol_out - V2.glycol_in;   % temperaturdifferanse glycolkrets

% Fyller inn manglende verdier:
dv_halltemp  = fillmissing(dv_halltemp,  'previous');
dv_glycol_dT = fillmissing(dv_glycol_dT, 'previous');

% E = b0 + b1*ventil + b2*pumpe + b3*halltemp + b4*dT_glycol
X_e = [ones(N,1), V2.valve_two_setvalue, V2.flowpump_freqout, ...
       dv_halltemp, dv_glycol_dT];
beta_e = X_e \ energy_proxy;

y_e_pred = X_e * beta_e;
SS_res = sum((energy_proxy - y_e_pred).^2);
SS_tot = sum((energy_proxy - mean(energy_proxy)).^2);
R2_e = 1 - SS_res/SS_tot;

fprintf('  E = %.1f + %.2f*ventil + %.3f*pumpe + %.2f*hallT + %.2f*dT_glycol\n', ...
    beta_e(1), beta_e(2), beta_e(3), beta_e(4), beta_e(5));
fprintf('  R² = %.4f\n', R2_e);

% Energistigninger for QP (MV1=ventil bruker sig_u(1), MV2=pumpe bruker sig_u(3)):
% MERK: nå er sig_u(1)=ventil, sig_u(2)=halltemp, sig_u(3)=pumpe
E_slope_valve = -abs(beta_e(2)) * sig_u(1);    % ventil
E_slope_pump  =  abs(beta_e(3)) * sig_u(3);    % pumpe (NB: sig_u(3) ikke sig_u(2)!)
fprintf('  dE/du1_norm = %.2f, dE/du2_norm = %.2f\n', ...
    E_slope_valve, E_slope_pump);

beta_e_halltemp  = beta_e(4);
beta_e_dT_glycol = beta_e(5);
beta_e_intercept = beta_e(1);
fprintf('  DV-koeffisienter: hallT=%.2f, dT_glycol=%.2f\n\n', ...
    beta_e_halltemp, beta_e_dT_glycol);

%% ===================================================================
%  SEKSJON 4: STEP-RESPONS FRA TRANSFERFUNKSJONER
%  Nå med 3 kanaler: ventil, halltemp, pumpe
%% ===================================================================
fprintf('=== SEKSJON 4: Step-respons fra transferfunksjoner ===\n');

Ns = Np + Nc + 100;
t_step = (0:Ns-1)' * Ts;

g_mv1   = step(G(1), t_step);   % ventil   --> is (MV1)
g_dv_h  = step(G(2), t_step);   % halltemp --> is (DV)
g_mv2   = step(G(3), t_step);   % pumpe    --> is (MV2)

% 95% responstid for ventil:
g1_ss = g_mv1(end);
idx95 = find(abs(g_mv1) >= 0.95*abs(g1_ss), 1, 'first');
t95_min = (idx95-1) * 10;

fprintf('  95%% responstid ventil: %d min = %.1f timer\n', t95_min, t95_min/60);
fprintf('  Np=%d (%dh) gir %.1f× responstid i fremtidssyn\n', ...
    Np, Np*10/60, Np*10/60/(t95_min/60));
fprintf('  G1(ss)=%.4f (ventil), G2(ss)=%.4f (halltemp), G3(ss)=%.4f (pumpe)\n\n', ...
    g_mv1(end), g_dv_h(end), g_mv2(end));

%% ================================================================
%  SEKSJON 5: DMC MATRISER
%  Sdu bygges KUN for MV (ventil, pumpe). Halltemps bidrag til
%  prediksjon håndteres separat i seksjon 10 via halltemp-step.
%% ================================================================
fprintf('=== SEKSJON 5: Bygger DMC matriser ===\n');

% DMC-matriser for MV (ventil og pumpe):
Sdu1 = buildDMCMatrix(g_mv1, Np, Nc);
Sdu2 = buildDMCMatrix(g_mv2, Np, Nc);
Sdu  = [Sdu1, Sdu2];

Tu1 = buildCumSumMatrix(Np, Nc);
Tu2 = buildCumSumMatrix(Np, Nc);

% Normaliserte grenser — pass på indekser! (1=ventil, 3=pumpe)
u1_min_n  = (u1_min_phys  - mu_u(1)) / sig_u(1);
u1_max_n  = (u1_max_phys  - mu_u(1)) / sig_u(1);
du1_min_n = du1_min_phys / sig_u(1);
du1_max_n = du1_max_phys / sig_u(1);

u2_min_n  = (u2_min_phys  - mu_u(3)) / sig_u(3);   % pumpe = indeks 3
u2_max_n  = (u2_max_phys  - mu_u(3)) / sig_u(3);
du2_min_n = du2_min_phys / sig_u(3);
du2_max_n = du2_max_phys / sig_u(3);

fprintf('  MV1 ventil: [%.2f, %.2f]°C, du=[%.3f, %.3f]°C/steg\n', ...
    u1_min_phys, u1_max_phys, du1_min_phys, du1_max_phys);
fprintf('  MV2 pumpe:  [%.0f, %.0f] Hz, du=[%.1f, %.1f] Hz/steg\n\n', ...
    u2_min_phys, u2_max_phys, du2_min_phys, du2_max_phys);

%% ============================================================
%  SEKSJON 6: STRØMPRIS
%% ============================================================
fprintf('=== SEKSJON 6: Strømpris ===\n');

P_tbl = readtable(priceFile);
P_tbl.time = datetime(P_tbl.time);

tPrice = timetable(P_tbl.price, 'RowTimes', P_tbl.time, 'VariableNames', {'price'});
tPrice_resampled = retime(tPrice, timeVec, 'previous');

price_all = tPrice_resampled.price;
price_all = fillmissing(price_all, 'previous');
price_all = fillmissing(price_all, 'next');

mPrice = median(price_all, 'omitnan');
if isnan(mPrice) || ~isfinite(mPrice); mPrice = 0.5; end
price_all = fillmissing(price_all, 'constant', mPrice);

fprintf('  Pris: snitt=%.3f, min=%.3f, max=%.3f NOK/kWh\n\n', ...
    mean(price_all,'omitnan'), min(price_all), max(price_all));

%% ==============================================================
%  SEKSJON 7: BOOKING → REFERANSEPLAN
%% ==============================================================
fprintf('=== SEKSJON 7: Referanseplan ===\n');

B = readtable(bookingFile);
B.dato     = datetime(string(B.dato), 'InputFormat', 'yyyy-MM-dd');
B.starttid = duration(string(B.starttid), 'InputFormat', 'hh:mm');
B.sluttid  = duration(string(B.sluttid),  'InputFormat', 'hh:mm');

B.start_dt = B.dato + B.starttid;
B.slutt_dt = B.dato + B.sluttid;

isLane2 = strcmpi(strtrim(string(B.lane)), '2-lane');
B2 = sortrows(B(isLane2, :), 'start_dt');

idle_ref = 0.5*(T_idle_min + T_idle_max);
r_phys    = idle_ref   * ones(N,1);
Tmin_phys = T_idle_min * ones(N,1);
Tmax_phys = T_idle_max * ones(N,1);
group_all = repmat("idle", N, 1);

mask_precool_all = false(N, 1);
terminal_ref_norm = NaN(N, 1);

for i = 1:height(B2)
    g = string(B2.brukergruppe(i));
    [Tmin_g, Tmax_g, ~, lbl] = mapGroup(g, ...
        T_idle_min, T_idle_max, T_hobby_min, T_hobby_max, ...
        T_elite_min, T_elite_max);
    target_g = 0.5*(Tmin_g + Tmax_g);
    
    if lbl == "elite"
        leadtime = hours(3);
    elseif lbl == "hobby"
        leadtime = hours(3);
    else
        leadtime = hours(0);
    end
    
    if leadtime > 0
        precool_start = B2.start_dt(i) - leadtime;
        for j = 1:height(B2)
            if B2.slutt_dt(j) > precool_start && B2.slutt_dt(j) <= B2.start_dt(i)
                precool_start = max(precool_start, B2.slutt_dt(j));
            end
        end
        mask_precool = timeVec >= precool_start & timeVec < B2.start_dt(i);
        Tmin_phys(mask_precool) = Tmin_g;
        mask_precool_all = mask_precool_all | mask_precool;
    end

    mask_book = timeVec >= B2.start_dt(i) & timeVec < B2.slutt_dt(i);
    r_phys(mask_book)    = target_g;
    Tmin_phys(mask_book) = Tmin_g;
    Tmax_phys(mask_book) = Tmax_g;
    group_all(mask_book) = lbl;

    idx_start = find(timeVec >= B2.start_dt(i), 1, 'first');
    if ~isempty(idx_start) && idx_start <= N
        terminal_ref_norm(idx_start) = (target_g - mu_y) / sig_y;
    end
end

r_norm    = (r_phys    - mu_y) ./ sig_y;
Tmin_norm = (Tmin_phys - mu_y) ./ sig_y;
Tmax_norm = (Tmax_phys - mu_y) ./ sig_y;

n_transitions = sum(diff(r_phys) ~= 0);
n_terminals = sum(~isnan(terminal_ref_norm));
fprintf('  %d bookinger (lane 2), %d step-endringer, %d terminalmål\n\n', ...
    height(B2), n_transitions, n_terminals);

%% ================================================================
%  SEKSJON 8: PLANT-SIMULATOR SETUP (AR(1) støy)
%  Nå med 3 inputs (ventil, halltemp, pumpe).
%% ================================================================
fprintf('=== SEKSJON 8: Plant-simulator ===\n');

% Beregner modellens istemperatur ved å simulere alle 3 inputs:
t_all = (0:N-1)' * Ts;
y_model_all = lsim(sys_tf, u_sim_norm, t_all);
residual_all = y_sim_norm - y_model_all;

resid_std = std(residual_all, 0, 'omitnan');
resid_ac  = corr(residual_all(1:end-1), residual_all(2:end));

rho_noise = resid_ac;
sigma_w   = resid_std * sqrt(max(1 - rho_noise^2, 0.01));

rng(42);
d_noise = zeros(N, 1);
for k = 2:N
    d_noise(k) = rho_noise * d_noise(k-1) + sigma_w * randn();
end

fprintf('  Residual: std=%.4f (norm) = %.4f°C\n', resid_std, resid_std*sig_y);
fprintf('  AR(1) støy: rho=%.3f, sigma_w=%.4f\n\n', rho_noise, sigma_w);

%% ============================================================
%  SEKSJON 9: PRECOMPUTE KONSTANTE MATRISER
%% ============================================================
fprintf('=== SEKSJON 9: Precompute QP matriser ===\n');

Ts_hours = Ts / 3600;
nDV = 2*Nc + 1;

H_q = W_quality * (Sdu' * Sdu);
H_m = blkdiag(R_du1 * eye(Nc), R_du2 * eye(Nc));
H11 = 2*(H_q + H_m);
H_base = zeros(nDV, nDV);
H_base(1:2*Nc, 1:2*Nc) = (H11 + H11') / 2;
H_base(end, end) = 2 * W_slack;

Tu1_red = Tu1(1:Nc, :);   Tu1_last = Tu1(Nc, :);
Tu2_red = Tu2(1:Nc, :);   Tu2_last = Tu2(Nc, :);
Z1_red = zeros(Nc, Nc);   Z1_one = zeros(1, Nc);

A_full = [ Tu1_red,  Z1_red, zeros(Nc,1);
           Tu1_last, Z1_one, zeros(1,1);
          -Tu1_red,  Z1_red, zeros(Nc,1);
          -Tu1_last, Z1_one, zeros(1,1);
           Z1_red,  Tu2_red, zeros(Nc,1);
           Z1_one,  Tu2_last, zeros(1,1);
           Z1_red, -Tu2_red, zeros(Nc,1);
           Z1_one, -Tu2_last, zeros(1,1);
           Sdu, -ones(Np,1);
          -Sdu, -ones(Np,1)];

lb = [du1_min_n*ones(Nc,1); du2_min_n*ones(Nc,1); 0];
ub = [du1_max_n*ones(Nc,1); du2_max_n*ones(Nc,1); 1e12];

qpOpt = optimoptions('quadprog', 'Display', 'off', ...
    'MaxIterations', 500, 'OptimalityTolerance', 1e-8);

fprintf('  H: %dx%d, A: %dx%d\n', size(H_base), size(A_full));
fprintf('  quadprog klar\n\n');

%% ============================================================
%  SEKSJON 10: MPC SIMULERING
%  NB: Halltemps fremtidige bidrag til prediksjon hentes fra 
%  datasettet (perfekt prediksjon-antakelse for DV).
%% ============================================================
fprintf('=== SEKSJON 10: MPC simulering (%d steg) ===\n', N);

% Konverter til tilstandsrom for plant-simulator:
sys_d = c2d(ss(sys_tf), Ts, 'zoh');
[A_plant, B_plant, C_plant, D_plant] = ssdata(sys_d);
nx = size(A_plant, 1);
fprintf('  State-space: nx=%d (3 inputs: ventil, halltemp, pumpe)\n', nx);

N_warmup = min(N_warmup, N - Np - 2);
k_start  = N_warmup + 1;

fprintf('  Warm-start med %d samples (%.1f timer)\n', ...
    N_warmup, N_warmup * Ts / 3600);
fprintf('  MPC starter ved k = %d\n', k_start);

u1_mpc_n = nan(N,1);   u2_mpc_n = nan(N,1);
y_mpc_n  = nan(N,1);   y_pred_n = nan(N,1);
slack_log = nan(N,1);   cost_mpc = nan(N,1);

% Halltemp (DV) i normalisert form — brukes både i plant-sim og prediksjon:
hallTemp_norm = u_sim_norm(:, 2);

% Warm-start plant-simulatoren med 3 inputs:
x_plant = zeros(nx, 1);
for kw = 1:N_warmup
    u_w = [u_sim_norm(kw,1); u_sim_norm(kw,2); u_sim_norm(kw,3)];   % 3 inputs
    x_plant = A_plant * x_plant + B_plant * u_w;
end

u1_mpc_n(k_start-1) = max(min(u_sim_norm(k_start-1,1), u1_max_n), u1_min_n);
u2_mpc_n(k_start-1) = max(min(u_sim_norm(k_start-1,3), u2_max_n), u2_min_n);

% Initial output med halltemp som DV:
u_init = [u1_mpc_n(k_start-1); hallTemp_norm(k_start-1); u2_mpc_n(k_start-1)];
y0 = C_plant * x_plant + D_plant * u_init + d_noise(k_start-1);
y_mpc_n(k_start-1)  = y0;
y_pred_n(k_start-1) = y0;

d_est = 0;
nFail = 0;

profile on;
tic;
for k = k_start:(N - Np - 1)

    yk      = y_mpc_n(k-1);
    u1_prev = u1_mpc_n(k-1);
    u2_prev = u2_mpc_n(k-1);

    if ~isnan(y_mpc_n(k-1)) && ~isnan(y_pred_n(k-1))
        d_raw = y_mpc_n(k-1) - y_pred_n(k-1);  
        d_est = alpha_dest * d_raw + (1 - alpha_dest) * d_est;
    end

    idx_h = k : min(k + Np - 1, N);
    h_len = numel(idx_h);
    pad   = Np - h_len;

    p_fut  = [price_all(idx_h);     price_all(end)*ones(pad,1)];
    r_h    = [r_norm(idx_h);        r_norm(end)*ones(pad,1)];
    Tmin_h = [Tmin_norm(idx_h);     Tmin_norm(end)*ones(pad,1)];
    Tmax_h = [Tmax_norm(idx_h);     Tmax_norm(end)*ones(pad,1)];

    % Halltemp (DV) for prediksjonshorisonten — perfekt prediksjon fra data:
    hT_h = [hallTemp_norm(idx_h); hallTemp_norm(end)*ones(pad,1)];
    % Endring i halltemp gjennom horisonten (relativt nåværende verdi):
    hT_now = hallTemp_norm(k-1);
    dhT_h = hT_h - hT_now;

    N_hist = min(150, Ns);
    du1_hist = zeros(N_hist, 1);
    du2_hist = zeros(N_hist, 1);
    dhT_hist = zeros(N_hist, 1);
    for i = 1:min(N_hist, k-2)
        ki = k - i;
        if ki >= 2
            if ~isnan(u1_mpc_n(ki)) && ~isnan(u1_mpc_n(ki-1))
                du1_hist(i) = u1_mpc_n(ki) - u1_mpc_n(ki-1);
            end
            if ~isnan(u2_mpc_n(ki)) && ~isnan(u2_mpc_n(ki-1))
                du2_hist(i) = u2_mpc_n(ki) - u2_mpc_n(ki-1);
            end
            % Halltemp er DV — bruker historiske endringer fra data:
            dhT_hist(i) = hallTemp_norm(ki) - hallTemp_norm(ki-1);
        end
    end

    % y_free: fri prediksjon uten nye kontrollendringer.
    % Inkluderer bidrag fra både MV-historikk OG halltemp (fortid + fremtid).
    y_free = yk * ones(Np, 1);
    y_free = y_free + convPastMoves(g_mv1,  du1_hist, Np);   % ventil-historikk
    y_free = y_free + convPastMoves(g_mv2,  du2_hist, Np);   % pumpe-historikk
    y_free = y_free + convPastMoves(g_dv_h, dhT_hist, Np);   % halltemp-historikk
    
    % Halltemps FREMTIDIGE bidrag til istemperaturen:
    y_free = y_free + g_dv_h(1:Np) .* dhT_h;
    
    y_free = y_free + d_est; 

    E = y_free - r_h;
    f_q = W_quality * (Sdu' * E);

    f_e1 = W_energy * Ts_hours * E_slope_valve * (Tu1' * p_fut);
    f_e2 = W_energy * Ts_hours * E_slope_pump  * (Tu2' * p_fut);

    f_vec = zeros(nDV, 1);
    f_vec(1:2*Nc) = 2*f_q + [f_e1; f_e2];

    H_step = H_base;
    f_term = zeros(nDV, 1);
    term_indices = find(~isnan(terminal_ref_norm(idx_h)));
    if ~isempty(term_indices)
        for ti = 1:numel(term_indices)
            ii = term_indices(ti);
            r_term = terminal_ref_norm(idx_h(ii));
            s_row = Sdu(ii, :);
            e_term = y_free(ii) - r_term;
            H_step(1:2*Nc, 1:2*Nc) = H_step(1:2*Nc, 1:2*Nc) ...
                + 2 * W_terminal * (s_row' * s_row);
            f_term(1:2*Nc) = f_term(1:2*Nc) ...
                + 2 * W_terminal * e_term * s_row';
        end
        H_step = (H_step + H_step') / 2;
        f_vec = f_vec + f_term;
    end

    b_upper = [ (u1_max_n - u1_prev) * ones(Nc,1);
                (u1_max_n - u1_prev);
                (u1_prev - u1_min_n) * ones(Nc,1);
                (u1_prev - u1_min_n);
                (u2_max_n - u2_prev) * ones(Nc,1);
                (u2_max_n - u2_prev);
                (u2_prev - u2_min_n) * ones(Nc,1);
                (u2_prev - u2_min_n);
                Tmax_h - y_free;
                y_free - Tmin_h ];

    if any(~isfinite(f_vec)) || any(~isfinite(b_upper))
        u1_mpc_n(k) = u1_prev;
        u2_mpc_n(k) = u2_prev;
        y_pred_n(k) = yk;
        u_plant_k = [u1_prev; hallTemp_norm(k); u2_prev];
        x_plant = A_plant * x_plant + B_plant * u_plant_k;
        y_mpc_n(k) = C_plant * x_plant + D_plant * u_plant_k + d_noise(k);
        nFail = nFail + 1;
        continue;
    end

    [z_opt, ~, exitflag] = quadprog(H_step, f_vec, A_full, b_upper, ...
        [], [], lb, ub, [], qpOpt);

    if exitflag <= 0 || isempty(z_opt)
        dU1 = 0; dU2 = 0;
        nFail = nFail + 1;
    else
        dU1 = z_opt(1);
        dU2 = z_opt(Nc + 1);
    end

    u1_mpc_n(k) = min(max(u1_prev + dU1, u1_min_n), u1_max_n);
    u2_mpc_n(k) = min(max(u2_prev + dU2, u2_min_n), u2_max_n);

    if exitflag > 0 && ~isempty(z_opt)
        slack_log(k) = z_opt(end);
        y_pred_h = y_free + Sdu * z_opt(1:2*Nc);
        y_pred_n(k) = y_pred_h(1);
    else
        y_pred_n(k) = yk;
    end

    % Plant-simulator med 3 inputs (ventil, halltemp, pumpe):
    u_plant_k = [u1_mpc_n(k); hallTemp_norm(k); u2_mpc_n(k)];
    x_plant = A_plant * x_plant + B_plant * u_plant_k;
    y_mpc_n(k) = C_plant * x_plant + D_plant * u_plant_k + d_noise(k);

    % Energikostnad (KPI-beregning):
    u1_phys_k = u1_mpc_n(k) * sig_u(1) + mu_u(1);
    u2_phys_k = u2_mpc_n(k) * sig_u(3) + mu_u(3);    % pumpe = indeks 3
    E_est = beta_e_intercept + beta_e(2)*u1_phys_k + beta_e(3)*u2_phys_k ...
          + beta_e_halltemp*dv_halltemp(k) + beta_e_dT_glycol*dv_glycol_dT(k);
    cost_mpc(k) = price_all(k) * max(E_est, 0) * Ts_hours / 100;
end

elapsed = toc;
profile off;
profile viewer;
fprintf('  MPC ferdig: %.1f sek, QP-feil: %d/%d\n\n', elapsed, nFail, N);

%% ============================================================
%  SEKSJON 11: HISTORISK BASELINE
%  Også med 3 inputs (ventil, halltemp, pumpe).
%% ============================================================
fprintf('=== SEKSJON 11: Historisk baseline ===\n');

u1_base_phys_vec = u_sim_phys(:,1);   % historisk ventilsetpunkt
u2_base_phys_vec = u_sim_phys(:,3);   % historisk pumpefrekvens (indeks 3 nå!)

y_base_n = nan(N,1);
cost_base = nan(N,1);

x_base = zeros(nx, 1);
for kw = 1:N_warmup
    u_b_w = [u_sim_norm(kw,1); u_sim_norm(kw,2); u_sim_norm(kw,3)];
    x_base = A_plant * x_base + B_plant * u_b_w;
end

u_b_init = [u_sim_norm(k_start-1,1); u_sim_norm(k_start-1,2); u_sim_norm(k_start-1,3)];
y_base_n(k_start-1) = C_plant * x_base + D_plant * u_b_init + d_noise(k_start-1);

for k = k_start:N
    u_b = [u_sim_norm(k,1); u_sim_norm(k,2); u_sim_norm(k,3)];
    x_base = A_plant * x_base + B_plant * u_b;
    y_base_n(k) = C_plant * x_base + D_plant * u_b + d_noise(k);
    
    E_b = beta_e_intercept + beta_e(2)*u1_base_phys_vec(k) + beta_e(3)*u2_base_phys_vec(k) ...
        + beta_e_halltemp*dv_halltemp(k) + beta_e_dT_glycol*dv_glycol_dT(k);
    cost_base(k) = price_all(k) * max(E_b, 0) * Ts_hours / 100;
end

fprintf('  Historisk baseline: bruker faktiske setpunkter fra datasett\n');
fprintf('  Ventil snitt=%.2f°C, Pumpe snitt=%.1f Hz\n\n', ...
    mean(u1_base_phys_vec,'omitnan'), mean(u2_base_phys_vec,'omitnan'));

%% ============================================================
%  SEKSJON 12: RESULTATER
%% ============================================================
u1_mpc_phys = u1_mpc_n * sig_u(1) + mu_u(1);
u2_mpc_phys = u2_mpc_n * sig_u(3) + mu_u(3);   % indeks 3 for pumpe!
y_mpc_phys  = y_mpc_n  * sig_y    + mu_y;
y_base_phys = y_base_n * sig_y    + mu_y;

eval_mask = false(N,1);
eval_mask(k_start-1:end) = true;

valid = eval_mask & ~isnan(cost_mpc) & ~isnan(cost_base) & ...
        ~isnan(y_mpc_phys) & ~isnan(y_base_phys) & ~mask_precool_all;

fprintf('  Forkjøling ekskludert: %d steg (%.1f timer) av %d totalt\n', ...
    sum(mask_precool_all & eval_mask), ...
    sum(mask_precool_all & eval_mask) * Ts / 3600, sum(eval_mask));

total_mpc  = sum(cost_mpc(valid));
total_base = sum(cost_base(valid));
savings     = total_base - total_mpc;
savings_pct = 100 * savings / total_base;

rmse_mpc  = sqrt(mean((y_mpc_phys(valid) - r_phys(valid)).^2));
rmse_base = sqrt(mean((y_base_phys(valid) - r_phys(valid)).^2));
in_rng_mpc  = 100*mean(y_mpc_phys(valid) >= Tmin_phys(valid) & ...
                        y_mpc_phys(valid) <= Tmax_phys(valid));
in_rng_base = 100*mean(y_base_phys(valid) >= Tmin_phys(valid) & ...
                        y_base_phys(valid) <= Tmax_phys(valid));

fprintf('\n==============================================================\n');
fprintf('RESULTATER — Economic MPC — LANE 2 (3-input plant)\n');
fprintf('==============================================================\n');
fprintf('Warm-start: %d steg (%.1f timer), evaluering fra k=%d\n', ...
    N_warmup, N_warmup*Ts/3600, k_start-1);
fprintf('                         MPC        Historisk\n');
fprintf('Energikostnad [NOK]:     %-10.1f %-10.1f\n', total_mpc, total_base);
fprintf('Besparelse:              %.1f NOK (%.1f%%)\n', savings, savings_pct);
fprintf('RMSE vs referanse [°C]:  %-10.4f %-10.4f\n', rmse_mpc, rmse_base);
fprintf('Tid i intervall [%%]:     %-10.1f %-10.1f\n', in_rng_mpc, in_rng_base);
fprintf('==============================================================\n');
fprintf('Vekter: W_q=%.0f, W_e=%.1f, R_du1=%.0f, R_du2=%.0f\n', ...
    W_quality, W_energy, R_du1, R_du2);
fprintf('Plant-sim: 3-input håndtunet TF + AR(1) støy\n\n');

% Gruppespesifikke KPI-er
fprintf('--- Gruppespesifikke KPI-er ---\n');
groups = {"elite", "hobby", "idle"};
for gi = 1:numel(groups)
    mask = group_all == groups{gi} & valid;
    n_s = sum(mask);
    if n_s == 0; continue; end
    n_h = n_s * Ts / 3600;
    rmg = sqrt(mean((y_mpc_phys(mask) - r_phys(mask)).^2));
    rbg = sqrt(mean((y_base_phys(mask) - r_phys(mask)).^2));
    ig  = 100*mean(y_mpc_phys(mask) >= Tmin_phys(mask) & ...
                    y_mpc_phys(mask) <= Tmax_phys(mask));
    ibg = 100*mean(y_base_phys(mask) >= Tmin_phys(mask) & ...
                    y_base_phys(mask) <= Tmax_phys(mask));
    cg  = sum(cost_mpc(mask));
    cbg = sum(cost_base(mask));
    fprintf('  %-8s (%3.0fh) RMSE: M=%.4f H=%.4f | InRng: M=%.0f%% H=%.0f%% | Cost: M=%.0f H=%.0f\n', ...
        upper(groups{gi}), n_h, rmg, rbg, ig, ibg, cg, cbg);
end

%% ============================================================
%  SEKSJON 13: FIGURER
%% ============================================================
t_hr = hours(timeVec - timeVec(1));
last_valid = find(~isnan(y_mpc_phys), 1, 'last');
t_end = t_hr(last_valid);
c_mpc  = [0.00 0.45 0.74];
c_base = [0.85 0.33 0.10];
c_ref  = [0.47 0.67 0.19];
c_spot = [0.93 0.69 0.13];
c_pump = [0.55 0.00 0.55];

% --- Figur 1: Istemperatur ---
figure('Name','Istemperatur Lane 2','Position',[50 50 1400 550]);
hold on;
for k = 1:N-1
    if group_all(k) == "hobby"
        fill([t_hr(k),t_hr(k+1),t_hr(k+1),t_hr(k)], ...
             [-4.7,-4.7,-3.5,-3.5],[0.75 0.85 1.0], ...
             'EdgeColor','none','FaceAlpha',0.2,'HandleVisibility','off');
    elseif group_all(k) == "elite"
        fill([t_hr(k),t_hr(k+1),t_hr(k+1),t_hr(k)], ...
             [-4.7,-4.7,-3.5,-3.5],[1.0 0.75 0.75], ...
             'EdgeColor','none','FaceAlpha',0.2,'HandleVisibility','off');
    end
end
fill([t_hr; flipud(t_hr)],[Tmin_phys; flipud(Tmax_phys)], ...
    [0.85 0.95 0.85],'EdgeColor','none','FaceAlpha',0.4, ...
    'DisplayName','Tillatt intervall');
stairs(t_hr, r_phys, '--', 'Color', c_ref, 'LineWidth', 1.3, ...
    'DisplayName','Referanse (step)');
plot(t_hr, y_base_phys, '-', 'Color', c_base, 'LineWidth', 1.2, ...
    'DisplayName', sprintf('Historisk (RMSE=%.3f°C, %.0f%%)', rmse_base, in_rng_base));
plot(t_hr, y_mpc_phys, '-', 'Color', c_mpc, 'LineWidth', 1.8, ...
    'DisplayName', sprintf('MPC (RMSE=%.3f°C, %.0f%%)', rmse_mpc, in_rng_mpc));
xlabel('Tid [timer]'); ylabel('Istemperatur [°C]');
title(sprintf(['MPC Lane 2 (3-input) | Cost: MPC=%.0f, Hist=%.0f NOK (%+.1f%%)\n' ...
    'Warm-start=%d steg | W_q=%.0f, W_e=%.1f'], ...
    total_mpc, total_base, savings_pct, N_warmup, W_quality, W_energy));
legend('Location','northwest','FontSize',8);
ylim([-4.7, -3.5]); xlim([0, t_end]); grid on;

% --- Figur 2: Ventil + pris ---
figure('Name','MV1 + Pris','Position',[50 50 1400 550]);
subplot(2,1,1); hold on;
plot(t_hr, u1_base_phys_vec, '-', 'Color', c_base, 'LineWidth', 1.2, ...
    'DisplayName', 'Historisk ventilsetpunkt');
plot(t_hr, u1_mpc_phys, '-', 'Color', c_mpc, 'LineWidth', 1.5, ...
    'DisplayName', 'MPC ventilsetpunkt');
yline(u1_min_phys,':k'); yline(u1_max_phys,':k');
ylabel('valve\_two.setvalue [°C]');
title('MV1 + Strømpris');
legend('Location','best','FontSize',8); grid on; xlim([0 t_end]);
subplot(2,1,2);
plot(t_hr, price_all, 'Color', c_spot, 'LineWidth', 1);
ylabel('NOK/kWh'); xlabel('Tid [timer]'); grid on; xlim([0 t_end]);

% --- Figur 3: Pumpe ---
figure('Name','MV2','Position',[50 50 1400 380]);
hold on;
plot(t_hr, u2_base_phys_vec, '--', 'Color', c_base, 'LineWidth', 1.2, ...
    'DisplayName', 'Historisk pumpefrekvens');
plot(t_hr, u2_mpc_phys, '-', 'Color', c_pump, 'LineWidth', 1.5, ...
    'DisplayName', 'MPC pumpefrekvens');
ylabel('flowpump.freqout [Hz]'); xlabel('Tid [timer]');
title('MV2: Pumpe'); legend('Location','best'); grid on; xlim([0 t_end]);

% --- Figur 4: Kumulativ kostnad ---
figure('Name','Kumulativ kostnad','Position',[50 50 1400 380]);
hold on;
cc_mpc  = cumsum(fillmissing(cost_mpc .* valid, 'constant', 0));
cc_base = cumsum(fillmissing(cost_base .* valid, 'constant', 0));
fill([t_hr; flipud(t_hr)], [cc_base; flipud(cc_mpc)], ...
    c_mpc, 'FaceAlpha', 0.12, 'EdgeColor', 'none', ...
    'DisplayName', sprintf('Besparelse: %.1f NOK', savings));
plot(t_hr, cc_base, '-', 'Color', c_base, 'LineWidth', 2, ...
    'DisplayName', sprintf('Historisk: %.0f NOK', total_base));
plot(t_hr, cc_mpc, '-', 'Color', c_mpc, 'LineWidth', 2, ...
    'DisplayName', sprintf('MPC: %.0f NOK', total_mpc));
xlabel('Tid [timer]'); ylabel('Kumulativ kostnad [NOK]');
title(sprintf('Kumulativ Energikostnad (%+.1f%%)', savings_pct));
legend('Location','northwest','FontSize',9); grid on; xlim([0 t_end]);

% --- Figur 5: Step-respons (3 kanaler nå) ---
figure('Name','Step-respons','Position',[50 50 800 450]);
hold on;
t_s_hr = t_step / 3600;
plot(t_s_hr, g_mv1, '-b', 'LineWidth', 2, ...
    'DisplayName', sprintf('G1 ventil (ss=%.3f)', g_mv1(end)));
plot(t_s_hr, g_dv_h, '-', 'Color', [0.85 0.33 0.10], 'LineWidth', 2, ...
    'DisplayName', sprintf('G2 halltemp DV (ss=%.3f)', g_dv_h(end)));
plot(t_s_hr, g_mv2, '-', 'Color', c_pump, 'LineWidth', 2, ...
    'DisplayName', sprintf('G3 pumpe (ss=%.3f)', g_mv2(end)));
xline(t95_min/60, '--r', '95%', 'LineWidth', 1.5);
xlabel('Timer'); ylabel('Normalisert respons');
title('3-input plantmodell → is'); legend('FontSize',10); grid on;

% --- Figur 6: Zoom 3 dager ---
figure('Name','Zoom','Position',[50 50 1400 700]);
zoom_idx = t_hr >= 70 & t_hr <= 160;
subplot(3,1,1); hold on;
fill([t_hr(zoom_idx); flipud(t_hr(zoom_idx))], ...
    [Tmin_phys(zoom_idx); flipud(Tmax_phys(zoom_idx))], ...
    [0.85 0.95 0.85],'EdgeColor','none','FaceAlpha',0.4);
stairs(t_hr(zoom_idx), r_phys(zoom_idx), '--', 'Color', c_ref, 'LineWidth', 1.5);
plot(t_hr(zoom_idx), y_base_phys(zoom_idx), '-', 'Color', c_base, 'LineWidth', 1.2);
plot(t_hr(zoom_idx), y_mpc_phys(zoom_idx), '-', 'Color', c_mpc, 'LineWidth', 1.8);
ylabel('°C'); title('Zoom: Istemperatur Lane 2'); grid on;
subplot(3,1,2); hold on;
plot(t_hr(zoom_idx), u1_base_phys_vec(zoom_idx), '-', 'Color', c_base, 'LineWidth', 1.2);
plot(t_hr(zoom_idx), u1_mpc_phys(zoom_idx), '-', 'Color', c_mpc, 'LineWidth', 1.5);
ylabel('°C'); title('MV1 ventil'); grid on;
subplot(3,1,3); hold on;
plot(t_hr(zoom_idx), u2_base_phys_vec(zoom_idx), '--', 'Color', c_base, 'LineWidth', 1.2);
plot(t_hr(zoom_idx), u2_mpc_phys(zoom_idx), '-', 'Color', c_pump, 'LineWidth', 1.5);
ylabel('Hz'); xlabel('Tid [timer]'); title('MV2 pumpe'); grid on;
sgtitle('3-dagers zoom — MPC Lane 2 (3-input plant)');

% --- Figur 7: Gruppespesifikk KPI-oversikt ---
figure('Name','Gruppe-KPI','Position',[50 50 1000 550]);

groups = {"elite", "hobby", "idle"};
grp_names = {'Elite','Hobby','Idle'};
rmse_mpc_arr = nan(1,3); rmse_base_arr = nan(1,3);
inrng_mpc_arr = nan(1,3); inrng_base_arr = nan(1,3);
cost_mpc_arr = nan(1,3); cost_base_arr = nan(1,3);

for gi = 1:3
    mask = group_all == groups{gi} & valid;
    if sum(mask) == 0; continue; end
    rmse_mpc_arr(gi)  = sqrt(mean((y_mpc_phys(mask) - r_phys(mask)).^2));
    rmse_base_arr(gi) = sqrt(mean((y_base_phys(mask) - r_phys(mask)).^2));
    inrng_mpc_arr(gi) = 100*mean(y_mpc_phys(mask) >= Tmin_phys(mask) & ...
                                  y_mpc_phys(mask) <= Tmax_phys(mask));
    inrng_base_arr(gi) = 100*mean(y_base_phys(mask) >= Tmin_phys(mask) & ...
                                   y_base_phys(mask) <= Tmax_phys(mask));
    cost_mpc_arr(gi) = sum(cost_mpc(mask), 'omitnan');
    cost_base_arr(gi) = sum(cost_base(mask), 'omitnan');
end

subplot(1,3,1);
b1 = bar([rmse_mpc_arr; rmse_base_arr]');
b1(1).FaceColor = c_mpc; b1(2).FaceColor = c_base;
set(gca, 'XTickLabel', grp_names); ylabel('RMSE [°C]');
title('RMSE vs referanse'); legend('MPC','Historisk'); grid on;

subplot(1,3,2);
b2 = bar([inrng_mpc_arr; inrng_base_arr]');
b2(1).FaceColor = c_mpc; b2(2).FaceColor = c_base;
set(gca, 'XTickLabel', grp_names); ylabel('Tid i intervall [%]');
title('Temperaturkvalitet'); legend('MPC','Historisk'); grid on;

subplot(1,3,3);
b3 = bar([cost_mpc_arr; cost_base_arr]');
b3(1).FaceColor = c_mpc; b3(2).FaceColor = c_base;
set(gca, 'XTickLabel', grp_names); ylabel('Energikostnad [NOK]');
title('Kostnad per gruppe'); legend('MPC','Historisk'); grid on;

sgtitle(sprintf('KPI-er — MPC Lane 2 (3-input) | Besparelse: %.1f NOK (%.1f%%)', ...
    savings, savings_pct));

fprintf('\nAlle figurer generert.\nFERDIG!\n');

%% ============================================================
%  HJELPEFUNKSJONER
%% ============================================================

function S = buildDMCMatrix(g, Np, Nc)
    S = zeros(Np, Nc);
    for i = 1:Np
        for j = 1:Nc
            idx = i - j + 1;
            if idx >= 1; S(i,j) = g(idx); end
        end
    end
end

function Tu = buildCumSumMatrix(Np, Nc)
    Tu = zeros(Np, Nc);
    for i = 1:Np
        for j = 1:min(i,Nc); Tu(i,j) = 1; end
    end
end

function y_add = convPastMoves(g, du_hist, Np)
    y_add = zeros(Np,1);
    Ng = numel(g);
    M  = numel(du_hist);
    for i = 1:Np
        m_max = min(M, Ng - i);
        if m_max < 1; continue; end
        idx_fwd = i + (1:m_max);
        y_add(i) = (g(idx_fwd) - g(1:m_max))' * du_hist(1:m_max);
    end
end

function [Tmin_g, Tmax_g, target_g, label] = mapGroup(g, ...
    T_idle_min, T_idle_max, T_hobby_min, T_hobby_max, ...
    T_elite_min, T_elite_max)
    switch lower(strtrim(string(g)))
        case {'turnering','trening','divisjonsspill'}
            Tmin_g = T_elite_min; Tmax_g = T_elite_max; label = "elite";
        case {'booking','kurs','pensjonister'}
            Tmin_g = T_hobby_min; Tmax_g = T_hobby_max; label = "hobby";
        otherwise
            Tmin_g = T_idle_min;  Tmax_g = T_idle_max;  label = "idle";
    end
    target_g = 0.5*(Tmin_g + Tmax_g);
end