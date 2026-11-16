%% test_kalman.m
cfg = config_parameters();

fprintf('\n========================================\n');
fprintf('  KALMAN FILTER VERIFICATION\n');
fprintf('========================================\n\n');

% ---- Initialize filter and baseline ----
kf = kalman_filter_design('initialize', cfg);
kf.baseline = kalman_filter_design('init_baseline', cfg);

% ---- Simulate a full run with 100% load ----
state = motor_model('initialize', cfg);

HI_est_history  = [];
HI_true_history = [];
RUL_history     = [];
sigma_history   = [];
t_history       = [];
alert_history   = [];

report_interval = 2000;
next_report = 0;

fprintf('%-10s | %-10s | %-10s | %-10s | %-10s | %-6s\n', ...
    'Time(h)', 'HI_true', 'HI_est', 'sigma', 'RUL(h)', 'Level');
fprintf('%s\n', repmat('-', 1, 75));

for k = 1:40000
    % Physics step
    state = motor_model('step', state, cfg, 1.0, 1);
    
    % Sensor measurement
    x_meas = sensor_simulator('measure', state, cfg);
    
    % Feature extraction
    features = signal_processing('extract_features', x_meas, cfg);
    
    % Kalman filter step
    [kf, est] = kalman_filter_design('step', kf, features, cfg);
    
    % Record
    HI_true_history(end+1) = 1 - state.D_total;
    HI_est_history(end+1)  = est.HI;
    RUL_history(end+1)     = est.RUL_nominal_hours;
    sigma_history(end+1)   = est.sigma_HI;
    t_history(end+1)       = state.t_hours;
    alert_history(end+1)   = est.alert_level;
    
    if state.t_hours >= next_report && est.baseline_learned
        if isnan(est.RUL_nominal_hours) || isinf(est.RUL_nominal_hours)
    RUL_str = 'NaN';
    fprintf('%-10.0f | %-10.4f | %-10.4f | %-10.4f | %-10s | %-6d\n', ...
        state.t_hours, 1-state.D_total, est.HI, est.sigma_HI, ...
        RUL_str, est.alert_level);
        else
    fprintf('%-10.0f | %-10.4f | %-10.4f | %-10.4f | %-10.0f | %-6d\n', ...
        state.t_hours, 1-state.D_total, est.HI, est.sigma_HI, ...
        est.RUL_nominal_hours, est.alert_level);
        end

        next_report = state.t_hours + report_interval;
    end
    
    if state.is_failed, break; end
end

fprintf('\n*** Failure at t = %.0f hours ***\n', state.t_hours);
fprintf('    HI_true  = %.4f\n', 1 - state.D_total);
fprintf('    HI_est   = %.4f ± %.4f\n', est.HI, est.sigma_HI);

% ---- Plot results ----
figure('Position', [100 100 1400 900]);

subplot(3,1,1);
plot(t_history, HI_true_history, 'b-', 'LineWidth', 2); hold on;
plot(t_history, HI_est_history, 'r--', 'LineWidth', 1.5);
fill([t_history, fliplr(t_history)], ...
     [HI_est_history + 2*sigma_history, fliplr(HI_est_history - 2*sigma_history)], ...
     'r', 'FaceAlpha', 0.15, 'EdgeColor', 'none');
yline(cfg.health.HI_mild, '--k', 'Plan');
yline(cfg.health.HI_moderate, '--k', 'Schedule');
yline(cfg.health.HI_severe, '--k', 'Urgent');
yline(cfg.health.HI_critical, '--r', 'Emergency');
xlabel('Time [hours]'); ylabel('Health Index');
title('Health Estimation: Kalman Filter vs. Ground Truth');
legend('True HI', 'Kalman Estimate', '±2σ confidence', 'Location', 'southwest');
grid on; ylim([0 1.1]);

subplot(3,1,2);
plot(t_history, RUL_history, 'b-', 'LineWidth', 1.5);
xlabel('Time [hours]'); ylabel('RUL [hours]');
title('Remaining Useful Life Estimate ');
ylim([0 10000]);      
grid on;

subplot(3,1,3);
plot(t_history, alert_history, 'k-', 'LineWidth', 1);
xlabel('Time [hours]'); ylabel('Alert Level');
title('Maintenance Alert Level');
yticks(1:5); yticklabels({'Normal', 'Plan', 'Schedule', 'Urgent', 'EMERGENCY'});
ylim([0.5 5.5]); grid on;

sgtitle('Kalman Filter: Health State Estimation', ...
    'FontSize', 14, 'FontWeight', 'bold');