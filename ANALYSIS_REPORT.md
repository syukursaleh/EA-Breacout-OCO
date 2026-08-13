# ANALYSIS REPORT — EA Breakout OCO (XAUUSD, MT4)

## 1) Ringkasan Metrics per Versi

> Sumber utama: file `*_log_XAUUSD.csv` (aksi `close`).  
> Untuk **V7.1**, metrik diestimasi dari `EA_Breakout_OCO_V7_1_Behavior.csv` (event `POSITION_CLOSED` + `TRADELOG_RECOVER_CLOSE`, parse `pnl=` pada `detail`).

| Version | Trades (close) | Net PnL | Win Rate | Profit Factor | Max Drawdown* | Avg Win | Avg Loss | Max Consecutive Loss |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| V6 | 45 | -91.31 | 51.11% | 0.666 | 125.97 | 7.92 | -12.43 | 4 |
| V7 | 17 | -47.35 | 64.71% | 0.523 | 90.54 | 4.72 | -16.55 | 2 |
| V7.1 (estimasi) | 12 | -76.30 | 50.00% | 0.232 | 95.14 | 3.83 | -16.55 | 3 |
| V7.1a | 77 | +10.02 | 64.94% | 1.028 | 83.96 | 7.23 | -13.02 | 3 |
| V8 | 128 | -59.75 | 60.94% | 0.896 | 89.07 | 6.59 | -11.48 | 5 |

\*Max Drawdown dihitung dari kurva cumulative realized PnL dalam urutan log close.

### Trend penting (V6 → V8)
- **V7.1a** sempat profitable (PF > 1), namun **V8 kembali negatif**.
- Walau win rate V8 masih >60%, **profit factor <1** menandakan average/total loss masih terlalu besar.
- **Max consecutive losses naik ke 5 pada V8**, indikasi overtrading saat edge menurun.

## 2) Root Cause Kerugian (berdasarkan CSV)

### A. Exit loss dominan masih buruk
Di V8, exit reason paling merugikan:
- `soft_sl_momentum`: **19 close, total -197.46**
- `time_loss_exit` / keluarga time-loss di versi sebelumnya juga konsisten buruk

Makna: posisi cut-loss masih terlambat pada fase market tidak mendukung.

### B. SELL side tetap underperform
Dari V7/V7.1a/V8, trade SELL main cenderung lebih lemah dari BUY (net lebih buruk, win-rate lebih rendah/inkonsisten).

### C. Kondisi spread tinggi menurunkan edge
Pada V8, bucket spread menunjukkan:
- spread `<=35`: lebih sehat (win rate & net lebih baik)
- spread `36–40`: performa jauh lebih lemah

### D. Overtrading setelah loss
Consecutive losses yang memanjang (hingga 5 pada V8) menunjukkan perlunya cooldown lebih cepat, bukan hanya menunggu threshold loss beruntun besar.

## 3) Perubahan pada `EA_Breakout_OCO_V9.mq4` dan Justifikasi

Basis: copy dari `EA_Breakout_OCO_V8.mq4`, lalu tuning minimal namun terarah data.

### 3.1 Entry & market quality filters
- `UseTimeFilter`: **false → true**
- `TradeEndHour`: **22 → 18**
- `SellEntryExtraADX`: **3.0 → 5.0**
- `MaxSpreadPoints`: **38 → 35**
- Preset AGGRESSIVE:
  - `P_MainEntryMinADX`: **20.0 → 22.0**
  - `P_MinATR_Dollar`: **2.0 → 2.5**
  - `P_MaxSpreadPoints`: **50 → 35**

**Alasan:** memperketat quality gate entry, terutama SELL dan kondisi spread/volatilitas yang kurang sehat.

### 3.2 Exit loss hardening
- `SoftSL_USD`: **12.0 → 9.0**
- `SoftSL_RSIThresh`: **55 → 58**
- `TimeLossExitMinutes`: **10 → 8**
- `TimeLossExitUSD`: **15.0 → 12.0**
- `TimeLossExit_HardMultiplier`: **1.5 → 1.3**

**Alasan:** mengurangi keterlambatan cut-loss yang pada data jadi kontributor rugi terbesar.

### 3.3 Kurangi overtrading setelah loss
- Tambah input baru: `LossCooldownAfterLossSec = 300`
- Tambah logik di `RecordCycleResult()`:
  - Set `g_lossPauseUntil` selepas setiap cycle rugi (`cyclePnL < -1.0`)
  - Log event: `LOSS_COOLDOWN_AFTER_LOSS`

**Alasan:** cooldown ringan selepas rugi untuk memutus loss clustering sebelum mencapai hard-stop beruntun.

### 3.4 Risk scaling SELL
- `SellLotMult`: **0.85 → 0.75**

**Alasan:** data menunjukkan SELL masih sisi yang lebih lemah; lot SELL diperkecil untuk menurunkan downside tail risk.

### 3.5 Metadata/version update
- File baru: `EA_Breakout_OCO_V9.mq4`
- `#property version`: `9.0`
- `EA_Name`: `EA_Breakout_OCO_V9`
- `CSV_FileName`: `EA_Breakout_OCO_V9_Behavior.csv`
- `EA_INIT` log label: `V9`

## 4) Catatan OCO Core Strategy
- Core breakout + OCO tetap dipertahankan.
- Logik OCO cancel lawan saat trigger tetap digunakan dari V8 (tidak dirombak total), perubahan difokuskan ke quality filter, risk, dan loss-exit sesuai pola CSV.

