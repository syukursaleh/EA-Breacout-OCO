# Optimization Checklist — EA_Breakout_OCO V7.1 (XAUUSD)

Derived from: `docs/analysis/2026-08-11-xauusd-ea-v7-analysis.md`
Scope: documentation/planning only — **no code or parameter changes have been made in this task**.

## A. Actionable Checklist

- [ ] **Reduce or make adaptive the `time_loss_exit` max-hold window.** It caused 5 of 6 losses (avg −15.47, total −77.37). Test shorter hold times and confirm net P/L improves without materially cutting win rate.
- [ ] **Add a break-even-or-trail rule before the hard time-based exit fires**, so a trade that reached partial profit before turning negative doesn't fully round-trip to a fixed max loss.
- [ ] **Tighten the `soft_sl_momentum` trigger threshold.** It fired once but produced the largest single loss (−21.92) at RSI 54.8 (not extreme) — test an earlier trigger point.
- [ ] **Test a partial-close-then-trail approach for momentum reversals** instead of one full exit, to reduce the "too late" effect.
- [ ] **Add a direction-lockout after repeated same-direction consecutive losses**, independent of the fixed-duration pause (e.g., block a 4th consecutive SELL unless ADX/trend realign).
- [ ] **Re-tune `CONSEC_LOSS_PAUSE` durations** — current escalation (60s → 300s → 3600s) still allowed a losing SELL to repeat in the same regime; test longer initial pauses or regime-confirmation gating.
- [ ] **Re-tune hedge sizing (`LotRatio`, `HedgeMaxNeg`) and `giveback_cap`.** Current hedge offset is only 11–20% of the paired main loss; target should be materially higher if hedge is meant to reduce net loss rather than just cushion it.
- [ ] **Add an overextension/momentum-deceleration check for entries in the 60–70 RSI band** (not just a hard RSI≥70 ceiling) — cycle `1786380082`'s BUY at RSI 66.4 preceded the worst loss.
- [ ] **Confirm ADX/ATR filter thresholds (`min=24`, `min=2.00`) are optimal** — they correctly produced a 3-cycle no-trade zone; verify via backtest that these thresholds aren't too loose in other regimes.
- [ ] **Investigate and fix duplicate log-write behavior** in the recovery/reconciliation path (`FAILSAFE_RECOVER_OPEN`/`TRADELOG_RECOVER_OPEN` and duplicate `RECONCILED_BROKER_CLOSE` rows) so future log-based analysis isn't at risk of double-counting trades — confirm whether this is log-only duplication or reflects duplicate broker-side actions.
- [ ] **Verify the double hedge-open at cycle `1786380090`** (00:16 and 00:40) is intentional trail/replace behavior, not an unintended duplicate pending order.
- [ ] **Re-run this analysis against a longer (multi-day/multi-week) log** to confirm the 5-win/6-loss pattern is structural and not a short-session artifact.

## B. Parameter Ideas to Retest (backtest only, not applied yet)

| Parameter | Current | Ideas to test |
|---|---|---|
| `time_loss_exit` max-hold duration | Held 14–39 min before exit in losses | −25%, −50% shorter hold; or hold-with-breakeven-trail |
| `soft_sl_momentum` trigger sensitivity | Fired at RSI 54.8, after −21.92 move | Earlier deviation threshold; partial close at first reversal signal |
| `CONSEC_LOSS_PAUSE` durations | 60s → 300s → 3600s (escalating) | Longer initial pause (e.g., 300s → 900s → 3600s+); add direction-aware gating |
| `HedgeMaxNeg` / hedge `LotRatio` | $10.0 / 1.25 | Increase ratio (e.g., 1.5–2.0) to test larger genuine offset |
| Hedge `giveback_cap` | 1.50 | Loosen (e.g., 2.5–3.0) to let hedge ride further before capping |
| RSI BUY ceiling | 70.0 | Add secondary momentum/ADX check in 60–70 band, not just hard ceiling |
| `FILTER_RSI_EXTREME_PAUSE` duration | 300s | Test 600–900s given multi-hour regime persistence observed |
| `ADX` weak-main minimum | 24.0 | Backtest sensitivity across 20–28 range |
| `ATR` minimum | 2.00 | Backtest sensitivity across 1.5–2.5 range |

## C. Logic Areas to Review in Code Later (no changes made yet)

- [ ] Time-based exit (`time_loss_exit`) calculation path — confirm whether hold-duration and exit-price logic use a static timer vs. any market-condition input.
- [ ] Momentum-based soft-stop (`soft_sl_momentum`) trigger condition — review the RSI/momentum deviation formula and confirm the lag between signal and execution.
- [ ] Hedge reversal/giveback-cap logic (`hedge_reversal_giveback_cap`) — review cap sizing relative to paired main-trade risk, not just a fixed dollar/point cap.
- [ ] Consecutive-loss pause logic (`CONSECUTIVE_LOSS_PAUSE` / `CONSEC_LOSS_HARD_STOP` / `CONSEC_LOSS_FULL_DAY_STOP`) — review whether direction of prior losses is considered when re-arming after a pause.
- [ ] RSI/ADX/ATR filter gating — review whether these filters interact (e.g., combined score) vs. independent hard cutoffs, and whether a "moderate but wrong-direction" regime can be detected.
- [ ] Failsafe/reconciliation logging path (`FAILSAFE_RECOVER_OPEN`, `TRADELOG_RECOVER_OPEN/CLOSE`, `RECONCILED_BROKER_CLOSE`) — review for duplicate log-write issue identified in the analysis.
- [ ] Hedge pending re-placement logic around trailing stops — confirm no unintended duplicate hedge orders are created when the main stop trails.
