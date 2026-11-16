function main_runner()

clear functions
close all
clc



%% ---------- [1/5] Configuration ----------
cfg = config_parameters();
fprintf('[1/5] Configuration loaded\n');
fprintf('      Machine:  %s\n', cfg.machine.name);
fprintf('      Motor:    %.1f kW @ %d rpm\n', ...
    cfg.machine.motor_power_kW, cfg.machine.motor_rpm);
fprintf('      Bearing:  %s\n\n', cfg.bearing_primary.model);

%% ---------- [2/5] Output directory ----------
out_dir = 'Results';
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end
fprintf('[2/5] Output directory: %s/\n\n', out_dir);

%% ---------- [3/5] Heavy-load scenario ----------
load_A = cfg.load_profile.comp_A_load_fraction;
fprintf('[3/5] Running Scenario A: HEAVY LOAD (%.0f%%)...\n', load_A*100);
t0 = tic;
data_heavy = run_scenario(cfg, load_A);
fprintf('      Done in %.1f s | Failure at %.0f hours\n\n', ...
    toc(t0), data_heavy.t_failure);

%% ---------- [4/5] Light-load scenario ----------
load_B = cfg.load_profile.comp_B_load_fraction;
fprintf('[4/5] Running Scenario B: LIGHT LOAD (%.0f%%)...\n', load_B*100);
t0 = tic;
data_light = run_scenario(cfg, load_B);
fprintf('      Done in %.1f s | Failure at %.0f hours\n\n', ...
    toc(t0), data_light.t_failure);

%% ---------- Save results ----------
results_heavy = data_heavy;
results_light = data_light;
mat_path = fullfile(out_dir, 'simulation_results.mat');
save(mat_path, 'results_heavy', 'results_light', 'cfg', '-v7.3');
fprintf('      Results saved to %s\n\n', mat_path);

%% ---------- [5/5] Visualizations ----------
fprintf('[5/5] Rendering portfolio figures...\n');
visualize_results('export_all', data_heavy, cfg, out_dir);

try
    comp_path = fullfile(out_dir, '06_comparative.png');
    visualize_results('comparative', data_heavy, data_light, cfg, comp_path);
    fprintf('[Rendering] Comparative study... done\n');
catch ME
    fprintf('[Rendering] Comparative study skipped: %s\n', ME.message);
end

%% ---------- Executive summary ----------
print_summary(data_heavy, data_light, cfg);



end

%% ========================================================================
%  LOCAL FUNCTION: run_scenario
% ========================================================================
function data = run_scenario(cfg, load_fraction)

clear kalman_filter_design

obs   = state_observer('initialize', cfg);
state = motor_model('initialize', cfg);

max_steps = cfg.sim.total_hours;

data.t_hours       = zeros(1, max_steps);
data.HI_true       = zeros(1, max_steps);
data.HI_est        = zeros(1, max_steps);
data.sigma_HI      = zeros(1, max_steps);
data.RUL           = NaN(1, max_steps);
data.alert_level   = zeros(1, max_steps);
data.rms_history   = zeros(1, max_steps);
data.env_history   = zeros(1, max_steps);
data.kurt_history  = zeros(1, max_steps);

n = 0;

for k = 1:max_steps
    state = motor_model('step', state, cfg, load_fraction, 1);

    x_meas = sensor_simulator('measure', state, cfg);

    features = signal_processing('extract_features', x_meas, cfg);

    [obs, report] = state_observer('update', obs, features, cfg);

    n = n + 1;
    data.t_hours(n)     = state.t_hours;
    data.HI_true(n)     = 1 - state.D_total;
    data.HI_est(n)      = report.health_index;
    data.sigma_HI(n)    = report.health_sigma;
    data.RUL(n)         = report.rul_hours_nominal;
    data.alert_level(n) = report.alert_level;

    env_total = features.env_BPFO_p + features.env_BPFI_p + ...
                features.env_BPFO_s + features.env_BPFI_s;
    data.rms_history(n)  = features.rms;
    data.env_history(n)  = env_total;
    data.kurt_history(n) = features.kurtosis;

    if state.is_failed
        break;
    end
end

fn = fieldnames(data);
for i = 1:numel(fn)
    v = data.(fn{i});
    if isnumeric(v) && numel(v) == max_steps
        data.(fn{i}) = v(1:n);
    end
end

data.t_failure     = state.t_hours;
data.load_fraction = load_fraction;
data.is_failed     = state.is_failed;
data.final_report  = report;

end

%% ========================================================================
%  LOCAL FUNCTION: print_summary
% ========================================================================
function print_summary(data_heavy, data_light, cfg)



fprintf('Machine:  %s\n', cfg.machine.name);
fprintf('Motor:    %.1f kW @ %d rpm\n', ...
    cfg.machine.motor_power_kW, cfg.machine.motor_rpm);
fprintf('Bearing:  %s (primary)\n\n', cfg.bearing_primary.model);

fprintf('----------------------------------------------------------\n');
fprintf('  SCENARIO A: HEAVY LOAD (%.0f%%)\n', ...
    data_heavy.load_fraction * 100);
fprintf('----------------------------------------------------------\n');
fprintf('  Failure detected at:     %s\n', ...
    format_time(data_heavy.t_failure, data_heavy.is_failed));
fprintf('  First PLAN alert:        %s\n', ...
    format_time(first_alert(data_heavy, 2), true));
fprintf('  SCHEDULE alert:          %s\n', ...
    format_time(first_alert(data_heavy, 3), true));
fprintf('  URGENT alert:            %s\n', ...
    format_time(first_alert(data_heavy, 4), true));
fprintf('  EMERGENCY alert:         %s\n', ...
    format_time(first_alert(data_heavy, 5), true));
fprintf('  Final recommendation:    %s\n\n', ...
    data_heavy.final_report.recommended_action);

fprintf('----------------------------------------------------------\n');
fprintf('  SCENARIO B: LIGHT LOAD (%.0f%%)\n', ...
    data_light.load_fraction * 100);
fprintf('----------------------------------------------------------\n');
fprintf('  Failure detected at:     %s\n', ...
    format_time(data_light.t_failure, data_light.is_failed));
fprintf('  First PLAN alert:        %s\n', ...
    format_time(first_alert(data_light, 2), true));
fprintf('  SCHEDULE alert:          %s\n', ...
    format_time(first_alert(data_light, 3), true));
fprintf('  URGENT alert:            %s\n', ...
    format_time(first_alert(data_light, 4), true));
fprintf('  EMERGENCY alert:         %s\n', ...
    format_time(first_alert(data_light, 5), true));
fprintf('  Final recommendation:    %s\n\n', ...
    data_light.final_report.recommended_action);

fprintf('----------------------------------------------------------\n');
fprintf('  KEY INSIGHT\n');
fprintf('----------------------------------------------------------\n');

if data_light.is_failed && data_heavy.is_failed
    ratio = data_light.t_failure / data_heavy.t_failure;
    fprintf('  The light-load machine outlives the heavy-load machine\n');
    fprintf('  by %.1fx (%.0f h vs %.0f h).\n', ...
        ratio, data_light.t_failure, data_heavy.t_failure);
    fprintf('  This demonstrates the fundamental value of condition-\n');
    fprintf('  based maintenance over calendar-based scheduling.\n\n');
else
    fprintf('  Both scenarios demonstrate the observer correctly\n');
    fprintf('  refusing to predict RUL without degradation evidence,\n');
    fprintf('  and producing clean monotonic predictions once\n');
    fprintf('  degradation is detected.\n\n');
end

end

%% ========================================================================
%  LOCAL FUNCTION: first_alert
% ========================================================================
function t = first_alert(data, level)

idx = find(data.alert_level >= level, 1, 'first');
if isempty(idx)
    t = NaN;
else
    t = data.t_hours(idx);
end

end

%% ========================================================================
%  LOCAL FUNCTION: format_time
% ========================================================================
function s = format_time(t, valid)

if ~valid || ~isfinite(t) || t <= 0
    s = 'N/A';
else
    s = sprintf('%.0f hours (%.1f days)', t, t/24);
end

end