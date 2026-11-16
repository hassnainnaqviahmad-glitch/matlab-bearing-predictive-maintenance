% ========================================================================
%  File: signal_processing.m
%  Purpose: Extract health-relevant features from raw vibration signals.
% ========================================================================

function varargout = signal_processing(action, varargin)

switch lower(action)
    case 'filter'
        varargout{1} = bandpass_filter(varargin{:});
    case 'spectrum'
        [varargout{1}, varargout{2}] = compute_spectrum(varargin{:});
    case 'envelope'
        [varargout{1}, varargout{2}] = compute_envelope_spectrum(varargin{:});
    case 'time_features'
        varargout{1} = extract_time_features(varargin{:});
    case 'freq_features'
        varargout{1} = extract_freq_features(varargin{:});
    case 'extract_features'
        varargout{1} = extract_all_features(varargin{:});
    otherwise
        error('signal_processing: unknown action "%s"', action);
end

end

%% ========================================================================
%  MAIN ENTRY POINT: FULL FEATURE VECTOR
% ========================================================================

function features = extract_all_features(x, cfg)

if ~isvector(x)
    error('signal_processing: x must be a vector');
end
x = x(:);

x_filt = bandpass_filter(x, cfg);

features = extract_time_features(x_filt);

ff = extract_freq_features(x_filt, cfg);
fn = fieldnames(ff);
for i = 1:numel(fn)
    features.(fn{i}) = ff.(fn{i});
end

env_feat = extract_envelope_features(x_filt, cfg);
fn = fieldnames(env_feat);
for i = 1:numel(fn)
    features.(fn{i}) = env_feat.(fn{i});
end

features.feature_vector = [
    features.rms / 0.1;
    features.crest_factor / 3;
    features.kurtosis / 3;
    features.ratio_BPFO_p / 0.1;
    features.ratio_BPFI_p / 0.1;
    features.ratio_BPFO_s / 0.1;
    features.env_BPFO_p / 0.01;
    features.env_BPFI_p / 0.01;
    features.env_BPFO_s / 0.01;
];

end

%% ========================================================================
%  BANDPASS FILTERING
% ========================================================================

function x_filt = bandpass_filter(x, cfg)

Wn = [cfg.sensor.bandpass_low, cfg.sensor.bandpass_high] / (cfg.sensor.Fs / 2);
[b, a] = butter(4, Wn, 'bandpass');

x_filt = filtfilt(b, a, x);

end

%% ========================================================================
%  TIME-DOMAIN FEATURES
% ========================================================================

function tf = extract_time_features(x)

x = x(:);

tf.rms = sqrt(mean(x.^2));
tf.peak = max(abs(x));
tf.crest_factor = tf.peak / max(tf.rms, eps);

mu = mean(x);
sigma = std(x);
tf.kurtosis = mean(((x - mu) / max(sigma, eps)).^4);
tf.skewness = mean(((x - mu) / max(sigma, eps)).^3);
tf.variance = tf.rms^2;

end

%% ========================================================================
%  FREQUENCY-DOMAIN FEATURES
% ========================================================================

function ff = extract_freq_features(x, cfg)

x = x(:);
Fs = cfg.sensor.Fs;

window   = min(2048, length(x));
noverlap = round(window / 2);
nfft     = max(4096, window);
[Pxx, f] = pwelch(x, hann(window), noverlap, nfft, Fs);

band_width_frac = 0.02;

ff.energy_1x = band_energy(Pxx, f, cfg.machine.rot_freq_Hz, band_width_frac);

ff.energy_BPFO_p = band_energy(Pxx, f, cfg.fault_freq.primary.BPFO, band_width_frac);
ff.energy_BPFI_p = band_energy(Pxx, f, cfg.fault_freq.primary.BPFI, band_width_frac);

ff.energy_BPFO_s = band_energy(Pxx, f, cfg.fault_freq.secondary.BPFO, band_width_frac);
ff.energy_BPFI_s = band_energy(Pxx, f, cfg.fault_freq.secondary.BPFI, band_width_frac);

ff.ratio_BPFO_p = ff.energy_BPFO_p / max(ff.energy_1x, eps);
ff.ratio_BPFI_p = ff.energy_BPFI_p / max(ff.energy_1x, eps);
ff.ratio_BPFO_s = ff.energy_BPFO_s / max(ff.energy_1x, eps);
ff.ratio_BPFI_s = ff.energy_BPFI_s / max(ff.energy_1x, eps);

ff.f = f;
ff.Pxx = Pxx;

end

%% ========================================================================
%  ENVELOPE ANALYSIS
% ========================================================================

function env_feat = extract_envelope_features(x, cfg)

x = x(:);
Fs = cfg.sensor.Fs;

resonance_low  = 500;
resonance_high = 2000;

Wn = [resonance_low, resonance_high] / (Fs / 2);
[b, a] = butter(4, Wn, 'bandpass');
x_resonance = filtfilt(b, a, x);

x_env = abs(hilbert(x_resonance));
x_env = x_env - mean(x_env);

window = min(2048, length(x_env));
noverlap = round(window / 2);
nfft = max(4096, window);
[Pxx_env, f_env] = pwelch(x_env, hann(window), noverlap, nfft, Fs);

band_width_frac = 0.02;

env_feat.env_BPFO_p = band_energy(Pxx_env, f_env, ...
    cfg.fault_freq.primary.BPFO, band_width_frac);
env_feat.env_BPFI_p = band_energy(Pxx_env, f_env, ...
    cfg.fault_freq.primary.BPFI, band_width_frac);
env_feat.env_BPFO_s = band_energy(Pxx_env, f_env, ...
    cfg.fault_freq.secondary.BPFO, band_width_frac);
env_feat.env_BPFI_s = band_energy(Pxx_env, f_env, ...
    cfg.fault_freq.secondary.BPFI, band_width_frac);

env_feat.f_env = f_env;
env_feat.Pxx_env = Pxx_env;
env_feat.x_env = x_env;

end

%% ========================================================================
%  HELPER: BAND ENERGY CALCULATION
% ========================================================================

function E = band_energy(Pxx, f, f_center, width_frac)

f_low  = f_center * (1 - width_frac);
f_high = f_center * (1 + width_frac);

idx = (f >= f_low) & (f <= f_high);

if ~any(idx)
    E = 0;
    return;
end

E = trapz(f(idx), Pxx(idx));

end

%% ========================================================================
%  DIAGNOSTICS & ACCESSORS
% ========================================================================

function [f, Pxx] = compute_spectrum(x, cfg)

x = x(:);
window = min(2048, length(x));
noverlap = round(window / 2);
nfft = max(4096, window);
[Pxx, f] = pwelch(x, hann(window), noverlap, nfft, cfg.sensor.Fs);

end

function [f, Pxx] = compute_envelope_spectrum(x, cfg)

feat = extract_envelope_features(x, cfg);
f = feat.f_env;
Pxx = feat.Pxx_env;

end