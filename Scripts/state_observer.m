% ========================================================================
%  File: state_observer.m
%  Purpose: Health state observer and maintenance decision engine.
% ========================================================================

function varargout = state_observer(action, varargin)

switch lower(action)
    case 'initialize'
        varargout{1} = init_observer(varargin{:});
    case 'update'
        [varargout{1}, varargout{2}] = update_observer(varargin{:});
    case 'report'
        varargout{1} = query_report(varargin{:});
    case 'reset'
        varargout{1} = reset_observer(varargin{:});
    otherwise
        error('state_observer: unknown action "%s"', action);
end

end

%% ========================================================================
%  INITIALIZATION & RESET
% ========================================================================

function obs = init_observer(cfg)

kf = kalman_filter_design('initialize', cfg);
kf.baseline = kalman_filter_design('init_baseline', cfg);
obs.kf = kf;

obs.history.t_hours  = [];
obs.history.HI       = [];
obs.history.sigma_HI = [];

obs.trend.buffer_size = 400;       
obs.trend.min_samples = 120;       
obs.trend.min_R2      = 0.75;      
obs.trend.HI_gate     = 0.85;      
obs.trend.rate_gate   = -1.8e-4;     
obs.trend.max_RUL     = 50000;

obs.trend.persistence_required = 24;    
obs.trend.persistence_counter  = 0;
obs.trend.last_valid_RUL = Inf;  

obs.alert.last_level = 1;
obs.alert.hysteresis = 0.02;

obs.is_failed = false;
obs.n_updates = 0;

end

function obs = reset_observer(obs, cfg)

kf = kalman_filter_design('initialize', cfg);
kf.baseline = kalman_filter_design('init_baseline', cfg);
obs.kf = kf;

obs.history.t_hours  = [];
obs.history.HI       = [];
obs.history.sigma_HI = [];
obs.alert.last_level = 1;
obs.is_failed = false;
obs.n_updates = 0;

end

%% ========================================================================
%  MAIN UPDATE PIPELINE
% ========================================================================

function [obs, report] = update_observer(obs, features, cfg)

obs.n_updates = obs.n_updates + 1;

if obs.is_failed
    report = failure_report(obs, cfg);
    return;
end

[obs.kf, est] = kalman_filter_design('step', obs.kf, features, cfg);

t_now = obs.kf.t_history(end);
obs.history.t_hours(end+1)  = t_now;
obs.history.HI(end+1)       = est.HI;
obs.history.sigma_HI(end+1) = est.sigma_HI;

if length(obs.history.HI) > obs.trend.buffer_size
    obs.history.t_hours(1)  = [];
    obs.history.HI(1)       = [];
    obs.history.sigma_HI(1) = [];
end

[obs, rul] = compute_trend_rul(obs, est, cfg);

% ---- Enforce monotonicity: RUL can only decrease ----
if isfinite(rul.value_hours)
    if rul.value_hours > obs.trend.last_valid_RUL
        % New RUL is HIGHER than previous → spurious. Reject.
        rul.value_hours = obs.trend.last_valid_RUL;
        rul.upper_hours = obs.trend.last_valid_RUL * 1.25;
        rul.lower_hours = obs.trend.last_valid_RUL * 0.75;
        rul.method      = 'hold';
    else
        obs.trend.last_valid_RUL = rul.value_hours;
    end
end

[obs, alert_level] = classify_alert(obs, est.HI, cfg);
report = build_report(t_now, est, rul, alert_level, cfg);

if est.HI <= cfg.health.HI_critical && est.baseline_learned
    obs.is_failed = true;
    report.is_failed = true;
    report.recommended_action = 'MACHINE FAILED. Shut down immediately.';
end

end

%% ========================================================================
%  TREND EXTRAPOLATION
% ========================================================================

function [obs, rul] = compute_trend_rul(obs, est, cfg)

rul.value_hours = NaN;
rul.upper_hours = NaN;
rul.lower_hours = NaN;
rul.method      = 'none';
rul.R2          = NaN;

if ~isfinite(est.HI) || est.HI >= obs.trend.HI_gate
    obs.trend.persistence_counter = 0;  
    return;
end

if ~isfinite(est.HI_rate) || est.HI_rate >= obs.trend.rate_gate
    obs.trend.persistence_counter = 0;   
    return;
end


obs.trend.persistence_counter = obs.trend.persistence_counter + 1;
if obs.trend.persistence_counter < obs.trend.persistence_required
    return;
end

n_samples = length(obs.history.HI);
if n_samples < obs.trend.min_samples
    return;
end

t_buf  = obs.history.t_hours(:);
HI_buf = obs.history.HI(:);

t0    = t_buf(1);
t_buf = t_buf - t0;

A = [ones(size(t_buf)), t_buf, t_buf.^2];
coeffs = A \ HI_buf;
c0 = coeffs(1);
c1 = coeffs(2);
c2 = coeffs(3);

HI_fit = A * coeffs;
SS_res = sum((HI_buf - HI_fit).^2);
SS_tot = sum((HI_buf - mean(HI_buf)).^2);
R2 = 1 - SS_res / max(SS_tot, eps);
rul.R2 = R2;

if R2 < obs.trend.min_R2
    return;
end

if c2 >= 0
    return;
end

HI_crit = cfg.health.HI_critical;
a = c2;
b = c1;
c = c0 - HI_crit;

disc = b^2 - 4*a*c;
if disc < 0
    return;
end

sqrt_disc = sqrt(disc);
t_root1 = (-b + sqrt_disc) / (2*a);
t_root2 = (-b - sqrt_disc) / (2*a);

t_buffer_end = t_buf(end);
candidates = [t_root1, t_root2];
valid = candidates(candidates > t_buffer_end);

if isempty(valid)
    return;
end

t_failure_in_buffer = min(valid);
RUL_hours = t_failure_in_buffer - t_buffer_end;

if RUL_hours <= 0 || RUL_hours > obs.trend.max_RUL
    return;
end

rul.value_hours = RUL_hours;
rul.method      = 'trend';
rul.upper_hours = RUL_hours * 1.25;
rul.lower_hours = RUL_hours * 0.75;

end

%% ========================================================================
%  ALERT CLASSIFICATION
% ========================================================================

function [obs, level] = classify_alert(obs, HI, cfg)

t1 = cfg.health.HI_healthy;
t2 = cfg.health.HI_mild;
t3 = cfg.health.HI_moderate;
t4 = cfg.health.HI_severe;

hy   = obs.alert.hysteresis;
last = obs.alert.last_level;

if HI > t1
    raw = 1;
elseif HI > t2
    raw = 2;
elseif HI > t3
    raw = 3;
elseif HI > t4
    raw = 4;
else
    raw = 5;
end

if raw > last
    level = raw;
elseif raw < last
    switch last
        case 5
            if HI > t4 + hy, level = 4; else, level = 5; end
        case 4
            if HI > t3 + hy, level = 3; else, level = 4; end
        case 3
            if HI > t2 + hy, level = 2; else, level = 3; end
        case 2
            if HI > t1 + hy, level = 1; else, level = 2; end
        otherwise
            level = raw;
    end
else
    level = last;
end

obs.alert.last_level = level;

end

%% ========================================================================
%  REPORT GENERATION
% ========================================================================

function report = build_report(t_hours, est, rul, alert_level, cfg)

report.timestamp_hours = t_hours;

report.health_index = est.HI;
report.health_sigma = est.sigma_HI;
report.health_rate  = est.HI_rate;
report.health_upper = min(1, est.HI + 2*est.sigma_HI);
report.health_lower = max(0, est.HI - 2*est.sigma_HI);

report.rul_hours_nominal = rul.value_hours;
report.rul_hours_upper   = rul.upper_hours;
report.rul_hours_lower   = rul.lower_hours;
report.rul_method        = rul.method;
report.rul_fit_R2        = rul.R2;

report.alert_level        = alert_level;
report.alert_label        = alert_label(alert_level);
report.recommended_action = recommended_action(alert_level, rul.value_hours);

report.is_failed        = false;
report.is_valid         = isfinite(est.HI);
report.baseline_learned = est.baseline_learned;

end

function report = failure_report(obs, cfg)

t_end = 0;
if ~isempty(obs.history.t_hours)
    t_end = obs.history.t_hours(end);
end

report.timestamp_hours = t_end;
report.health_index   = 0;
report.health_sigma   = 0;
report.health_rate    = NaN;
report.health_upper   = 0;
report.health_lower   = 0;
report.rul_hours_nominal = 0;
report.rul_hours_upper   = 0;
report.rul_hours_lower   = 0;
report.rul_method        = 'none';
report.rul_fit_R2        = NaN;
report.alert_level        = 5;
report.alert_label        = 'FAILED';
report.recommended_action = 'MACHINE FAILED. Shut down immediately.';
report.is_failed        = true;
report.is_valid         = true;
report.baseline_learned = true;

end

function report = query_report(obs, cfg)

if obs.is_failed
    report = failure_report(obs, cfg);
    return;
end

if isempty(obs.history.HI)
    error('state_observer: no history yet — call ''update'' first');
end

est.HI            = obs.history.HI(end);
est.sigma_HI      = obs.history.sigma_HI(end);
est.HI_rate       = obs.kf.x(2);

if isfield(obs.kf, 'last_est') && ~isempty(obs.kf.last_est)
    est_rul = obs.kf.last_est;
else
    est_rul.RUL_nominal_hours = NaN;
    est_rul.RUL_upper_hours   = NaN;
    est_rul.RUL_lower_hours   = NaN;
end

[~, rul] = compute_trend_rul(obs, est, cfg);

report = build_report(obs.history.t_hours(end), est, rul, ...
    obs.alert.last_level, cfg);

end

%% ========================================================================
%  TEXT MAPPINGS
% ========================================================================

function label = alert_label(level)
switch level
    case 1, label = 'NORMAL';
    case 2, label = 'PLAN';
    case 3, label = 'SCHEDULE';
    case 4, label = 'URGENT';
    case 5, label = 'EMERGENCY';
    otherwise, label = 'UNKNOWN';
end
end

function txt = recommended_action(level, rul_hours)
if ~isfinite(rul_hours)
    rul_txt = '';
else
    rul_txt = sprintf(' (RUL ~ %.0f h)', rul_hours);
end

switch level
    case 1
        txt = 'Continue normal operation. No action required.';
    case 2
        txt = ['Degradation detected. Plan maintenance within ' ...
               'the next scheduled window.' rul_txt];
    case 3
        txt = ['Schedule maintenance soon. Order spare parts and ' ...
               'prepare work order.' rul_txt];
    case 4
        txt = ['URGENT: Schedule intervention at the next safe ' ...
               'opportunity.' rul_txt];
    case 5
        txt = ['EMERGENCY: Stop machine at next safe opportunity. ' ...
               'Immediate inspection required.' rul_txt];
    otherwise
        txt = 'Unknown state.';
end
end