%% ========================================================================
%  File: test_state_observer.m
%  Purpose: End-to-end verification of the state observer pipeline.
% ========================================================================

clear functions   % reset any persistent state in kalman_filter_design

cfg = config_parameters();

fprintf('\n========================================\n');
fprintf('  STATE OBSERVER VERIFICATION\n');
fprintf('========================================\n\n');

% ---- Initialize observer and physics ----
obs   = state_observer('initialize', cfg);
state = motor_model('initialize', cfg);

% ---- History buffers ----
t_history       = [];
HI_true_history = [];
HI_est_history  = [];
sigma_history   = [];
rul_history     = [];
method_history  = {};
alert_history   = [];

% ---- Reporting ----
report_interval = 1000;
next_report = 0;

fprintf('%-8s | %-8s | %-8s | %-8s | %-10s | %-8s | %-10s\n', ...
    'Time(h)', 'HI_true', 'HI_est', 'Sigma', 'RUL(h)', 'Method', 'Alert');
fprintf('%s\n', repmat('-', 1, 82));

% ---- Main loop ----
for k = 1:15000
    % Physics
    state = motor_model('step', state, cfg, 1.0, 1);

    % Sensor measurement
    x_meas = sensor_simulator('measure', state, cfg);

    % Feature extraction
    features = signal_processing('extract_features', x_meas, cfg);

    % Observer update
    [obs, report] = state_observer('update', obs, features, cfg);

    % Record
    t_history(end+1)       = state.t_hours;
    HI_true_history(end+1) = 1 - state.D_total;
    HI_est_history(end+1)  = report.health_index;
    sigma_history(end+1)   = report.health_sigma;
    rul_history(end+1)     = report.rul_hours_nominal;
    method_history{end+1}  = report.rul_method;
    alert_history(end+1)   = report.alert_level;

    % Periodic print
    if state.t_hours >= next_report && report.baseline_learned
        if ~isfinite(report.rul_hours_nominal)
            rul_str = 'NaN';
        else
            rul_str = sprintf('%.0f', report.rul_hours_nominal);
        end
        fprintf('%-8.0f | %-8.4f | %-8.4f | %-8.4f | %-10s | %-8s | %-10s\n', ...
            state.t_hours, 1-state.D_total, report.health_index, ...
            report.health_sigma, rul_str, report.rul_method, report.alert_label);
        next_report = state.t_hours + report_interval;
    end

    if state.is_failed
        break;
    end
end

fprintf('\n*** Simulation ended at t = %.0f hours ***\n', state.t_hours);
if obs.is_failed
    fprintf('    Status: FAILED\n');
else
    fprintf('    Status: RUNNING\n');
end
fprintf('    Final report: %s\n', report.recommended_action);
fprintf('    HI_true  = %.4f\n', 1 - state.D_total);
fprintf('    HI_est   = %.4f +/- %.4f\n', ...
    report.health_index, report.health_sigma);

% ========================================================================
%  VISUALIZATION
% ========================================================================

figure('Position', [100 100 1400 900]);

% ---- Plot 1: Health ----
subplot(3,1,1);
plot(t_history, HI_true_history, 'b-', 'LineWidth', 2); hold on;
plot(t_history, HI_est_history, 'r--', 'LineWidth', 1.5);
xlabel('Time [hours]'); ylabel('Health Index');
title('Health Estimation: True vs. Observer Estimate');
legend('True HI', 'Observer estimate', 'Location', 'southwest');
yline(cfg.health.HI_mild, ':k');
yline(cfg.health.HI_moderate, ':k');
yline(cfg.health.HI_severe, ':k');
yline(cfg.health.HI_critical, '--r');
grid on; ylim([0 1.1]);

% ---- Plot 2: RUL ----
subplot(3,1,2);
plot(t_history, rul_history, 'b-', 'LineWidth', 1.5);
xlabel('Time [hours]'); ylabel('RUL [hours]');
title('Remaining Useful Life (NaN = not yet predictable)');
ylim([0 5000]); grid on;

% ---- Plot 3: Alert Level ----
subplot(3,1,3);
stairs(t_history, alert_history, 'k-', 'LineWidth', 1.5);
xlabel('Time [hours]'); ylabel('Alert Level');
title('Maintenance Alert Level');
yticks(1:5);
yticklabels({'Normal', 'Plan', 'Schedule', 'Urgent', 'Emergency'});
ylim([0.5 5.5]); grid on;

sgtitle('State Observer: End-to-End SHM Pipeline', ...
    'FontSize', 14, 'FontWeight', 'bold');