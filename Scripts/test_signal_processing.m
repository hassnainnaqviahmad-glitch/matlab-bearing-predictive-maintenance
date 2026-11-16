%% test_signal_processing.m
cfg = config_parameters();

fprintf('\n========================================\n');
fprintf('  SIGNAL PROCESSING VERIFICATION\n');
fprintf('========================================\n\n');

% ---- Generate healthy signal ----
state = motor_model('initialize', cfg);
[x_healthy, ~] = sensor_simulator('measure', state, cfg);
feat_healthy = signal_processing('extract_features', x_healthy, cfg);

% ---- Generate degraded signal (D ~= 0.7) ----
state = motor_model('initialize', cfg);
while state.D_total < 0.7 && ~state.is_failed
    state = motor_model('step', state, cfg, 1.0, 1);
end
[x_degraded, ~] = sensor_simulator('measure', state, cfg);
feat_degraded = signal_processing('extract_features', x_degraded, cfg);

% ---- Print comparison table ----
fprintf('%-25s | %-14s | %-14s | %-10s\n', ...
    'Feature', 'Healthy', 'Degraded', 'Ratio');
fprintf('%s\n', repmat('-', 1, 70));

feature_list = {
    'RMS',              'rms'
    'Peak',             'peak'
    'Crest Factor',     'crest_factor'
    'Kurtosis',         'kurtosis'
    'Skewness',         'skewness'
    'BPFO_p / 1x',      'ratio_BPFO_p'
    'BPFI_p / 1x',      'ratio_BPFI_p'
    'BPFO_s / 1x',      'ratio_BPFO_s'
    'Env BPFO_p',       'env_BPFO_p'
    'Env BPFI_p',       'env_BPFI_p'
    'Env BPFO_s',       'env_BPFO_s'
};

for i = 1:size(feature_list, 1)
    name = feature_list{i, 1};
    field = feature_list{i, 2};
    v_h = feat_healthy.(field);
    v_d = feat_degraded.(field);
    ratio = v_d / max(v_h, eps);
    fprintf('%-25s | %-14.6f | %-14.6f | %-10.2f\n', name, v_h, v_d, ratio);
end

fprintf('\n--- Feature Vector (normalized) ---\n');
fprintf('Healthy  : [');
fprintf('%.3f ', feat_healthy.feature_vector);
fprintf(']\n');
fprintf('Degraded : [');
fprintf('%.3f ', feat_degraded.feature_vector);
fprintf(']\n\n');

% ---- Visualize spectra ----
figure('Position', [100 100 1400 800]);

% Healthy spectrum
subplot(2,2,1);
[f, Pxx] = signal_processing('spectrum', x_healthy, cfg);
semilogy(f, Pxx, 'b', 'LineWidth', 1); hold on;
xline(cfg.machine.rot_freq_Hz, '--g', '1x');
xline(cfg.fault_freq.primary.BPFO, '--r', 'BPFO_p');
xline(cfg.fault_freq.primary.BPFI, '--m', 'BPFI_p');
xlim([0 500]); grid on;
xlabel('Frequency [Hz]'); ylabel('PSD [m²/s⁴/Hz]');
title('Healthy: Spectrum');

% Degraded spectrum
subplot(2,2,2);
[f, Pxx] = signal_processing('spectrum', x_degraded, cfg);
semilogy(f, Pxx, 'r', 'LineWidth', 1); hold on;
xline(cfg.machine.rot_freq_Hz, '--g', '1x');
xline(cfg.fault_freq.primary.BPFO, '--r', 'BPFO_p');
xline(cfg.fault_freq.primary.BPFI, '--m', 'BPFI_p');
xlim([0 500]); grid on;
xlabel('Frequency [Hz]'); ylabel('PSD [m²/s⁴/Hz]');
title('Degraded: Spectrum');

% Healthy envelope
subplot(2,2,3);
[f_env, Pxx_env] = signal_processing('envelope', x_healthy, cfg);
semilogy(f_env, Pxx_env, 'b', 'LineWidth', 1); hold on;
xline(cfg.fault_freq.primary.BPFO, '--r', 'BPFO_p');
xline(cfg.fault_freq.primary.BPFI, '--m', 'BPFI_p');
xlim([0 500]); grid on;
xlabel('Frequency [Hz]'); ylabel('Envelope PSD');
title('Healthy: Envelope Spectrum');

% Degraded envelope
subplot(2,2,4);
[f_env, Pxx_env] = signal_processing('envelope', x_degraded, cfg);
semilogy(f_env, Pxx_env, 'r', 'LineWidth', 1); hold on;
xline(cfg.fault_freq.primary.BPFO, '--r', 'BPFO_p');
xline(cfg.fault_freq.primary.BPFI, '--m', 'BPFI_p');
xlim([0 500]); grid on;
xlabel('Frequency [Hz]'); ylabel('Envelope PSD');
title('Degraded: Envelope Spectrum');

sgtitle('Feature Extraction: Healthy vs. Degraded', ...
    'FontSize', 14, 'FontWeight', 'bold');