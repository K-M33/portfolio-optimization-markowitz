%% =========================================================================
%  MFV_CenturionCapital.m
%
%  PURPOSE : Minimum Variance Portfolio (MVP) construction and Efficient
%            Frontier analysis for 10 U.S. equities.
%            Three constraint schemes are compared: short-sales allowed,
%            long-only, and client-mandate restricted.
%
%  CLIENT  : Centurion Capital, S.C. (fictional institutional client)
%  COURSE  : Mercados Financieros — EGADE Business School, 2025-2026
%  AUTHOR  : Diana Krystell Magallanes Pichardo
%  DATA    : Datos_Portafolio_CenturionCapital.xlsx (Bloomberg)
%  PERIOD  : January 2016 – January 2026 (120 monthly log-returns)
%
%  ASSETS  : LMT  NEE  JPM  XOM  LLY  K  CB  CAT  NVDA  AMT
%  BENCHMARK: S&P 500
%  RISK-FREE: U.S. 10-Year Treasury (Bloomberg USGG10YR), avg 2.70% p.a.
%
%  OUTPUTS : 8 figures (Fig 7–14), console summary tables
%    Fig 7  — Efficient Frontier (short sales allowed)
%    Fig 8  — Portfolio weights along frontier (no restrictions)
%    Fig 9  — Three-frontier comparison
%    Fig 10 — Portfolio weights (long-only)
%    Fig 11 — Portfolio weights (Centurion mandate constraints)
%    Fig 12 — Capital Market Line (CML) with Tangency Portfolio
%    Fig 13 — CML comparison across three schemes
%    Fig 14 — Monte Carlo bootstrap confidence band (300 sims, 24 months)
%
%  DEPENDENCIES: Financial Toolbox (Portfolio object, estimateFrontier,
%                estimateMaxSharpeRatio, portsim)
%
%  NOTES   : All intermediate calculations use MONTHLY scale.
%            Annualisation: return × 12, risk × sqrt(12).
% =========================================================================

clc; clear; close all;

%% =========================================================================
%  SECTION 1: LOAD DATA FROM EXCEL
%
%  Sheet '05_Covarianza':
%    A16:A25  — Asset tickers (string)
%    C16:C25  — CAPM expected monthly returns  E[r_i]
%    D16:D25  — Historical monthly std dev     σ_i
%    B4:K13   — Monthly covariance matrix 10×10
%
%  Sheet '03_Estadisticos': (reserved for future use)
% =========================================================================

file_path  = fullfile(pwd, 'Datos_Portafolio_CenturionCapital.xlsx');
sheet_cov  = '05_Covarianza';
sheet_stat = '03_Estadisticos';

% --- Asset tickers -------------------------------------------------------
AssetList = readmatrix(file_path, 'Sheet', sheet_cov, ...
                       'Range', 'A16:A25', 'OutputType', 'string');

% --- CAPM expected monthly returns (row 15 = header, data from row 16) ---
AssetMean = readmatrix(file_path, 'Sheet', sheet_cov, 'Range', 'C16:C25');

% --- Historical monthly standard deviations (reference only) -------------
AssetStd  = readmatrix(file_path, 'Sheet', sheet_cov, 'Range', 'D16:D25');

% --- Monthly 10×10 covariance matrix (row 3 = column headers) ------------
AssetCovar = readmatrix(file_path, 'Sheet', sheet_cov, 'Range', 'B4:K13');

% Enforce exact symmetry to avoid numerical issues in the QP optimizer.
% Small floating-point asymmetries can cause quadprog to fail.
AssetCovar = (AssetCovar + AssetCovar') / 2;

% --- Risk-free rate -------------------------------------------------------
% Source: Bloomberg USGG10YR, 10-year average 2016–2026 = 2.70% p.a.
rf_anual   = 0.0270;
rf_mensual = rf_anual / 12;   % 0.225% monthly

% --- Console output: asset summary ---------------------------------------
fprintf('\n=== ASSETS LOADED ===\n');
fprintf('%-6s  %-10s  %-10s  %-10s\n', 'Ticker', 'E[r] mo.', 'σ mo.', 'E[r] ann.');
fprintf('%s\n', repmat('-',1,42));
for i = 1:length(AssetList)
    fprintf('%-6s  %8.4f%%  %8.4f%%  %8.4f%%\n', ...
            AssetList(i), AssetMean(i)*100, AssetStd(i)*100, AssetMean(i)*12*100);
end
fprintf('\nrf monthly = %.4f%%  |  rf annual = %.2f%%\n', rf_mensual*100, rf_anual*100);


%% =========================================================================
%  SECTION 2: CORRELATION HEAT MAP
%
%  Derives the correlation matrix directly from the covariance matrix using:
%    ρ_ij = σ_ij / (σ_i × σ_j)
%
%  corrcoef() requires raw data, not a covariance matrix, so we use the
%  direct formula. Values are clipped to [-1, 1] to clean numeric noise.
% =========================================================================

sigma_vec         = sqrt(diag(AssetCovar));               % 10×1 monthly σ vector
CorrelationMatrix = AssetCovar ./ (sigma_vec * sigma_vec'); % ρ_ij formula
CorrelationMatrix = real(CorrelationMatrix);               % remove complex eps noise
CorrelationMatrix = min(max(CorrelationMatrix, -1), 1);    % hard-clip to valid range

figure('Name', 'Heat Map — Correlation Matrix', 'Position', [50,50,820,680]);
imagesc(CorrelationMatrix);
colormap(parula);
colorbar;
caxis([-0.2 1.0]);
title('\bf Heat Map — Correlation Matrix (2016–2026)', 'FontSize', 13);
xlabel('Assets');  ylabel('Assets');
set(gca, 'XTick', 1:length(AssetList), 'XTickLabel', AssetList, ...
         'YTick', 1:length(AssetList), 'YTickLabel', AssetList, 'FontSize', 10);
axis equal tight;

% Annotate each cell with its numeric value
for i = 1:size(CorrelationMatrix, 1)
    for j = 1:size(CorrelationMatrix, 2)
        text(j, i, num2str(CorrelationMatrix(i,j), '%.2f'), ...
             'HorizontalAlignment', 'Center', 'VerticalAlignment', 'Middle', ...
             'Color', 'k', 'FontSize', 8, 'FontWeight', 'bold');
    end
end

fprintf('\n=== KEY CORRELATIONS ===\n');
fprintf('Maximum off-diagonal correlation: %.4f\n', ...
        max(CorrelationMatrix(~eye(length(AssetList), 'logical'))));


%% =========================================================================
%  SECTION 3: PORTFOLIO OBJECTS — THREE CONSTRAINT SCHEMES
%
%  (a) pShort    — Short sales allowed (lower bound = -1, unconstrained)
%  (b) pBase     — Long-only, no short sales (lower bound = 0)
%  (c) pRestrict — Centurion Capital mandate constraints:
%                    • 2%  ≤ w_i ≤ 30%  for all assets
%                    • w_NVDA ≤ 20%     (NVDA cap)
%                    • w_LMT + w_XOM ≤ 35%  (sector concentration limit)
%
%  All Portfolio objects work in MONTHLY scale (AssetMean, AssetCovar, and
%  RiskFreeRate are all monthly). Annualisation is applied only for output.
% =========================================================================

% --- (a) Unconstrained — short sales allowed -----------------------------
pShort = Portfolio('AssetList',    AssetList,   ...
                   'RiskFreeRate', rf_mensual,  ...
                   'AssetMean',    AssetMean,   ...
                   'AssetCovar',   AssetCovar,  ...
                   'LowerBound',  -ones(size(AssetMean)), ...  % short allowed
                   'UpperBudget',  1,           ...
                   'LowerBudget',  1);

% --- (b) Long-only — no short sales  w_i ≥ 0 ----------------------------
pBase = Portfolio('AssetList',    AssetList,   ...
                  'RiskFreeRate', rf_mensual,  ...
                  'AssetMean',    AssetMean,   ...
                  'AssetCovar',   AssetCovar,  ...
                  'LowerBound',   zeros(size(AssetMean)), ...  % long-only
                  'UpperBudget',  1,           ...
                  'LowerBudget',  1);

% --- (c) Centurion Capital mandate constraints ---------------------------
n        = length(AssetMean);
lb_restr = 0.02 * ones(n, 1);    % minimum 2% per asset
ub_restr = 0.30 * ones(n, 1);    % maximum 30% per asset

% NVDA individual cap: 20% maximum
idx_NVDA           = find(strcmp(AssetList, 'NVDA'));
ub_restr(idx_NVDA) = 0.20;

pRestrict = Portfolio('AssetList',    AssetList,   ...
                      'RiskFreeRate', rf_mensual,  ...
                      'AssetMean',    AssetMean,   ...
                      'AssetCovar',   AssetCovar,  ...
                      'LowerBound',   lb_restr,    ...
                      'UpperBound',   ub_restr,    ...
                      'UpperBudget',  1,           ...
                      'LowerBudget',  1);

% Group constraint: Defense/Energy sector cap — LMT + XOM ≤ 35%
idx_LMT                  = find(strcmp(AssetList, 'LMT'));
idx_XOM                  = find(strcmp(AssetList, 'XOM'));
groupMat_DefEng          = zeros(1, n);
groupMat_DefEng(idx_LMT) = 1;
groupMat_DefEng(idx_XOM) = 1;
pRestrict = setGroups(pRestrict, groupMat_DefEng, 0, 0.35);

fprintf('\n=== PORTFOLIO OBJECTS CREATED ===\n');
fprintf('pShort   : short sales allowed   (LB = -1)\n');
fprintf('pBase    : long-only             (LB = 0)\n');
fprintf('pRestrict: Centurion mandate     (LB=2%%, UB=30%%, NVDA<=20%%, LMT+XOM<=35%%)\n');


%% =========================================================================
%  SECTION 4: MINIMUM VARIANCE PORTFOLIO (MVP) — THREE SCHEMES
%
%  estimateFrontierLimits(..., 'min') returns the leftmost point of the
%  frontier, which is the Global Minimum Variance Portfolio.
%
%  Monthly moments are annualised for reporting:
%    Annual return = monthly return × 12
%    Annual risk   = monthly risk   × sqrt(12)
% =========================================================================

numPorts = 25;   % number of portfolios to trace the efficient frontier

% Compute MVP weights for each scheme
w_pmv_short = estimateFrontierLimits(pShort,    'min');
w_pmv_base  = estimateFrontierLimits(pBase,     'min');
w_pmv_restr = estimateFrontierLimits(pRestrict, 'min');

% Estimate monthly risk and return for each MVP
[rsk_s, ret_s] = estimatePortMoments(pShort,    w_pmv_short);
[rsk_b, ret_b] = estimatePortMoments(pBase,     w_pmv_base);
[rsk_r, ret_r] = estimatePortMoments(pRestrict, w_pmv_restr);

% --- Console output: monthly scale ---------------------------------------
fprintf('\n=== MVP — THREE SCHEMES (MONTHLY SCALE) ===\n');
fprintf('%-30s  %-10s  %-10s  %-10s\n', 'Portfolio', 'E[rp] mo.', 'σp mo.', 'Sharpe');
fprintf('%s\n', repmat('-',1,65));
fprintf('%-30s  %8.4f%%  %8.4f%%  %8.4f\n', ...
        'MVP Unconstrained',  ret_s*100, rsk_s*100, (ret_s - rf_mensual)/rsk_s);
fprintf('%-30s  %8.4f%%  %8.4f%%  %8.4f\n', ...
        'MVP Long-only',      ret_b*100, rsk_b*100, (ret_b - rf_mensual)/rsk_b);
fprintf('%-30s  %8.4f%%  %8.4f%%  %8.4f\n', ...
        'MVP Centurion',      ret_r*100, rsk_r*100, (ret_r - rf_mensual)/rsk_r);

% --- Console output: annualised ------------------------------------------
fprintf('\n=== MVP — ANNUALISED ===\n');
fprintf('%-30s  %-10s  %-10s  %-10s\n', 'Portfolio', 'E[rp] ann.', 'σp ann.', 'Sharpe');
fprintf('%s\n', repmat('-',1,65));
fprintf('%-30s  %8.2f%%  %8.2f%%  %8.4f\n', ...
        'MVP Unconstrained',  ret_s*12*100, rsk_s*sqrt(12)*100, (ret_s*12-rf_anual)/(rsk_s*sqrt(12)));
fprintf('%-30s  %8.2f%%  %8.2f%%  %8.4f\n', ...
        'MVP Long-only',      ret_b*12*100, rsk_b*sqrt(12)*100, (ret_b*12-rf_anual)/(rsk_b*sqrt(12)));
fprintf('%-30s  %8.2f%%  %8.2f%%  %8.4f\n', ...
        'MVP Centurion',      ret_r*12*100, rsk_r*sqrt(12)*100, (ret_r*12-rf_anual)/(rsk_r*sqrt(12)));


%% =========================================================================
%  SECTION 5 / FIG 7: EFFICIENT FRONTIER — SHORT SALES ALLOWED
%
%  Plots the unconstrained frontier (pShort) with 25 portfolios.
%  Portfolios are labelled P1–P25 along the curve.
% =========================================================================

pwgt_short = estimateFrontier(pShort, numPorts);
[prsk_s, pret_s] = estimatePortMoments(pShort, pwgt_short);

figure('Name', 'Fig 7 — Frontier (Short Sales Allowed)', 'Position', [100,100,900,620]);
plot(prsk_s*sqrt(12)*100, pret_s*12*100, 'b-o', 'LineWidth', 2, 'MarkerSize', 5);
hold on;
plot(rsk_s*sqrt(12)*100, ret_s*12*100, 'g^', 'MarkerSize', 12, ...
     'MarkerFaceColor', 'g', 'DisplayName', 'MVP');
for i = 1:numPorts
    text(prsk_s(i)*sqrt(12)*100, pret_s(i)*12*100, sprintf('P%d', i), ...
         'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'right', 'FontSize', 7);
end
xlabel('Portfolio Risk σ (% annual)',      'FontSize', 11);
ylabel('Expected Return E[r] (% annual)',  'FontSize', 11);
title('\bf Efficient Frontier — Short Sales Allowed (2016–2026)', 'FontSize', 12);
legend('Frontier', 'MVP', 'Location', 'best');
grid on;
xlim([0 60]);  ylim([0 60]);


%% =========================================================================
%  SECTION 6 / FIG 8: PORTFOLIO WEIGHTS ALONG FRONTIER — NO RESTRICTIONS
%
%  Stacked bar chart showing asset allocation for each of the 25 frontier
%  portfolios. Useful for identifying corner solutions.
% =========================================================================

colors_palette = lines(length(AssetList));

figure('Name', 'Fig 8 — Weights (No Restrictions)', 'Position', [100,100,1100,500]);
b = bar(pwgt_short', 'stacked');
for i = 1:length(b)
    b(i).FaceColor = colors_palette(i,:);
end
xticks(1:numPorts);
xticklabels(arrayfun(@(x) sprintf('P%d', x), 1:numPorts, 'UniformOutput', false));
xlabel('Portfolios on the Efficient Frontier', 'FontSize', 11);
ylabel('Asset Weight',                         'FontSize', 11);
title('\bf Portfolio Composition — No Restrictions', 'FontSize', 12);
grid on;
lgd = legend(b, AssetList, 'Location', 'southoutside', ...
             'Orientation', 'horizontal', 'NumColumns', 5);
lgd.FontSize = 9;
set(gcf, 'Position', [100,100,1100,600]);


%% =========================================================================
%  SECTION 7 / FIG 9: THREE-FRONTIER COMPARISON
%
%  Overlays the efficient frontiers for all three constraint schemes.
%  MVP markers (triangles) are plotted for each scheme.
% =========================================================================

pwgt_base  = estimateFrontier(pBase,     numPorts);
pwgt_restr = estimateFrontier(pRestrict, numPorts);

[prsk_b, pret_b] = estimatePortMoments(pBase,     pwgt_base);
[prsk_r, pret_r] = estimatePortMoments(pRestrict, pwgt_restr);

figure('Name', 'Fig 9 — Three-Frontier Comparison', 'Position', [100,100,900,620]);
plot(prsk_s*sqrt(12)*100, pret_s*12*100, 'b--', 'LineWidth', 1.5, ...
     'DisplayName', 'Unconstrained (short)');
hold on;
plot(prsk_b*sqrt(12)*100, pret_b*12*100, 'g-',  'LineWidth', 2, ...
     'DisplayName', 'Long-only');
plot(prsk_r*sqrt(12)*100, pret_r*12*100, 'r-',  'LineWidth', 2, ...
     'DisplayName', 'Centurion Mandate');
% MVP markers
plot(rsk_s*sqrt(12)*100, ret_s*12*100, 'b^', 'MarkerSize', 10, 'MarkerFaceColor', 'b');
plot(rsk_b*sqrt(12)*100, ret_b*12*100, 'g^', 'MarkerSize', 10, 'MarkerFaceColor', 'g');
plot(rsk_r*sqrt(12)*100, ret_r*12*100, 'r^', 'MarkerSize', 10, 'MarkerFaceColor', 'r');
xlabel('Risk σ (% annual)',            'FontSize', 11);
ylabel('Expected Return (% annual)',   'FontSize', 11);
title('\bf Efficient Frontier Comparison — Three Constraint Schemes', 'FontSize', 12);
legend('Location', 'best');
grid on;


%% =========================================================================
%  SECTION 8 / FIG 10-11: PORTFOLIO WEIGHTS — LONG-ONLY AND CONSTRAINED
%
%  Fig 10: Long-only weights (pBase)
%  Fig 11: Centurion mandate weights (pRestrict)
%          Includes horizontal reference lines for LB (2%) and UB (30%).
% =========================================================================

% --- Fig 10: Long-only weights -------------------------------------------
figure('Name', 'Fig 10 — Weights (Long-Only)', 'Position', [100,100,1100,500]);
b = bar(pwgt_base', 'stacked');
for i = 1:length(b); b(i).FaceColor = colors_palette(i,:); end
xticks(1:numPorts);
xticklabels(arrayfun(@(x) sprintf('P%d', x), 1:numPorts, 'UniformOutput', false));
xlabel('Portfolios on the Efficient Frontier', 'FontSize', 11);
ylabel('Asset Weight',                         'FontSize', 11);
title('\bf Portfolio Composition — Long-Only (No Short Sales)', 'FontSize', 12);
grid on;
lgd = legend(b, AssetList, 'Location', 'southoutside', ...
             'Orientation', 'horizontal', 'NumColumns', 5);
lgd.FontSize = 9;
set(gcf, 'Position', [100,100,1100,600]);

% --- Fig 11: Centurion mandate weights -----------------------------------
figure('Name', 'Fig 11 — Weights (Centurion Mandate)', 'Position', [100,100,1100,500]);
b = bar(pwgt_restr', 'stacked');
for i = 1:length(b); b(i).FaceColor = colors_palette(i,:); end
xticks(1:numPorts);
xticklabels(arrayfun(@(x) sprintf('P%d', x), 1:numPorts, 'UniformOutput', false));
xlabel('Portfolios on the Efficient Frontier', 'FontSize', 11);
ylabel('Asset Weight',                         'FontSize', 11);
title('\bf Portfolio Composition — Centurion Capital Mandate Constraints', 'FontSize', 12);
grid on;
% Reference lines for lower/upper bounds
yline(0.02, 'k--', 'LB 2%',  'FontSize', 9, 'LineWidth', 1);
yline(0.30, 'k--', 'UB 30%', 'FontSize', 9, 'LineWidth', 1);
lgd = legend(b, AssetList, 'Location', 'southoutside', ...
             'Orientation', 'horizontal', 'NumColumns', 5);
lgd.FontSize = 9;
set(gcf, 'Position', [100,100,1100,620]);


%% =========================================================================
%  SECTION 9: TANGENCY PORTFOLIO — MAXIMUM SHARPE RATIO
%
%  estimateMaxSharpeRatio solves: max  (E[rp] - rf) / σp
%  Computed for both pBase (long-only) and pRestrict (Centurion mandate).
%
%  The tangency portfolio is the single risky portfolio every rational
%  investor would hold in combination with the risk-free asset (CAPM).
% =========================================================================

w_tan_base  = estimateMaxSharpeRatio(pBase);
w_tan_restr = estimateMaxSharpeRatio(pRestrict);

[risk_tan_b, ret_tan_b] = estimatePortMoments(pBase,     w_tan_base);
[risk_tan_r, ret_tan_r] = estimatePortMoments(pRestrict, w_tan_restr);

% Annualised Sharpe ratios
SR_tan_b = (ret_tan_b*12 - rf_anual) / (risk_tan_b*sqrt(12));
SR_tan_r = (ret_tan_r*12 - rf_anual) / (risk_tan_r*sqrt(12));

fprintf('\n=== TANGENCY PORTFOLIO (ANNUALISED) ===\n');
fprintf('%-30s  %-10s  %-10s  %-10s\n', 'Portfolio', 'E[rp]', 'σp', 'Sharpe');
fprintf('%s\n', repmat('-',1,65));
fprintf('%-30s  %8.2f%%  %8.2f%%  %8.4f\n', ...
        'Tangency (pBase)',     ret_tan_b*12*100, risk_tan_b*sqrt(12)*100, SR_tan_b);
fprintf('%-30s  %8.2f%%  %8.2f%%  %8.4f\n', ...
        'Tangency (pRestrict)', ret_tan_r*12*100, risk_tan_r*sqrt(12)*100, SR_tan_r);


%% =========================================================================
%  SECTION 10 / FIG 12: CAPITAL MARKET LINE (CML) — MAIN
%
%  CML equation: E[rp] = rf + SR_tan × σp
%  Plots the frontier (pBase), CML, Tangency Portfolio, and recommended MVP.
% =========================================================================

sigma_range = linspace(0, max(prsk_b)*sqrt(12)*100*1.5, 200);  % σ grid for CML
CML_returns = rf_anual*100 + SR_tan_b * sigma_range;

figure('Name', 'Fig 12 — CML (Main)', 'Position', [100,100,920,640]);
plot(prsk_b*sqrt(12)*100, pret_b*12*100, 'b-', 'LineWidth', 2, ...
     'DisplayName', 'Frontier (Long-only)');
hold on;
plot(sigma_range, CML_returns, 'r-', 'LineWidth', 2.5, ...
     'DisplayName', sprintf('CML  (SR=%.4f)', SR_tan_b));
plot(risk_tan_b*sqrt(12)*100, ret_tan_b*12*100, 'r*', 'MarkerSize', 14, ...
     'LineWidth', 2, 'DisplayName', 'Tangency Portfolio');
plot(rsk_r*sqrt(12)*100, ret_r*12*100, 'gs', 'MarkerSize', 12, ...
     'MarkerFaceColor', 'g', 'DisplayName', 'MVP Centurion (recommended)');
plot(0, rf_anual*100, 'kd', 'MarkerSize', 10, 'MarkerFaceColor', 'k', ...
     'DisplayName', sprintf('rf = %.2f%%', rf_anual*100));
xlabel('Risk σ (% annual)',            'FontSize', 11);
ylabel('Expected Return (% annual)',   'FontSize', 11);
title('\bf Capital Market Line — Centurion Capital, S.C.', 'FontSize', 12);
legend('Location', 'best');
grid on;
xlim([0 50]);  ylim([0 30]);
text(risk_tan_b*sqrt(12)*100+0.5, ret_tan_b*12*100-1, ...
     sprintf('  TP (%.2f%%, %.2f%%)', risk_tan_b*sqrt(12)*100, ret_tan_b*12*100), ...
     'FontSize', 9, 'Color', 'r');
text(rsk_r*sqrt(12)*100+0.5, ret_r*12*100+0.8, ...
     sprintf('  MVP Rec. (%.2f%%, %.2f%%)', rsk_r*sqrt(12)*100, ret_r*12*100), ...
     'FontSize', 9, 'Color', [0 0.5 0]);


%% =========================================================================
%  SECTION 11 / FIG 13: THREE CMLs OVERLAID
%
%  Compares the CML from each constraint scheme.
%  The unconstrained frontier produces the steepest CML (highest SR).
%  Constraints flatten the CML, reflecting the cost of restricting the
%  investment universe.
% =========================================================================

w_tan_short = estimateMaxSharpeRatio(pShort);
[risk_tan_s, ret_tan_s] = estimatePortMoments(pShort, w_tan_short);
SR_tan_s = (ret_tan_s*12 - rf_anual) / (risk_tan_s*sqrt(12));

CML_s = rf_anual*100 + SR_tan_s * sigma_range;
CML_b = rf_anual*100 + SR_tan_b * sigma_range;
CML_r = rf_anual*100 + SR_tan_r * sigma_range;

figure('Name', 'Fig 13 — Three CMLs', 'Position', [100,100,920,640]);
plot(sigma_range, CML_s, 'b--', 'LineWidth', 2, ...
     'DisplayName', sprintf('CML Unconstrained  SR=%.4f', SR_tan_s));
hold on;
plot(sigma_range, CML_b, 'g-',  'LineWidth', 2, ...
     'DisplayName', sprintf('CML Long-only       SR=%.4f', SR_tan_b));
plot(sigma_range, CML_r, 'r-',  'LineWidth', 2, ...
     'DisplayName', sprintf('CML Centurion       SR=%.4f', SR_tan_r));
plot(0, rf_anual*100, 'kd', 'MarkerSize', 10, 'MarkerFaceColor', 'k', ...
     'DisplayName', sprintf('rf = %.2f%%', rf_anual*100));
xlabel('Risk σ (% annual)',           'FontSize', 11);
ylabel('Expected Return (% annual)',  'FontSize', 11);
title('\bf Capital Market Line Comparison — Three Constraint Schemes', 'FontSize', 12);
legend('Location', 'best');
grid on;
xlim([0 50]);  ylim([0 35]);

fprintf('\n=== TANGENCY PORTFOLIO SHARPE RATIOS ===\n');
fprintf('SR Unconstrained : %.4f\n', SR_tan_s);
fprintf('SR Long-only     : %.4f\n', SR_tan_b);
fprintf('SR Centurion     : %.4f\n', SR_tan_r);


%% =========================================================================
%  SECTION 12 / FIG 14: MONTE CARLO BOOTSTRAP — 95% CONFIDENCE BAND
%
%  Methodology:
%    1. Simulate T=24 months of returns for 10 assets using portsim()
%       (Geometric Brownian Motion with monthly mean and covariance).
%    2. Annualise simulated statistics: return×12, covariance×12.
%    3. Construct a Portfolio object and trace its efficient frontier.
%    4. Repeat nSim=300 times; compute mean frontier and 95% CI band.
%
%  Interpretation: The confidence band shows how much the historical
%  frontier could shift due to estimation error in returns and covariances.
%  The recommended MVP should ideally sit well within the band.
%
%  rng('default') is set for reproducibility.
% =========================================================================

nSim = 300;    % number of bootstrap simulations
T    = 24;     % simulation horizon (months)
dt   = 1/12;   % time step (monthly)

allReturns = zeros(nSim, numPorts);
allRisks   = zeros(nSim, numPorts);

fprintf('\nRunning %d Monte Carlo simulations (T=%d months)...\n', nSim, T);
rng('default');   % fixed seed for reproducibility

for i = 1:nSim
    % Simulate T months of log-returns for 10 assets (GBM)
    % portsim inputs: mean vector (1×n), covariance (n×n), periods, dt
    simRet = portsim(AssetMean', AssetCovar, T, dt)';   % output: T×10

    % Annualise simulated statistics
    AssetMeanSim  = mean(simRet)' * 12;            % 10×1 annual means
    AssetCovarSim = cov(simRet) * 12;              % 10×10 annual covariance

    % Build Portfolio object on annual scale for this simulation
    pSim = Portfolio('AssetMean',  AssetMeanSim,                          ...
                     'AssetCovar', (AssetCovarSim + AssetCovarSim') / 2,  ...
                     'LowerBound', zeros(size(AssetMeanSim)),             ...
                     'UpperBudget', 1, 'LowerBudget', 1);

    % Trace frontier; catch non-positive-definite covariance edge cases
    try
        pwgt_sim = estimateFrontier(pSim, numPorts);
        [rsk_sim, ret_sim] = estimatePortMoments(pSim, pwgt_sim);
        allReturns(i,:) = ret_sim';
        allRisks(i,:)   = rsk_sim';
    catch
        % Discard simulation if covariance matrix is not positive definite
        allReturns(i,:) = NaN;
        allRisks(i,:)   = NaN;
    end
end

% Remove failed simulations
valid      = ~any(isnan(allReturns), 2);
allReturns = allReturns(valid, :);
allRisks   = allRisks(valid, :);
fprintf('Valid simulations: %d / %d\n', sum(valid), nSim);

% Compute bootstrap statistics
meanReturns  = mean(allReturns);
meanRisks    = mean(allRisks);
confInterval = 1.96 * std(allReturns) / sqrt(sum(valid));   % 95% CI

% Historical frontier for overlay (pBase, annualised)
[prsk_b_a, pret_b_a] = estimatePortMoments(pBase, pwgt_base);

% --- Fig 14 --------------------------------------------------------------
figure('Name', 'Fig 14 — Frontier with 95% Bootstrap CI', 'Position', [100,100,920,640]);
hold on;
% Confidence band (light blue fill)
fill([meanRisks, fliplr(meanRisks)], ...
     [meanReturns - confInterval, fliplr(meanReturns + confInterval)], ...
     [0.7 0.85 1.0], 'FaceAlpha', 0.45, 'EdgeColor', 'none', ...
     'DisplayName', '95% Bootstrap CI');
% Mean bootstrapped frontier
plot(meanRisks, meanReturns, 'b--', 'LineWidth', 1.5, ...
     'DisplayName', 'Mean bootstrapped frontier');
% Historical frontier (annualised)
plot(prsk_b_a*sqrt(12)*100, pret_b_a*12*100, 'b-', 'LineWidth', 2.5, ...
     'DisplayName', 'Historical frontier (2016–2026)');
% Recommended MVP
plot(rsk_r*sqrt(12)*100, ret_r*12*100, 'g^', 'MarkerSize', 12, ...
     'MarkerFaceColor', 'g', 'DisplayName', 'MVP Centurion (recommended)');
xlabel('Risk σ (% annual)',           'FontSize', 11);
ylabel('Expected Return (% annual)',  'FontSize', 11);
title('\bf Efficient Frontier with 95% CI — Bootstrap 300 Simulations (T=24 months)', ...
      'FontSize', 12);
legend('Location', 'best');
grid on;


%% =========================================================================
%  SECTION 13: FINAL SUMMARY — PORTFOLIO COMPARISON TABLE
%
%  Annualised metrics for the recommended MVP (Centurion mandate) vs
%  long-only MVP and tangency portfolio.
%  Risk reduction is benchmarked against S&P 500 historical vol (~17%).
% =========================================================================

% Recommended MVP (Centurion mandate) — annualised
ret_rec   = ret_r * 12;
rsk_rec   = rsk_r * sqrt(12);
SR_rec    = (ret_rec - rf_anual) / rsk_rec;
prima_rec = ret_rec - rf_anual;    % excess return over risk-free

% Tangency portfolio — annualised
ret_pt = ret_tan_b * 12;
rsk_pt = risk_tan_b * sqrt(12);
SR_pt  = SR_tan_b;

fprintf('\n');
fprintf('=============================================================\n');
fprintf('  FINAL SUMMARY — CENTURION CAPITAL, S.C.\n');
fprintf('=============================================================\n');
fprintf('  rf annual    : %.2f%%\n', rf_anual*100);
fprintf('  E[rm] annual : %.2f%%\n', (mean(AssetMean)*12 + rf_anual)*100);
fprintf('  MRP annual   : %.2f%%\n', 10.04);   % Market Risk Premium (CAPM input)
fprintf('-------------------------------------------------------------\n');
fprintf('  %-28s  %8s  %8s  %8s\n', 'Portfolio', 'E[rp]', 'σp', 'Sharpe');
fprintf('  %-28s  %8s  %8s  %8s\n', repmat('-',1,28), repmat('-',1,8), ...
                                     repmat('-',1,8), repmat('-',1,8));
fprintf('  %-28s  %7.2f%%  %7.2f%%  %7.4f\n', ...
        'MVP RECOMMENDED (restricted)', ret_rec*100, rsk_rec*100, SR_rec);
fprintf('  %-28s  %7.2f%%  %7.2f%%  %7.4f\n', ...
        'MVP Long-only', ret_b*12*100, rsk_b*sqrt(12)*100, ...
        (ret_b*12 - rf_anual)/(rsk_b*sqrt(12)));
fprintf('  %-28s  %7.2f%%  %7.2f%%  %7.4f\n', ...
        'Tangency Portfolio', ret_pt*100, rsk_pt*100, SR_pt);
fprintf('=============================================================\n');
fprintf('  Excess return over rf (recommended MVP) : %.2f%%\n', prima_rec*100);
fprintf('  Risk reduction vs S&P 500 (σ~17%%)      : %.1f%%\n', (1 - rsk_rec/0.17)*100);
fprintf('=============================================================\n');

fprintf('\nScript complete. 8 figures generated (Fig 7–14).\n');
fprintf('To save a figure: print(fig_handle, ''filename'', ''-dpng'',''-r300'')\n');
