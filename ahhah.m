%% export_sw_solution.m
% Solves SW2007 via Dynare and exports the full first-order solution
% (state-space matrices, variable names, IRFs) to sw_solution.json
%
% Requirements: Dynare 4.5+, Smets_Wouters_2007_45.mod in same folder
%
% Output: sw_solution.json with fields:
%   ghx        - decision rule on states (n_vars x n_states)
%   ghu        - decision rule on shocks (n_vars x n_shocks)  
%   A          - full VAR(1) transition matrix in declaration order
%   B          - full impact matrix in declaration order
%   var_names  - endogenous variable names (declaration order)
%   shock_names- exogenous shock names
%   order_var  - Dynare's reordering index (DR order -> declaration order)
%   steady_state - steady state values
%   params     - key calibration parameters for the website
%
% Usage: run this script from the folder containing the .mod file

clear; clc;
fprintf('=== SW2007 Solution Export ===\n\n');

%% 1. Read and prepare the mod file
% Strip estimation block — we only need stoch_simul
fid = fopen('Smets_Wouters_2007_45.mod', 'r');
if fid == -1
    error('Cannot open Smets_Wouters_2007_45.mod. Run from the correct folder.');
end
mod_content = fread(fid, '*char')';
fclose(fid);

% Remove estimated_params block (keeps parameters at their initial values)
mod_content = regexprep(mod_content, 'estimated_params;.*?end;', '', 'dotall');

% Remove estimation() command if present
mod_content = regexprep(mod_content, 'estimation\s*\(.*?\)\s*;', '', 'dotall');

% Remove prior_function block if present
mod_content = regexprep(mod_content, 'prior_function.*?end;', '', 'dotall');

% Remove steady; check; if they appear after model block (Dynare adds these internally)
% Keep them — they are harmless and useful for verification

% Add stoch_simul at the end (order=1 gives ghx, ghu directly)
% irf=0: we compute IRFs ourselves for full control
% noprint: suppress Dynare output clutter
stoch_cmd = sprintf(['\n\nstoch_simul(order=1, irf=0, noprint);\n']);
mod_content = [mod_content, stoch_cmd];

% Write temporary mod file
tmp_mod = 'sw_export_tmp.mod';
fid = fopen(tmp_mod, 'w');
fprintf(fid, '%s', mod_content);
fclose(fid);

%% 2. Run Dynare
fprintf('Running Dynare (this may take ~30 seconds)...\n');
tmp_mod_base = strsplit(tmp_mod, '.mod'); tmp_mod_base = tmp_mod_base{1};
dynare(tmp_mod_base, 'noclearall', 'nolog');
fprintf('Dynare done.\n\n');

%% 3. Extract solution matrices
% Dynare stores decision rules in DR (decision rule) order, not declaration order.
% order_var maps DR order -> declaration order:
%   endo_names(order_var(i)) is the i-th variable in DR order
% We want everything in declaration order for simplicity.

n_endo  = M_.endo_nbr;
n_exo   = M_.exo_nbr;
n_state = size(oo_.dr.ghx, 2);  % number of state variables

% DR-ordered matrices
ghx_dr = oo_.dr.ghx;  % n_endo x n_states (DR order)
ghu_dr = oo_.dr.ghu;  % n_endo x n_exo   (DR order)

% Reorder rows to declaration order
inv_order(oo_.dr.order_var) = 1:n_endo;
ghx_decl = ghx_dr(inv_order, :);
ghu_decl = ghu_dr(inv_order, :);

% Steady state in declaration order
ys = oo_.dr.ys;  % already in declaration order

% Variable and shock names as cell arrays of strings
var_names   = cellstr(M_.endo_names);
shock_names = cellstr(M_.exo_names);

fprintf('Model dimensions:\n');
fprintf('  Endogenous variables: %d\n', n_endo);
fprintf('  Exogenous shocks:     %d\n', n_exo);
fprintf('  State variables:      %d\n', n_state);

%% 4. Build full VAR(1) in declaration order
% The state vector in Dynare is the vector of predetermined variables
% (lagged endogenous + lagged exogenous). ghx maps states -> variables.
% 
% Full VAR(1): x_t = A * x_{t-1} + B * eps_t
% where x = all endogenous variables in declaration order.
% 
% Note: Dynare's state vector is a subset of endogenous vars (the predetermined ones)
% plus possibly lagged exogenous. We export ghx and ghu directly — the website
% will propagate states, not the full vector.
%
% State variable indices in declaration order:
state_names = cellstr(M_.endo_names(oo_.dr.order_var(M_.nstatic+1 : M_.nstatic+M_.npred+M_.nboth), :));
fprintf('\nState variables (%d):\n', length(state_names));
for i = 1:length(state_names)
    fprintf('  %d: %s\n', i, state_names{i});
end

%% 5. Key variable indices (declaration order) for website display
display_vars = {'y', 'yf', 'pinf', 'r', 'rrf', 'c', 'inve', 'lab', 'w', ...
                'a', 'b', 'g', 'qs', 'ms', 'spinf', 'sw'};
display_idx = zeros(1, length(display_vars));
for i = 1:length(display_vars)
    idx = find(strcmp(var_names, display_vars{i}));
    if isempty(idx)
        warning('Variable %s not found', display_vars{i});
        display_idx(i) = NaN;
    else
        display_idx(i) = idx;
    end
end

fprintf('\nDisplay variable indices:\n');
for i = 1:length(display_vars)
    if ~isnan(display_idx(i))
        fprintf('  %s -> index %d (ss=%.4f)\n', display_vars{i}, display_idx(i), ys(display_idx(i)));
    end
end

%% 6. Key parameters for the website
params = struct();
params.beta       = 1 / (1 + M_.params(strcmp(M_.param_names, 'constebeta')) / 100);
params.ctrend     = M_.params(strcmp(M_.param_names, 'ctrend'));     % quarterly growth rate (%)
params.constepinf = M_.params(strcmp(M_.param_names, 'constepinf')); % SS inflation (%)
params.crr        = M_.params(strcmp(M_.param_names, 'crr'));
params.crpi       = M_.params(strcmp(M_.param_names, 'crpi'));
params.cry        = M_.params(strcmp(M_.param_names, 'cry'));
params.crdy       = M_.params(strcmp(M_.param_names, 'crdy'));
params.cprobp     = M_.params(strcmp(M_.param_names, 'cprobp'));
params.cprobw     = M_.params(strcmp(M_.param_names, 'cprobw'));
params.chabb      = M_.params(strcmp(M_.param_names, 'chabb'));
params.csigma     = M_.params(strcmp(M_.param_names, 'csigma'));
params.calfa      = M_.params(strcmp(M_.param_names, 'calfa'));

% Shock standard deviations (from SW posterior mode)
params.sigma_ea   = 0.4618;
params.sigma_eb   = 1.8513;
params.sigma_eg   = 0.6090;
params.sigma_eqs  = 0.6017;
params.sigma_em   = 0.2397;
params.sigma_epinf = 0.1455;
params.sigma_ew   = 0.2089;

fprintf('\nKey parameters:\n');
fprintf('  Trend growth: %.4f%% per quarter (%.2f%% annual)\n', params.ctrend, params.ctrend*4);
fprintf('  SS inflation: %.4f%% per quarter (%.2f%% annual)\n', params.constepinf, params.constepinf*4);

%% 7. Export to JSON
% Dynare's state ordering: states are in DR order, columns of ghx
% We export in this form so JS can propagate: state_{t+1} = ghx * state_t + ghu * eps_t
% (restricted to the state rows only for propagation)

% State row indices in DR order (for propagation loop in JS):
state_rows_dr = M_.nstatic + 1 : M_.nstatic + M_.npred + M_.nboth;

export_data = struct();
export_data.ghx           = ghx_dr;          % DR order, used for IRF propagation
export_data.ghu           = ghu_dr;          % DR order
export_data.state_rows_dr = state_rows_dr;   % which rows of ghx are state vars
export_data.var_names_dr  = cellstr(M_.endo_names(oo_.dr.order_var, :));  % DR order names
export_data.var_names_decl= var_names;       % declaration order names  
export_data.order_var     = oo_.dr.order_var;% DR->decl mapping
export_data.shock_names   = shock_names;
export_data.steady_state  = num2cell(ys);
export_data.display_vars  = display_vars;
export_data.display_idx_decl = num2cell(display_idx);  % 1-indexed, decl order
export_data.state_names   = state_names;
export_data.params        = params;
export_data.n_endo        = n_endo;
export_data.n_exo         = n_exo;
export_data.n_state       = n_state;

% Convert matrices to nested cell arrays for jsonencode
export_data.ghx = mat2cell(ghx_dr, ones(1,size(ghx_dr,1)), size(ghx_dr,2));
export_data.ghu = mat2cell(ghu_dr, ones(1,size(ghu_dr,1)), size(ghu_dr,2));

json_str = jsonencode(export_data, 'PrettyPrint', true);

out_file = 'sw_solution.json';
fid = fopen(out_file, 'w');
fprintf(fid, '%s', json_str);
fclose(fid);

fprintf('\n✅ Exported: %s\n', out_file);
fprintf('   ghx: %dx%d (DR order)\n', size(ghx_dr,1), size(ghx_dr,2));
fprintf('   ghu: %dx%d\n', size(ghu_dr,1), size(ghu_dr,2));
fprintf('   State vars: %d\n', n_state);

%% 8. Quick IRF verification in MATLAB
% Technology shock (ea) — should raise y and yf, lower inflation temporarily
T = 40;
ea_idx = find(strcmp(shock_names, 'ea'));
fprintf('\nVerification IRF — technology shock (ea):\n');

% Find state rows in DR order for propagation
state_dr_idx = M_.nstatic + 1 : M_.nstatic + M_.npred + M_.nboth;

irf_states = zeros(n_endo, T);
irf_states(:, 1) = ghu_dr(:, ea_idx);

for t = 2:T
    state_t_minus_1 = irf_states(state_dr_idx, t-1);
    irf_states(:, t) = ghx_dr * state_t_minus_1;
end

y_idx_dr   = find(strcmp(export_data.var_names_dr, 'y'));
yf_idx_dr  = find(strcmp(export_data.var_names_dr, 'yf'));
pi_idx_dr  = find(strcmp(export_data.var_names_dr, 'pinf'));

fprintf('  y[1]  = %.4f (should be +)\n', irf_states(y_idx_dr,  1));
fprintf('  yf[1] = %.4f (should be + and larger)\n', irf_states(yf_idx_dr, 1));
fprintf('  pi[1] = %.4f (should be -)\n', irf_states(pi_idx_dr, 1));
fprintf('  gap[1] = y-yf = %.4f (should be -)\n', irf_states(y_idx_dr,1)-irf_states(yf_idx_dr,1));

%% Cleanup
delete(tmp_mod);
% Dynare creates several temp files — clean up the main ones
tmp_parts = strsplit(tmp_mod, '.mod'); tmp_base = tmp_parts{1};
system(sprintf('rm -rf %s.log %s', tmp_base, tmp_base));
fprintf('\nDone. Run generate_html.py next.\n');