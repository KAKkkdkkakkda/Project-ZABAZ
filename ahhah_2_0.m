%% export_sw_solution.m
% Solves SW2007 via Dynare and exports solution to sw_solution.json
% Run from the folder containing Smets_Wouters_2007_45.mod

clear; clc;

%% 1. Prepare mod file
fid = fopen('Smets_Wouters_2007_45.mod', 'r');
if fid == -1, error('Cannot open mod file.'); end
mod_content = fread(fid, '*char')';
fclose(fid);

mod_content = regexprep(mod_content, 'estimated_params;.*?end;', '', 'dotall');
mod_content = regexprep(mod_content, 'estimation\s*\(.*?\)\s*;',  '', 'dotall');
mod_content = [mod_content, sprintf('\n\nstoch_simul(order=1, irf=0, noprint);\n')];

fid = fopen('sw_tmp.mod', 'w');
fprintf(fid, '%s', mod_content);
fclose(fid);

%% 2. Run Dynare
dynare('sw_tmp', 'noclearall', 'nolog');

%% 3. Build DR-order index map
% ghx (n_endo x n_states) and ghu (n_endo x n_exo) are in DR order.
% oo_.dr.order_var(dr_pos) = declaration_pos  (1-indexed)
% We need the inverse: decl_pos -> dr_pos

n_endo  = M_.endo_nbr;
n_exo   = M_.exo_nbr;
n_state = size(oo_.dr.ghx, 2);

decl2dr = zeros(n_endo, 1);
decl2dr(oo_.dr.order_var) = 1:n_endo;

%% 4. State row indices in DR order (used for propagation in JS)
% States occupy DR rows nstatic+1 .. nstatic+npred+nboth
state_rows_dr = (M_.nstatic+1 : M_.nstatic+M_.npred+M_.nboth)';

%% 5. Display variable indices IN DR ORDER (so JS indexes path correctly)
var_names   = cellstr(M_.endo_names);
shock_names = cellstr(M_.exo_names);

display_vars = {'y','yf','pinf','r','rrf','c','inve','lab','w'};
VI_dr = struct();
fprintf('Variable DR-order indices (0-indexed for JS):\n');
for i = 1:length(display_vars)
    v        = display_vars{i};
    decl_idx = find(strcmp(var_names, v));
    dr_idx   = decl2dr(decl_idx);
    VI_dr.(v) = dr_idx - 1;   % convert to 0-indexed for JavaScript
    fprintf('  %s: decl=%d  dr=%d  js=%d\n', v, decl_idx, dr_idx, dr_idx-1);
end

%% 6. Shock indices (already 0-indexed for JS)
shock_config = {
    'ea',    'Technology',           0;
    'eb',    'Risk premium (demand)',0;
    'eg',    'Govt spending',        0;
    'eqs',   'Investment tech',      0;
    'em',    'Monetary policy',      0;
    'epinf', 'Price markup',         0;
    'ew',    'Wage markup',          0;
};
for i = 1:size(shock_config,1)
    idx = find(strcmp(shock_names, shock_config{i,1}));
    shock_config{i,3} = idx - 1;   % 0-indexed
    fprintf('  shock %s: js_idx=%d\n', shock_config{i,1}, idx-1);
end

%% 7. Quick IRF verification with plots
fprintf('\nVerification (technology shock):\n');
T = 40;
ea_js  = shock_config{1,3};           % 0-indexed
ea_mat = ea_js + 1;                   % 1-indexed for MATLAB

irf = zeros(n_endo, T);
irf(:,1) = oo_.dr.ghu(:, ea_mat);
for t = 2:T
    state_vec    = irf(state_rows_dr, t-1);
    irf(:,t)     = oo_.dr.ghx * state_vec;
end

% Индексы переменных
y_dr  = VI_dr.y  + 1;
yf_dr = VI_dr.yf + 1;
pi_dr = VI_dr.pinf + 1;
r_dr  = VI_dr.r + 1;
rrf_dr = VI_dr.rrf + 1;
c_dr  = VI_dr.c + 1;
inve_dr = VI_dr.inve + 1;
lab_dr = VI_dr.lab + 1;
w_dr = VI_dr.w + 1;

% Вывод первых периодов
fprintf('\nImpact (t=1):\n');
fprintf('  y[1]   = %.4f  (should be +)\n', irf(y_dr, 1));
fprintf('  yf[1]  = %.4f  (should be + and larger)\n', irf(yf_dr, 1));
fprintf('  pi[1]  = %.4f  (should be -)\n', irf(pi_dr, 1));
fprintf('  gap    = %.4f  (should be -)\n', irf(y_dr,1) - irf(yf_dr,1));
fprintf('  r[1]   = %.4f  (should be -)\n', irf(r_dr, 1));
fprintf('  rrf[1] = %.4f  (should be -)\n', irf(rrf_dr, 1));

%% 7. Quick IRF verification with plots
y_dr   = VI_dr.y   + 1;
yf_dr  = VI_dr.yf  + 1;
pi_dr  = VI_dr.pinf + 1;
r_dr   = VI_dr.r   + 1;
rrf_dr = VI_dr.rrf + 1;
c_dr   = VI_dr.c   + 1;
inve_dr = VI_dr.inve + 1;
lab_dr  = VI_dr.lab + 1;
w_dr    = VI_dr.w   + 1;

fprintf('\nVerification (technology shock):\n');
T = 40;
ea_js  = shock_config{1,3};           
ea_mat = ea_js + 1;                   

irf = zeros(n_endo, T);
irf(:,1) = oo_.dr.ghu(:, ea_mat);
for t = 2:T
    state_vec    = irf(state_rows_dr, t-1);
    irf(:,t)     = oo_.dr.ghx * state_vec;
end

% Найдем индексы
var_names_dr = cellstr(M_.endo_names(oo_.dr.order_var, :));
y_idx   = find(strcmp(var_names_dr, 'y'));
yf_idx  = find(strcmp(var_names_dr, 'yf'));
pi_idx  = find(strcmp(var_names_dr, 'pinf'));
r_idx   = find(strcmp(var_names_dr, 'r'));
rrf_idx = find(strcmp(var_names_dr, 'rrf'));

% Параметры для уровней
trend_q = 0.3982;        % % per quarter
pi_target = 0.7;         % % per quarter
r_star_real = 1.0;       % реальная ставка в SS
r_nom_ss = r_star_real + pi_target * 4;

t = (0:T-1)';
trend = trend_q * t;

% Переводим в уровни
y_lev   = irf(y_idx, :)' + trend;
yf_lev  = irf(yf_idx, :)' + trend;
pi_ann  = irf(pi_idx, :)' * 4 + pi_target * 4;
r_ann   = irf(r_idx, :)' * 4 + r_nom_ss;
rrf_ann = irf(rrf_idx, :)' * 4 + r_star_real;

% HP фильтр
lam = 1600;
n = length(y_lev);
D = zeros(n-2, n);
for i = 1:n-2
    D(i,i) = 1; D(i,i+1) = -2; D(i,i+2) = 1;
end
A = eye(n) + lam * (D' * D);
hp_trend = A \ y_lev;

% Три разрыва
gap_flex = irf(y_idx, :)' - irf(yf_idx, :)';
gap_hp = y_lev - hp_trend;
gap_trend = irf(y_idx, :)';

figure('Name', 'SW2007 IRF - Technology Shock', 'Position', [100, 100, 1000, 800]);

% График 1: Output с уровнями
subplot(2, 2, 1);
plot(t, y_lev, 'b-', 'LineWidth', 1.5); hold on;
plot(t, yf_lev, 'r--', 'LineWidth', 1.5);
plot(t, hp_trend, 'g:', 'LineWidth', 1.5);
xlabel('Quarters'); ylabel('% level');
title('Output: Actual, Flexible, HP Trend');
legend('y (sticky)', 'y^f (flex)', 'HP trend', 'Location', 'best');
grid on;

% График 2: Output gaps
subplot(2, 2, 2);
plot(t, gap_flex, 'b-', 'LineWidth', 1.5); hold on;
plot(t, gap_hp, 'r--', 'LineWidth', 1.5);
plot(t, gap_trend, 'g-.', 'LineWidth', 1.5);
xlabel('Quarters'); ylabel('%');
title('Output Gaps');
legend('y - y^f', 'y - HP', 'y - trend', 'Location', 'best');
grid on;

% График 3: Inflation
subplot(2, 2, 3);
plot(t, pi_ann, 'b-', 'LineWidth', 1.5); hold on;
yline(pi_target*4, 'r--', 'LineWidth', 1.2);
xlabel('Quarters'); ylabel('% annualised');
title('Inflation');
legend('π', 'target', 'Location', 'best');
grid on;

% График 4: Interest rates
subplot(2, 2, 4);
plot(t, r_ann, 'b-', 'LineWidth', 1.5); hold on;
plot(t, rrf_ann, 'r--', 'LineWidth', 1.5);
xlabel('Quarters'); ylabel('% annualised');
title('Interest Rates');
legend('Nominal', 'Natural r*', 'Location', 'best');
grid on;


%% 8. Pack and export JSON
out = struct();
out.ghx          = oo_.dr.ghx;           % n_endo x n_states, DR order
out.ghu          = oo_.dr.ghu;           % n_endo x n_exo,    DR order
out.state_rows   = state_rows_dr - 1;    % 0-indexed for JS
out.VI           = VI_dr;                % 0-indexed DR positions of display vars
out.shock_keys   = shock_config(:,1)';
out.shock_labels = shock_config(:,2)';
out.shock_js_idx = cell2mat(shock_config(:,3))';   % 0-indexed
out.model_rhos   = [0, 0, 0, 0, 0, 0, 0];
out.params       = struct( ...
    'ctrend',     M_.params(strcmp(cellstr(M_.param_names),'ctrend')), ...
    'constepinf', M_.params(strcmp(cellstr(M_.param_names),'constepinf')), ...
    'crr',        M_.params(strcmp(cellstr(M_.param_names),'crr')), ...
    'crpi',       M_.params(strcmp(cellstr(M_.param_names),'crpi')), ...
    'cry',        M_.params(strcmp(cellstr(M_.param_names),'cry')), ...
    'crdy',       M_.params(strcmp(cellstr(M_.param_names),'crdy')), ...
    'cprobp',     M_.params(strcmp(cellstr(M_.param_names),'cprobp')), ...
    'cprobw',     M_.params(strcmp(cellstr(M_.param_names),'cprobw')), ...
    'chabb',      M_.params(strcmp(cellstr(M_.param_names),'chabb')), ...
    'csigma',     M_.params(strcmp(cellstr(M_.param_names),'csigma')) ...
);

fid = fopen('sw_solution.json', 'w');
fprintf(fid, '%s', jsonencode(out, 'PrettyPrint', true));
fclose(fid);

delete('sw_tmp.mod');
fprintf('\nExported sw_solution.json\n');