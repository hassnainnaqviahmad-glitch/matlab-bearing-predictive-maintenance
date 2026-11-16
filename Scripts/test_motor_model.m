%% test_motor_model.m
cfg = config_parameters();

fprintf('\n========================================\n');
fprintf('  MOTOR MODEL VERIFICATION\n');
fprintf('========================================\n\n');

% Initialize state
state = motor_model('initialize', cfg);

% Run under constant 100% load
dt = cfg.sim.sample_interval_hours;
fprintf('Running at 100%% load, dt = %d hour...\n\n', dt);
fprintf('%-10s | %-12s | %-12s | %-12s | %-8s\n', ...
    'Time(h)', 'D_fatigue', 'a_crack(m)', 'D_total', 'Phase');
fprintf('%s\n', repmat('-', 1, 70));

report_interval = 2000;
next_report = 0;

for k = 1:60000
    state = motor_model('step', state, cfg, 1.0, dt);
    
    if state.t_hours >= next_report
        fprintf('%-10.0f | %-12.6f | %-12.3e | %-12.6f | %-8d\n', ...
            state.t_hours, state.D_fatigue, state.a_crack, ...
            state.D_total, state.phase);
        next_report = state.t_hours + report_interval;
    end
    
    if state.is_failed
        fprintf('\n*** FAILURE at t = %.0f hours ***\n', state.t_hours);
        fprintf('    D_total = %.4f\n', state.D_total);
        fprintf('    Crack length = %.4e m (%.2f mm)\n', ...
            state.a_crack, state.a_crack*1000);
        break;
    end
end

% Compare heavy vs. light load
fprintf('\n========================================\n');
fprintf('  COMPARATIVE TEST: Heavy vs. Light Load\n');
fprintf('========================================\n\n');

for L = [1.0, 0.4]
    state = motor_model('initialize', cfg);
    while ~state.is_failed && state.t_hours < cfg.sim.total_hours
        state = motor_model('step', state, cfg, L, dt);
    end
    fprintf('Load = %.0f%%  →  Failure at %.0f hours\n', ...
        L*100, state.t_hours);
end