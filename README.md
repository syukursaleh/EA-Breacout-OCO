# EA-Breacout-OCO
EA Breacout OCO V6 - MT4 Expert Advisor Development

## Versions
- `EA_Breakout_OCO_V7.mq4` - baseline V7.0.
- `EA_Breakout_OCO_V7_1.mq4` - V7.1 patch: adds a hard "Minus Block" (`UseMinusBlock`/`MinusBlockUSD`,
  default $20), an unconditional, time-independent floating-loss circuit breaker checked with top
  priority on every tick. Analysis of `EA_V7_log_XAUUSD.csv` showed every losing trade in V7.0 only
  exited via `time_loss_exit`, which is gated behind a 10-minute hold time, letting one trade run to
  -$30.18 (2x the intended -$15 cap) before it could close.
