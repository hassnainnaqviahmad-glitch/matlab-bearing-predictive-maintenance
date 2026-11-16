function varargout = visualize_results(action, varargin)

switch lower(action)
    case 'dashboard'
        varargout{1} = plot_dashboard(varargin{:});
    case 'health'
        varargout{1} = plot_health(varargin{:});
    case 'rul'
        varargout{1} = plot_rul(varargin{:});
    case 'features'
        varargout{1} = plot_features(varargin{:});
    case 'comparative'
        varargout{1} = plot_comparative(varargin{:});
    case 'timeline'
        varargout{1} = plot_alert_timeline(varargin{:});
    case 'export_all'
        varargout{1} = export_all(varargin{:});
    otherwise
        error('visualize_results: unknown action "%s"', action);
end

end

%% ========================================================================
%  THEME DEFINITION — MINIMAL / NOTION-INSPIRED
% ========================================================================

function T = theme()
%THEME Clean, paper-like palette. Minimal saturation, restrained color.

% ---- Backgrounds ----
T.bg       = [1.000 1.000 1.000];       % pure white canvas
T.bg_panel = [0.985 0.985 0.980];       % very faint off-white for panels

% ---- Text ----
T.fg       = [0.110 0.110 0.110];       % near-black, Notion-style
T.fg_dim   = [0.420 0.420 0.420];       % medium gray for labels
T.fg_mute  = [0.680 0.680 0.680];       % light gray for tertiary

% ---- Axis / Grid ----
T.axis     = [0.780 0.780 0.780];       % subtle axis lines
T.grid     = [0.900 0.900 0.900];       % very light gridlines

% ---- Data Lines ----
T.accent   = [0.165 0.420 0.780];       % muted blue — primary data
T.accent_d = [0.110 0.310 0.610];       % darker blue — hover / emphasis
T.truth    = [0.620 0.620 0.620];       % gray — reference (ground truth)
T.estimate = [0.165 0.420 0.780];       % blue — observer estimate
T.band     = [0.165 0.420 0.780];       % blue — confidence band (low α)

% ---- Status Colors (muted, professional) ----
T.good     = [0.180 0.630 0.360];       % green
T.plan     = [0.290 0.540 0.840];       % blue
T.schedule = [0.920 0.680 0.170];       % amber
T.urgent   = [0.900 0.440 0.150];       % orange
T.crit     = [0.820 0.220 0.200];       % red

% ---- Typography ----
T.font     = 'Helvetica';
T.fs_title = 10.5;
T.fs_label = 8.5;
T.fs_tick  = 8;
T.fs_annot = 8;

% ---- Line widths ----
T.lw_main  = 1.4;
T.lw_thin  = 0.6;
T.lw_grid  = 0.4;

end

%% ========================================================================
%  THEME APPLICATION
% ========================================================================

function apply_axes_theme(ax, T)

set(ax, ...
    'Color',          T.bg_panel, ...
    'XColor',         T.axis, ...
    'YColor',         T.axis, ...
    'GridColor',      T.grid, ...
    'GridAlpha',      1.0, ...
    'FontName',       T.font, ...
    'FontSize',       T.fs_tick, ...
    'TickDir',        'out', ...
    'TickLength',     [0.006 0.006], ...
    'XGrid',          'off', ...
    'YGrid',          'off', ...
    'Box',            'off', ...
    'LineWidth',      0.5);

% Keep only the left and bottom spines visible (Notion-style)
ax.XAxis.Color = T.axis;
ax.YAxis.Color = T.axis;

end

function apply_figure_theme(fig, T)

set(fig, 'Color', T.bg, 'InvertHardcopy', 'off');

end

%% ========================================================================
%  DASHBOARD
% ========================================================================

function fig = plot_dashboard(data, cfg, save_path)

if nargin < 3, save_path = ''; end

T = theme();

fig = figure('Units', 'pixels', 'Position', [80 60 1280 780], ...
             'Name', 'SHM Dashboard', 'NumberTitle', 'off');
set(fig, 'ToolBar', 'none', 'MenuBar', 'none');
apply_figure_theme(fig, T);

left   = 0.075;
right  = 0.035;
top    = 0.90;
bottom = 0.08;
gap    = 0.075;
height = (top - bottom - 2*gap) / 3;

ax1 = axes('Position', [left, bottom + 2*(height+gap), 1-left-right, height]);
ax2 = axes('Position', [left, bottom + 1*(height+gap), 1-left-right, height]);
ax3 = axes('Position', [left, bottom,                  1-left-right, height]);

plot_health_content(ax1, data, cfg, T);
plot_rul_content(ax2, data, T);
plot_timeline_content(ax3, data, T);

if ~isempty(save_path)
    exportgraphics(fig, save_path, 'Resolution', 200, 'BackgroundColor', T.bg);
end

end

%% ========================================================================
%  HEALTH PANEL
% ========================================================================

function plot_health_content(ax, data, cfg, T)

t    = data.t_hours(:);
HI_t = data.HI_true(:);
HI_e = data.HI_est(:);
sig  = data.sigma_HI(:);

upper = min(1, HI_e + 2*sig);
lower = max(0, HI_e - 2*sig);

hold(ax, 'on');

% Confidence band — very faint
fill(ax, [t; flipud(t)], [upper; flipud(lower)], T.band, ...
    'FaceAlpha', 0.08, 'EdgeColor', 'none', 'HandleVisibility', 'off');

% Threshold lines — dotted, very light
yline(ax, cfg.health.HI_mild,     ':', 'Color', T.fg_mute, 'LineWidth', T.lw_thin, 'HandleVisibility', 'off');
yline(ax, cfg.health.HI_moderate, ':', 'Color', T.fg_mute, 'LineWidth', T.lw_thin, 'HandleVisibility', 'off');
yline(ax, cfg.health.HI_severe,   ':', 'Color', T.fg_mute, 'LineWidth', T.lw_thin, 'HandleVisibility', 'off');
yline(ax, cfg.health.HI_critical, ':', 'Color', T.crit,    'LineWidth', T.lw_thin, 'HandleVisibility', 'off');

% Right-side threshold annotations
xlim_end = max(t);
text(ax, xlim_end, cfg.health.HI_mild,     '  Plan',     ...
    'Color', T.fg_mute, 'FontSize', T.fs_annot, 'FontName', T.font, ...
    'VerticalAlignment', 'middle', 'HorizontalAlignment', 'left');
text(ax, xlim_end, cfg.health.HI_moderate, '  Schedule', ...
    'Color', T.fg_mute, 'FontSize', T.fs_annot, 'FontName', T.font, ...
    'VerticalAlignment', 'middle', 'HorizontalAlignment', 'left');
text(ax, xlim_end, cfg.health.HI_severe,   '  Urgent',   ...
    'Color', T.fg_mute, 'FontSize', T.fs_annot, 'FontName', T.font, ...
    'VerticalAlignment', 'middle', 'HorizontalAlignment', 'left');

% Ground truth — thin gray reference
plot(ax, t, HI_t, '-', 'Color', T.truth, 'LineWidth', 0.8, ...
    'HandleVisibility', 'off');

% Observer estimate — the primary data
plot(ax, t, HI_e, '-', 'Color', T.estimate, 'LineWidth', T.lw_main);

hold(ax, 'off');
apply_axes_theme(ax, T);
xlim(ax, [0, xlim_end]);
ylim(ax, [0, 1.05]);

title(ax, 'HEALTH INDEX', ...
    'Color', T.fg, 'FontName', T.font, 'FontSize', T.fs_title, ...
    'FontWeight', 'bold', 'HorizontalAlignment', 'left', ...
    'Units', 'normalized', 'Position', [0, 1.02, 0]);

xlabel(ax, 'Time [hours]', 'Color', T.fg_dim, ...
    'FontName', T.font, 'FontSize', T.fs_label);
ylabel(ax, 'HI', 'Color', T.fg_dim, ...
    'FontName', T.font, 'FontSize', T.fs_label);

% Minimal legend
legend(ax, {'Observer estimate'}, ...
    'TextColor', T.fg_dim, 'Color', 'none', 'Box', 'off', ...
    'FontName', T.font, 'FontSize', T.fs_annot, ...
    'Location', 'southwest');

end

%% ========================================================================
%  RUL PANEL
% ========================================================================

function plot_rul_content(ax, data, T)

t   = data.t_hours(:);
rul = data.RUL(:);
valid = isfinite(rul);

hold(ax, 'on');

if any(valid)
    t_start = t(find(valid, 1, 'first'));

    % RUL curve
    plot(ax, t, rul, '-', 'Color', T.accent, 'LineWidth', T.lw_main);

    % Subtle fill
    t_v = t(valid);
    r_v = rul(valid);
    fill(ax, [t_v; flipud(t_v)], [r_v; zeros(size(r_v))], ...
        T.accent, 'FaceAlpha', 0.07, 'EdgeColor', 'none', ...
        'HandleVisibility', 'off');

    % Marker for prediction start
    plot(ax, t_start, rul(find(valid, 1, 'first')), 'o', ...
        'MarkerSize', 4, 'MarkerFaceColor', T.accent, ...
        'MarkerEdgeColor', 'none', 'HandleVisibility', 'off');

    % Annotation
    text(ax, t_start + 50, max(r_v) * 0.6, ...
        sprintf('Prediction begins  \\rightarrow'), ...
        'Color', T.fg_dim, 'FontName', T.font, 'FontSize', T.fs_annot, ...
        'VerticalAlignment', 'middle', 'HorizontalAlignment', 'left');
else
    text(ax, 0.5, 0.5, 'RUL not yet predictable', ...
        'Units', 'normalized', 'HorizontalAlignment', 'center', ...
        'Color', T.fg_dim, 'FontName', T.font, 'FontSize', T.fs_label);
end

hold(ax, 'off');
apply_axes_theme(ax, T);

if any(valid)
    t_start = t(find(valid, 1, 'first'));
    t_end   = t(find(valid, 1, 'last'));
    padding = max(50, 0.05 * (t_end - t_start));
    xlim(ax, [t_start - padding, t_end + padding]);
    ylim(ax, [0, max(rul(valid)) * 1.15]);
else
    xlim(ax, [0, max(t)]);
end

title(ax, 'REMAINING USEFUL LIFE', ...
    'Color', T.fg, 'FontName', T.font, 'FontSize', T.fs_title, ...
    'FontWeight', 'bold', 'HorizontalAlignment', 'left', ...
    'Units', 'normalized', 'Position', [0, 1.02, 0]);

xlabel(ax, 'Time [hours]', 'Color', T.fg_dim, ...
    'FontName', T.font, 'FontSize', T.fs_label);
ylabel(ax, 'RUL [hours]', 'Color', T.fg_dim, ...
    'FontName', T.font, 'FontSize', T.fs_label);

end

%% ========================================================================
%  TIMELINE PANEL
% ========================================================================

function plot_timeline_content(ax, data, T)

t      = data.t_hours(:);
alerts = data.alert_level(:);

colors = {T.good, T.plan, T.schedule, T.urgent, T.crit};
labels = {'Normal', 'Plan', 'Schedule', 'Urgent', 'Emergency'};

hold(ax, 'on');

for L = 1:5
    is_L = (alerts == L);
    if ~any(is_L), continue; end

    d = diff([0; is_L; 0]);
    starts = find(d ==  1);
    ends   = find(d == -1) - 1;

    for k = 1:length(starts)
        t1 = t(starts(k));
        t2 = t(ends(k));
        patch(ax, [t1 t2 t2 t1], [L-0.32 L-0.32 L+0.32 L+0.32], ...
            colors{L}, 'EdgeColor', 'none');
    end
end

hold(ax, 'off');
apply_axes_theme(ax, T);

xlim(ax, [0, max(t)]);
ylim(ax, [0.4, 5.6]);
yticks(ax, 1:5);
yticklabels(ax, labels);

title(ax, 'MAINTENANCE STATUS', ...
    'Color', T.fg, 'FontName', T.font, 'FontSize', T.fs_title, ...
    'FontWeight', 'bold', 'HorizontalAlignment', 'left', ...
    'Units', 'normalized', 'Position', [0, 1.02, 0]);

xlabel(ax, 'Time [hours]', 'Color', T.fg_dim, ...
    'FontName', T.font, 'FontSize', T.fs_label);

end

%% ========================================================================
%  STANDALONE FIGURES
% ========================================================================

function fig = plot_health(data, cfg, save_path)

if nargin < 3, save_path = ''; end
T = theme();

fig = figure('Units', 'pixels', 'Position', [100 100 1000 420], ...
             'Name', 'Health Estimation', 'NumberTitle', 'off');
set(fig, 'ToolBar', 'none', 'MenuBar', 'none');
apply_figure_theme(fig, T);

ax = axes('Position', [0.10 0.16 0.82 0.72]);
plot_health_content(ax, data, cfg, T);

if ~isempty(save_path)
    exportgraphics(fig, save_path, 'Resolution', 200, 'BackgroundColor', T.bg);
end

end

function fig = plot_rul(data, cfg, save_path)

if nargin < 3, save_path = ''; end
T = theme();

fig = figure('Units', 'pixels', 'Position', [100 100 1000 380], ...
             'Name', 'RUL Prediction', 'NumberTitle', 'off');
set(fig, 'ToolBar', 'none', 'MenuBar', 'none');
apply_figure_theme(fig, T);

ax = axes('Position', [0.10 0.18 0.82 0.70]);
plot_rul_content(ax, data, T);

if ~isempty(save_path)
    exportgraphics(fig, save_path, 'Resolution', 200, 'BackgroundColor', T.bg);
end

end

function fig = plot_alert_timeline(data, cfg, save_path)

if nargin < 3, save_path = ''; end
T = theme();

fig = figure('Units', 'pixels', 'Position', [100 100 1000 280], ...
             'Name', 'Alert Timeline', 'NumberTitle', 'off');
set(fig, 'ToolBar', 'none', 'MenuBar', 'none');
apply_figure_theme(fig, T);

ax = axes('Position', [0.10 0.20 0.82 0.68]);
plot_timeline_content(ax, data, T);

if ~isempty(save_path)
    exportgraphics(fig, save_path, 'Resolution', 200, 'BackgroundColor', T.bg);
end

end

%% ========================================================================
%  FEATURES FIGURE
% ========================================================================

function fig = plot_features(data, cfg, save_path)

if nargin < 3, save_path = ''; end
T = theme();

fig = figure('Units', 'pixels', 'Position', [80 60 1280 720], ...
             'Name', 'Feature Evolution', 'NumberTitle', 'off');
set(fig, 'ToolBar', 'none', 'MenuBar', 'none');
apply_figure_theme(fig, T);

left   = 0.075;
right  = 0.035;
top    = 0.90;
bottom = 0.09;
gap    = 0.085;
height = (top - bottom - 2*gap) / 3;

ax1 = axes('Position', [left, bottom + 2*(height+gap), 1-left-right, height]);
ax2 = axes('Position', [left, bottom + 1*(height+gap), 1-left-right, height]);
ax3 = axes('Position', [left, bottom,                  1-left-right, height]);

plot_feature_panel(ax1, data.t_hours, data.rms_history, ...
    'RMS ACCELERATION', 'RMS [m/s²]', T, T.accent);

plot_feature_panel(ax2, data.t_hours, data.env_history, ...
    'ENVELOPE ENERGY', 'Energy [a.u.]', T, T.schedule);

plot_feature_panel(ax3, data.t_hours, data.kurt_history, ...
    'KURTOSIS', 'κ', T, T.urgent);

if ~isempty(save_path)
    exportgraphics(fig, save_path, 'Resolution', 200, 'BackgroundColor', T.bg);
end

end

function plot_feature_panel(ax, t, y, title_str, ylabel_str, T, color)

hold(ax, 'on');
plot(ax, t(:), y(:), '-', 'Color', color, 'LineWidth', T.lw_main);
hold(ax, 'off');

apply_axes_theme(ax, T);
xlim(ax, [0, max(t(:))]);

title(ax, title_str, ...
    'Color', T.fg, 'FontName', T.font, 'FontSize', T.fs_title, ...
    'FontWeight', 'bold', 'HorizontalAlignment', 'left', ...
    'Units', 'normalized', 'Position', [0, 1.02, 0]);

xlabel(ax, 'Time [hours]', 'Color', T.fg_dim, 'FontName', T.font, 'FontSize', T.fs_label);
ylabel(ax, ylabel_str, 'Color', T.fg_dim, 'FontName', T.font, 'FontSize', T.fs_label);

end

%% ========================================================================
%  COMPARATIVE STUDY
% ========================================================================

function fig = plot_comparative(data_heavy, data_light, cfg, save_path)

if nargin < 4, save_path = ''; end
T = theme();

fig = figure('Units', 'pixels', 'Position', [80 60 1200 500], ...
             'Name', 'Load Comparison', 'NumberTitle', 'off');
set(fig, 'ToolBar', 'none', 'MenuBar', 'none');
apply_figure_theme(fig, T);

ax = axes('Position', [0.09 0.15 0.86 0.72]);
hold(ax, 'on');

plot_health_band(ax, data_heavy, T.accent, T);
plot(ax, data_heavy.t_hours, data_heavy.HI_est, '-', ...
    'Color', T.accent, 'LineWidth', T.lw_main);

plot_health_band(ax, data_light, T.good, T);
plot(ax, data_light.t_hours, data_light.HI_est, '-', ...
    'Color', T.good, 'LineWidth', T.lw_main);

yline(ax, cfg.health.HI_critical, ':', 'Color', T.crit, ...
    'LineWidth', T.lw_thin, 'HandleVisibility', 'off');

hold(ax, 'off');
apply_axes_theme(ax, T);

xlim(ax, [0, max([data_heavy.t_hours, data_light.t_hours])]);
ylim(ax, [0, 1.05]);

title(ax, 'LOAD-DEPENDENT DEGRADATION', ...
    'Color', T.fg, 'FontName', T.font, 'FontSize', T.fs_title+1, ...
    'FontWeight', 'bold', 'HorizontalAlignment', 'left', ...
    'Units', 'normalized', 'Position', [0, 1.03, 0]);

xlabel(ax, 'Time [hours]', 'Color', T.fg_dim, 'FontName', T.font, 'FontSize', T.fs_label);
ylabel(ax, 'Health Index', 'Color', T.fg_dim, 'FontName', T.font, 'FontSize', T.fs_label);

t_heavy_fail = data_heavy.t_hours(find(data_heavy.HI_est <= cfg.health.HI_critical, 1));
t_light_fail = data_light.t_hours(find(data_light.HI_est <= cfg.health.HI_critical, 1));

if ~isempty(t_heavy_fail)
    xline(ax, t_heavy_fail, '--', 'Color', T.accent, 'LineWidth', T.lw_thin, ...
        'HandleVisibility', 'off', 'Alpha', 0.35);
    text(ax, t_heavy_fail, 1.02, sprintf('  Heavy: %.0f h', t_heavy_fail), ...
        'Color', T.accent, 'FontName', T.font, 'FontSize', T.fs_annot, ...
        'VerticalAlignment', 'top');
end
if ~isempty(t_light_fail)
    xline(ax, t_light_fail, '--', 'Color', T.good, 'LineWidth', T.lw_thin, ...
        'HandleVisibility', 'off', 'Alpha', 0.35);
    text(ax, t_light_fail, 1.02, sprintf('  Light: %.0f h', t_light_fail), ...
        'Color', T.good, 'FontName', T.font, 'FontSize', T.fs_annot, ...
        'VerticalAlignment', 'top');
end

legend(ax, {'Heavy load (100%)', 'Light load (40%)'}, ...
    'TextColor', T.fg_dim, 'Color', 'none', 'Box', 'off', ...
    'FontName', T.font, 'FontSize', T.fs_label, ...
    'Location', 'southwest');

if ~isempty(save_path)
    exportgraphics(fig, save_path, 'Resolution', 200, 'BackgroundColor', T.bg);
end

end

function plot_health_band(ax, data, color, T)
t = data.t_hours(:);
HI = data.HI_est(:);
sig = data.sigma_HI(:);
upper = min(1, HI + 2*sig);
lower = max(0, HI - 2*sig);
fill(ax, [t; flipud(t)], [upper; flipud(lower)], color, ...
    'FaceAlpha', 0.06, 'EdgeColor', 'none', 'HandleVisibility', 'off');
end

%% ========================================================================
%  EXPORT ALL
% ========================================================================

function paths = export_all(data, cfg, out_dir)

if nargin < 3 || isempty(out_dir)
    out_dir = 'Results';
end
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

paths = struct();

paths.dashboard = fullfile(out_dir, '01_dashboard.png');
paths.health    = fullfile(out_dir, '02_health.png');
paths.rul       = fullfile(out_dir, '03_rul.png');
paths.timeline  = fullfile(out_dir, '04_timeline.png');

fprintf('\n[Rendering] Dashboard... '); plot_dashboard(data, cfg, paths.dashboard);       fprintf('done\n');
fprintf('[Rendering] Health...    '); plot_health(data, cfg, paths.health);               fprintf('done\n');
fprintf('[Rendering] RUL...       '); plot_rul(data, cfg, paths.rul);                    fprintf('done\n');
fprintf('[Rendering] Timeline...  '); plot_alert_timeline(data, cfg, paths.timeline);    fprintf('done\n');

if isfield(data, 'rms_history') && ~isempty(data.rms_history)
    paths.features = fullfile(out_dir, '05_features.png');
    fprintf('[Rendering] Features...  ');
    plot_features(data, cfg, paths.features);
    fprintf('done\n');
else
    paths.features = '';
end

fprintf('\nAll figures saved to: %s\n\n', out_dir);

end