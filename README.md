# Portfolio Optimization — Markowitz Efficient Frontier

> **Minimum Variance Portfolio construction and Capital Market Line analysis  
> for a fictional institutional pension fund mandate.**

[![MATLAB](https://img.shields.io/badge/MATLAB-R2023b%2B-orange?logo=mathworks)](https://www.mathworks.com/)
[![Bloomberg](https://img.shields.io/badge/Data-Bloomberg%20Terminal-black)](https://www.bloomberg.com/professional/)
[![License](https://img.shields.io/badge/License-MIT-blue)](LICENSE)
[![Course](https://img.shields.io/badge/Course-Mercados%20Financieros%20EGADE-purple)](https://egade.tec.mx/)

---

## Overview

This project implements a full **Markowitz Mean-Variance Optimization** framework for a $50M USD institutional mandate. It builds and compares three constraint schemes — unconstrained (short sales allowed), long-only, and a custom client mandate — and traces the **Efficient Frontier**, **Capital Market Line (CML)**, and **Tangency Portfolio** for each.

A **Monte Carlo bootstrap** (300 simulations, 24-month horizon) validates the robustness of the recommended portfolio against estimation error.

---

## Client & Mandate

| Parameter | Value |
|---|---|
| Client | Centurion Capital, S.C. (fictional) |
| Mandate size | $50,000,000 USD |
| Universe | 10 U.S. equities |
| Benchmark | S&P 500 |
| Risk-free rate | U.S. 10Y Treasury (Bloomberg USGG10YR), avg 2.70% p.a. |
| Data period | January 2016 – January 2026 (120 monthly log-returns) |

---

## Assets

| Ticker | Company | Sector |
|--------|---------|--------|
| LMT | Lockheed Martin | Defense |
| NEE | NextEra Energy | Utilities |
| JPM | JPMorgan Chase | Financials |
| XOM | ExxonMobil | Energy |
| LLY | Eli Lilly | Healthcare |
| K | Kellanova | Consumer Staples |
| CB | Chubb | Insurance |
| CAT | Caterpillar | Industrials |
| NVDA | NVIDIA | Technology |
| AMT | American Tower | Real Estate |

---

## Mandate Constraints

Three constraint schemes are modeled and compared:

| Scheme | Description |
|--------|-------------|
| **Unconstrained** | Short sales allowed, no weight limits |
| **Long-only** | w_i ≥ 0 for all assets |
| **Centurion Mandate** | 2% ≤ w_i ≤ 30% · w_NVDA ≤ 20% · w_LMT + w_XOM ≤ 35% |

---

## Methodology

```
Bloomberg data (monthly adjusted prices)
        ↓
Log-returns → Mean vector (CAPM) + Covariance matrix
        ↓
Portfolio object (MATLAB Financial Toolbox)
        ↓
Efficient Frontier (25 portfolios per scheme)
        ↓
Minimum Variance Portfolio (MVP) — estimateFrontierLimits
Tangency Portfolio (Max Sharpe) — estimateMaxSharpeRatio
Capital Market Line (CML) — rf + SR × σ
        ↓
Monte Carlo Bootstrap (300 sims × 24 months) — 95% CI band
```

**Key formulas:**

- **Expected return (CAPM):** `E[r_i] = rf + β_i × MRP`
- **Portfolio variance:** `σ²_p = wᵀ Σ w`
- **Sharpe ratio:** `SR = (E[rp] - rf) / σp`
- **Annualisation:** `E[r] × 12` for returns, `σ × √12` for risk
- **Correlation from covariance:** `ρ_ij = σ_ij / (σ_i × σ_j)`

---

## Outputs

| Figure | Description |
|--------|-------------|
| Fig 7  | Efficient Frontier — short sales allowed |
| Fig 8  | Portfolio weights along frontier (unconstrained) |
| Fig 9  | Three-frontier comparison overlay |
| Fig 10 | Portfolio weights — long-only |
| Fig 11 | Portfolio weights — Centurion mandate |
| Fig 12 | Capital Market Line with Tangency Portfolio |
| Fig 13 | CML comparison across three schemes |
| Fig 14 | Monte Carlo bootstrap 95% confidence band |

---

## Key Results

> *Note: Exact values depend on Bloomberg data inputs.*

| Portfolio | E[rp] annual | σp annual | Sharpe Ratio |
|-----------|-------------|-----------|--------------|
| MVP — Unconstrained | — | — | — |
| MVP — Long-only | — | — | — |
| **MVP — Centurion (recommended)** | **—** | **—** | **—** |
| Tangency Portfolio | — | — | — |

*Results omitted pending data file. Run the script to populate.*

---

## Repository Structure

```
portfolio-optimization-markowitz/
│
├── README.md                              ← this file
│
├── src/
│   └── MFV_CenturionCapital.m            ← main MATLAB script
│
├── data/
│   └── Datos_Portafolio_CenturionCapital.xlsx  ← Bloomberg data (not tracked)
│
├── outputs/
│   ├── fig07_frontier_short.png
│   ├── fig08_weights_short.png
│   ├── fig09_three_frontiers.png
│   ├── fig10_weights_longonly.png
│   ├── fig11_weights_centurion.png
│   ├── fig12_CML_main.png
│   ├── fig13_three_CMLs.png
│   └── fig14_bootstrap_CI.png
│
└── .gitignore
```

---

## Requirements

- **MATLAB R2023b or later**
- **Financial Toolbox** (required for `Portfolio`, `estimateFrontier`, `estimateMaxSharpeRatio`, `portsim`)
- Bloomberg Terminal access (for data sourcing — data file not included in repo)

---

## How to Run

```matlab
% 1. Place Datos_Portafolio_CenturionCapital.xlsx in the working directory
% 2. Open MATLAB and navigate to the /src folder
% 3. Run:
MFV_CenturionCapital

% 4. Optionally save figures:
print(gcf, '../outputs/fig07_frontier_short', '-dpng', '-r300')
```

---

## Academic Context

This project was developed as part of the **Mercados Financieros** course at  
**EGADE Business School, Tecnológico de Monterrey** (2025–2026).

The fictional client *Centurion Capital, S.C.* was designed to simulate a real institutional mandate with investment policy constraints, mimicking the decision-making process of a pension fund or endowment.

---

## Author

**Diana Krystell Magallanes Pichardo**  
Master's in Finance — EGADE Business School  
[LinkedIn](https://linkedin.com/in/krystell-magallanes) | krystellmag.94@gmail.com

---

## License

MIT License — free to use for educational and non-commercial purposes.  
See [LICENSE](LICENSE) for details.

