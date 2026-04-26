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

%% 7. Quick IRF verification
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

y_dr  = VI_dr.y  + 1;
yf_dr = VI_dr.yf + 1;
pi_dr = VI_dr.pinf + 1;

fprintf('  y[1]  = %.4f  (expect +)\n', irf(y_dr,  1));
fprintf('  yf[1] = %.4f  (expect + and larger)\n', irf(yf_dr, 1));
fprintf('  pi[1] = %.4f  (expect -)\n', irf(pi_dr, 1));
fprintf('  gap   = %.4f  (expect -)\n', irf(y_dr,1) - irf(yf_dr,1));

%% 8. Pack and export JSON
out = struct();
out.ghx          = oo_.dr.ghx;           % n_endo x n_states, DR order
out.ghu          = oo_.dr.ghu;           % n_endo x n_exo,    DR order
out.state_rows   = state_rows_dr - 1;    % 0-indexed for JS
out.VI           = VI_dr;                % 0-indexed DR positions of display vars
out.shock_keys   = shock_config(:,1)';
out.shock_labels = shock_config(:,2)';
out.shock_js_idx = cell2mat(shock_config(:,3))';   % 0-indexed
out.model_rhos   = [0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7];
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