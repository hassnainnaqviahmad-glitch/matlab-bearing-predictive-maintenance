% ========================================================================
%  File: kalman_filter_design.m
%  Purpose: Estimate the health state of the bearing from noisy feature
%           measurements and provide uncertainty quantification.
% ========================================================================

function varargout = kalman_filter_design(action, varargin)

switch lower(action)
    case 'initialize'
        varargout{1} = init_filter(varargin{:});
    case {'step'}             
        [varargout{1}, varargout{2}] = step_filter(varargin{:});
    case 'predict_only'
        [varargout{1}, varargout{2}] = predict_only(varargin{:});
    case 'init_baseline'
        varargout{1} = init_baseline(varargin{:});
    case 'measurement'
        [varargout{1}, varargout{2}] = compute_measurement(varargin{:});
    case 'smooth'
        varargout{1} = rts_smoother(varargin{:});
    otherwise
        error('kalman_filter_design: unknown action "%s"', action);
end

end

%% ========================================================================
%  FILTER INITIALIZATION
% ========================================================================

function kf = init_filter(cfg)

kf.x = cfg.kalman.x0(:);

dt = cfg.sim.sample_interval_hours;
kf.A = [1, dt; 0, 1];
kf.H = [1, 0];
kf.Q = cfg.kalman.Q;
kf.R = cfg.kalman.R;
kf.P = cfg.kalman.P0;
kf.I = eye(2);

kf.innovation_history = [];
kf.HI_history = kf.x(1);
kf.rate_history = kf.x(2);
kf.sigma_HI_history = sqrt(kf.P(1,1));
kf.sigma_rate_history = sqrt(kf.P(2,2));
kf.t_history = 0;
kf.z_history = [];

end

%% ========================================================================
%  MAIN STEP: PREDICT + UPDATE
% ========================================================================

function [kf, est] = step_filter(kf, features, cfg)

[kf.baseline, z] = compute_measurement(kf.baseline, features, ...
    length(kf.z_history) + 1, cfg);

dt = cfg.sim.sample_interval_hours;

x_pred = kf.A * kf.x;
P_pred = kf.A * kf.P * kf.A' + kf.Q;

if isnan(z)
    kf.x = x_pred;
    kf.P = P_pred;
    innovation = 0;
    S = 1;
    K = [0; 0];
else
    innovation = z - kf.H * x_pred;
    S = kf.H * P_pred * kf.H' + kf.R;
    K = (P_pred * kf.H') / S;
    kf.x = x_pred + K * innovation;
    
    IKH = kf.I - K * kf.H;
    kf.P = IKH * P_pred * IKH' + K * kf.R * K';
end

kf.x(1) = max(0, min(1, kf.x(1)));

HI_critical = cfg.health.HI_critical;
HI_current = kf.x(1);
rate_current = kf.x(2);
sigma_rate = sqrt(kf.P(2,2));
sigma_HI = sqrt(kf.P(1,1));

sigma_rate = sqrt(kf.P(2,2));
rate_threshold = -2e-4;      % [1/hour]
HI_gate        = 0.90;       % [-] below this, degradation is clear

if HI_current < HI_gate && rate_current < rate_threshold
    % Nominal RUL (using point estimate)
    RUL_nominal = (HI_current - HI_critical) / abs(rate_current);

    % Confidence bounds via error propagation (±1σ on rate)
    rate_fast = rate_current - sigma_rate;   % faster degradation
    rate_slow = rate_current + sigma_rate;   % slower degradation

    if rate_fast < rate_threshold
        RUL_upper = (HI_current - HI_critical) / abs(rate_fast);
    else
        RUL_upper = RUL_nominal * 2;         % cap at 2× nominal
    end

    if rate_slow < rate_threshold
        RUL_lower = (HI_current - HI_critical) / abs(rate_slow);
    else
        RUL_lower = RUL_nominal / 2;         % cap at 0.5× nominal
    end
else
    % Not enough evidence for reliable RUL prediction
    RUL_nominal = NaN;
    RUL_upper   = NaN;
    RUL_lower   = NaN;
end

kf.innovation_history(end+1) = innovation;
kf.HI_history(end+1) = kf.x(1);
kf.rate_history(end+1) = kf.x(2);
kf.sigma_HI_history(end+1) = sigma_HI;
kf.sigma_rate_history(end+1) = sigma_rate;
kf.z_history(end+1) = z;
kf.t_history(end+1) = kf.t_history(end) + dt;

est.HI               = kf.x(1);
est.HI_rate          = kf.x(2);
est.sigma_HI         = sigma_HI;
est.sigma_rate       = sigma_rate;
est.z_measured       = z;
est.innovation       = innovation;
est.Kalman_gain      = K;
est.P                = kf.P;
est.RUL_nominal_hours = RUL_nominal;   
est.RUL_upper_hours   = RUL_upper;
est.RUL_lower_hours   = RUL_lower;
est.baseline_learned = kf.baseline.is_learned;

est.alert_level = classify_alert_level(est.HI, cfg);

end

%% ========================================================================
%  PREDICT-ONLY
% ========================================================================

function [kf, est] = predict_only(kf, cfg)

dt = cfg.sim.sample_interval_hours;

x_pred = kf.A * kf.x;
P_pred = kf.A * kf.P * kf.A' + kf.Q;

kf.x = x_pred;
kf.P = P_pred;

HI_critical = cfg.health.HI_critical;
HI_current = kf.x(1);
rate_current = kf.x(2);

if rate_current < -1e-6
    RUL_nominal = (HI_current - HI_critical) / abs(rate_current);
else
    RUL_nominal = Inf;
end

est.HI = kf.x(1);
est.HI_rate = kf.x(2);
est.sigma_HI = sqrt(kf.P(1,1));
est.sigma_rate = sqrt(kf.P(2,2));
est.RUL_nominal_hours = RUL_nominal;

end

%% ========================================================================
%  MEASUREMENT MODEL: FEATURES → HEALTH
% ========================================================================

function baseline = init_baseline(cfg)

baseline.is_learned = false;
baseline.n_required = 24;
baseline.samples_env_total = [];
baseline.samples_kurtosis = [];
baseline.samples_rms = [];
baseline.env_total_healthy = 0;
baseline.kurtosis_healthy = 3;
baseline.rms_healthy = 0; 

end

function [baseline, z] = compute_measurement(baseline, features, k, cfg)

env_total_now = features.env_BPFO_p + features.env_BPFI_p + ...
                features.env_BPFO_s + features.env_BPFI_s;
kurt_now = features.kurtosis;

if ~baseline.is_learned
    baseline.samples_env_total(end+1) = env_total_now;
    baseline.samples_kurtosis(end+1)  = kurt_now;
    baseline.samples_rms(end+1)       = features.rms;        
    
    z = NaN;
    
    if length(baseline.samples_env_total) >= baseline.n_required
        % Use MEDIAN for robustness against outliers during learning
        baseline.env_total_healthy = median(baseline.samples_env_total);
        baseline.kurtosis_healthy = median(baseline.samples_kurtosis);
        baseline.rms_healthy = median(baseline.samples_rms);  
        baseline.is_learned = true;
    end
    return;
end

env_ratio_dB = 10 * log10( max(env_total_now, eps) / ...
                           max(baseline.env_total_healthy, eps) );
env_ratio_dB = max(0, min(30, env_ratio_dB));
env_indicator = env_ratio_dB / 30;

kurt_excess = max(0, kurt_now - 3);
kurt_excess = min(kurt_excess, 20);
kurt_indicator = kurt_excess / 20;


% ---- Indicator 3: RMS growth ----
rms_ratio = features.rms / max(baseline.rms_healthy, eps);
rms_ratio = max(1, min(5, rms_ratio));
rms_indicator = (rms_ratio - 1) / 4;

% ---- Combine into damage proxy ----
D_proxy = 0.35 * rms_indicator + ...
          0.45 * env_indicator + ...
          0.20 * kurt_indicator;

z = max(0, min(1, 1 - D_proxy));

end

%% ========================================================================
%  RTS SMOOTHER
% ========================================================================

function sm = rts_smoother(kf_history, cfg)

n = length(kf_history.HI_history);
sm.x_smooth = zeros(2, n);
sm.P_smooth = zeros(2, 2, n);

sm.x_smooth(:, end) = kf_history.x_final;
sm.P_smooth(:, :, end) = kf_history.P_final;

for k = (n-1):-1:1
    x_pred = kf_history.A * [kf_history.HI_history(k); kf_history.rate_history(k)];
    P_pred = kf_history.A * kf_history.P_history(:, :, k) * kf_history.A' + kf_history.Q;
    
    C_k = kf_history.P_history(:, :, k) * kf_history.A' / P_pred;
    
    sm.x_smooth(:, k) = [kf_history.HI_history(k); kf_history.rate_history(k)] + ...
        C_k * (sm.x_smooth(:, k+1) - x_pred);
    
    sm.P_smooth(:, :, k) = kf_history.P_history(:, :, k) + ...
        C_k * (sm.P_smooth(:, :, k+1) - P_pred) * C_k';
end

end

%% ========================================================================
%  ALERT CLASSIFICATION
% ========================================================================

function level = classify_alert_level(HI, cfg)

persistent last_level

if isempty(last_level)
    last_level = 1;
end

% Hysteresis band: 2% of health
hysteresis = 0.02;

% Thresholds
t1 = cfg.health.HI_healthy;      
t2 = cfg.health.HI_mild;         
t3 = cfg.health.HI_moderate;     
t4 = cfg.health.HI_severe;       


if HI > t1
    raw_level = 1;
elseif HI > t2
    raw_level = 2;
elseif HI > t3
    raw_level = 3;
elseif HI > t4
    raw_level = 4;
else
    raw_level = 5;
end


if raw_level > last_level
   
    level = raw_level;
elseif raw_level < last_level
   
    switch last_level
        case 5
            if HI > t4 + hysteresis, level = 4; else, level = 5; end
        case 4
            if HI > t3 + hysteresis, level = 3; else, level = 4; end
        case 3
            if HI > t2 + hysteresis, level = 2; else, level = 3; end
        case 2
            if HI > t1 + hysteresis, level = 1; else, level = 2; end
        otherwise
            level = raw_level;
    end
else
    level = last_level;
end

last_level = level;

end