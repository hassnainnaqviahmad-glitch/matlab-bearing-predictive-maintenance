% ========================================================================
%  File: config_parameters.m
%  Purpose: Central configuration for the Structural Health Monitoring
%           and Condition-Based Maintenance Framework for Industrial
%           Rotating Machinery.
% ========================================================================

function cfg = config_parameters()

%% SECTION 1: OPERATIONAL CONTEXT
cfg.machine.name = 'Industrial Screw Compressor';
cfg.machine.motor_power_kW = 75;
cfg.machine.motor_power_hp = 100.6;
cfg.machine.motor_rpm = 1500;
cfg.machine.motor_rpm_60Hz = 1800;
cfg.machine.rot_freq_Hz = cfg.machine.motor_rpm / 60;   

cfg.machine.max_pressure_bar = 10;
cfg.machine.ref_pressure_bar = 9.5;
cfg.machine.oil_setpoint_C = 40;
cfg.machine.air_outlet_C = 27;

% Load Profile Configuration
cfg.load_profile.mode = 'comparative';  % 'constant' | 'random' | 'comparative'
cfg.load_profile.constant_load_fraction = 1.0;
cfg.load_profile.random_min = 0.3;       
cfg.load_profile.random_max = 1.0;       
cfg.load_profile.random_change_interval_hours = 2;

cfg.load_profile.comp_A_load_fraction = 1.0;    
cfg.load_profile.comp_B_load_fraction = 0.4;    

%% SECTION 2: BEARING GEOMETRY, LOAD RATINGS, AND MATERIAL PROPERTIES
% Primary Bearing: Cylindrical Roller Bearing
cfg.bearing_primary.model = 'Cylindrical Roller Bearing';
cfg.bearing_primary.type = 'cylindrical_roller';
cfg.bearing_primary.bore_d = 40e-3;          
cfg.bearing_primary.outer_D = 80e-3;         
cfg.bearing_primary.width_B = 18e-3;         
cfg.bearing_primary.roller_diameter_d = 9.5e-3;   
cfg.bearing_primary.pitch_diameter_Pd = 59.5e-3;  
cfg.bearing_primary.num_rollers_N = 12;            
cfg.bearing_primary.contact_angle_beta = 0;       
cfg.bearing_primary.C_dynamic_kN = 62;
cfg.bearing_primary.C0_static_kN = 53;
cfg.bearing_primary.Pu_fatigue_kN = 6.7;
cfg.bearing_primary.ref_speed_rpm = 9500;
cfg.bearing_primary.limit_speed_rpm = 11000;

% Secondary Bearing: Deep Groove Ball Bearing
cfg.bearing_secondary.model = 'Deep Groove Ball Bearing';
cfg.bearing_secondary.type = 'deep_groove_ball';
cfg.bearing_secondary.bore_d = 40e-3;
cfg.bearing_secondary.outer_D = 80e-3;
cfg.bearing_secondary.width_B = 18e-3;
cfg.bearing_secondary.ball_diameter_d = 12.70e-3;   
cfg.bearing_secondary.pitch_diameter_Pd = 60.0e-3;  
cfg.bearing_secondary.num_balls_Z = 9;
cfg.bearing_secondary.contact_angle_beta = 0;       
cfg.bearing_secondary.C_dynamic_kN = 32.5;
cfg.bearing_secondary.C0_static_kN = 19;
cfg.bearing_secondary.ref_speed_rpm = 18000;
cfg.bearing_secondary.limit_speed_rpm = 11000;
cfg.bearing_secondary.clearance = 'C3';
cfg.num_secondary_bearings = 6;

% Material Properties (Bearing Steel AISI 52100)
cfg.material.E_GPa = 210;                    
cfg.material.nu = 0.30;                      
cfg.material.sigma_fatigue_MPa = 1200;       
cfg.material.K_IC_MPa_m05 = 20;              
cfg.material.Paris_C = 1e-11;                
cfg.material.Paris_m = 3.0;                  

%% SECTION 3: FATIGUE DAMAGE EVOLUTION MODEL (PHASE 1)
cfg.fatigue.p_roller = 10/3;                  
cfg.fatigue.p_ball = 3;                      
cfg.fatigue.P_ref_kN = 12;                    
cfg.fatigue.L10_hours_at_ref = 8000;          

cfg.damage.D_onset = 0.3;                    
cfg.damage.D_failure = 1.0;                  
cfg.damage.D_initial = 0;                    

%% SECTION 4: CRACK PROPAGATION MODEL (PHASE 2)
cfg.crack.initial_length_m = 1e-5;            
cfg.crack.critical_length_m = 5e-3;          
cfg.crack.DeltaK_ref_MPa_m05 = 10;            
% Recalibrated for 1500 rpm (4-pole motor):
% Cycles/hour halved → C doubled to maintain ~5000 h Phase 2 duration
cfg.crack.Paris_C_calibrated = 4.28e-17;     

%% SECTION 5: DAMAGE-TO-VIBRATION COUPLING MODEL
cfg.vibration.A_healthy_1x_g = 0.3;          
cfg.vibration.A_healthy_noise_g = 0.05;      

cfg.vibration.k_defect_primary = 25.0;       
cfg.vibration.gamma_defect_primary = 1.5;    

cfg.vibration.k_defect_secondary = 20.0;     
cfg.vibration.gamma_defect_secondary = 1.5;  

cfg.vibration.k_noise = 5.0;                       

cfg.stiffness.alpha_K = 0.95;                
cfg.stiffness.alpha_C = 2.0;                 

cfg.bearing_primary.K_healthy_N_per_m = 3.5e8;
cfg.bearing_secondary.K_healthy_N_per_m = 2.0e8;

cfg.bearing_primary.psi_loss = 0.01;
cfg.bearing_secondary.psi_loss = 0.005;

cfg.bearing_primary.C_healthy_Ns_per_m = ...
    cfg.bearing_primary.psi_loss * cfg.bearing_primary.K_healthy_N_per_m / ...
    (2 * pi * cfg.machine.rot_freq_Hz);

cfg.bearing_secondary.C_healthy_Ns_per_m = ...
    cfg.bearing_secondary.psi_loss * cfg.bearing_secondary.K_healthy_N_per_m / ...
    (2 * pi * cfg.machine.rot_freq_Hz);


% Resonance frequency
cfg.resonance.freq_Hz = 1500;

% Baseline resonance amplitude 
cfg.resonance.A_healthy_g = 0.02;

% Amplification factor 
cfg.resonance.k_defect = 40.0;
cfg.resonance.gamma_defect = 1.5;            % Nonlinearity exponent

% AM modulation depth 
cfg.resonance.modulation_depth = 0.8;

%% SECTION 6: BEARING FAULT FREQUENCIES (Theoretical)
fr = cfg.machine.rot_freq_Hz;

% Primary Bearing Fault Frequencies
N_p = cfg.bearing_primary.num_rollers_N;
d_p = cfg.bearing_primary.roller_diameter_d;
Pd_p = cfg.bearing_primary.pitch_diameter_Pd;
beta_p = cfg.bearing_primary.contact_angle_beta;

cfg.fault_freq.primary.BPFO = (N_p / 2) * fr * (1 - (d_p/Pd_p)*cos(beta_p));
cfg.fault_freq.primary.BPFI = (N_p / 2) * fr * (1 + (d_p/Pd_p)*cos(beta_p));
cfg.fault_freq.primary.BSF  = (Pd_p/(2*d_p)) * fr * (1 - ((d_p/Pd_p)*cos(beta_p))^2);
cfg.fault_freq.primary.FTF  = (fr/2) * (1 - (d_p/Pd_p)*cos(beta_p));

% Secondary Bearing Fault Frequencies
N_s = cfg.bearing_secondary.num_balls_Z;
d_s = cfg.bearing_secondary.ball_diameter_d;
Pd_s = cfg.bearing_secondary.pitch_diameter_Pd;
beta_s = cfg.bearing_secondary.contact_angle_beta;

cfg.fault_freq.secondary.BPFO = (N_s/2) * fr * (1 - (d_s/Pd_s)*cos(beta_s));
cfg.fault_freq.secondary.BPFI = (N_s/2) * fr * (1 + (d_s/Pd_s)*cos(beta_s));
cfg.fault_freq.secondary.BSF  = (Pd_s/(2*d_s)) * fr * (1 - ((d_s/Pd_s)*cos(beta_s))^2);
cfg.fault_freq.secondary.FTF  = (fr/2) * (1 - (d_s/Pd_s)*cos(beta_s));

%% SECTION 7: SENSOR & SIGNAL ACQUISITION PARAMETERS
cfg.sensor.Fs = 10000;                        
cfg.sensor.Ts = 1 / cfg.sensor.Fs;            
cfg.sensor.noise_std = 0.15;                  
cfg.sensor.saturation_max = 50;               
cfg.sensor.saturation_min = -50;              

cfg.sensor.bandpass_low = 10;                  
cfg.sensor.bandpass_high = 2000;               

cfg.sensor.window_seconds = 1;                
cfg.sensor.window_samples = cfg.sensor.window_seconds * cfg.sensor.Fs;

%% SECTION 8: KALMAN FILTER PARAMETERS
cfg.kalman.Q = diag([1e-4, 1e-10]);
cfg.kalman.R = cfg.sensor.noise_std^2;
cfg.kalman.x0 = [1.0; 0];                    
cfg.kalman.P0 = diag([1e-2, 1e-6]);

%% SECTION 9: HEALTH INDEX & FAULT DETECTION THRESHOLDS
cfg.health.HI_healthy = 0.90;                
cfg.health.HI_mild = 0.70;                   
cfg.health.HI_moderate = 0.50;               
cfg.health.HI_severe = 0.30;                 
cfg.health.HI_critical = 0.10;               

cfg.alerts.LEVEL_1 = cfg.health.HI_healthy;   
cfg.alerts.LEVEL_2 = cfg.health.HI_mild;      
cfg.alerts.LEVEL_3 = cfg.health.HI_moderate;  
cfg.alerts.LEVEL_4 = cfg.health.HI_severe;    
cfg.alerts.LEVEL_5 = cfg.health.HI_critical;  

%% SECTION 10: SIMULATION TIME SETTINGS
cfg.sim.total_hours = 50000;                 
cfg.sim.sample_interval_hours = 1;            
cfg.sim.num_steps = cfg.sim.total_hours / cfg.sim.sample_interval_hours;

cfg.sim.stop_on_failure = true;                
cfg.sim.stop_on_critical_health = false;      

%% SECTION 11: VISUALIZATION & OUTPUT SETTINGS
cfg.viz.fig_width = 1400;
cfg.viz.fig_height = 900;
cfg.viz.dpi = 150;
cfg.viz.font_name = 'Arial';
cfg.viz.font_size = 10;

cfg.viz.color_normal   = [0.2, 0.7, 0.2];    
cfg.viz.color_warning  = [1.0, 0.8, 0.0];    
cfg.viz.color_critical = [0.9, 0.1, 0.1];     
cfg.viz.color_healthy  = [0.0, 0.5, 0.8];     

%% SECTION 12: UNITS & CONVERSION FACTORS
cfg.units.hours_to_days = 1/24;
cfg.units.bar_to_psi = 14.5038;
cfg.units.kW_to_hp = 1.34102;
cfg.units.m_to_mm = 1000;
cfg.units.kg_to_lb = 2.20462;

end