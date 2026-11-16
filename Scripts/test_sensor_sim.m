%% test_sensor_sim.m
cfg = config_parameters();

fprintf('\n========================================\n');
fprintf('  SENSOR SIMULATOR VERIFICATION\n');
fprintf('========================================\n\n');

% --- Test 1: Healthy Bearing ---
state = motor_model('initialize', cfg);
[x_healthy, info_healthy] = sensor_simulator('measure', state, cfg);

fprintf('Test 1: Healthy Bearing (D = %.3f)\n', state.D_total);
fprintf('  Signal length:    %d samples (%.2f s)\n', ...
    length(x_healthy), length(x_healthy)/cfg.sensor.Fs);
fprintf('  RMS (measured):   %.4f m/s²\n', info_healthy.rms_total);
fprintf('  RMS (clean):      %.4f m/s²\n', info_healthy.rms_clean);
fprintf('  SNR:              %.2f dB\n\n', info_healthy.snr_dB);

% --- Test 2: Degraded Bearing (simulate a few thousand hours) ---
state = motor_model('initialize', cfg);
fprintf('Simulating degradation at 100%% load...\n');
for k = 1:30000
    state = motor_model('step', state, cfg, 1.0, 1);
    if state.is_failed, break; end
end

% Force damage to a high level for testing (bypass to reach the target)
% Instead, run until D_total reaches ~0.7
state = motor_model('initialize', cfg);
while state.D_total < 0.7 && ~state.is_failed
    state = motor_model('step', state, cfg, 1.0, 1);
end

[x_degraded, info_degraded] = sensor_simulator('measure', state, cfg);

fprintf('\nTest 2: Degraded Bearing (D = %.3f, t = %.0f h)\n', ...
    state.D_total, state.t_hours);
fprintf('  RMS (measured):   %.4f m/s²\n', info_degraded.rms_total);
fprintf('  RMS (clean):      %.4f m/s²\n', info_degraded.rms_clean);
fprintf('  SNR:              %.2f dB\n\n', info_degraded.snr_dB);

% --- Test 3: Saturation Check ---
fprintf('Test 3: Saturation Check\n');
fprintf('  Max amplitude measured:  %.2f m/s²\n', max(abs(x_degraded)));
fprintf('  Saturation limit:        %.2f m/s²\n', cfg.sensor.saturation_max);
fprintf('  Saturated samples:       %d / %d\n\n', ...
    sum(abs(x_degraded) >= cfg.sensor.saturation_max - 1e-6), length(x_degraded));

% --- Test 4: Visual Comparison ---
figure('Position', [100 100 1200 700]);

subplot(2,2,1);
plot(info_healthy.t(1:2000), x_healthy(1:2000), 'b', 'LineWidth', 0.5);
xlabel('Time [s]'); ylabel('Acceleration [m/s²]');
title(sprintf('Healthy Bearing (RMS = %.3f m/s²)', info_healthy.rms_total));
grid on;

subplot(2,2,2);
plot(info_degraded.t(1:2000), x_degraded(1:2000), 'r', 'LineWidth', 0.5);
xlabel('Time [s]'); ylabel('Acceleration [m/s²]');
title(sprintf('Degraded Bearing (RMS = %.3f m/s²)', info_degraded.rms_total));
grid on;

subplot(2,2,3);
[P_h, f_h] = pwelch(x_healthy, [], [], [], cfg.sensor.Fs);
semilogy(f_h, P_h, 'b', 'LineWidth', 1.2); hold on;
xlabel('Frequency [Hz]'); ylabel('PSD [m²/s⁴/Hz]');
title('Spectrum: Healthy');
xlim([0 1000]); grid on;

subplot(2,2,4);
[P_d, f_d] = pwelch(x_degraded, [], [], [], cfg.sensor.Fs);
semilogy(f_d, P_d, 'r', 'LineWidth', 1.2); hold on;
xlabel('Frequency [Hz]'); ylabel('PSD [m²/s⁴/Hz]');
title('Spectrum: Degraded');
xlim([0 1000]); grid on;

% Mark expected fault frequencies
for ax = [3, 4]
    subplot(2,2,ax); hold on;
    xline(cfg.fault_freq.primary.BPFO, '--k', 'BPFO', ...
        'LabelOrientation', 'horizontal', 'LabelVerticalAlignment', 'bottom');
    xline(cfg.fault_freq.primary.BPFI, '--k', 'BPFI', ...
        'LabelOrientation', 'horizontal', 'LabelVerticalAlignment', 'bottom');
    xline(cfg.machine.rot_freq_Hz, '--g', '1x', ...
        'LabelOrientation', 'horizontal', 'LabelVerticalAlignment', 'bottom');
end

sgtitle('Sensor Simulator: Healthy vs. Degraded', 'FontSize', 14, 'FontWeight', 'bold');