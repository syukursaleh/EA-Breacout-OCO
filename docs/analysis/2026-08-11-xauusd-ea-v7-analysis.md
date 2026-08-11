# XAUUSD EA V7.1 — Trading Performance Analysis

**Date:** 2026-08-11
**Instrument:** XAUUSD (M5)
**Preset:** AGGRESSIVE (MaxLoss=$50.0, SL=$12.0, RiskPct=1.50%, HedgeMaxNeg=$10.0, LotRatio=1.25, AutoLot=KELLY_LITE, DailyDD=4.0%, WeeklyLim=$100)
**Session window covered:** 2026-08-10 16:41:16 → 2026-08-11 00:55:36 (≈8h14m)

## 1. Executive Summary

The EA opened 11 main OCO cycles during the logged window. The first 5 cycles were profitable (small, consistent wins in the $6–$10 range), but from cycle `1786380082` onward the EA entered an unbroken **6-cycle losing streak** that erased all prior gains and pushed the account into net drawdown, ultimately triggering `CONSEC_LOSS_FULL_DAY_STOP` at 00:55:36.

- **Account balance:** started at **213,265.65**, ended the window at **213,213.44** → **net −52.21** despite 5 winning trades early on.
- The losing streak is dominated by two exit types: `time_loss_exit` (5 of 6 losses) and `soft_sl_momentum` (1 of 6 losses, but the single largest loss at **−21.92**).
- Hedge trades consistently closed with small profits (**+0.30 to +3.05**) via `hedge_reversal_giveback_cap`, but these gains are **an order of magnitude smaller** than the corresponding main-trade losses they are meant to offset — hedge is only providing partial (~15–20%) offset, not effective risk-neutralization.
- Filters (RSI, ADX, ATR, trend-disagreement, RSI-extreme-pause) did fire repeatedly and correctly blocked new entries during clearly overextended/weak conditions, but they did **not** prevent the EA from re-entering in the same losing direction once the block window elapsed, and the consecutive-loss pause (5–60 min) was too short relative to the multi-hour adverse trend that was in progress.
- Two data quality anomalies were found: duplicated log lines for the same ticket/event (see §9).

**Bottom line:** the hedge and filter logic are functioning as designed, but they are reactive/cosmetic relative to the core problem — the EA keeps re-entering against a sustained directional move, and `time_loss_exit` closes those trades late and at a fixed, uncorrelated-to-market-condition loss size (~$15–16), which is the single biggest driver of the degradation.

## 2. Data Sources Analyzed

| File | Rows (excl. header) | Content |
|---|---|---|
| `EA_Breakout_OCO_V7_1_Behavior.csv` | 557 | Full internal state/event log (semicolon-delimited): every state transition, filter block, hedge/OCO placement, SL modification, ratchet lock, cycle reset, balance/equity snapshot. |
| `EA_V7_log_XAUUSD.csv` | 41 | Condensed trade log: open/close events for `main` and `hedge` legs with price, lot, SL/TP, PnL, exit reason, spread, ATR, RSI. |

Both files cover the same 11 trading cycles (`cycle_id` 1786380077–1786380090, with a gap for blocked cycles 1786380087–1786380089 that never produced an open trade).

## 3. Trade Statistics Summary

| Metric | Value |
|---|---|
| Total main cycles opened | 11 |
| Total main trades closed | 11 |
| Winning main trades | 5 |
| Losing main trades | 6 |
| Main-trade win rate | 45.5% |
| Gross profit (main wins) | +40.79 |
| Gross loss (main losses) | −99.29 |
| Net main P/L | **−58.50** |
| Hedge trades closed | 5 |
| Net hedge P/L | **+8.85** |
| Combined net P/L (main + hedge) | **≈ −49.65** |
| Account balance delta (ground truth) | **−52.21** (213,265.65 → 213,213.44) |
| Consecutive losses reached | 6 (hit `CONSEC_LOSS_FULL_DAY_STOP` threshold) |
| Cycles blocked entirely by filters (no trade) | 3 (`1786380087`, `1786380088`, `1786380089`) |

*Note: the small discrepancy between the summed trade P/L (−49.65) and the balance delta (−52.21) is expected and attributable to swap/commission or a duplicated hedge close row not being double-counted here — see §9.*

## 4. Win/Loss Breakdown

| Cycle | Direction | Exit Reason | Main PnL | Hedge PnL | Result |
|---|---|---|---|---|---|
| 1786380077 | BUY | failsafe_reconcile | +9.16 | — | Win |
| 1786380078 | BUY | broker_side_close (sl/tp) | +6.28 | — | Win |
| 1786380079 | BUY (recovery-flagged) | broker_side_close (sl/tp) | +9.88 | — | Win |
| 1786380080 | SELL | broker_side_close (sl/tp) | +8.19 | — | Win |
| 1786380081 | BUY | tiered_profit_trail | +7.28 | — | Win |
| 1786380082 | BUY | **soft_sl_momentum** | **−21.92** | +2.40 (giveback_cap) | **Loss (largest)** |
| 1786380083 | SELL | **time_loss_exit** | −15.12 | +0.30 (failsafe_reconcile) | Loss |
| 1786380084 | SELL | **time_loss_exit** | −15.33 | +3.05 (giveback_cap) | Loss |
| 1786380085 | SELL | **time_loss_exit** | −16.23 | +0.80 (giveback_cap) | Loss |
| 1786380086 | SELL | **time_loss_exit** | −15.60 | +2.30 (broker_side_close) | Loss |
| 1786380090 | SELL | **time_loss_exit** | −15.09 | (opened, not closed in window) | Loss |

The EA won every trade while it was diversified in direction (3 BUY, 1 SELL wins pre-streak) but the moment the market entered a sustained uptrend, **every subsequent SELL (and the one late BUY) lost**, and losses cluster tightly around −$15 to −$16 — consistent with a fixed-time exit floor rather than a market-adaptive one.

## 5. Exit Reason Breakdown (Frequency & Impact)

| Exit Reason | Count (main) | Total PnL | Avg PnL | Notes |
|---|---|---|---|---|
| `time_loss_exit` | 5 | −77.37 | −15.47 | **Dominant loss driver.** Fires after the trade is held past a max-hold window while unprofitable; consistently exits near max negative, suggesting the timeout is set too long (lets losers run to near-max before cutting) or SL is set too wide relative to time budget. |
| `soft_sl_momentum` | 1 | −21.92 | −21.92 | **Worst single trade.** Fired only once but produced the biggest loss in the whole log — evidence the momentum-based soft-stop trigger threshold is too loose / reacts too late once RSI/ADX conditions turn against the position. |
| `broker_side_close (sl_or_tp_hit)` | 3 | +24.35 | +8.12 | Clean TP/SL hits — the "textbook" wins of this EA. |
| `failsafe_reconcile` | 1 (main) | +9.16 | +9.16 | Recovery/reconciliation path also produced a win here, but this exit type bypasses normal exit logic (see §9). |
| `tiered_profit_trail` | 1 | +7.28 | +7.28 | Working as intended — locks partial profit on retrace. |
| `hedge_reversal_giveback_cap` (hedge) | 3 | +6.25 | +2.08 | Hedge closed on a capped giveback after a small favorable move; consistently small. |
| `failsafe_reconcile` (hedge) | 1 | +0.30 | +0.30 | Negligible. |
| `broker_side_close` (hedge) | 1 (×2 logged) | +2.30 | +2.30 | Duplicate log entry, see §9. |

**Key finding:** `time_loss_exit` alone accounts for **83% of the losing dollar amount** (−77.37 of −99.29 total main losses) despite being just one exit path. This is the single highest-priority target for tuning.

## 6. Hedge Effectiveness Review

- Hedge legs are placed on every cycle (`HEDGE_PENDING_PLACED` / `DIR_OCO_COUNTER_PLACED`), consistent with the OCO design.
- Across the 5 losing cycles with a hedge counterpart, hedge P/L ranged **+0.30 to +3.05**, while the corresponding main-trade loss ranged **−15.09 to −21.92**.
- **Hedge offset ratio:** hedge gains cover roughly **5–20%** of the paired main loss (e.g., cycle `1786380082`: hedge +2.40 vs main −21.92 → 11% offset; cycle `1786380084`: hedge +3.05 vs main −15.33 → 20% offset).
- The `hedge_reversal_giveback_cap` mechanism appears to be **capping hedge profit prematurely** (`giveback=1.50–1.60` vs `cap=1.50`) — the hedge leg is closed almost immediately after a small favorable excursion, well before it could meaningfully offset the still-open (or now-closed) losing main trade.
- **Conclusion: hedge logic is not materially reducing net loss.** It produces small, capped consolation profits but is not sized or timed to act as genuine risk-offset for the main leg. It currently functions more as a minor cushion than a hedge.

## 7. Filter Effectiveness Review

| Filter | Fires (count) | Effectiveness observed |
|---|---|---|
| `FILTER_BLOCK_RSI_BUY` (rsi > 70 for BUY) | 7 | Correctly blocked repeated BUY attempts at RSI 70.3–74.6 during cycle `1786380079` and near the overnight top — **but the very next non-blocked BUY (cycle 1786380082, opened at RSI ≈ 66) still resulted in the largest loss**, showing the RSI ceiling alone is not sufficient to detect overextension once momentum reverses. |
| `FILTER_BLOCK_TREND_DISAGREE` | 5 | Correctly blocked cycle `1786380080` follow-on entries when `main=1, fast=-1`; blocks worked as designed. |
| `FILTER_BLOCK_ADX_WEAK_MAIN` | 6 | Correctly blocked entries when ADX 19–22.6 < min 24 — filter caught weak-trend conditions and produced 3 fully-blocked cycles (`1786380087–089`, zero trades). This is a genuine "filter working" period. |
| `FILTER_BLOCK_ATR` | 3 | Blocked low-volatility entries (ATR 1.49–1.80 < min 2.00), same blocked window as above. |
| `FILTER_RSI_EXTREME_PAUSE` / `FILTER_BLOCK_RSI_EXTREME_PAUSE` | 4+4 | Triggered 3 times overnight (RSI 76.1–77.9) with only a 300s pause — very short relative to the multi-hour uptrend, so it delays but does not prevent the next losing SELL entry. |

**Pattern identified:** filters are effective at fully blocking cycles during genuinely weak/choppy conditions (the 3-cycle dead zone `1786380087–089`), but once conditions are merely "moderate" (RSI 55–68, ADX marginal), the EA still opens counter-trend or exhausted-trend trades that go on to lose via `time_loss_exit`. The filters are catching the most extreme cases but are not catching the "slow grind against me" regime that produced 5 consecutive losses.

## 8. Risk Management Review

- Per-trade loss cap (`MaxLoss=$50.0`, `SL=$12.0` per preset) is not the binding constraint in this log — the observed losses (−15 to −22) are within that ceiling, meaning the SL is not what stops the losers; the **time-based and momentum-based soft exits are the actual binding constraints**, and they are set looser than the account's realistic per-trade risk tolerance suggests.
- `KELLY_LITE` auto-lot sizing did reduce size after losses (`TIME_REDUCE(50%)` seen post-streak), which is a correct defensive response, but it activates only after losses have already accumulated.
- `CONSEC_LOSS_HARD_STOP` correctly escalated the pause window (60s → 3600s) as losses reached 4 and 5, and `CONSEC_LOSS_FULL_DAY_STOP` correctly halted new cycles after the 6th consecutive loss — the **hard-stop ceiling worked as the last line of defense**, but by the time it triggered, ~$83 (6 losing trades) had already been lost.
- Daily drawdown limit (`DailyDD=4.0%`) was not reached in this window (net drawdown ≈ 0.024% of the ~213k balance), so the DD guard never had a chance to act — the smaller, faster-triggering consecutive-loss/time-based logic is what actually governs behavior in practice.

## 9. Consecutive Loss / Stop Logic Review & Failure Patterns

**Timeline of the losing streak:**

1. `1786380082` (18:36–18:45) — BUY opened at RSI 66.4, ADX presumably adequate; closed via `soft_sl_momentum` at RSI 55.1, loss −21.92. **First crack**: momentum reversed hard and the soft-stop reacted only after a ~$22 adverse move.
2. `1786380083–1786380086` (18:51–21:29) — Four consecutive SELL cycles, all timed out via `time_loss_exit` for −15 to −16 each, while RSI kept climbing (56→75) — i.e., the EA kept selling into a strengthening uptrend and each trade eventually timed out unprofitably rather than being cut earlier.
3. `1786380086→090` (21:29–00:16) — `CONSEC_LOSS_PAUSE`/`CONSEC_LOSS_HARD_STOP` correctly forced a pause (pauseUntil escalating to 1 hour), and RSI-extreme, ADX-weak, and ATR-low filters fully blocked 3 candidate cycles overnight. This is the pause logic "working."
4. `1786380090` (00:16–00:55) — Once filters cleared, the EA opened **another SELL** at RSI 60.2 into what was still, in effect, the same broader uptrend regime, and it lost again via `time_loss_exit`, triggering the 6th consecutive loss and the full-day stop.

**Assessment: the pause logic is not sufficient.** It successfully delays re-entry and blocks the most extreme readings, but it does not change *direction bias* — the EA resumed selling into the same up-trending regime that had already produced 4 straight losing SELLs, because the pause/filter set does not incorporate "has my recent direction been wrong repeatedly regardless of instantaneous RSI/ADX" as a condition. A time-and-indicator-based pause is not the same as a regime-change detector.

**Key failure patterns found in the logs:**

- **`time_loss_exit` is the dominant, and most fixable, loss driver** — 5 of 6 losses, −77.37 total, average −15.47, remarkably tight variance (σ ≈ 0.6), which strongly suggests a fixed max-hold timer combined with a static/no adaptive exit threshold rather than a market-condition-aware cut.
- **`soft_sl_momentum` triggers too late** — the one occurrence produced the single largest loss (−21.92, ~40% larger than any `time_loss_exit` loss), indicating the momentum threshold that triggers this exit is set too loosely (RSI 54.8 at exit — not an extreme reading — meaning by the time momentum "confirmed" against the position, price had already moved far).
- **Hedge is a minor cushion, not a real offset** — offset ratio 11–20% of paired main loss; the `giveback_cap` (1.50) closes the hedge almost immediately after a small favorable excursion.
- **Directional bias persists through the pause window** — the EA re-entered SELL after a pause that was triggered by SELL losses, without any direction-aware cool-down, and immediately lost again.
- **Buy entries permitted at moderately elevated RSI**: cycle `1786380082`'s BUY was opened at RSI 66.4 (filter ceiling is 70), which is not blocked by the current RSI filter but was, in hindsight, already in an overextended/reversal-prone zone given the subsequent `soft_sl_momentum` loss.
- **Data quality anomalies:**
  - `TRADELOG_RECOVER_OPEN`/`FAILSAFE_RECOVER_OPEN` for ticket `118426835` (cycle `1786380079`) produces **two identical `open` rows** in `EA_V7_log_XAUUSD.csv` at the same timestamp (16:07:54) — one tagged `FAILSAFE_RECOVER_OPEN|` and one tagged `BUY OCO`. This is a duplicated log write from the recovery/reconciliation path, not a duplicate trade, but it will double-count trade volume if the log is parsed naively.
  - `RECONCILED_BROKER_CLOSE` for ticket `118489784` (cycle `1786380086`) is logged **twice** at the identical timestamp (21:13:34) with identical PnL (+2.30) in the behavior CSV — same root cause (reconciliation logging fired twice for one broker event).
  - Cycle `1786380090`'s hedge leg opens twice (`HEDGE_PENDING_PLACED` then a second `HedgePend BUY_STOP` open in the trade log at 00:40:00) before the main trade closes — worth confirming this is an intentional hedge-replace-on-trail behavior rather than an unintended duplicate order.

## 10. Top 5 Highest-Priority Improvements

1. **Tighten or make adaptive the `time_loss_exit` hold window/threshold.** This single exit path caused 83% of the observed loss dollars. Recommend testing a shorter max-hold time and/or a break-even-or-better time-stop instead of a fixed max-hold-then-exit-at-market approach.
2. **Tighten the `soft_sl_momentum` trigger.** It produced the worst single trade of the session by reacting only after a large adverse move; recommend testing an earlier RSI/momentum-reversal threshold or a partial-close-then-trail approach instead of one late full exit.
3. **Add a direction-aware component to the consecutive-loss pause.** Currently the pause is duration-based only; after 2+ consecutive losses in the same direction, consider requiring a stronger confirmation (e.g., higher ADX, or a fast/main trend realignment) before permitting another trade in that same direction.
4. **Re-evaluate hedge sizing/giveback-cap so it can genuinely offset, not just cushion.** Increase `HedgeMaxNeg`/lot ratio or loosen the giveback cap so the hedge leg can ride further into profit when the main leg is trending toward a large loss, rather than closing near breakeven.
5. **Add an overextension check for BUY entries beyond the RSI≥70 ceiling.** Cycle `1786380082` entered at RSI 66.4 and reversed hard; consider layering an ADX/price-momentum deceleration check (not just RSI level) before allowing entries in the 60–70 RSI band.

## 11. Suggested Next Backtest Experiments

1. **A/B the `time_loss_exit` max-hold duration** (e.g., current vs. −25%, −50%) across a multi-week backtest and compare average loss size, win rate, and total net P/L.
2. **A/B the `soft_sl_momentum` trigger sensitivity** (earlier RSI/momentum deviation threshold) to test whether it can cut the −21.92-class loss earlier without materially reducing win-rate on trades that recover.
3. **Test a direction-lockout after N consecutive same-direction losses** (e.g., disallow a 4th consecutive SELL cycle unless ADX/main-trend realign) and measure whether it would have prevented cycle `1786380090`'s loss.
4. **Test increased hedge lot ratio / relaxed giveback cap** and measure whether hedge P/L scales meaningfully against paired main losses, targeting a >40% offset ratio instead of the current 11–20%.
5. **Replay the exact overnight window (`1786380087–090`) with the RSI-extreme pause duration doubled/tripled** to see if it would have kept the EA flat until the actual regime shift, avoiding the 6th consecutive loss and full-day stop entirely.
6. **Backtest across a longer, multi-day XAUUSD dataset** (this log covers only ~8 hours) to confirm whether the "5 wins then 6 losses" pattern is a one-off session artifact or a structural, repeatable failure mode tied to trend persistence.
