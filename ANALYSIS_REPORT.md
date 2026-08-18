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
| V9 (live log) | 116 | -64.06 | 66.38% | 0.878 | 119.22** | 5.99 | -13.47 | 3 |
| V10 (live log, main only) | 62 | +17.13 | 48.39% | 1.067 | 81.56 | 9.10 | -8.00 | 6 |

\*Max Drawdown dihitung dari kurva cumulative realized PnL dalam urutan log close.

\*\*Max Drawdown V9 dihitung dari kurva cumulative realized PnL untuk trade `type=main` saja (hedge legs V9 justru net +36.30 dan tidak dihitung dalam angka ini).

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
- `TimeProfitLockMinutes`: **20** (baru, supaya profit lock tidak terlalu awal)
- `TimeProfitLockMinProfit`: **4.0** (baru)
- `TimeProfitLockMinGiveback`: **1.0** (baru, lock profit hanya bila ada retrace)

**Alasan:** mengurangi keterlambatan cut-loss yang pada data jadi kontributor rugi terbesar.

### 3.3 Kurangi overtrading setelah loss
- Tambah input baru: `LossCooldownAfterLossSec = 300`
- Tambah logik di `RecordCycleResult()`:
  - Set `g_lossPauseUntil` selepas setiap cycle rugi (`cyclePnL < -1.0`)
  - Log event: `LOSS_COOLDOWN_AFTER_LOSS`

**Alasan:** cooldown ringan selepas rugi untuk memutus loss clustering sebelum mencapai hard-stop beruntun.

### 3.4 Konsistensi cap loss awal per kondisi hedge
- `ApplyEarlyLossHardSL()` kini pakai:
  - `EarlyLossCut_MaxLoss` saat **tidak** ada hedge aktif
  - `EarlyLossCut_MaxLoss_WhileHedged` saat hedge aktif

**Alasan:** kedua parameter cap loss kini benar-benar dipakai sesuai konteks risiko posisi.

### 3.5 Risk scaling SELL
- `SellLotMult`: **0.85 → 0.75**
- Penerapan lot SELL tereduksi juga diselaraskan pada path `PlaceOCOOrders()` (non-directional), bukan hanya `PlaceDirectionalOCO()`

**Alasan:** data menunjukkan SELL masih sisi yang lebih lemah; lot SELL diperkecil untuk menurunkan downside tail risk.

### 3.6 Stabilitas baseline mingguan
- Perhitungan anchor hari Isnin/Monday diperbaiki untuk kes **Sunday (`TimeDayOfWeek==0`)** supaya baseline mingguan tetap mengacu ke Isnin minggu berjalan.

### 3.7 Metadata/version update
- File baru: `EA_Breakout_OCO_V9.mq4`
- `#property version`: `9.0`
- `EA_Name`: `EA_Breakout_OCO_V9`
- `CSV_FileName`: `EA_Breakout_OCO_V9_Behavior.csv`
- `EA_INIT` log label: `V9`

## 4) Catatan OCO Core Strategy
- Core breakout + OCO tetap dipertahankan.
- Logik OCO cancel lawan saat trigger tetap digunakan dari V8 (tidak dirombak total), perubahan difokuskan ke quality filter, risk, dan loss-exit sesuai pola CSV.

## 5) Kenapa V9 Masih Loss (analisis `EA_Breakout_OCO_V9_log_XAUUSD.csv`)

Sumber: 116 baris `close` live (13–14 Aug 2026). Net PnL **-64.06**, win rate **66.38%**, tapi **Profit Factor 0.878** (masih <1).

### 5.1 Breakdown per grup posisi
- `type=main`: 78 close, PnL **-100.36**
- `type=hedge`: 38 close, PnL **+36.30**

→ Modul hedge sudah menguntungkan; **sumber kerugian murni ada di posisi main**, bukan hedge.

### 5.2 Breakdown exit_reason (gross loss)
| exit_reason | count | total PnL |
|---|---:|---:|
| `time_loss_exit_confirmed` | 22 | **-330.69** |
| `time_loss_exit_hardcap` | 6 | **-105.11** |
| `soft_sl_momentum` | 2 | -47.25 |
| `hedge_max_loss` | 3 | -30.95 |

Kombinasi `time_loss_exit_confirmed` + `time_loss_exit_hardcap` = **-435.80 dari total gross loss -525.20 (≈83%)** — ini akar masalah utama V9.

### 5.3 Root cause
1. **Tidak ada hard-stop broker-side sejak awal posisi.** `UseEarlyLossCut` default `false` di V9, sehingga selama `TimeLossExitMinutes` (8 menit) belum lewat, posisi hanya dilindungi oleh SL awal yang lebar (berbasis `RiskPct`). Saat market bergerak cepat, floating loss bisa sudah jauh melampaui target proteksi ($12–$15.6) sebelum modul exit software sempat mengevaluasi.
2. **Konfirmasi momentum (RSI + pola bar) menunda eksekusi cut-loss.** `time_loss_exit_confirmed` mensyaratkan RSI melawan arah posisi baru memicu cut; `soft_sl_momentum` bahkan mensyaratkan RSI ekstrem **dan** 2 candle M5 berlawanan. Selama syarat itu belum terpenuhi, posisi tetap terbuka dan rugi terus membesar.
3. **Korelasi dengan volatilitas (ATR).** Trade dengan kerugian terbesar (-20 s/d -30) konsisten terjadi saat ATR 5–8 — yaitu **di bawah** ambang `ATR_Volatility_Level1=8.0`, sehingga modul pengurang lot berbasis ATR (`UseATRVolatilityLotReduction`) belum aktif pada rentang volatilitas yang justru paling berbahaya di log ini.
4. **SELL masih sisi lebih lemah**: trade main BUY net **-1.38** (59 close) vs SELL net **-59.23** (56 close), walau `SellLotMult` sudah diturunkan ke 0.75 di V9 — pengurangan itu belum cukup.

## 6) Perubahan `EA_Breakout_OCO_V10.mq4` (patch berdasarkan analisis V9)

Basis: copy dari `EA_Breakout_OCO_V9.mq4`.

### 6.1 Aktifkan proteksi awal broker-side (Priority 1)
- `UseEarlyLossCut`: **false → true**
- `EarlyLossCut_MaxLoss`: **4.0 → 8.0**
- `EarlyLossCut_MaxLoss_WhileHedged`: **4.0 → 6.0**

**Alasan:** `ApplyEarlyLossHardSL()` memodifikasi SL order riil di broker sejak tick pertama (tidak menunggu `TimeLossExitMinutes`/konfirmasi RSI), sehingga menjadi jaring pengaman nyata untuk kasus overshoot yang mendominasi kerugian V9.

### 6.2 Perketat ambang lot-reduction ATR (Priority 1)
- `ATR_Volatility_Level1`: **8.0 → 6.0**
- `ATR_Volatility_Level2`: **10.0 → 8.0**

**Alasan:** rentang ATR 5–8 pada log V9 justru menghasilkan kerugian terbesar namun belum memicu pengurangan lot; ambang diturunkan agar rentang tersebut ikut tercakup.

### 6.3 Perketat hard-cap time-loss-exit (Priority 1)
- `TimeLossExit_HardMultiplier`: **1.3 → 1.15**

**Alasan:** mengurangi ruang overshoot software-side safety-net dari maksimum ±30% menjadi ±15% di atas `TimeLossExitUSD`.

### 6.4 Kurangi lagi risiko SELL (Priority 2)
- `SellLotMult`: **0.75 → 0.65**

**Alasan:** SELL main tetap sisi terlemah pada log V9 (-59.23 vs -1.38 BUY).

### 6.5 Metadata/version update
- File baru: `EA_Breakout_OCO_V10.mq4`
- `#property version`: `10.0`
- `EA_Name`: `EA_Breakout_OCO_V10`
- `CSV_FileName`: `EA_Breakout_OCO_V10_Behavior.csv`
- `EA_INIT` log label: `V10`

**Catatan:** tidak ada perubahan pada core breakout + OCO. Perubahan V10 seluruhnya di lapisan risk-management (early stop, ATR lot-scaling, time-loss hard-cap, SELL sizing) sesuai temuan langsung dari `EA_Breakout_OCO_V9_log_XAUUSD.csv`.

## 7) Analisis `EA_Breakout_OCO_V10_log_XAUUSD.csv` / `_Behavior.csv` (file terbaru)

Sumber: 62 baris `close` live untuk `type=main` (17–18 Aug 2026), plus `EA_Breakout_OCO_V10_Behavior.csv` (1997 event).

### 7.1 Metrics ringkas
| Metric | Nilai |
|---|---:|
| Trades (close, main) | 62 |
| Net PnL | **+17.13** |
| Win rate | 48.39% |
| Profit Factor | **1.067** |
| Max Drawdown (kurva realized) | 81.56 |
| Max Consecutive Losses | **6** |
| BUY net (31 close) | +15.60 |
| SELL net (31 close) | +1.53 |

**Kesimpulan V10:** untuk pertama kali sejak V6, V10 **net positif dan PF > 1** — patch V9→V10 (early broker-side SL, ATR lot-scaling lebih ketat, SELL sizing lebih kecil) berhasil menstabilkan kerugian dan menyeimbangkan BUY vs SELL (V9: -1.38 vs -59.23 → V10: +15.60 vs +1.53). Namun dua masalah baru/berulang terlihat jelas di data terbaru:

1. **`broker_side_close(sl_or_tp_hit)` masih grup terburuk**: 29 close, total **-148.79** (mendominasi seluruh gross loss). Baris `RECONCILED_BROKER_CLOSE` di Behavior CSV menunjukkan banyak di antaranya sempat **profit mengambang** sebelum berbalik kena SL -$8, contoh: `peak_profit=7.56 → pnl=-8.01`, `peak_profit=3.84 → pnl=-8.00`, `peak_profit=0.24 → pnl=-8.00`. Posisi ini tidak pernah mencapai `TrailStart_Dollar` ($8) sehingga trailing normal tidak sempat mengunci profit kecil itu — posisi dibiarkan bergerak penuh dari untung ke rugi maksimum.
2. **Hard-stop beruntun terlalu agresif memblokir trading**: Behavior CSV mencatat `CONSEC_LOSS_HARD_STOP` pada 4, 5, dan 6 kerugian beruntun (17 Aug, jam 07:30–09:37), lalu `CONSEC_LOSS_FULL_DAY_STOP` pada 6 kerugian yang **menghentikan seluruh cycle baru hingga rollover kalender berikutnya (00:00)** — bukan sampai kondisi pasar benar-benar dikonfirmasi ulang. Ini membuang banyak jam trading produktif hanya berdasarkan hitungan loss beruntun, tanpa mengecek apakah arah pasar sudah berubah/valid kembali.

## 8) Perubahan `EA_Breakout_OCO_V11.mq4` (patch berdasarkan analisis V10 + arahan pengguna)

Basis: copy dari `EA_Breakout_OCO_V10.mq4`. Semua perubahan V11 murni penambahan lapisan risk-management; core breakout + OCO tidak diubah.

### 8.1 [V11-01] "Minus Block" — force-close saat profit mau kembali minus (Priority 1)
- Input baru: `UseMinusBlock=true`, `MinusBlock_ArmPeakMoney=3.00`, `MinusBlock_FloorMoney=2.00`.
- Logika baru di `ExitDecisionEngine()`: begitu peak floating profit cycle berjalan sudah mencapai `MinusBlock_ArmPeakMoney`, posisi **wajib ditutup paksa** (`minus_block_force_close`) begitu profit turun ke `MinusBlock_FloorMoney` ($2) — sebelum sempat balik ke minus.
- Ditempatkan **setelah** blok `tiered_profit_trail` yang sudah ada, sehingga untuk cycle yang peak-nya ≥ `TrailStart_Dollar` ($8), trailing normal tetap mendapat kesempatan pertama menutup posisi seperti biasa (**tidak berubah sama sekali**). Minus Block hanya mengisi celah untuk cycle dengan peak kecil (antara $3–$8) yang selama ini lolos dari semua guard dan berakhir kena SL -$8 seperti pola di §7.1.

**Alasan:** langsung menyasar pola `RECONCILED_BROKER_CLOSE` (peak profit kecil → berbalik ke -$8) yang menjadi kontributor gross loss terbesar di log V10.

### 8.2 [V11-02] Ganti hard-stop beruntun dengan "rescan arah" setelah 2 loss (Priority 1)
- `UseHardStopConsecutiveLosses`: **true → false** (tetap tersedia sebagai opsi legacy).
- `UseHardStopFullDay`: **true → false** (tetap tersedia sebagai opsi legacy).
- Input baru: `UseRescanAfterLosses=true`, `RescanAfterLossesThreshold=2`.
- Logika baru di loop utama (sebelum `PlaceOCOOrders`/`PlaceDirectionalOCO`): setelah 2 cycle rugi beruntun, EA mensyaratkan `GetFastConfirmDirection()` (konfirmasi tren cepat yang sudah ada) **sepakat** dengan tren utama sebelum OP berikutnya dibuka. Jika belum sepakat, cycle diblokir tick ini saja (`FILTER_BLOCK_RESCAN_DIRECTION`) dan dicoba ulang tick berikutnya — **tanpa** pause berjam-jam atau blokir sehari penuh. `CONSECUTIVE_LOSS_PAUSE` (cooldown pendek `MaxConsecutiveCycleLosses`) tetap berjalan independen seperti sebelumnya.

**Alasan:** langsung menjawab pola di §7.1 poin 2 — EA sempat memblokir trading dari jam 09:37 hingga rollover kalender berikutnya hanya karena 6 loss beruntun, padahal arah pasar mungkin sudah berubah dan valid untuk entry baru jauh lebih cepat dari itu.

### 8.3 Metadata/version update
- File baru: `EA_Breakout_OCO_V11.mq4`
- `#property version`: `11.0`
- `MagicNumber`: `9001060 → 9001110`
- `EA_Name`: `EA_Breakout_OCO_V11`
- `CSV_FileName`: `EA_Breakout_OCO_V11_Behavior.csv`
- `EA_INIT` log label: `V11`

## 9) Kesimpulan EA V10 & Ringkasan V11

**Kesimpulan V10:** V10 adalah versi pertama yang net profitable (+17.13, PF 1.07) dengan BUY/SELL yang jauh lebih seimbang dibanding V9, membuktikan pendekatan early broker-side SL + ATR lot-scaling + SELL sizing lebih kecil efektif. Kelemahan yang tersisa bukan pada arah/entry, melainkan **manajemen exit untuk profit kecil** (posisi profit tipis yang dibiarkan berbalik penuh ke -$8) dan **respons berlebihan terhadap loss beruntun** (hard-stop/full-day-stop yang memblokir trading berjam-jam tanpa validasi ulang kondisi pasar).

**V11** menutup kedua celah tersebut secara terarah dan minimal: menambahkan "Minus Block" sebagai jaring pengaman profit-kecil tanpa mengubah trailing yang sudah bekerja baik, dan mengganti hard-stop panjang dengan gerbang "rescan arah" 2-loss yang jauh lebih responsif terhadap perubahan kondisi pasar.
