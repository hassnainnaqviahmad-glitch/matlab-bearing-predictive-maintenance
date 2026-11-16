%% test_visualize.m
clear functions
cfg = config_parameters();

fprintf('\n========================================\n');
fprintf('  VISUALIZATION TEST\n');
fprintf('========================================\n\n');

% --- Run simulation and capture full history ---
obs   = state_observer('initialize', cfg);
state = motor_model('initialize', cfg);

data.t_hours       = [];
data.HI_true       = [];
data.HI_est        = [];
data.sigma_HI      = [];
data.RUL           = [];
data.alert_level   = [];
data.rms_history   = [];
data.env_history   = [];
data.kurt_history  = [];

for k = 1:15000
    state    = motor_model('step', state, cfg, 1.0, 1);
    x_meas   = sensor_simulator('measure', state, cfg);
    features = signal_processing('extract_features', x_meas, cfg);
    [obs, report] = state_observer('update', obs, features, cfg);
    
    data.t_hours(end+1)     = state.t_hours;
    data.HI_true(end+1)     = 1 - state.D_total;
    data.HI_est(end+1)      = report.health_index;
    data.sigma_HI(end+1)    = report.health_sigma;
    data.RUL(end+1)         = report.rul_hours_nominal;
    data.alert_level(end+1) = report.alert_level;
    
    % Feature history (for feature plot)
    env_total = features.env_BPFO_p + features.env_BPFI_p + ...
                features.env_BPFO_s + features.env_BPFI_s;
    data.rms_history(end+1)  = features.rms;
    data.env_history(end+1)  = env_total;
    data.kurt_history(end+1) = features.kurtosis;
    
    if state.is_failed, break; end
end

% --- Render all figures to Results/ ---
visualize_results('export_all', data, cfg, 'Results');