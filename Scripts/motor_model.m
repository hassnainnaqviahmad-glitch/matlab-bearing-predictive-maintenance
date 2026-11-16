% ========================================================================
%  File: motor_model.m
%  Purpose: Damage evolution and vibration signature generation for a
%           motor-bearing system.
% ========================================================================

function varargout = motor_model(action, varargin)

switch lower(action)
    case 'initialize'
        varargout{1} = init_state(varargin{:});
    case 'step'
        varargout{1} = step_state(varargin{:});
    case 'bearing_properties'
        [varargout{1}, varargout{2}] = compute_bearing_K_C(varargin{:});
    case 'vibration_amplitudes'
        varargout{1} = compute_vibration_amplitudes(varargin{:});
    case 'health'
        varargout{1} = compute_health_index(varargin{:});
    case 'diagnostics'
        varargout{1} = compute_diagnostics(varargin{:});
    otherwise
        error('motor_model: unknown action "%s"', action);
end

end

%% ========================================================================
%  STATE INITIALIZATION
% ========================================================================

function state = init_state(cfg)

state.t_hours = 0;
state.D_fatigue = cfg.damage.D_initial;
state.a_crack = 0;
state.D_total = cfg.damage.D_initial;
state.phase = 1;

state.load_history = [];
state.load_fraction_current = 1.0;
state.motor_torque_Nm = 0;
state.bearing_load_kN = 0;

state.is_failed = false;
state.cumulative_load_cycles = 0;
state.peak_load_observed = 0;
state.min_load_observed = 1;

end

%% ========================================================================
%  MAIN STEP FUNCTION
% ========================================================================

function state = step_state(state, cfg, load_fraction, dt_hours)

if load_fraction < 0 || load_fraction > 1
    error('motor_model: load_fraction must be in [0, 1], got %f', load_fraction);
end
if dt_hours <= 0
    error('motor_model: dt_hours must be positive, got %f', dt_hours);
end

if state.is_failed
    return;
end

state.t_hours = state.t_hours + dt_hours;
state.load_history(end+1) = load_fraction;
state.load_fraction_current = load_fraction;

if load_fraction > state.peak_load_observed
    state.peak_load_observed = load_fraction;
end
if load_fraction < state.min_load_observed
    state.min_load_observed = load_fraction;
end

omega_rated = 2 * pi * cfg.machine.motor_rpm / 60;
T_rated = (cfg.machine.motor_power_kW * 1000) / omega_rated;
state.motor_torque_Nm = load_fraction * T_rated;
state.bearing_load_kN = load_fraction * cfg.fatigue.P_ref_kN;

cycles_this_step = dt_hours * 3600 * cfg.machine.rot_freq_Hz;
state.cumulative_load_cycles = state.cumulative_load_cycles + cycles_this_step;

state.D_fatigue = update_fatigue_damage(state.D_fatigue, load_fraction, dt_hours, cfg);

if state.D_fatigue >= cfg.damage.D_onset && state.phase == 1
    state.phase = 2;
    state.a_crack = cfg.crack.initial_length_m;
end

if state.phase == 2
    state.a_crack = update_crack_length(state.a_crack, load_fraction, dt_hours, cfg);
end

state.D_total = compute_total_damage(state.D_fatigue, state.a_crack, state.phase, cfg);

if state.D_total >= cfg.damage.D_failure || state.a_crack >= cfg.crack.critical_length_m
    state.is_failed = true;
    state.D_total = cfg.damage.D_failure;
end

end

%% ========================================================================
%  FATIGUE DAMAGE ACCUMULATION (PHASE 1)
% ========================================================================

function D_new = update_fatigue_damage(D, load_fraction, dt_hours, cfg)

p = cfg.fatigue.p_roller;
damage_rate = (load_fraction ^ p) / cfg.fatigue.L10_hours_at_ref;
D_new = D + damage_rate * dt_hours;

if D_new > cfg.damage.D_onset
    D_new = cfg.damage.D_onset;
end

end

%% ========================================================================
%  CRACK PROPAGATION (PHASE 2)
% ========================================================================

function a_new = update_crack_length(a, load_fraction, dt_hours, cfg)

C = cfg.crack.Paris_C_calibrated;
m = cfg.material.Paris_m;
Y = 1.12;

sigma_ref = cfg.crack.DeltaK_ref_MPa_m05 / (Y * sqrt(pi * cfg.crack.initial_length_m));
DeltaK = Y * (load_fraction * sigma_ref) * sqrt(pi * a);

cycles_per_hour = 3600 * cfg.machine.rot_freq_Hz;
da_dN = C * (DeltaK ^ m);
da_dt = da_dN * cycles_per_hour;

a_new = a + da_dt * dt_hours;

if a_new > cfg.crack.critical_length_m
    a_new = cfg.crack.critical_length_m;
end

a_new = max(a_new, a);

end

%% ========================================================================
%  TOTAL DAMAGE MAPPING
% ========================================================================

function D_total = compute_total_damage(D_fatigue, a_crack, phase, cfg)

if phase == 1
    D_total = D_fatigue;
else
    a_frac = (a_crack - cfg.crack.initial_length_m) / ...
             (cfg.crack.critical_length_m - cfg.crack.initial_length_m);
    
    a_frac = max(0, min(1, a_frac));
    D_total = cfg.damage.D_onset + a_frac * (cfg.damage.D_failure - cfg.damage.D_onset);
end

end

%% ========================================================================
%  BEARING STIFFNESS & DAMPING
% ========================================================================

function [K, C] = compute_bearing_K_C(state, cfg)

D = state.D_total;

K = cfg.bearing_primary.K_healthy_N_per_m * (1 - cfg.stiffness.alpha_K * D);
C = cfg.bearing_primary.C_healthy_Ns_per_m * (1 + cfg.stiffness.alpha_C * D);

K = max(K, 0.01 * cfg.bearing_primary.K_healthy_N_per_m);
C = max(C, 0);

end

%% ========================================================================
%  VIBRATION SIGNATURE AMPLITUDES
% ========================================================================

function amps = compute_vibration_amplitudes(state, cfg)

D = state.D_total;

A_BPFO_baseline_ratio = 0.15;
A_BPFI_baseline_ratio = 0.10;

A_1x = cfg.vibration.A_healthy_1x_g * (1 + 0.10 * D);
amps.A_1x = A_1x;

A_BPFO_primary = A_1x * A_BPFO_baseline_ratio * ...
    (1 + cfg.vibration.k_defect_primary * D ^ cfg.vibration.gamma_defect_primary);
amps.A_BPFO_primary = A_BPFO_primary;

A_BPFI_primary = A_1x * A_BPFI_baseline_ratio * ...
    (1 + 0.7 * cfg.vibration.k_defect_primary * D ^ cfg.vibration.gamma_defect_primary);
amps.A_BPFI_primary = A_BPFI_primary;

A_BPFO_secondary = A_1x * A_BPFO_baseline_ratio * ...
    (1 + cfg.vibration.k_defect_secondary * D ^ cfg.vibration.gamma_defect_secondary);
amps.A_BPFO_secondary = A_BPFO_secondary;

A_BPFI_secondary = A_1x * A_BPFI_baseline_ratio * ...
    (1 + 0.7 * cfg.vibration.k_defect_secondary * D ^ cfg.vibration.gamma_defect_secondary);
amps.A_BPFI_secondary = A_BPFI_secondary;

A_noise = cfg.vibration.A_healthy_noise_g * (1 + cfg.vibration.k_noise * D);
amps.A_noise = A_noise;

amps.D_total = D;
amps.HI_true = compute_health_index(state);

end

%% ========================================================================
%  TRUE HEALTH INDEX GROUND TRUTH
% ========================================================================

function HI = compute_health_index(state)

HI = max(0, 1 - state.D_total);

end

%% ========================================================================
%  DIAGNOSTICS
% ========================================================================

function diag = compute_diagnostics(state, cfg)

diag.t_hours = state.t_hours;
diag.D_fatigue = state.D_fatigue;
diag.a_crack = state.a_crack;
diag.D_total = state.D_total;
diag.phase = state.phase;
diag.is_failed = state.is_failed;
diag.HI_true = compute_health_index(state);
diag.load_fraction = state.load_fraction_current;
diag.motor_torque_Nm = state.motor_torque_Nm;
diag.bearing_load_kN = state.bearing_load_kN;
diag.cumulative_cycles = state.cumulative_load_cycles;

[K, C] = compute_bearing_K_C(state, cfg);
diag.K_N_per_m = K;
diag.C_Ns_per_m = C;

amps = compute_vibration_amplitudes(state, cfg);
diag.vibration = amps;

end