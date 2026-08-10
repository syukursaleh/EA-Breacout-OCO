//+------------------------------------------------------------------+
//| EA_Breakout_OCO_V7_1.mq4                                      |
//| Breakout OCO Cycle Engine V7.1 (Optimized Risk/Trail)           |
//+------------------------------------------------------------------+
//
// V7 CHANGELOG (from V6.47):
// [V7-01] Reversal-flip protection: aggressive BE/lock ($1.0 start, $0.5 lock), tight trailing, fast loss exit
// [V7-02] ATR volatility lot scaling: auto-reduce lots at high ATR levels (Level1/Level2 tiers)
// [V7-03] RSI entry gates: block BUY if RSI>70, block SELL if RSI<30; extreme pause RSI>75/<25
// [V7-04] Time-based lot reduction: 50% lot reduction after hour 17:00 (MaxLossHourStart)
// [V7-05] Order lifecycle logging: complete open/close trade logging with lifecycle markers
//
// V7.1 CHANGELOG (behavior fixes from analysis of live behavior/log CSV):
// [V7.1-01] HEDGE_BLOCK_MINUS_CAP was logged on every tick with no throttle, flooding the
//           behavior log (>96% of all log rows in observed sessions, e.g. 57471/59338 rows).
//           Now throttled like the other hedge-block events (logged at most once every 30s).
// [V7.1-02] Hedge worst-case cap (HedgeBlockMinusMaxLossDollar) and hedge SL distance
//           (HedgeSL_Dollar) were fixed inputs that did not scale with PresetMode, while
//           HedgeLotRatio does scale per preset. Under BALANCED/AGGRESSIVE presets this caused
//           the hedge to be blocked almost permanently (hedge lot's worst case routinely
//           exceeded the fixed $10 cap), silently disabling the hedge safety net. Both values
//           are now preset-scaled (P_HedgeSL_Dollar / P_HedgeBlockMinusMaxLossDollar).
//+------------------------------------------------------------------+
#property strict
#property version   "7.1"
#property description "Breakout OCO V7.1 - Reversal Protection, ATR Lots, RSI Gates, Lifecycle Log, Hedge Fix"

//============================== INPUTS ==============================
// --- General ---
input int      MagicNumber              = 9001061;
input string   EA_Name                  = "EA_Breakout_OCO_V7_1";
input bool     PrintDebug               = true;

// --- [V6-01] Preset Mode ------------------------------------------
input int      PresetMode              = 3;

// --- Lot / Money Management ---
input double   Lots                     = 0.01;
input bool     UseAutoLot               = true;
input int      AutoLotMode              = 3;
input double   AutoLotPer1000           = 0.10;
input double   RiskPercent              = 1.0;
input double   MinLotInput              = 0.01;
input double   MaxLotInput              = 5.00;
input bool     CapLotByMaxLossMoney     = true;
input double   MaxLossMoney             = 50.0;   
input double   HardRiskCapPct           = 2.0;
input bool     UseEmergencyTotalRiskCap = true;
input double   EmergencyTotalRiskCapPct = 6.0;

// --- [V6-03] Money Management V6 ---
input bool     UseDailyDrawdownPct      = true;
input double   MaxDailyDrawdownPct      = 4.0;    
input bool     UseWeeklyLossLimit       = true;
input bool     UseWeeklyLossLimitPct    = true;
input double   MaxWeeklyLossPct         = 3.0;
input double   MaxWeeklyLossMoney       = 100.0;
input int      Kelly_LookbackTrades     = 20;
input double   Kelly_MinLotMult         = 0.30;
input double   Kelly_MaxLotMult         = 1.50;
input double   Kelly_BaseWinrate        = 0.50;

// --- Entry / Exit Distance ---
input bool     UseATRDistance            = true;
input double   ATR_DistanceMultiplier    = 0.40;
input double   PendingDistance_Dollar    = 3.0;
input double   InitialSL_Dollar          = 12.0;   
input bool     UseDynamicSL             = true;
input double   DynamicSL_ATR_Multiplier = 1.5;
input double   DynamicSL_Min            = 15.0;   
input double   DynamicSL_Max            = 25.0;   
input double   TakeProfit_RR             = 1.5;
input double   MinPendingDistance        = 1.5;
input double   MaxPendingDistance        = 12.0;

// --- Trend Filter ---
input bool     UseTrendFilter            = true;
input int      TrendFilterMethod         = 0;
input bool     UseMainEntryADXFilter     = true;
input double   MainEntryMinADX           = 20.0;   
input int      Trend_Timeframe           = PERIOD_M5;
input int      FastEMA                   = 20;
input int      SlowEMA                   = 50;
input bool     UseFastTrendConfirm       = true;
input int      FastConfirm_Timeframe     = PERIOD_M1;
input int      FastConfirmEMA            = 13;
input int      SlowConfirmEMA            = 34;
input double   FastConfirm_MinSepATRMult = 0.15;
input double   TrendMinSepATRMult        = 0.15;
input int      ADX_Period                = 14;
input double   ADX_Threshold             = 25.0;

// --- Time Filter ---
input bool     UseTimeFilter             = false;
input int      TradeStartHour            = 7;
input int      TradeStartMinute          = 0;
input int      TradeEndHour              = 22;
input int      TradeEndMinute            = 0;
input bool     SkipMondayFirstHours      = true;
input int      MondaySkipHours           = 2;

// --- [V6-05] Session Filter ---
input int      SessionFilter            = 0;

// --- [V6-04] News Filter ---
input bool     UseNewsFilter            = false;
input string   NewsTimesCSV             = "";
input int      NewsPauseMinutesBefore   = 15;
input int      NewsPauseMinutesAfter    = 15;

// --- Exit / Protection ---
input double   BE_Start_Dollar           = 8.0;    // [V6.46 FIX] Naikkan dari 5.0 ke 8.0
input double   BE_Lock_Dollar            = 5.0;    // [V6.46 FIX] Naikkan dari 1.0 ke 5.0
input bool     UseReversalFlipProtection  = true;
input double   ReversalBE_Start_Dollar    = 1.0;
input double   ReversalBE_Lock_Dollar     = 0.5;
input double   ReversalTrailStart_Dollar  = 1.0;
input double   ReversalTrailRetrace_Dollar= 1.0;
input double   ReversalFastLossExit_Dollar= 3.0;
input int      ReversalFastLossExit_Minutes = 2;
input double   TrailStart_Dollar         = 8.0;    
input double   TrailDrop_Money           = 8.0;
input double   FastProfitStart_Money     = 6.0;
input double   FastProfitRetracePct      = 72.0;
input double   TrailDrop_SmallPeak       = 2.00;   // [V6.46 FIX] Ketatkan dari 3.00 ke 2.00
input double   TrailDrop_MedPeak         = 5.00;   
input double   TrailDrop_LargePeak       = 8.00;   
input double   TrailRetracePct_Small     = 25.0;   // [V6.46 FIX] 55.0 -> 25.0
input double   TrailRetracePct_Med       = 25.0;   // [V6.46 FIX] 40.0 -> 25.0
input double   TrailRetracePct_Large     = 20.0;   // [V6.46 FIX] 25.0 -> 20.0
input bool     UseTrendAdaptiveTrail     = true;
input double   TrendIntactTrailMult      = 1.30;
input double   TrendWeakTrailMult        = 0.60;
input double   MedPeakBoundary_Dollar    = 8.0;    
input double   LargePeakBoundary_Dollar  = 20.0;   
input bool     UseProfitRatchetSL        = true;
input double   ProfitRatchetLockFraction = 0.50;
input int      MaxHoldMinutes            = 60;
input double   TimeExitMinProfit         = -1.0;
input double   TimeExitMaxProfit         = 2.0;

// --- Early Loss Cut ---
input bool     UseEarlyLossCut          = false;  
input double   EarlyLossCut_NoPeakAbove = 6.0;
input double   EarlyLossCut_MaxLoss     = 4.0;
input double   EarlyLossCut_MaxLoss_WhileHedged = 4.0; 
input bool     UseTrendFlipExit               = false; 
input double   TrendFlipExit_MinPeakToIgnore  = 8.0;

// --- [V6.46 NEW] Smart Early Exit (SoftSL) ---
input bool     UseSoftSL_Momentum       = true;
input double   SoftSL_USD               = 20.0;   // Exit jika floating -$20 DAN momentum against
input int      SoftSL_RSIThresh         = 55;     // RSI kontra < 55

// --- [V6.46 NEW] Time-based Stop Loss ---
input int      TimeLossExitMinutes      = 10;      // Auto cut loss jika held > 10 menit
input double   TimeLossExitUSD          = 15.0;    // Dan floating di -$15

// --- [V6.46 NEW] Time-based Lot Reduction ---
input int      MaxLossHourStart         = 17;      // Reduksi lot 50% setelah jam 17:00 (post-NY)
input int      MaxLossHourEnd           = 22;

// --- [V6.47 PATCH] ATR Volatility Lot Reduction ---
input bool     UseATRVolatilityLotReduction = true;
input double   ATR_Volatility_Level1      = 8.0;
input double   ATR_Volatility_Level2      = 10.0;
input double   ATR_Volatility_Multiplier1 = 0.75;
input double   ATR_Volatility_Multiplier2 = 0.50;

// --- V1D Profit Guard ---
input bool     UseV1DProfitLockGuard      = true;
input double   V1D_MicroProfitStartMoney  = 10.00;
input double   V1D_MicroProfitLockMoney   = 6.00;
input double   V1D_ProfitToLossCutMoney   = 4.00;
input double   V1D_MaxLossAfterProfit     = 8.00;
input bool     UseV1DLotRiskSync          = true;
input bool     V1D_BlockIfMinLotTooRisky  = false;
input double   V1D_MinProfitPeakForTightLoss = 999.0;
input double   V1D_TightLossAfterSmallPeak   = 8.00;
input bool     UseV1DStrictOCOCleanup      = true;

// --- Pyramid ---
input bool     UsePyramid                = false;  
input int      PyramidMaxPositions       = 2;
input double   PyramidMinPriceMove       = 4.00;
input double   PyramidMaxPriceMove       = 6.00;
input bool     UsePyramidDynamicDistance = true;
input double   PyramidMinATRMult         = 0.7;
input double   PyramidMaxATRMult         = 1.1;
input double   PyramidMinMoveDollar      = 2.0;
input double   PyramidSameLotRatio       = 1.0;
input bool     PyramidRecheckTrend       = true;
input double   PyramidMinADX             = 20.0;   
input int      PyramidCooldownSeconds    = 60;
input bool     UsePyramidIndividualTrail = false;
input double   PyramidLegTrailStart_Dollar = 1.50;
input double   PyramidLegMaxLoss           = 2.50;

// --- [V6.49 NEW] SL protection robustness ---
input int      MinStopBufferPoints      = 15;     // [V6.46 FIX] Naikkan dari 15 agar aman dari err=0
input int      UnprotectedForceCloseSec = 20;    

// --- Filters ---
input int      MaxSpreadPoints           = 45;
input int      SlippagePoints            = 30;
input bool     UseATRFilter              = true;
input int      ATR_Period                = 14;
input double   MinATR_Dollar             = 2.0;    
input int      OrderRetryMax             = 3;
input int      OrderRetryDelayMs         = 300;

// --- Daily $ loss ---
input bool     UseDailyLossLimit        = false;
input double   DailyLossLimit           = 35.0;

// --- Cycle ---
input bool     AutoRestartCycle          = true;
input int      RestartDelaySeconds       = 300;    
input int      PendingExpireMinutes      = 20;
input bool     EnableCSVLog              = true;
input string   CSV_FileName              = "EA_Breakout_OCO_V7_Behavior.csv";
input bool     EnforceSingleInstance     = true;

// --- Pending trail ---
input bool     TrailPendingOrders        = true;
input double   PendingTrailMinMove       = 0.30;
input int      PendingTrailMaxModifications = 50;

// --- Consecutive Loss Limiter ---
input int      MaxConsecutiveCycleLosses = 3;      
input int      ConsecutiveLossPauseSec   = 900;    
input bool     UseConsecLossLotReduction = true;
input double   ConsecLossLotReduce2      = 0.50;
input double   ConsecLossLotReduce3      = 0.50;
input bool     UseHardStopConsecutiveLosses = true;
input int      HardStopConsecutiveLosses    = 4;
input int      HardStopPauseSec             = 3600; 
input bool     UseHardStopFullDay        = true;
input int      HardStopFullDayThreshold  = 6;      
input bool     UseAdaptiveADXOnLosses    = true;
input double   AdaptiveADXStepPerLoss    = 1.0;    
input double   MaxAdaptiveADXAdd         = 4.0;    

// --- RSI ---
input bool     UseRSIFilter              = true;
input int      RSI_Period               = 14;
input double   RSI_Oversold             = 15.0;   
input double   RSI_Overbought           = 85.0;   
input bool     UseEntryRSIFilter         = true;
input double   EntryRSI_BuyMax           = 70.0;
input double   EntryRSI_SellMin          = 30.0;
input double   EntryRSI_ExtremeHigh      = 75.0;
input double   EntryRSI_ExtremeLow       = 25.0;
input int      EntryRSI_ExtremePauseSec  = 300;

// --- Mean Reversion ---
input bool     UseMeanReversionEntry     = false;  
input double   MR_RSI_Oversold           = 25.0;
input double   MR_RSI_Overbought         = 75.0;
input double   MR_MaxADXForEntry         = 20.0;
input double   MR_Lot                    = 0.01;
input double   MR_SL_Dollar              = 3.00;
input double   MR_TP_Dollar              = 3.00;
input int      MR_MaxConsecutiveLosses   = 2;
input int      MR_LossPauseSec           = 900;

// --- Range Bound ---
input bool     UseRangeBoundEntry        = false;  
input int      Range_LookbackBars        = 24;
input double   Range_MaxADXForEntry      = 20.0;
input double   Range_MinSizeATRMult      = 1.5;
input double   Range_MaxSizeATRMult      = 5.0;
input double   Range_EdgeATRMult         = 0.35;
input double   Range_Lot                 = 0.01;
input double   Range_SL_Dollar           = 4.00;
input double   Range_TP_Dollar           = 6.00;
input int      Range_MaxConsecutiveLosses = 2;
input int      Range_LossPauseSec        = 900;

// --- Dual Sided OCO & Chaser ---
input bool     UseDualSidedOCO           = true;
input double   CounterSideLotMult        = 0.5;
input bool     UseReversalChaser         = false;  
input double   ChaserDistance            = 2.00;
input double   ChaserSL_Dollar           = 4.00;
input double   ChaserTrailMinMove        = 0.30;
input double   ChaserDistance_TrendIntactMult = 1.5;
input double   ChaserDistance_TrendWeakMult   = 0.6;
input int      ChaserFlipCooldownSec     = 120;
input int      ChaserMaxFlipsPerHour     = 3;

// --- [V6-02] Hedge ---
input bool     HedgeEnabled             = true;    // [V6.46 FIX] Aktifkan hedge default
input double   HedgePendingDistance     = 3.0;
input double   HedgeLotRatio            = 1.50;
input double   HedgeSL_Dollar           = 3.00;
input double   HedgeTrailPct            = 70.0;
input double   HedgeMinPeakForTrail     = 2.00;
input double   HedgeMaxNegDollar        = 10.0;   
input int      HedgePendingExpireSec    = 900;
input int      HedgeMinConfirmBars      = 1;
input int      HedgeCooldownSec         = 60;
input double   HedgeBlockMinusMaxLossDollar = 10.0;
input double   HedgeBreakevenArmDollar  = 1.00;
input double   HedgeGivebackCapDollar   = 1.50;

// --- [V6-06] Dashboard ---
input bool     ShowDashboard            = true;
input int      Dashboard_X              = 10;
input int      Dashboard_Y              = 20;
input int      Dashboard_FontSize       = 9;
input string   Dashboard_Font           = "Consolas";
input int      Dashboard_UpdateSec      = 2;
input color    Dash_ColorText           = clrWhite;
input color    Dash_ColorProfit         = clrLime;
input color    Dash_ColorLoss           = clrTomato;
input color    Dash_ColorWarn           = clrGold;
input color    Dash_ColorMuted          = clrSilver;

// --- [V6-07] Trade Logger ---
input bool     EnableTradeLogger        = true;

//============================== STATE ================================
enum EAState
{
   STATE_IDLE = 0, STATE_PLACE_PENDING = 1, STATE_WAIT_TRIGGER = 2,
   STATE_POSITION_ACTIVE = 3, STATE_MANAGE_PROFIT = 4, STATE_EXIT = 5,
   STATE_RESET = 6, STATE_BLOCKED_BY_FILTER = 7
};
enum RiskStatus { RISK_SAFE=0, RISK_WATCH=1, RISK_WARNING=2, RISK_DANGER=3, RISK_EMERGENCY=4 };

EAState    g_state              = STATE_IDLE;
RiskStatus g_risk               = RISK_SAFE;
int        g_buyStopTicket       = -1;
int        g_sellStopTicket      = -1;
datetime   g_cycleStartTime      = 0;
datetime   g_lastResetTime       = 0;
datetime   g_lastActionTime      = 0;
double     g_peakProfitMoney     = 0.0;
double     g_peakPriceMove       = 0.0;
double     g_worstProfitMoney    = 0.0;
int        g_cycleId             = 0;
int        g_csvHandle           = INVALID_HANDLE;
int        g_tradeLogHandle      = INVALID_HANDLE;
double     g_lastCalculatedLot   = 0.0;
double     g_lastLotBase         = 0.0;
double     g_lastLotRaw          = 0.0;
string     g_lastLotReason       = "INIT";
bool       g_lastLotRiskBlocked  = false;
double     g_lastProjectedRisk   = 0.0;
string     g_instanceOwnerKey     = "";
string     g_instanceBeatKey      = "";
string     g_lastBlockReason      = "";
int        g_positionDirection   = 0;
double     g_ratchetLockedFloor  = -999999.0;
bool       g_isReversalFlipPosition = false;
datetime   g_rsiExtremePauseUntil = 0;

// --- Preset applied values ---
double     P_MaxLossMoney;
double     P_InitialSL_Dollar;
double     P_HedgeMaxNegDollar;
double     P_HedgeLotRatio;
double     P_HedgeSL_Dollar;
double     P_HedgeBlockMinusMaxLossDollar;
double     P_MaxDailyDrawdownPct;
double     P_ADX_Threshold;
double     P_RiskPercent;
double     P_AutoLotPer1000;
double     P_MainEntryMinADX;
double     P_RSI_Oversold;
double     P_RSI_Overbought;
double     P_PyramidMinADX;
double     P_PyramidMinATRMult;
double     P_PyramidMaxATRMult;
double     P_AdaptiveADXStepPerLoss;
double     P_MaxAdaptiveADXAdd;
int        P_RestartDelaySeconds;
int        P_ConsecutiveLossPauseSec;
int        P_MaxConsecutiveCycleLosses;

double     P_TrendMinSepATRMult;
double     P_FastConfirm_MinSepATRMult;
double     P_MinATR_Dollar;
int        P_MaxSpreadPoints;
int        P_PendingExpireMinutes;
double     P_BE_Start_Dollar;
double     P_TrailDrop_SmallPeak;
double     P_TrailDrop_MedPeak;
double     P_TrendFlipExit_MinPeakToIgnore;
int        P_HardStopFullDayThreshold;
bool       P_UseAdaptiveADXOnLosses;
bool       P_UseFastTrendConfirm;

bool       P_UseReversalChaser;
bool       P_UseMeanReversionEntry;
bool       P_UseRangeBoundEntry;
bool       P_UseTrendFlipExit;
double     P_EarlyLossCut_MaxLoss_WhileHedged; 

// --- Pyramid ---
int        g_pyramidLevel        = 0;
int        g_pyramidTickets[3];
double     g_legPeakProfit[3];
double     g_pyramidEntryPrices[3];
datetime   g_pyramidLastAddTime = 0;
double     g_firstEntryPrice    = 0.0;
double     g_pyramidLot         = 0.0;

// --- Exit persistence ---
bool       g_exitRequested       = false;
string     g_exitReason          = "";

// --- Consecutive loss ---
int        g_consecutiveLosses   = 0;
datetime   g_lossPauseUntil      = 0;
double     g_lastCyclePnL        = 0.0;
int        g_pendingTrailCount   = 0;
bool       g_consecLossHardStopped = false;
int        g_mrTicket              = -1;
int        g_mrConsecutiveLosses   = 0;
datetime   g_mrLossPauseUntil      = 0;
int        g_rangeTicket             = -1;
int        g_rangeConsecutiveLosses  = 0;
datetime   g_rangeLossPauseUntil     = 0;
int        g_reversalChaserTicket   = -1;
int        g_reversalChaserDir      = 0;
datetime   g_lastChaserFlipTime     = 0;
datetime   g_chaserFlipWindowStart  = 0;
int        g_chaserFlipsThisWindow  = 0;

// --- Daily/Weekly ---
double     g_dailyStartEquity     = 0.0;
datetime   g_dailyStartDay        = 0;
bool       g_dailyLossPaused      = false;
double     g_weeklyStartEquity    = 0.0;
datetime   g_weeklyStartDay       = 0;
bool       g_weeklyLossPaused     = false;

// --- Hedge ---
int        g_hedgePendingTicket   = -1;
datetime   g_hedgePendingTime     = 0;
int        g_hedgeTicket         = -1;
int        g_hedgeDirection      = 0;
double     g_hedgeLot            = 0.0;
datetime   g_hedgeOpenTime       = 0;
double     g_hedgePeakProfit     = 0.0;
bool       g_hedgeClosed         = false;
int        g_hedgeRearmCount     = 0;
datetime   g_hedgeLastCloseTime  = 0;
datetime   g_hedgeAdverseSince   = 0;

// --- News ---
int        g_newsCount            = 0;
int        g_newsHour[32];
int        g_newsMin[32];

// --- Kelly-lite trade history ---
#define KELLY_MAX 100
double     g_tradeHist[KELLY_MAX];
int        g_tradeHistCount = 0;
int        g_tradeHistIdx = 0;
int        g_dailyWins = 0;
int        g_dailyLosses = 0;

// --- Dashboard ---
datetime   g_dashLastUpdate = 0;
string     g_dashPrefix = "V6DASH_";
int        g_dashLineCount = 0;

//============================== HELPERS ==============================
string StateToString(EAState s)
{
   if(s == STATE_IDLE) return "IDLE";
   if(s == STATE_PLACE_PENDING) return "PLACE_PENDING";
   if(s == STATE_WAIT_TRIGGER) return "WAIT_TRIGGER";
   if(s == STATE_POSITION_ACTIVE) return "POSITION_ACTIVE";
   if(s == STATE_MANAGE_PROFIT) return "MANAGE_PROFIT";
   if(s == STATE_EXIT) return "EXIT";
   if(s == STATE_RESET) return "RESET";
   if(s == STATE_BLOCKED_BY_FILTER) return "BLOCKED";
   return "UNKNOWN";
}
string RiskToString(RiskStatus r)
{
   if(r == RISK_SAFE) return "SAFE";
   if(r == RISK_WATCH) return "WATCH";
   if(r == RISK_WARNING) return "WARNING";
   if(r == RISK_DANGER) return "DANGER";
   if(r == RISK_EMERGENCY) return "EMERGENCY";
   return "UNKNOWN";
}

int SpreadPoints() { RefreshRates(); return (int)MathRound((Ask - Bid) / Point); }
double NormalizePrice(double price) { return NormalizeDouble(price, Digits); }

double NormalizeLot(double lot)
{
   double brokerMin = MarketInfo(Symbol(), MODE_MINLOT);
   double brokerMax = MarketInfo(Symbol(), MODE_MAXLOT);
   double step = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minLot = MathMax(brokerMin, MinLotInput);
   double maxLot = MathMin(brokerMax, MaxLotInput);
   if(maxLot < minLot) maxLot = minLot;
   if(lot < minLot) lot = minLot; if(lot > maxLot) lot = maxLot;
   if(step > 0.0) lot = MathFloor(lot / step) * step;
   if(lot < minLot) lot = minLot; if(lot > maxLot) lot = maxLot;
   return NormalizeDouble(lot, 2);
}

string AutoLotModeToString()
{
   if(AutoLotMode == 0) return "BALANCE_LINEAR";
   if(AutoLotMode == 1) return "EQUITY_LINEAR";
   if(AutoLotMode == 2) return "RISK_PERCENT_BY_SL";
   if(AutoLotMode == 3) return "KELLY_LITE";
   return "UNKNOWN";
}

double MoneyBaseForLot() { return (AutoLotMode == 0) ? AccountBalance() : AccountEquity(); }

double MoneyPerPriceUnitPerLot()
{
   double tv = MarketInfo(Symbol(), MODE_TICKVALUE);
   double ts = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tv <= 0.0 || ts <= 0.0) return 0.0;
   return tv / ts;
}

double LotCapFromMaxLossMoney()
{
   if(!CapLotByMaxLossMoney || P_MaxLossMoney <= 0.0 || P_InitialSL_Dollar <= 0.0) return 999999.0;
   double mpp = MoneyPerPriceUnitPerLot(); if(mpp <= 0.0) return 999999.0;
   double riskPerLot = P_InitialSL_Dollar * mpp; if(riskPerLot <= 0.0) return 999999.0;
   return P_MaxLossMoney / riskPerLot;
}
double MinTradableLot() { return MathMax(MarketInfo(Symbol(), MODE_MINLOT), MinLotInput); }

double RiskMoneyForLot(double lot)
{
   double mpp = MoneyPerPriceUnitPerLot();
   if(mpp <= 0.0 || P_InitialSL_Dollar <= 0.0 || lot <= 0.0) return 0.0;
   return lot * P_InitialSL_Dollar * mpp;
}

double CalcRiskPercentLot(double baseMoney)
{
   double mpp = MoneyPerPriceUnitPerLot();
   if(mpp <= 0.0 || P_InitialSL_Dollar <= 0.0)
   { g_lastLotReason = "RISK_FALLBACK"; return baseMoney / 1000.0 * P_AutoLotPer1000; }
   double riskMoney = baseMoney * P_RiskPercent / 100.0;
   double riskPerLot = P_InitialSL_Dollar * mpp;
   if(riskPerLot <= 0.0) { g_lastLotReason = "RISK_FALLBACK_ZERO"; return baseMoney / 1000.0 * P_AutoLotPer1000; }
   g_lastLotReason = "RISK_PERCENT_BY_SL";
   return riskMoney / riskPerLot;
}

double GetKellyLiteMultiplier()
{
   if(g_tradeHistCount < 5) return 1.0;
   int n = MathMin(g_tradeHistCount, Kelly_LookbackTrades);
   int wins = 0;
   for(int i = 0; i < n; i++)
   {
      int idx = (g_tradeHistIdx - 1 - i + KELLY_MAX) % KELLY_MAX;
      if(g_tradeHist[idx] > 0.0) wins++;
   }
   double wr = (double)wins / (double)n;
   double baseWr = (Kelly_BaseWinrate > 0.01) ? Kelly_BaseWinrate : 0.50;
   double mult = wr / baseWr;
   if(mult < Kelly_MinLotMult) mult = Kelly_MinLotMult;
   if(mult > Kelly_MaxLotMult) mult = Kelly_MaxLotMult;
   double confidence = MathMin(1.0, (double)n / MathMax(1, Kelly_LookbackTrades));
   mult = 1.0 + (mult - 1.0) * confidence;
   return mult;
}

double GetDailyDrawdownTaperMultiplier()
{
   if(g_dailyStartEquity <= 0.0) return 1.0;
   double dailyPnL = AccountEquity() - g_dailyStartEquity;
   if(dailyPnL >= 0.0) return 1.0;
   double limitDollar = 0.0;
   if(UseDailyLossLimit && DailyLossLimit > 0.0) limitDollar = DailyLossLimit;
   else if(UseDailyDrawdownPct && P_MaxDailyDrawdownPct > 0.0) limitDollar = g_dailyStartEquity * P_MaxDailyDrawdownPct / 100.0;
   if(limitDollar <= 0.0) return 1.0;
   double usedFrac = MathAbs(dailyPnL) / limitDollar;
   if(usedFrac <= 0.5) return 1.0;
   double taperFrac = MathMin(1.0, (usedFrac - 0.5) / 0.5);
   return 1.0 - taperFrac * (1.0 - Kelly_MinLotMult / Kelly_MaxLotMult);
}

double CalcKellyLiteLot(double baseMoney)
{
   double base = baseMoney / 1000.0 * P_AutoLotPer1000;
   double mult = GetKellyLiteMultiplier();
   double taper = GetDailyDrawdownTaperMultiplier();
   mult = mult * taper;
   if(mult < Kelly_MinLotMult) mult = Kelly_MinLotMult;
   g_lastLotReason = StringFormat("KELLY_LITE(mult=%.2f taper=%.2f n=%d)", mult, taper, MathMin(g_tradeHistCount, Kelly_LookbackTrades));
   return base * mult;
}

double GetConsecLossLotMultiplier()
{
   if(!UseConsecLossLotReduction) return 1.0;
   if(g_consecutiveLosses >= 3) return ConsecLossLotReduce3;
   if(g_consecutiveLosses >= 2) return ConsecLossLotReduce2;
   return 1.0;
}

double ApplyHardRiskCap(double lot, string &reason)
{
   if(HardRiskCapPct <= 0.0) return lot;
   double mpp = MoneyPerPriceUnitPerLot();
   if(mpp <= 0.0 || P_InitialSL_Dollar <= 0.0) return lot;
   
   // [V6.46 PATCH] Allow higher cap for deep pyramids
   double currentHardRiskCap = HardRiskCapPct;
   if(g_pyramidLevel >= 5) currentHardRiskCap = 3.0; 
   
   double maxRisk = AccountEquity() * currentHardRiskCap / 100.0;
   double riskAtLot = lot * P_InitialSL_Dollar * mpp;
   if(riskAtLot > maxRisk && riskAtLot > 0.0)
   {
      double capped = maxRisk / (P_InitialSL_Dollar * mpp);
      reason = reason + StringFormat("+HARD_RISK_CAP(%.1f%%)", currentHardRiskCap);
      return capped;
   }
   return lot;
}

double GetATRVolatilityLotMultiplier(string &reason)
{
   if(!UseATRVolatilityLotReduction) return 1.0;
   double atr = iATR(Symbol(), PERIOD_M5, ATR_Period, 0);
   if(ATR_Volatility_Level2 > ATR_Volatility_Level1 && atr >= ATR_Volatility_Level2)
   {
      reason = reason + StringFormat("+ATR_VOL(%.2f@%.2f)", ATR_Volatility_Multiplier2, atr);
      return ATR_Volatility_Multiplier2;
   }
   if(atr >= ATR_Volatility_Level1)
   {
      reason = reason + StringFormat("+ATR_VOL(%.2f@%.2f)", ATR_Volatility_Multiplier1, atr);
      return ATR_Volatility_Multiplier1;
   }
   return 1.0;
}

double CalculateTradeLot(string context)
{
   double rawLot = Lots; double baseMoney = MoneyBaseForLot();
   g_lastLotBase = baseMoney; g_lastLotRiskBlocked = false; g_lastProjectedRisk = 0.0;
   if(!UseAutoLot) { g_lastLotReason = "FIXED_LOT"; rawLot = Lots; }
   else if(AutoLotMode == 2) rawLot = CalcRiskPercentLot(baseMoney);
   else if(AutoLotMode == 3) rawLot = CalcKellyLiteLot(baseMoney);
   else { g_lastLotReason = AutoLotModeToString(); rawLot = baseMoney / 1000.0 * P_AutoLotPer1000; }

   double consecMult = GetConsecLossLotMultiplier();
   if(consecMult < 1.0)
   { rawLot = rawLot * consecMult;
     g_lastLotReason = g_lastLotReason + "+CONSEC_REDUCE(" + DoubleToString(consecMult, 2) + ")"; }

   // [V6.46 PATCH] Time-based Lot Reduction
   if(MaxLossHourStart > 0) {
      int h = TimeHour(TimeCurrent());
      if(h >= MaxLossHourStart && h < MaxLossHourEnd) {
         rawLot = rawLot * 0.5;
         g_lastLotReason = g_lastLotReason + "+TIME_REDUCE(50%)";
      }
   }

   double volMult = GetATRVolatilityLotMultiplier(g_lastLotReason);
   if(volMult > 0.0 && volMult < 1.0) rawLot = rawLot * volMult;

   rawLot = ApplyHardRiskCap(rawLot, g_lastLotReason);

   double capLot = LotCapFromMaxLossMoney(); double minTradableLot = MinTradableLot();
   double minLotRisk = RiskMoneyForLot(minTradableLot);
   if(UseV1DLotRiskSync && CapLotByMaxLossMoney && P_MaxLossMoney > 0.0
      && capLot < minTradableLot && minLotRisk > P_MaxLossMoney)
   {
      g_lastLotRiskBlocked = V1D_BlockIfMinLotTooRisky; g_lastLotRaw = rawLot; g_lastProjectedRisk = minLotRisk;
      g_lastLotReason = g_lastLotReason + "+MINLOT_RISK_SYNC";
      if(V1D_BlockIfMinLotTooRisky) { g_lastCalculatedLot = 0.0; return 0.0; }
      rawLot = minTradableLot; g_lastLotReason = g_lastLotReason + "+OPEN_MINLOT";
   }
   if(CapLotByMaxLossMoney && capLot < rawLot && (!UseV1DLotRiskSync || capLot >= minTradableLot))
   { rawLot = capLot; g_lastLotReason = g_lastLotReason + "+MAXLOSS_CAP"; }
   g_lastLotRaw = rawLot;
   double finalLot = NormalizeLot(rawLot);
   g_lastCalculatedLot = finalLot; g_lastProjectedRisk = RiskMoneyForLot(finalLot);
   return finalLot;
}

bool IsOurOrder() { return (OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber); }

int CountOurOrders(int typeFilter = -1)
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   { if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
     if(!IsOurOrder()) continue;
     if(typeFilter >= 0 && OrderType() != typeFilter) continue;
     count++; }
   return count;
}
int CountActivePositions()
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   { if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
     if(!IsOurOrder()) continue;
     if(StringFind(OrderComment(), "ISOBOX") >= 0) continue;
     if(OrderType() == OP_BUY || OrderType() == OP_SELL) count++; }
   return count;
}
int CountPendingOrders()
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   { if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
     if(!IsOurOrder()) continue;
     if(StringFind(OrderComment(), "ISOBOX") >= 0) continue;
     int t = OrderType();
     if(t == OP_BUYSTOP || t == OP_SELLSTOP || t == OP_BUYLIMIT || t == OP_SELLLIMIT) count++; }
   return count;
}

double TotalActiveProfitMoney()
{
   double total = 0.0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   { if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
     if(!IsOurOrder()) continue;
     if(OrderType() == OP_BUY || OrderType() == OP_SELL)
       total += OrderProfit() + OrderSwap() + OrderCommission(); }
   return total;
}

double FirstPositionMoveDollar()
{
   if(!SelectFirstPosition()) return 0.0;
   if(!OrderSelect(g_pyramidTickets[0], SELECT_BY_TICKET)) return 0.0;
   RefreshRates();
   double priceMove;
   if(OrderType() == OP_BUY) priceMove = Bid - OrderOpenPrice();
   else priceMove = OrderOpenPrice() - Ask;
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tickValue > 0.0 && tickSize > 0.0)
      return priceMove * (tickValue / tickSize) * OrderLots();
   double lotSize = MarketInfo(Symbol(), MODE_LOTSIZE);
   if(lotSize <= 0.0) lotSize = 100.0;
   return priceMove * lotSize * OrderLots();
}

bool SelectFirstPosition()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   { if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
     if(!IsOurOrder()) continue;
     if(OrderType() == OP_BUY || OrderType() == OP_SELL)
     { g_pyramidTickets[0] = OrderTicket(); return true; } }
   g_pyramidTickets[0] = -1; return false;
}

bool TradeAllowedNow() { return IsTradeAllowed() && !IsTradeContextBusy(); }

//============================ TREND FILTER ============================
int GetTrendDirection()
{
   if(!UseTrendFilter) return 0;
   if(TrendFilterMethod == 0)
   {
      double fast = iMA(Symbol(), Trend_Timeframe, FastEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
      double slow = iMA(Symbol(), Trend_Timeframe, SlowEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
      if(fast <= 0.0 || slow <= 0.0) return 0;
      double atrMain = iATR(Symbol(), Trend_Timeframe, ATR_Period, 1);
      double minSepMain = (atrMain > 0.0) ? atrMain * P_TrendMinSepATRMult : 0.0;
      double sepMain = fast - slow;
      if(sepMain > minSepMain) return 1;
      if(sepMain < -minSepMain) return -1;
      return 0;
   }
   else
   {
      double adx = iADX(Symbol(), Trend_Timeframe, ADX_Period, PRICE_CLOSE, MODE_MAIN, 1);
      double diP = iADX(Symbol(), Trend_Timeframe, ADX_Period, PRICE_CLOSE, MODE_PLUSDI, 1);
      double diM = iADX(Symbol(), Trend_Timeframe, ADX_Period, PRICE_CLOSE, MODE_MINUSDI, 1);
      if(adx < P_ADX_Threshold) return 0;
      if(diP > diM) return 1; return -1;
   }
}

int GetFastConfirmDirection()
{
   if(!P_UseFastTrendConfirm) return 0;
   double fast = iMA(Symbol(), FastConfirm_Timeframe, FastConfirmEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   double slow = iMA(Symbol(), FastConfirm_Timeframe, SlowConfirmEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   if(fast <= 0.0 || slow <= 0.0) return 0;
   double atr = iATR(Symbol(), FastConfirm_Timeframe, ATR_Period, 1);
   double minSep = (atr > 0.0) ? atr * P_FastConfirm_MinSepATRMult : 0.0;
   double sep = fast - slow;
   if(sep > minSep) return 1;
   if(sep < -minSep) return -1;
   return 0;
}

bool IsTrendStrongForPyramid()
{
   if(!PyramidRecheckTrend) return true;
   if(!UseTrendFilter) return true;
   double adx = iADX(Symbol(), Trend_Timeframe, ADX_Period, PRICE_CLOSE, MODE_MAIN, 0);
   if(adx < P_PyramidMinADX)
   {
      static datetime lastAdxLogTime = 0;
      if(TimeCurrent() - lastAdxLogTime >= 30)
      { LogEvent("PYRAMID_BLOCK_ADX_WEAK", StringFormat("adx=%.2f min=%.2f", adx, P_PyramidMinADX)); lastAdxLogTime = TimeCurrent(); }
      return false;
   }
   int trendNow = GetTrendDirection();
   if(trendNow != g_positionDirection)
   {
      static datetime lastFlipLogTime = 0;
      if(TimeCurrent() - lastFlipLogTime >= 30)
      { LogEvent("PYRAMID_BLOCK_TREND_FLIPPED", StringFormat("trendNow=%d posDir=%d", trendNow, g_positionDirection)); lastFlipLogTime = TimeCurrent(); }
      return false;
   }
   return true;
}

//============================ ATR DISTANCE ============================
double CalculatePendingDistance()
{
   if(!UseATRDistance) return PendingDistance_Dollar;
   double atr = iATR(Symbol(), PERIOD_M5, ATR_Period, 0);
   if(atr <= 0.0) return PendingDistance_Dollar;
   double dist = atr * ATR_DistanceMultiplier;
   if(dist < MinPendingDistance) dist = MinPendingDistance;
   if(dist > MaxPendingDistance) dist = MaxPendingDistance;
   return dist;
}

double GetActiveSLDollar()
{
   if(!UseDynamicSL) return P_InitialSL_Dollar;
   double atr = iATR(Symbol(), PERIOD_M5, ATR_Period, 1);
   if(atr <= 0.0) return P_InitialSL_Dollar;
   double dynSL = atr * DynamicSL_ATR_Multiplier;
   if(dynSL < DynamicSL_Min) dynSL = DynamicSL_Min;
   if(dynSL > DynamicSL_Max) dynSL = DynamicSL_Max;
   return dynSL;
}

double CalculateTakeProfit(double entryPrice, int direction)
{
   double slDollar = GetActiveSLDollar();
   if(TakeProfit_RR <= 0.0 || slDollar <= 0.0) return 0.0;
   double tpDist = slDollar * TakeProfit_RR;
   return (direction == 1) ? NormalizePrice(entryPrice + tpDist) : NormalizePrice(entryPrice - tpDist);
}

string GetSLDebugInfo()
{
   if(!UseDynamicSL) return StringFormat("SL=$%.2f(fixed)", P_InitialSL_Dollar);
   double atr = iATR(Symbol(), PERIOD_M5, ATR_Period, 1);
   double sl = GetActiveSLDollar();
   return StringFormat("SL=$%.2f(ATR=%.2f*%.1f)", sl, atr, DynamicSL_ATR_Multiplier);
}

//============================ TIME FILTER ==============================
bool IsInTradeSession()
{
   if(!UseTimeFilter) return true;
   datetime now = TimeCurrent();
   int h = TimeHour(now), m = TimeMinute(now), dow = TimeDayOfWeek(now);
   if(SkipMondayFirstHours && dow == 1 && (h * 60 + m) < MondaySkipHours * 60)
   { g_lastBlockReason = "TIME_MONDAY_SKIP"; return false; }
   int sm = TradeStartHour * 60 + TradeStartMinute, em = TradeEndHour * 60 + TradeEndMinute, nm = h * 60 + m;
   if(sm <= em) { if(nm >= sm && nm < em) return true; }
   else { if(nm >= sm || nm < em) return true; }
   g_lastBlockReason = "TIME_OUTSIDE_SESSION"; return false;
}

bool IsInSessionFilter()
{
   if(SessionFilter == 0) return true;
   int h = TimeHour(TimeCurrent());
   if(SessionFilter == 1) return (h >= 0 && h < 8);
   if(SessionFilter == 2) return (h >= 7 && h < 16);
   if(SessionFilter == 3) return (h >= 12 && h < 21);
   return true;
}
string SessionName()
{
   if(SessionFilter == 1) return "ASIA";
   if(SessionFilter == 2) return "LONDON";
   if(SessionFilter == 3) return "NY";
   return "ALL";
}

void ParseNewsTimes()
{
   g_newsCount = 0;
   if(!UseNewsFilter || StringLen(NewsTimesCSV) == 0) return;
   string s = NewsTimesCSV;
   int prev = 0;
   int len = StringLen(s);
   for(int i = 0; i <= len; i++)
   {
      if(i == len || StringGetChar(s, i) == ',')
      {
         string tok = StringSubstr(s, prev, i - prev);
         while(StringLen(tok) > 0 && StringGetChar(tok, 0) == ' ') tok = StringSubstr(tok, 1);
         while(StringLen(tok) > 0 && StringGetChar(tok, StringLen(tok)-1) == ' ') tok = StringSubstr(tok, 0, StringLen(tok)-1);
         int colon = StringFind(tok, ":");
         if(colon > 0 && g_newsCount < 32)
         {
            int hh = (int)StrToInteger(StringSubstr(tok, 0, colon));
            int mm = (int)StrToInteger(StringSubstr(tok, colon + 1));
            if(hh >= 0 && hh < 24 && mm >= 0 && mm < 60)
            { g_newsHour[g_newsCount] = hh; g_newsMin[g_newsCount] = mm; g_newsCount++; }
         }
         prev = i + 1;
      }
   }
}
bool IsNewsWindow()
{
   if(!UseNewsFilter || g_newsCount == 0) return false;
   datetime now = TimeCurrent();
   int today = (int)(now / 86400) * 86400;
   for(int i = 0; i < g_newsCount; i++)
   {
      datetime nt = today + g_newsHour[i] * 3600 + g_newsMin[i] * 60;
      long diff = (long)(now - nt);
      if(diff >= -NewsPauseMinutesBefore * 60 && diff <= NewsPauseMinutesAfter * 60)
         return true;
   }
   return false;
}

//============================ CSV LOGGER ==============================
void OpenCSVIfNeeded()
{
   if(!EnableCSVLog || g_csvHandle != INVALID_HANDLE) return;
   g_csvHandle = FileOpen(CSV_FileName, FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE, ';');
   if(g_csvHandle == INVALID_HANDLE) { ResetLastError(); return; }
   if(FileSize(g_csvHandle) == 0)
      FileWrite(g_csvHandle, "time","symbol","tf","cycle","event","detail","state","risk",
         "active_orders","pending_orders","pyramid_level","buy_stop_ticket","sell_stop_ticket",
         "entry_price","profit_money","price_move","peak_profit","worst_profit",
         "lot_mode","auto_lot","last_lot","lot_base","lot_raw","lot_reason",
         "balance","equity","spread","last_error");
   FileFlush(g_csvHandle);
}
void CloseCSV() { if(g_csvHandle != INVALID_HANDLE) { FileClose(g_csvHandle); g_csvHandle = INVALID_HANDLE; } }
void LogEvent(string eventName, string detail)
{
   if(PrintDebug) Print(EA_Name, " | ", eventName, " | ", detail);
   if(!EnableCSVLog) return;
   OpenCSVIfNeeded(); if(g_csvHandle == INVALID_HANDLE) return;
   FileSeek(g_csvHandle, 0, SEEK_END);
   FileWrite(g_csvHandle,
      TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), Symbol(), Period(), g_cycleId,
      eventName, detail, StateToString(g_state), RiskToString(g_risk),
      CountActivePositions(), CountPendingOrders(), g_pyramidLevel,
      g_buyStopTicket, g_sellStopTicket,
      DoubleToString(g_firstEntryPrice, Digits),
      DoubleToString(TotalActiveProfitMoney(), 2),
      DoubleToString(FirstPositionMoveDollar(), 2),
      DoubleToString(g_peakProfitMoney, 2),
      DoubleToString(g_worstProfitMoney, 2),
      AutoLotModeToString(), UseAutoLot ? "true" : "false",
      DoubleToString(g_lastCalculatedLot, 2),
      DoubleToString(g_lastLotBase, 2),
      DoubleToString(g_lastLotRaw, 4),
      g_lastLotReason,
      DoubleToString(AccountBalance(), 2),
      DoubleToString(AccountEquity(), 2),
      SpreadPoints(), GetLastError());
   FileFlush(g_csvHandle); ResetLastError();
}

void OpenTradeLoggerIfNeeded()
{
   if(!EnableTradeLogger || g_tradeLogHandle != INVALID_HANDLE) return;
   string fname = StringFormat("EA_V7_log_%s.csv", Symbol());
   g_tradeLogHandle = FileOpen(fname, FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE, ';');
   if(g_tradeLogHandle == INVALID_HANDLE) { ResetLastError(); return; }
   if(FileSize(g_tradeLogHandle) == 0)
      FileWrite(g_tradeLogHandle,
         "timestamp","cycle_id","type","action","ticket","price","lot","sl","tp",
         "pnl","exit_reason","spread","atr","rsi","comment");
   FileFlush(g_tradeLogHandle);
}
void CloseTradeLogger()
{ if(g_tradeLogHandle != INVALID_HANDLE) { FileClose(g_tradeLogHandle); g_tradeLogHandle = INVALID_HANDLE; } }

string TradeLifecycleKey(string action, int ticket)
{
   return GVKey("trlog_" + action + "_" + IntegerToString(ticket));
}

bool TradeLifecycleLogged(string action, int ticket)
{
   return GlobalVariableCheck(TradeLifecycleKey(action, ticket));
}

void MarkTradeLifecycleLogged(string action, int ticket)
{
   GlobalVariableSet(TradeLifecycleKey(action, ticket), (double)TimeCurrent());
}

string DetectTradeType(string comment, int legIndex = 0)
{
   if(StringFind(comment, "Hedge") >= 0) return "hedge";
   if(StringFind(comment, "Pyramid") >= 0 || legIndex > 0) return "pyramid";
   return "main";
}

void LogTradeCSV(string tradeType, string action, int ticket, double price, double lot,
                 double sl, double tp, double pnl, string exitReason, string comment)
{
   if(!EnableTradeLogger) return;
   OpenTradeLoggerIfNeeded();
   if(g_tradeLogHandle == INVALID_HANDLE) return;
   double atr = iATR(Symbol(), PERIOD_M5, ATR_Period, 0);
   double rsi = iRSI(Symbol(), PERIOD_M5, RSI_Period, PRICE_CLOSE, 0);
   FileSeek(g_tradeLogHandle, 0, SEEK_END);
   FileWrite(g_tradeLogHandle,
      TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
      g_cycleId, tradeType, action, ticket,
      DoubleToString(price, Digits),
      DoubleToString(lot, 2),
      DoubleToString(sl, Digits),
      DoubleToString(tp, Digits),
      DoubleToString(pnl, 2),
      exitReason,
      SpreadPoints(),
      DoubleToString(atr, 2),
      DoubleToString(rsi, 1),
      comment);
   FileFlush(g_tradeLogHandle);
   if(ticket > 0)
   {
      if(action == "open") MarkTradeLifecycleLogged("open", ticket);
      else if(action == "close") MarkTradeLifecycleLogged("close", ticket);
   }
}

void ReconcileTradeLifecycleLogs()
{
   if(!EnableTradeLogger) return;
   static datetime s_lastRun = 0;
   if(s_lastRun == TimeCurrent()) return;
   s_lastRun = TimeCurrent();

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsOurOrder()) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      int tkt = OrderTicket();
      if(TradeLifecycleLogged("open", tkt)) continue;
      string c = OrderComment();
      string t = DetectTradeType(c);
      LogTradeCSV(t, "open", tkt, OrderOpenPrice(), OrderLots(), OrderStopLoss(), OrderTakeProfit(), 0.0, "", "FAILSAFE_RECOVER_OPEN|" + c);
      LogEvent("TRADELOG_RECOVER_OPEN", StringFormat("ticket=%d type=%s", tkt, t));
   }

   int totalHist = OrdersHistoryTotal();
   int scanned = 0;
   for(int h = totalHist - 1; h >= 0 && scanned < 200; h--)
   {
      if(!OrderSelect(h, SELECT_BY_POS, MODE_HISTORY)) continue;
      scanned++;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      if(OrderCloseTime() <= 0) continue;
      int tkt = OrderTicket();
      if(TradeLifecycleLogged("close", tkt)) continue;
      string c = OrderComment();
      string t = DetectTradeType(c);
      double pnl = OrderProfit() + OrderSwap() + OrderCommission();
      LogTradeCSV(t, "close", tkt, OrderClosePrice(), OrderLots(), OrderStopLoss(), OrderTakeProfit(), pnl, "failsafe_reconcile", c);
      LogEvent("TRADELOG_RECOVER_CLOSE", StringFormat("ticket=%d type=%s pnl=%.2f", tkt, t, pnl));
   }
}

//============================ ORDER OPERATIONS =========================
bool DeleteOrderByTicket(int ticket, string reason)
{
   if(ticket <= 0) return true;
   if(!OrderSelect(ticket, SELECT_BY_TICKET))
   { if(ticket==g_buyStopTicket) g_buyStopTicket=-1; if(ticket==g_sellStopTicket) g_sellStopTicket=-1; if(ticket==g_reversalChaserTicket) {g_reversalChaserTicket=-1; g_reversalChaserDir=0;} return true; }
   if(UseV1DStrictOCOCleanup && OrderCloseTime() > 0)
   { if(ticket==g_buyStopTicket) g_buyStopTicket=-1; if(ticket==g_sellStopTicket) g_sellStopTicket=-1; if(ticket==g_reversalChaserTicket) {g_reversalChaserTicket=-1; g_reversalChaserDir=0;} return true; }
   if(!IsOurOrder()) return true;
   int type = OrderType();
   if(type!=OP_BUYSTOP && type!=OP_SELLSTOP && type!=OP_BUYLIMIT && type!=OP_SELLLIMIT) return true;
   if(!TradeAllowedNow()) return false;
   RefreshRates();
   if(!OrderSelect(ticket, SELECT_BY_TICKET) || OrderCloseTime() > 0 ||
      (OrderType() != OP_BUYSTOP && OrderType() != OP_SELLSTOP && OrderType() != OP_BUYLIMIT && OrderType() != OP_SELLLIMIT))
   { if(ticket==g_buyStopTicket) g_buyStopTicket=-1; if(ticket==g_sellStopTicket) g_sellStopTicket=-1; if(ticket==g_reversalChaserTicket) {g_reversalChaserTicket=-1; g_reversalChaserDir=0;} return true; }
   bool ok = OrderDelete(ticket);
   if(ok)
   { LogEvent("PENDING_DELETED", StringFormat("ticket=%d reason=%s", ticket, reason));
     if(ticket==g_buyStopTicket) g_buyStopTicket=-1; if(ticket==g_sellStopTicket) g_sellStopTicket=-1; if(ticket==g_reversalChaserTicket) {g_reversalChaserTicket=-1; g_reversalChaserDir=0;}
     g_lastActionTime=TimeCurrent(); return true; }
   int err=GetLastError();
   if(UseV1DStrictOCOCleanup && OrderSelect(ticket,SELECT_BY_TICKET) && OrderCloseTime()>0)
   { if(ticket==g_buyStopTicket) g_buyStopTicket=-1; if(ticket==g_sellStopTicket) g_sellStopTicket=-1; if(ticket==g_reversalChaserTicket) {g_reversalChaserTicket=-1; g_reversalChaserDir=0;} ResetLastError(); return true; }
   LogEvent("PENDING_DELETE_FAILED", StringFormat("ticket=%d reason=%s err=%d",ticket,reason,err)); ResetLastError(); return false;
}

bool DeleteAllPending(string reason)
{
   bool allOk = true;
   for(int i = OrdersTotal()-1; i>=0; i--)
   { if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
     if(!IsOurOrder()) continue;
     if(OrderTicket() == g_hedgePendingTicket) continue;
     int t=OrderType();
     if(t==OP_BUYSTOP||t==OP_SELLSTOP||t==OP_BUYLIMIT||t==OP_SELLLIMIT)
       if(!DeleteOrderByTicket(OrderTicket(),reason)) allOk=false; }
   return allOk;
}

bool CloseSinglePosition(int ticket, string reason)
{
   if(ticket <= 0) return true;
   if(!OrderSelect(ticket, SELECT_BY_TICKET)) return true;
   if(UseV1DStrictOCOCleanup && OrderCloseTime() > 0)
   {
      double pnlHist = OrderProfit() + OrderSwap() + OrderCommission();
      string commentHist = OrderComment();
      string tradeTypeHist = DetectTradeType(commentHist);
      LogTradeCSV(tradeTypeHist, "close", ticket, OrderClosePrice(), OrderLots(), OrderStopLoss(), OrderTakeProfit(),
                  pnlHist, reason + "(already_closed)", commentHist);
      return true;
   }
   if(!IsOurOrder()) return true;
   int type = OrderType();
   if(type != OP_BUY && type != OP_SELL) return true;
   if(!TradeAllowedNow()) return false;
   RefreshRates();
   double price = (type == OP_BUY) ? Bid : Ask;
   double pnlSnapshot = OrderProfit() + OrderSwap() + OrderCommission();
   double lotSnapshot = OrderLots();
   double slSnapshot = OrderStopLoss();
   double tpSnapshot = OrderTakeProfit();
   string comment = OrderComment();
   ResetLastError();
   bool ok = OrderClose(ticket, lotSnapshot, price, SlippagePoints, clrNONE);
   if(ok)
   { LogEvent("POSITION_CLOSED", StringFormat("ticket=%d reason=%s lots=%.2f price=%.2f pnl=%.2f", ticket, reason, lotSnapshot, price, pnlSnapshot));
     string tradeType = DetectTradeType(comment);
     LogTradeCSV(tradeType, "close", ticket, price, lotSnapshot, slSnapshot, tpSnapshot, pnlSnapshot, reason, comment);
     g_lastActionTime = TimeCurrent(); return true; }
   int err = GetLastError();
   if(!OrderSelect(ticket, SELECT_BY_TICKET) || (UseV1DStrictOCOCleanup && OrderCloseTime() > 0))
   { ResetLastError(); return true; }
   LogEvent("POSITION_CLOSE_FAILED", StringFormat("ticket=%d reason=%s err=%d", ticket, reason, err));
   ResetLastError(); return false;
}

void CheckDailyLossLimit()
{
   datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   if(g_dailyStartDay != today)
   {
      g_dailyStartEquity = AccountEquity();
      g_dailyStartDay = today;
      g_dailyLossPaused = false;
      g_dailyWins = 0;
      g_dailyLosses = 0;
      if(g_consecLossHardStopped)
      {
         g_consecLossHardStopped = false;
         LogEvent("CONSEC_LOSS_FULL_DAY_STOP_CLEARED", "real day rollover (no restart) — resuming new-cycle checks");
      }
      PersistDailyBaseline();
   }

   if(!UseDailyLossLimit && !UseDailyDrawdownPct && g_dailyLossPaused)
   {
      g_dailyLossPaused = false;
      PersistDailyBaseline();
      LogEvent("DAILY_LOSS_LIMIT_STALE_CLEARED", "both daily limit toggles are off — clearing leftover pause from a previous session");
   }

   double dailyPnL = AccountEquity() - g_dailyStartEquity;

   if(UseDailyDrawdownPct && g_dailyStartEquity > 0.0)
   {
      double ddPct = -(dailyPnL / g_dailyStartEquity) * 100.0;
      if(ddPct >= P_MaxDailyDrawdownPct && !g_dailyLossPaused)
      {
         g_dailyLossPaused = true;
         PersistDailyBaseline();
         LogEvent("DAILY_DD_PCT_HIT", StringFormat("dd=%.2f%% limit=%.2f%% equity=%.2f start=%.2f",
                  ddPct, P_MaxDailyDrawdownPct, AccountEquity(), g_dailyStartEquity));
      }
   }

   if(UseDailyLossLimit && dailyPnL <= -DailyLossLimit && !g_dailyLossPaused)
   {
      g_dailyLossPaused = true;
      PersistDailyBaseline();
      LogEvent("DAILY_LOSS_LIMIT", StringFormat("dailyPnL=%.2f limit=%.2f — PAUSED", dailyPnL, DailyLossLimit));
   }

   if(g_dailyLossPaused && (UseDailyLossLimit || UseDailyDrawdownPct) &&
      CountActivePositions() == 0 && CountPendingOrders() == 0)
   {
      g_state = STATE_BLOCKED_BY_FILTER;
      g_lastBlockReason = StringFormat("DAILY_LIMIT (P&L=$%.2f)", dailyPnL);
   }
}

void CheckWeeklyLossLimit()
{
   if(!UseWeeklyLossLimit)
   {
      if(g_weeklyLossPaused)
      {
         g_weeklyLossPaused = false;
         PersistWeeklyBaseline();
         LogEvent("WEEKLY_LOSS_LIMIT_STALE_CLEARED", "UseWeeklyLossLimit is off — clearing leftover pause from a previous session");
      }
      return;
   }
   datetime now = TimeCurrent();
   int dow = TimeDayOfWeek(now);
   datetime monday = now - dow * 86400;
   datetime mondayStart = StringToTime(TimeToString(monday, TIME_DATE));
   if(g_weeklyStartDay != mondayStart)
   {
      g_weeklyStartDay = mondayStart;
      g_weeklyStartEquity = AccountEquity();
      g_weeklyLossPaused = false;
      PersistWeeklyBaseline();
   }
   double wkPnL = AccountEquity() - g_weeklyStartEquity;
   double weeklyLimitDollar = (UseWeeklyLossLimitPct && MaxWeeklyLossPct > 0.0)
                               ? g_weeklyStartEquity * MaxWeeklyLossPct / 100.0
                               : MaxWeeklyLossMoney;
   if(wkPnL <= -weeklyLimitDollar && !g_weeklyLossPaused)
   {
      g_weeklyLossPaused = true;
      PersistWeeklyBaseline();
      LogEvent("WEEKLY_LOSS_LIMIT", StringFormat("wkPnL=%.2f limit=%.2f (%s) — PAUSED for week", wkPnL, weeklyLimitDollar,
               (UseWeeklyLossLimitPct ? StringFormat("%.1f%%", MaxWeeklyLossPct) : "fixed $")));
   }
   if(g_weeklyLossPaused && CountActivePositions() == 0 && CountPendingOrders() == 0)
   {
      g_state = STATE_BLOCKED_BY_FILTER;
      g_lastBlockReason = StringFormat("WEEKLY_LIMIT (P&L=$%.2f)", wkPnL);
   }
}

string GVKey(string suffix) { return EA_Name + "_" + Symbol() + "_" + IntegerToString(MagicNumber) + "_" + suffix; }

void PersistDailyBaseline()
{
   GlobalVariableSet(GVKey("dailyDay"), (double)g_dailyStartDay);
   GlobalVariableSet(GVKey("dailyEq"), g_dailyStartEquity);
   GlobalVariableSet(GVKey("dailyPaused"), g_dailyLossPaused ? 1.0 : 0.0);
   GlobalVariableSet(GVKey("consecHardStop"), g_consecLossHardStopped ? 1.0 : 0.0);
}

void PersistWeeklyBaseline()
{
   GlobalVariableSet(GVKey("weekDay"), (double)g_weeklyStartDay);
   GlobalVariableSet(GVKey("weekEq"), g_weeklyStartEquity);
   GlobalVariableSet(GVKey("weekPaused"), g_weeklyLossPaused ? 1.0 : 0.0);
}

void LoadOrInitDailyBaseline()
{
   datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   if(GlobalVariableCheck(GVKey("dailyDay")) && (datetime)GlobalVariableGet(GVKey("dailyDay")) == today)
   {
      g_dailyStartDay = today;
      g_dailyStartEquity = GlobalVariableGet(GVKey("dailyEq"));
      g_dailyLossPaused = (GlobalVariableGet(GVKey("dailyPaused")) > 0.5);
      g_consecLossHardStopped = GlobalVariableCheck(GVKey("consecHardStop")) && (GlobalVariableGet(GVKey("consecHardStop")) > 0.5);
      LogEvent("DAILY_BASELINE_RESTORED", StringFormat("startEquity=%.2f paused=%s hardStop=%s", g_dailyStartEquity, g_dailyLossPaused ? "true" : "false", g_consecLossHardStopped ? "true" : "false"));
   }
   else
   {
      g_dailyStartDay = today;
      g_dailyStartEquity = AccountEquity();
      g_dailyLossPaused = false;
      g_consecLossHardStopped = false;
      PersistDailyBaseline();
   }
}

void LoadOrInitWeeklyBaseline()
{
   int dow = TimeDayOfWeek(TimeCurrent());
   datetime monday = TimeCurrent() - dow * 86400;
   datetime mondayStart = StringToTime(TimeToString(monday, TIME_DATE));
   if(GlobalVariableCheck(GVKey("weekDay")) && (datetime)GlobalVariableGet(GVKey("weekDay")) == mondayStart)
   {
      g_weeklyStartDay = mondayStart;
      g_weeklyStartEquity = GlobalVariableGet(GVKey("weekEq"));
      g_weeklyLossPaused = (GlobalVariableGet(GVKey("weekPaused")) > 0.5);
      LogEvent("WEEKLY_BASELINE_RESTORED", StringFormat("startEquity=%.2f paused=%s", g_weeklyStartEquity, g_weeklyLossPaused ? "true" : "false"));
   }
   else
   {
      g_weeklyStartDay = mondayStart;
      g_weeklyStartEquity = AccountEquity();
      g_weeklyLossPaused = false;
      PersistWeeklyBaseline();
   }
}

bool CloseAllPositions(string reason)
{
   bool allOk = true;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   { if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
     if(!IsOurOrder()) continue;
     if(OrderType() == OP_BUY || OrderType() == OP_SELL)
       if(!CloseSinglePosition(OrderTicket(), reason)) allOk = false; }
   if(allOk) { DeleteAllPending("close_all_cleanup"); g_pyramidLevel = 0; for(int j=0;j<3;j++) {g_pyramidTickets[j]=-1; g_legPeakProfit[j]=0.0;}
                g_hedgeTicket=-1; g_hedgeClosed=true;
                if(g_hedgePendingTicket>0){DeleteOrderByTicket(g_hedgePendingTicket,"close_all_hedge");g_hedgePendingTicket=-1;}
                g_reversalChaserTicket=-1; g_reversalChaserDir=0; }
   return allOk;
}

bool CloseAllPositionsExcept(int exceptTicket, string reason)
{
   bool allOk = true;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   { if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
     if(!IsOurOrder()) continue;
     if(OrderTicket() == exceptTicket) continue;
     if(OrderType() == OP_BUY || OrderType() == OP_SELL)
       if(!CloseSinglePosition(OrderTicket(), reason)) allOk = false; }
   DeleteAllPending("chaser_flip_cleanup");
   g_hedgeTicket=-1; g_hedgeClosed=true;
   if(g_hedgePendingTicket>0){DeleteOrderByTicket(g_hedgePendingTicket,"chaser_flip_hedge_cleanup");g_hedgePendingTicket=-1;}
   return allOk;
}

bool ModifySL(int ticket, double newSL, string reason)
{
   if(ticket <= 0) return false;
   if(!OrderSelect(ticket, SELECT_BY_TICKET)) return false;
   if(!IsOurOrder()) return false;
   if(OrderType() != OP_BUY && OrderType() != OP_SELL) return false;
   newSL = NormalizePrice(newSL);

   RefreshRates();
   double rawStopLevelPts = MathMax(MarketInfo(Symbol(), MODE_STOPLEVEL), MarketInfo(Symbol(), MODE_FREEZELEVEL));
   double stopLevelPts = MathMax(rawStopLevelPts, MinStopBufferPoints);
   double minDist = (stopLevelPts + 2) * Point;
   if(OrderType() == OP_BUY)
   {
      double maxAllowedSL = NormalizePrice(Bid - minDist);
      if(newSL > maxAllowedSL) newSL = maxAllowedSL;
   }
   else
   {
      double minAllowedSL = NormalizePrice(Ask + minDist);
      if(newSL < minAllowedSL) newSL = minAllowedSL;
   }

   double oldSL = OrderStopLoss();
   if(oldSL > 0 && MathAbs(oldSL - newSL) < Point * 2) return true;
   if(oldSL > 0)
   {
      bool stillImproves = (OrderType() == OP_BUY) ? (newSL > oldSL) : (newSL < oldSL);
      if(!stillImproves) return false;
   }
   if(!TradeAllowedNow()) return false;
   bool ok = OrderModify(ticket, OrderOpenPrice(), newSL, OrderTakeProfit(), 0, clrNONE);
   if(ok) { LogEvent("SL_MODIFIED", StringFormat("ticket=%d oldSL=%.2f newSL=%.2f reason=%s", ticket, oldSL, newSL, reason));
     g_lastActionTime = TimeCurrent(); ResetSLProtectionFailClock(ticket); return true; }
   int err = GetLastError();
   int    bufferSteps[4] = {3, 8, 20, 40};
   for(int step = 0; step < 4 && (err == 130 || err == 138); step++)
   {
      ResetLastError(); RefreshRates();
      double stopLevelPtsN = MathMax(MathMax(MarketInfo(Symbol(), MODE_STOPLEVEL), MarketInfo(Symbol(), MODE_FREEZELEVEL)), MinStopBufferPoints);
      double minDistN = (stopLevelPtsN + bufferSteps[step]) * Point;
      double retrySL = newSL;
      if(OrderType() == OP_BUY) { double maxSLn = NormalizePrice(Bid - minDistN); if(retrySL > maxSLn) retrySL = maxSLn; }
      else                      { double minSLn = NormalizePrice(Ask + minDistN); if(retrySL < minSLn) retrySL = minSLn; }
      bool stillImprovesN = (oldSL <= 0) || ((OrderType() == OP_BUY) ? (retrySL > oldSL) : (retrySL < oldSL));
      if(stillImprovesN && OrderModify(ticket, OrderOpenPrice(), retrySL, OrderTakeProfit(), 0, clrNONE))
      { LogEvent("SL_MODIFIED", StringFormat("ticket=%d oldSL=%.2f newSL=%.2f reason=%s (retry buf=%dpt)", ticket, oldSL, retrySL, reason, bufferSteps[step]));
        g_lastActionTime = TimeCurrent(); ResetSLProtectionFailClock(ticket); return true; }
      err = GetLastError();
   }
   static datetime lastSLFailLogTime = 0;
   if(TimeCurrent() - lastSLFailLogTime >= 15)
   { LogEvent("SL_MODIFY_FAILED", StringFormat("ticket=%d newSL=%.2f reason=%s err=%d", ticket, newSL, reason, err));
     lastSLFailLogTime = TimeCurrent(); }
   FlagUnprotectedIfNeeded(ticket, reason);
   ResetLastError(); return false;
}

datetime g_slFailSince[50];
int      g_slFailTicket[50];
void ResetSLProtectionFailClock(int ticket)
{
   for(int i = 0; i < 50; i++) if(g_slFailTicket[i] == ticket) { g_slFailSince[i] = 0; g_slFailTicket[i] = -1; }
}
void FlagUnprotectedIfNeeded(int ticket, string reason)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET)) return;
   if(OrderStopLoss() > 0) return; 
   int slot = -1;
   for(int i = 0; i < 50; i++)
   {
      if(g_slFailTicket[i] == ticket) { slot = i; break; }
      if(slot < 0 && g_slFailTicket[i] <= 0) slot = i;
   }
   if(slot < 0) return;
   if(g_slFailTicket[slot] != ticket) { g_slFailTicket[slot] = ticket; g_slFailSince[slot] = TimeCurrent(); }
   int nakedSeconds = (int)(TimeCurrent() - g_slFailSince[slot]);
   if(nakedSeconds >= UnprotectedForceCloseSec)
   {
      LogEvent("SL_PROTECTION_TIMEOUT_FORCE_CLOSE", StringFormat("ticket=%d naked_for=%ds reason=%s", ticket, nakedSeconds, reason));
      CloseSinglePosition(ticket, "sl_protection_timeout");
      g_slFailTicket[slot] = -1; g_slFailSince[slot] = 0;
   }
}

bool ModifySLForAllPyramid(double newSL, string reason)
{
   bool allOk = true;
   for(int i = 0; i < 3; i++)
   { if(g_pyramidTickets[i] > 0) if(!ModifySL(g_pyramidTickets[i], newSL, reason)) allOk = false; }
   return allOk;
}

int OrderSendGetTicket(string symbol, int cmd, double volume, double price, int slippage,
                       double sl, double tp, string comment, int magic, datetime exp, color clr)
{
   for(int attempt = 1; attempt <= OrderRetryMax; attempt++)
   {
      ResetLastError();
      int ticket = OrderSend(symbol, cmd, volume, price, slippage, sl, tp, comment, magic, exp, clr);
      if(ticket > 0) return ticket;
      int err = GetLastError();
      if(err == 138 || err == 136 || err == 130 || err == 131 || err == 6 || err == 129)
      { LogEvent("ORDER_RETRY", StringFormat("attempt=%d/%d err=%d cmd=%d price=%.2f", attempt, OrderRetryMax, err, cmd, price));
        if(attempt < OrderRetryMax) { Sleep(OrderRetryDelayMs); RefreshRates();
          if(cmd == OP_BUY) price = Ask; if(cmd == OP_SELL) price = Bid; } }
      else { LogEvent("ORDER_FAILED_NO_RETRY", StringFormat("err=%d cmd=%d", err, cmd)); ResetLastError(); return -1; }
   }
   ResetLastError(); return -1;
}

bool OrderSendWithRetry(string symbol, int cmd, double volume, double price, int slippage,
                         double sl, double tp, string comment, int magic, datetime exp, color clr)
{ return (OrderSendGetTicket(symbol, cmd, volume, price, slippage, sl, tp, comment, magic, exp, clr) > 0); }

double TotalOpenRiskDollar()
{
   double total = 0.0;
   double mpp = MoneyPerPriceUnitPerLot();
   if(mpp <= 0.0) return 0.0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsOurOrder()) continue;
      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL) continue;
      double sl = OrderStopLoss();
      double dist;
      if(sl <= 0.0) dist = P_InitialSL_Dollar / MathMax(mpp, 0.0000001);
      else dist = MathAbs(OrderOpenPrice() - sl);
      total += dist * mpp * OrderLots();
   }
   return total;
}

bool EmergencyRiskCeilingOK(double extraLot)
{
   if(!UseEmergencyTotalRiskCap) return true;
   double mpp = MoneyPerPriceUnitPerLot();
   if(mpp <= 0.0) return true;
   double extraRisk = extraLot * GetActiveSLDollar() * mpp;
   double projected = TotalOpenRiskDollar() + extraRisk;
   double ceiling = AccountEquity() * EmergencyTotalRiskCapPct / 100.0;
   if(projected > ceiling)
   {
      LogEvent("EMERGENCY_RISK_CEILING_BLOCK", StringFormat("projected=%.2f ceiling=%.2f (%.1f%% equity)",
               projected, ceiling, EmergencyTotalRiskCapPct));
      return false;
   }
   return true;
}

//============================ PYRAMID EXECUTION ==================
bool CanAddPyramidPosition()
{
   if(!UsePyramid) return false;
   if(g_pyramidLevel >= PyramidMaxPositions) return false;
   if(CountActivePositions() < 1) return false;
   if(g_exitRequested) return false;
   if(g_pyramidLastAddTime > 0 && (TimeCurrent() - g_pyramidLastAddTime) < PyramidCooldownSeconds) return false;

   double pyMinDist = PyramidMinPriceMove;
   double pyMaxDist = PyramidMaxPriceMove;
   if(UsePyramidDynamicDistance)
   {
      double atrNow = iATR(Symbol(), PERIOD_M5, ATR_Period, 0);
      if(atrNow > 0.0)
      {
         pyMinDist = atrNow * P_PyramidMinATRMult;
         pyMaxDist = atrNow * P_PyramidMaxATRMult;
         if(pyMinDist < MinPendingDistance) pyMinDist = MinPendingDistance;
         if(pyMaxDist > MaxPendingDistance) pyMaxDist = MaxPendingDistance;
         if(pyMaxDist <= pyMinDist) pyMaxDist = pyMinDist * 1.5;
      }
   }
   double moveDollar = FirstPositionMoveDollar();
   if(moveDollar < pyMinDist)
   {
      static datetime lastBlockLogTime = 0;
      if(TimeCurrent() - lastBlockLogTime >= 30)
      {
         LogEvent("PYRAMID_BLOCK_PRICE_TOO_CLOSE", StringFormat("move=%.2f min=%.2f%s", moveDollar, pyMinDist, UsePyramidDynamicDistance ? "(atr)" : ""));
         lastBlockLogTime = TimeCurrent();
      }
      return false;
   }
   if(moveDollar > pyMaxDist)
   {
      static datetime lastFarLogTime = 0;
      if(TimeCurrent() - lastFarLogTime >= 30)
      { LogEvent("PYRAMID_BLOCK_PRICE_TOO_FAR", StringFormat("move=%.2f max=%.2f%s", moveDollar, pyMaxDist, UsePyramidDynamicDistance ? "(atr)" : "")); lastFarLogTime = TimeCurrent(); }
      return false;
   }
   if(!IsTrendStrongForPyramid()) return false;
   double prospectiveLot = NormalizeLot(g_pyramidLot * PyramidSameLotRatio);
   if(!EmergencyRiskCeilingOK(prospectiveLot)) return false;
   LogEvent("PYRAMID_READY", StringFormat("level=%d->%d move=%.2f", g_pyramidLevel, g_pyramidLevel+1, moveDollar));
   return true;
}

bool AddPyramidPosition()
{
   if(!TradeAllowedNow()) return false;
   if(!CanAddPyramidPosition()) return false;
   double lot = g_pyramidLot * PyramidSameLotRatio;
   if(lot <= 0.0) { LogEvent("PYRAMID_LOT_ZERO", ""); return false; }
   lot = NormalizeLot(lot);
   if(!SelectFirstPosition()) return false;
   if(!OrderSelect(g_pyramidTickets[0], SELECT_BY_TICKET)) return false;
   int direction = (OrderType() == OP_BUY) ? 1 : -1;
   g_positionDirection = direction;
   RefreshRates();
   double entryPrice, sl, tp;
   double slDol = GetActiveSLDollar();
   int cmd;
   string dirLabel;
   if(direction == 1)
   { cmd = OP_BUY; entryPrice = NormalizePrice(Ask); sl = NormalizePrice(entryPrice - slDol);
     tp = CalculateTakeProfit(entryPrice, 1); dirLabel = "BUY"; }
   else
   { cmd = OP_SELL; entryPrice = NormalizePrice(Bid); sl = NormalizePrice(entryPrice + slDol);
     tp = CalculateTakeProfit(entryPrice, -1); dirLabel = "SELL"; }
   int newTicket = OrderSendGetTicket(Symbol(), cmd, lot, entryPrice, SlippagePoints, sl, tp,
                          EA_Name + " Pyramid L" + IntegerToString(g_pyramidLevel+1), MagicNumber, 0,
                          (direction==1) ? clrBlue : clrRed);
   if(newTicket <= 0)
   { LogEvent("PYRAMID_ADD_FAILED", StringFormat("dir=%s level=%d lot=%.2f err=%d", dirLabel, g_pyramidLevel+1, lot, GetLastError())); return false; }
   g_pyramidTickets[g_pyramidLevel] = newTicket;
   g_pyramidEntryPrices[g_pyramidLevel] = entryPrice;
   g_pyramidLevel++;
   g_pyramidLastAddTime = TimeCurrent();
   g_lastActionTime = TimeCurrent();
   LogEvent("PYRAMID_ADDED", StringFormat("level=%d dir=%s ticket=%d price=%.2f sl=%.2f tp=%.2f lot=%.2f",
            g_pyramidLevel, dirLabel, newTicket, entryPrice, sl, tp, lot));
   LogTradeCSV("pyramid", "open", newTicket, entryPrice, lot, sl, tp, 0.0, "", EA_Name + " Pyramid L" + IntegerToString(g_pyramidLevel));
   return true;
}

//============================ HEDGE FUNCTIONS ================
bool HasMainPosition()
{
   for(int i = 0; i < 3; i++)
   {
      if(g_pyramidTickets[i] <= 0) continue;
      if(OrderSelect(g_pyramidTickets[i], SELECT_BY_TICKET))
         if(OrderCloseTime() == 0 && IsOurOrder()) return true;
   }
   return false;
}

double HedgeProfitMoney()
{
   if(g_hedgeTicket <= 0) return 0.0;
   if(!OrderSelect(g_hedgeTicket, SELECT_BY_TICKET)) return 0.0;
   if(OrderCloseTime() > 0) return 0.0;
   return OrderProfit() + OrderSwap() + OrderCommission();
}

bool HedgeConfirmationOK()
{
   if(HedgeMinConfirmBars <= 0) return true;
   if(g_positionDirection == 0 || g_firstEntryPrice <= 0.0) return false;
   int adverseBars = 0;
   for(int i = 1; i <= HedgeMinConfirmBars; i++)
   {
      double c = iClose(Symbol(), PERIOD_M5, i);
      if(c <= 0) return false;
      if(g_positionDirection == 1 && c < g_firstEntryPrice) adverseBars++;
      else if(g_positionDirection == -1 && c > g_firstEntryPrice) adverseBars++;
   }
   return (adverseBars >= HedgeMinConfirmBars);
}

bool HedgeCooldownOK()
{
   if(HedgeCooldownSec <= 0) return true;
   if(g_hedgeLastCloseTime <= 0) return true;
   return (TimeCurrent() - g_hedgeLastCloseTime) >= HedgeCooldownSec;
}

void PlaceHedgePending()
{
   if(!TradeAllowedNow()) return;
   if(g_positionDirection == 0) return;
   if(g_hedgePendingTicket > 0) return;
   if(g_hedgeClosed) return;

   if(!HedgeConfirmationOK())
   {
      static datetime lastHedgeConfirmLogTime = 0;
      if(TimeCurrent() - lastHedgeConfirmLogTime >= 30)
      { LogEvent("HEDGE_BLOCK_CONFIRM", StringFormat("need=%d adverse bars", HedgeMinConfirmBars)); lastHedgeConfirmLogTime = TimeCurrent(); }
      return;
   }
   if(!HedgeCooldownOK())
   { LogEvent("HEDGE_BLOCK_COOLDOWN", StringFormat("cooldown=%ds elapsed=%ds",
              HedgeCooldownSec, (int)(TimeCurrent()-g_hedgeLastCloseTime))); return; }

   int hedgeDir = (g_positionDirection == 1) ? -1 : 1;
   int pendingType = (hedgeDir == 1) ? OP_BUYSTOP : OP_SELLSTOP;
   double mainLot = (g_pyramidLot > 0.0) ? g_pyramidLot : g_lastCalculatedLot;
   double hedgeLot = NormalizeLot(mainLot * P_HedgeLotRatio);
   if(hedgeLot <= 0.0) hedgeLot = NormalizeLot(Lots * P_HedgeLotRatio);

   double mppl = MoneyPerPriceUnitPerLot();
   double hedgeWorstCaseLoss = hedgeLot * P_HedgeSL_Dollar * mppl;
   if(mppl > 0.0 && hedgeWorstCaseLoss > P_HedgeBlockMinusMaxLossDollar)
   {
      static datetime lastHedgeCapLogTime = 0;
      if(TimeCurrent() - lastHedgeCapLogTime >= 30)
      {
         LogEvent("HEDGE_BLOCK_MINUS_CAP", StringFormat("hedgeLot=%.2f worstCase=%.2f cap=%.2f",
                  hedgeLot, hedgeWorstCaseLoss, P_HedgeBlockMinusMaxLossDollar));
         lastHedgeCapLogTime = TimeCurrent();
      }
      return;
   }

   if(!EmergencyRiskCeilingOK(hedgeLot))
   { LogEvent("HEDGE_BLOCK_RISK_CEILING", StringFormat("hedgeLot=%.2f", hedgeLot)); return; }

   RefreshRates();
   double pendingPrice, sl;
   string dirLabel;
   if(pendingType == OP_BUYSTOP)
   { pendingPrice = NormalizePrice(Ask + HedgePendingDistance);
     sl = NormalizePrice(pendingPrice - P_HedgeSL_Dollar); dirLabel = "BUY_STOP"; }
   else
   { pendingPrice = NormalizePrice(Bid - HedgePendingDistance);
     sl = NormalizePrice(pendingPrice + P_HedgeSL_Dollar); dirLabel = "SELL_STOP"; }

   int newTicket = OrderSendGetTicket(Symbol(), pendingType, hedgeLot, pendingPrice, SlippagePoints, sl, 0,
                          EA_Name + " HedgePend", MagicNumber, 0,
                          (pendingType == OP_BUYSTOP) ? clrBlue : clrRed);
   if(newTicket <= 0)
   { LogEvent("HEDGE_PENDING_FAILED", StringFormat("dir=%s price=%.2f err=%d", dirLabel, pendingPrice, GetLastError())); return; }

   g_hedgePendingTicket = newTicket;
   g_hedgePendingTime = TimeCurrent();
   g_hedgeLot = hedgeLot;
   g_hedgeDirection = hedgeDir;
   g_lastActionTime = TimeCurrent();
   LogEvent("HEDGE_PENDING_PLACED", StringFormat("dir=%s ticket=%d price=%.2f sl=%.2f lot=%.2f mainEntry=%.2f dist=%.2f confirmBars=%d",
            dirLabel, newTicket, pendingPrice, sl, hedgeLot, g_firstEntryPrice, HedgePendingDistance, HedgeMinConfirmBars));
   LogTradeCSV("hedge", "open", newTicket, pendingPrice, hedgeLot, sl, 0.0, 0.0, "", "HedgePend " + dirLabel);
}

void ManageHedgePosition()
{
   if(g_hedgeTicket <= 0) return;
   if(!OrderSelect(g_hedgeTicket, SELECT_BY_TICKET))
   { g_hedgeTicket = -1; g_hedgeClosed = true; g_hedgeLastCloseTime = TimeCurrent(); return; }
   if(OrderCloseTime() > 0)
   { g_hedgeTicket = -1; g_hedgeClosed = true; g_hedgeLastCloseTime = TimeCurrent(); return; }

   if(!HasMainPosition())
   {
      double hp = OrderProfit() + OrderSwap() + OrderCommission();
      bool closed = CloseSinglePosition(g_hedgeTicket, "main_gone_close_hedge");
      LogEvent("HEDGE_CLOSED_MAIN_GONE", StringFormat("hedgeProfit=%.2f ok=%d reason=main_position_closed", hp, closed));
      if(closed) { g_hedgeTicket = -1; g_hedgeClosed = true; g_hedgeLastCloseTime = TimeCurrent(); }
      return;
   }

   if((TimeCurrent() - g_hedgeOpenTime) < 30) return;

   double hedgeProfit = OrderProfit() + OrderSwap() + OrderCommission();
   if(hedgeProfit > g_hedgePeakProfit) g_hedgePeakProfit = hedgeProfit;

   if(g_hedgePeakProfit >= HedgeMinPeakForTrail)
   {
      double trailThreshold = g_hedgePeakProfit * (1.0 - HedgeTrailPct / 100.0);
      trailThreshold = MathMax(0.01, trailThreshold);
      if(hedgeProfit <= trailThreshold)
      {
         bool closed = CloseSinglePosition(g_hedgeTicket, "hedge_trail_close");
         LogEvent("HEDGE_CLOSED_TRAIL", StringFormat("peak=%.2f close=%.2f threshold=%.2f reason=peak_retrace ok=%d",
                  g_hedgePeakProfit, hedgeProfit, trailThreshold, closed));
         if(closed) { g_hedgeTicket = -1; g_hedgeClosed = true; g_hedgeLastCloseTime = TimeCurrent(); }
         return;
      }
   }

   if(g_hedgePeakProfit >= HedgeBreakevenArmDollar)
   {
      double lockProfit = g_hedgePeakProfit - HedgeGivebackCapDollar;
      double lockPrice   = OrderOpenPrice();
      double perPriceUnit = MoneyPerPriceUnitPerLot();
      if(lockProfit > 0.0 && perPriceUnit > 0.0)
      {
         double lockMove = lockProfit / (OrderLots() * perPriceUnit);
         double desiredSL = (OrderType() == OP_BUY) ? NormalizePrice(lockPrice + lockMove)
                                                       : NormalizePrice(lockPrice - lockMove);
         bool improves = (OrderType() == OP_BUY) ? (desiredSL > OrderStopLoss()) : (desiredSL < OrderStopLoss() || OrderStopLoss() == 0.0);
         if(improves) ModifySL(g_hedgeTicket, desiredSL, "hedge_giveback_lock");
      }
   }

   if(g_hedgePeakProfit >= HedgeBreakevenArmDollar &&
      (g_hedgePeakProfit - hedgeProfit) >= HedgeGivebackCapDollar)
   {
      bool closed = CloseSinglePosition(g_hedgeTicket, "hedge_reversal_giveback_cap");
      LogEvent("HEDGE_CLOSED_REVERSAL", StringFormat("profit=%.2f peak=%.2f giveback=%.2f cap=%.2f reason=giveback_cap ok=%d",
               hedgeProfit, g_hedgePeakProfit, g_hedgePeakProfit - hedgeProfit, HedgeGivebackCapDollar, closed));
      if(closed) { g_hedgeTicket = -1; g_hedgeClosed = true; g_hedgeLastCloseTime = TimeCurrent(); }
      return;
   }

   if(hedgeProfit < -P_HedgeMaxNegDollar)
   {
      bool closed = CloseSinglePosition(g_hedgeTicket, "hedge_max_loss");
      LogEvent("HEDGE_CLOSED_MAX_LOSS", StringFormat("profit=%.2f limit=%.2f peak=%.2f reason=hard_dollar_stop ok=%d",
               hedgeProfit, P_HedgeMaxNegDollar, g_hedgePeakProfit, closed));
      if(closed) { g_hedgeTicket = -1; g_hedgeClosed = true; g_hedgeLastCloseTime = TimeCurrent(); }
      return;
   }
}

void ManageHedge()
{
   if(g_hedgePendingTicket > 0)
   {
      if(!OrderSelect(g_hedgePendingTicket, SELECT_BY_TICKET) || OrderCloseTime() > 0)
      { g_hedgePendingTicket = -1; }
      else if(OrderType() == OP_BUY || OrderType() == OP_SELL)
      {
         g_hedgeTicket = g_hedgePendingTicket;
         g_hedgePendingTicket = -1;
         g_hedgeOpenTime = OrderOpenTime();
         g_hedgePeakProfit = 0.0;
         g_hedgeLot = OrderLots();
         LogEvent("HEDGE_PENDING_FILLED", StringFormat("ticket=%d dir=%s price=%.2f lot=%.2f",
                  g_hedgeTicket, (g_hedgeDirection==1?"BUY":"SELL"), OrderOpenPrice(), g_hedgeLot));
      }
      return;
   }
   if(g_hedgeTicket > 0) { ManageHedgePosition(); return; }
   if(g_hedgeClosed) return;
   if(g_exitRequested) return;
}

//============================ OCO PLACEMENT ============================
bool PlaceOCOOrders()
{
   if(!TradeAllowedNow() || !MarketFiltersOK() || CountActivePositions() > 0) return false;
   DeleteAllPending("fresh_oco_cycle"); RefreshRates();
   double lot = CalculateTradeLot("PLACE_OCO"); if(lot <= 0.0) return false;
   double dist = CalculatePendingDistance();
   double buyP=NormalizePrice(Ask+dist), sellP=NormalizePrice(Bid-dist);
   double slDol=GetActiveSLDollar(); double buySL=NormalizePrice(buyP-slDol), sellSL=NormalizePrice(sellP+slDol);
   double buyTP=CalculateTakeProfit(buyP,1), sellTP=CalculateTakeProfit(sellP,-1);
   if(!OrderSendWithRetry(Symbol(),OP_BUYSTOP,lot,buyP,SlippagePoints,buySL,buyTP,EA_Name+" BuyStop",MagicNumber,0,clrBlue))
   { LogEvent("OCO_BUY_FAILED",StringFormat("price=%.2f err=%d",buyP,GetLastError())); return false; }
   int buyTicket=-1;
   for(int i=OrdersTotal()-1;i>=0;i--)
   { if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
     if(OrderSymbol()==Symbol()&&OrderMagicNumber()==MagicNumber&&OrderType()==OP_BUYSTOP){buyTicket=OrderTicket();break;} }
   if(!OrderSendWithRetry(Symbol(),OP_SELLSTOP,lot,sellP,SlippagePoints,sellSL,sellTP,EA_Name+" SellStop",MagicNumber,0,clrRed))
   { if(buyTicket>0) DeleteOrderByTicket(buyTicket,"oco_incomplete"); g_buyStopTicket=-1;g_sellStopTicket=-1; return false; }
   g_buyStopTicket=buyTicket; g_sellStopTicket=-1;
   for(int i=OrdersTotal()-1;i>=0;i--)
   { if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
     if(OrderSymbol()==Symbol()&&OrderMagicNumber()==MagicNumber&&OrderType()==OP_SELLSTOP){g_sellStopTicket=OrderTicket();break;} }
   g_state=STATE_WAIT_TRIGGER;g_cycleStartTime=TimeCurrent();g_lastActionTime=TimeCurrent();
   LogEvent("OCO_PLACED",StringFormat("buy=%d %.2f sell=%d %.2f lot=%.2f dist=%.2f",g_buyStopTicket,buyP,g_sellStopTicket,sellP,lot,dist));
   return true;
}

bool PlaceDirectionalOCO(int trend)
{
   if(!TradeAllowedNow()||!MarketFiltersOK()||CountActivePositions()>0) return false;
   DeleteAllPending("fresh_dir_oco"); RefreshRates();
   double lot=CalculateTradeLot("PLACE_OCO_DIR"); if(lot<=0.0) return false;
   double dist=CalculatePendingDistance();
   double slDol=GetActiveSLDollar();
   double counterLot = NormalizeLot(lot * CounterSideLotMult);
   if(trend==1)
   {
      double buyP=NormalizePrice(Ask+dist), buySL=NormalizePrice(buyP-slDol), buyTP=CalculateTakeProfit(buyP,1);
      if(!OrderSendWithRetry(Symbol(),OP_BUYSTOP,lot,buyP,SlippagePoints,buySL,buyTP,EA_Name+" Bull BuyStop",MagicNumber,0,clrBlue))
      { LogEvent("DIR_OCO_BUY_FAILED",StringFormat("price=%.2f err=%d",buyP,GetLastError())); return false; }
      for(int i=OrdersTotal()-1;i>=0;i--)
      { if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
        if(OrderSymbol()==Symbol()&&OrderMagicNumber()==MagicNumber&&OrderType()==OP_BUYSTOP){g_buyStopTicket=OrderTicket();break;} }
      g_sellStopTicket=-1;
      LogEvent("DIR_OCO_PLACED",StringFormat("dir=BULL ticket=%d price=%.2f sl=%.2f tp=%.2f lot=%.2f dist=%.2f",g_buyStopTicket,buyP,buySL,buyTP,lot,dist));
      if(UseDualSidedOCO && counterLot > 0.0)
      {
         double cSellP=NormalizePrice(Bid-dist), cSellSL=NormalizePrice(cSellP+slDol), cSellTP=CalculateTakeProfit(cSellP,-1);
         if(OrderSendWithRetry(Symbol(),OP_SELLSTOP,counterLot,cSellP,SlippagePoints,cSellSL,cSellTP,EA_Name+" CounterSellStop",MagicNumber,0,clrRed))
         { for(int i=OrdersTotal()-1;i>=0;i--)
           { if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
             if(OrderSymbol()==Symbol()&&OrderMagicNumber()==MagicNumber&&OrderType()==OP_SELLSTOP){g_sellStopTicket=OrderTicket();break;} }
           LogEvent("DIR_OCO_COUNTER_PLACED",StringFormat("dir=BEAR(counter) ticket=%d price=%.2f lot=%.2f",g_sellStopTicket,cSellP,counterLot)); }
         else LogEvent("DIR_OCO_COUNTER_FAILED",StringFormat("price=%.2f err=%d",cSellP,GetLastError()));
      }
   }
   else
   {
      double sellP=NormalizePrice(Bid-dist), sellSL=NormalizePrice(sellP+slDol), sellTP=CalculateTakeProfit(sellP,-1);
      if(!OrderSendWithRetry(Symbol(),OP_SELLSTOP,lot,sellP,SlippagePoints,sellSL,sellTP,EA_Name+" Bear SellStop",MagicNumber,0,clrRed))
      { LogEvent("DIR_OCO_SELL_FAILED",StringFormat("price=%.2f err=%d",sellP,GetLastError())); return false; }
      g_buyStopTicket=-1;
      for(int i=OrdersTotal()-1;i>=0;i--)
      { if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
        if(OrderSymbol()==Symbol()&&OrderMagicNumber()==MagicNumber&&OrderType()==OP_SELLSTOP){g_sellStopTicket=OrderTicket();break;} }
      LogEvent("DIR_OCO_PLACED",StringFormat("dir=BEAR ticket=%d price=%.2f sl=%.2f tp=%.2f lot=%.2f dist=%.2f",g_sellStopTicket,sellP,sellSL,sellTP,lot,dist));
      if(UseDualSidedOCO && counterLot > 0.0)
      {
         double cBuyP=NormalizePrice(Ask+dist), cBuySL=NormalizePrice(cBuyP-slDol), cBuyTP=CalculateTakeProfit(cBuyP,1);
         if(OrderSendWithRetry(Symbol(),OP_BUYSTOP,counterLot,cBuyP,SlippagePoints,cBuySL,cBuyTP,EA_Name+" CounterBuyStop",MagicNumber,0,clrBlue))
         { for(int i=OrdersTotal()-1;i>=0;i--)
           { if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
             if(OrderSymbol()==Symbol()&&OrderMagicNumber()==MagicNumber&&OrderType()==OP_BUYSTOP){g_buyStopTicket=OrderTicket();break;} }
           LogEvent("DIR_OCO_COUNTER_PLACED",StringFormat("dir=BULL(counter) ticket=%d price=%.2f lot=%.2f",g_buyStopTicket,cBuyP,counterLot)); }
         else LogEvent("DIR_OCO_COUNTER_FAILED",StringFormat("price=%.2f err=%d",cBuyP,GetLastError()));
      }
   }
   g_state=STATE_WAIT_TRIGGER;g_cycleStartTime=TimeCurrent();g_lastActionTime=TimeCurrent();
   return true;
}

//============================ ENGINE LOGIC =============================
void UpdateRiskStatus()
{
   double p = TotalActiveProfitMoney();
   if(CountActivePositions() == 0) { g_risk = RISK_SAFE; return; }
   double scaledMaxLoss = P_MaxLossMoney * MathMax(1.0, g_pyramidLevel * 0.8);
   if(p <= -scaledMaxLoss) g_risk = RISK_EMERGENCY;
   else if(p <= -scaledMaxLoss * 0.80) g_risk = RISK_DANGER;
   else if(p <= -scaledMaxLoss * 0.60) g_risk = RISK_WARNING;
   else if(p <= -scaledMaxLoss * 0.40) g_risk = RISK_WATCH;
   else g_risk = RISK_SAFE;
}

bool MarketFiltersOK()
{
   int sp = SpreadPoints();
   if(sp > P_MaxSpreadPoints) { LogEvent("FILTER_BLOCK_SPREAD", StringFormat("spread=%d max=%d", sp, P_MaxSpreadPoints)); return false; }
   if(UseATRFilter)
   { double atr = iATR(Symbol(), PERIOD_M5, ATR_Period, 0);
     if(atr < P_MinATR_Dollar)
     { LogEvent("FILTER_BLOCK_ATR", StringFormat("atr=%.2f min=%.2f", atr, P_MinATR_Dollar)); return false; } }
   return true;
}

bool PlaceIsolatedReversalOrder(int dir, double rsi, double adx, string triggerTag)
{
   if(dir == 0) return false;
   if(g_mrTicket > 0) return false;
   if(g_mrLossPauseUntil > 0 && TimeCurrent() < g_mrLossPauseUntil) return false;
   if(!MarketFiltersOK()) return false;
   if(!TradeAllowedNow()) return false;

   double mpp = MoneyPerPriceUnitPerLot();
   if(mpp <= 0.0) return false;
   double slDist = (MR_SL_Dollar / (MR_Lot * mpp));
   double tpDist = (MR_TP_Dollar / (MR_Lot * mpp));

   RefreshRates();
   int cmd = (dir == 1) ? OP_BUY : OP_SELL;
   double price = (dir == 1) ? Ask : Bid;
   double sl = (dir == 1) ? NormalizePrice(price - slDist) : NormalizePrice(price + slDist);
   double tp = (dir == 1) ? NormalizePrice(price + tpDist) : NormalizePrice(price - tpDist);
   string label = StringFormat("ISOBOX %s %s (%s)", triggerTag, dir == 1 ? "BUY" : "SELL", dir == 1 ? "valley" : "peak");

   ResetLastError();
   int ticket = OrderSend(Symbol(), cmd, NormalizeLot(MR_Lot), price, SlippagePoints, sl, tp, label, MagicNumber, 0, dir == 1 ? clrBlue : clrRed);
   if(ticket > 0)
   {
      g_mrTicket = ticket;
      LogEvent("MEANREV_ENTRY", StringFormat("trigger=%s dir=%s rsi=%.1f adx=%.1f price=%.2f sl=%.2f tp=%.2f", triggerTag, (dir==1?"BUY":"SELL"), rsi, adx, price, sl, tp));
      LogTradeCSV("mean_reversion", "open", ticket, price, MR_Lot, sl, tp, 0.0, "", label);
      return true;
   }
   LogEvent("MEANREV_ENTRY_FAILED", StringFormat("trigger=%s err=%d dir=%s", triggerTag, GetLastError(), (dir==1?"BUY":"SELL")));
   ResetLastError();
   return false;
}

bool TryMeanReversionEntry()
{
   if(!P_UseMeanReversionEntry) return false;
   if(g_mrTicket > 0) return false;
   if(g_mrLossPauseUntil > 0 && TimeCurrent() < g_mrLossPauseUntil) return false;
   if(!MarketFiltersOK()) return false;
   if(!TradeAllowedNow()) return false;

   double adx = iADX(Symbol(), Trend_Timeframe, ADX_Period, PRICE_CLOSE, MODE_MAIN, 1);
   if(adx > MR_MaxADXForEntry) return false;

   double rsi = iRSI(Symbol(), PERIOD_M5, RSI_Period, PRICE_CLOSE, 1);
   int dir = 0;
   if(rsi <= MR_RSI_Oversold) dir = 1;
   else if(rsi >= MR_RSI_Overbought) dir = -1;
   else return false;

   return PlaceIsolatedReversalOrder(dir, rsi, adx, "MeanRev-Quiet");
}

void CheckMeanReversionClosed()
{
   if(g_mrTicket <= 0) return;
   if(!OrderSelect(g_mrTicket, SELECT_BY_TICKET)) { g_mrTicket = -1; return; }
   if(OrderCloseTime() > 0)
   {
      double pnl = OrderProfit() + OrderSwap() + OrderCommission();
      LogEvent("MEANREV_CLOSED", StringFormat("ticket=%d pnl=%.2f", g_mrTicket, pnl));
      LogTradeCSV("mean_reversion", "close", g_mrTicket, OrderClosePrice(), OrderLots(), OrderStopLoss(), OrderTakeProfit(), pnl, "sl_or_tp", OrderComment());
      g_mrTicket = -1;
      if(pnl < 0.0)
      {
         g_mrConsecutiveLosses++;
         if(g_mrConsecutiveLosses >= MR_MaxConsecutiveLosses && MR_MaxConsecutiveLosses > 0)
         {
            g_mrLossPauseUntil = TimeCurrent() + MR_LossPauseSec;
            LogEvent("MR_CONSEC_LOSS_PAUSE", StringFormat("losses=%d pauseUntil=%s", g_mrConsecutiveLosses,
                     TimeToString(g_mrLossPauseUntil, TIME_DATE | TIME_SECONDS)));
         }
      }
      else
      {
         g_mrConsecutiveLosses = 0;
      }
   }
}

bool TryRangeBoundEntry()
{
   if(!P_UseRangeBoundEntry) return false;
   if(g_rangeTicket > 0) return false;
   if(g_rangeLossPauseUntil > 0 && TimeCurrent() < g_rangeLossPauseUntil) return false;
   if(!MarketFiltersOK()) return false;
   if(!TradeAllowedNow()) return false;

   double adx = iADX(Symbol(), Trend_Timeframe, ADX_Period, PRICE_CLOSE, MODE_MAIN, 1);
   if(adx > Range_MaxADXForEntry) return false;

   double atr = iATR(Symbol(), PERIOD_M5, ATR_Period, 1);
   if(atr <= 0.0) return false;

   double rangeHigh = -1, rangeLow = -1;
   int highBar = iHighest(Symbol(), PERIOD_M5, MODE_HIGH, Range_LookbackBars, 1);
   int lowBar  = iLowest(Symbol(), PERIOD_M5, MODE_LOW, Range_LookbackBars, 1);
   if(highBar < 0 || lowBar < 0) return false;
   rangeHigh = iHigh(Symbol(), PERIOD_M5, highBar);
   rangeLow  = iLow(Symbol(), PERIOD_M5, lowBar);
   double rangeSize = rangeHigh - rangeLow;
   if(rangeSize <= 0.0) return false;

   if(rangeSize < Range_MinSizeATRMult * atr) return false;
   if(rangeSize > Range_MaxSizeATRMult * atr) return false;

   RefreshRates();
   double edgeBuf = Range_EdgeATRMult * atr;
   int dir = 0;
   if(Bid <= rangeLow + edgeBuf) dir = 1;
   else if(Ask >= rangeHigh - edgeBuf) dir = -1;
   if(dir == 0) return false;

   double rsi = iRSI(Symbol(), PERIOD_M5, RSI_Period, PRICE_CLOSE, 1);
   return PlaceIsolatedRangeOrder(dir, rsi, adx, rangeLow, rangeHigh);
}

bool PlaceIsolatedRangeOrder(int dir, double rsi, double adx, double rangeLow, double rangeHigh)
{
   double mpp = MoneyPerPriceUnitPerLot();
   if(mpp <= 0.0) return false;
   double slDist = (Range_SL_Dollar / (Range_Lot * mpp));
   double tpDist = (Range_TP_Dollar / (Range_Lot * mpp));

   RefreshRates();
   int cmd = (dir == 1) ? OP_BUY : OP_SELL;
   double price = (dir == 1) ? Ask : Bid;
   double sl = (dir == 1) ? NormalizePrice(price - slDist) : NormalizePrice(price + slDist);
   double tp = (dir == 1) ? NormalizePrice(price + tpDist) : NormalizePrice(price - tpDist);
   string label = StringFormat("ISOBOX RangeBound %s (%s)", dir == 1 ? "BUY" : "SELL", dir == 1 ? "support" : "resistance");

   ResetLastError();
   int ticket = OrderSend(Symbol(), cmd, NormalizeLot(Range_Lot), price, SlippagePoints, sl, tp, label, MagicNumber, 0, dir == 1 ? clrBlue : clrRed);
   if(ticket > 0)
   {
      g_rangeTicket = ticket;
      LogEvent("RANGE_ENTRY", StringFormat("dir=%s rsi=%.1f adx=%.1f price=%.2f sl=%.2f tp=%.2f rangeLow=%.2f rangeHigh=%.2f",
               (dir==1?"BUY":"SELL"), rsi, adx, price, sl, tp, rangeLow, rangeHigh));
      LogTradeCSV("range_bound", "open", ticket, price, Range_Lot, sl, tp, 0.0, "", label);
      return true;
   }
   LogEvent("RANGE_ENTRY_FAILED", StringFormat("err=%d dir=%s", GetLastError(), (dir==1?"BUY":"SELL")));
   ResetLastError();
   return false;
}

void CheckRangeBoundClosed()
{
   if(g_rangeTicket <= 0) return;
   if(!OrderSelect(g_rangeTicket, SELECT_BY_TICKET)) { g_rangeTicket = -1; return; }
   if(OrderCloseTime() > 0)
   {
      double pnl = OrderProfit() + OrderSwap() + OrderCommission();
      LogEvent("RANGE_CLOSED", StringFormat("ticket=%d pnl=%.2f", g_rangeTicket, pnl));
      LogTradeCSV("range_bound", "close", g_rangeTicket, OrderClosePrice(), OrderLots(), OrderStopLoss(), OrderTakeProfit(), pnl, "sl_or_tp", OrderComment());
      g_rangeTicket = -1;
      if(pnl < 0.0)
      {
         g_rangeConsecutiveLosses++;
         if(g_rangeConsecutiveLosses >= Range_MaxConsecutiveLosses && Range_MaxConsecutiveLosses > 0)
         {
            g_rangeLossPauseUntil = TimeCurrent() + Range_LossPauseSec;
            LogEvent("RANGE_CONSEC_LOSS_PAUSE", StringFormat("losses=%d pauseUntil=%s", g_rangeConsecutiveLosses,
                     TimeToString(g_rangeLossPauseUntil, TIME_DATE | TIME_SECONDS)));
         }
      }
      else
      {
         g_rangeConsecutiveLosses = 0;
      }
   }
}

void SyncTicketsAndState()
{
   int active = CountActivePositions();
   int pending = CountPendingOrders();
   g_buyStopTicket = -1; g_sellStopTicket = -1;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   { if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
     if(!IsOurOrder()) continue;
     int tkt = OrderTicket();
     if(tkt == g_hedgePendingTicket) continue;
     if(tkt == g_reversalChaserTicket) continue;
     if(OrderType() == OP_BUYSTOP)  g_buyStopTicket = tkt;
     if(OrderType() == OP_SELLSTOP) g_sellStopTicket = tkt; }
   if(active > 0) {
      g_isReversalFlipPosition = false;
      if(SelectFirstPosition() && OrderSelect(g_pyramidTickets[0], SELECT_BY_TICKET))
      {
         string c = OrderComment();
         g_isReversalFlipPosition = (StringFind(c, "Counter") >= 0 || StringFind(c, "REVERSAL") >= 0 || StringFind(c, "reversal") >= 0);
      }
      g_state = STATE_POSITION_ACTIVE; return; }
   if(pending > 0) { g_state = STATE_WAIT_TRIGGER; return; }
   ResetCycleIfClean();
}

void HandleOCOTriggered()
{
   if(CountActivePositions() <= 0) return;
   if(!SelectFirstPosition()) return;
   if(!OrderSelect(g_pyramidTickets[0], SELECT_BY_TICKET)) return;
   int type = OrderType();
   double entry = OrderOpenPrice();
   double lot = OrderLots();
   double sl = OrderStopLoss();
   double tp = OrderTakeProfit();
   int mainTicket = g_pyramidTickets[0];
   int oppositeTicket = -1;
   if(type == OP_BUY)
   { oppositeTicket = g_sellStopTicket; g_positionDirection = 1;
     LogEvent("OCO_TRIGGERED_BUY", StringFormat("ticket=%d entry=%.2f", mainTicket, entry)); }
   else
   { oppositeTicket = g_buyStopTicket; g_positionDirection = -1;
     LogEvent("OCO_TRIGGERED_SELL", StringFormat("ticket=%d entry=%.2f", mainTicket, entry)); }
   if(TimeCurrent() - g_chaserFlipWindowStart > 3600)
   { g_chaserFlipWindowStart = TimeCurrent(); g_chaserFlipsThisWindow = 0; }
   bool chaserCooldownOk = (TimeCurrent() - g_lastChaserFlipTime) >= ChaserFlipCooldownSec;
   bool chaserUnderHourlyCap = (ChaserMaxFlipsPerHour <= 0) || (g_chaserFlipsThisWindow < ChaserMaxFlipsPerHour);
   if(P_UseReversalChaser && oppositeTicket > 0 && chaserCooldownOk && chaserUnderHourlyCap)
   {
      g_reversalChaserTicket = oppositeTicket;
      g_reversalChaserDir = -g_positionDirection;
      GlobalVariableSet(GVKey("chaserTicket"), (double)g_reversalChaserTicket);
      GlobalVariableSet(GVKey("chaserDir"), (double)g_reversalChaserDir);
      LogEvent("REVERSAL_CHASER_ARMED", StringFormat("ticket=%d dir=%d", oppositeTicket, g_reversalChaserDir));
   }
   else if(oppositeTicket > 0)
   {
      if(P_UseReversalChaser)
         LogEvent("REVERSAL_CHASER_SKIPPED_COOLDOWN", StringFormat(
                  "cooldownOk=%s flipsThisHour=%d/%d — deleting opposite leg instead",
                  chaserCooldownOk ? "true" : "false", g_chaserFlipsThisWindow, ChaserMaxFlipsPerHour));
      DeleteOrderByTicket(oppositeTicket, (type == OP_BUY) ? "oco_buy_triggered" : "oco_sell_triggered");
   }
   g_buyStopTicket = -1; g_sellStopTicket = -1;
   g_firstEntryPrice = entry;
   g_pyramidEntryPrices[0] = g_firstEntryPrice;
   g_pyramidLevel = 1;
   g_pyramidLot = g_lastCalculatedLot;
   g_isReversalFlipPosition = false;
   g_peakProfitMoney = MathMax(0.0, TotalActiveProfitMoney());
   g_worstProfitMoney = MathMin(0.0, TotalActiveProfitMoney());
   g_peakPriceMove = MathMax(0.0, FirstPositionMoveDollar());
   g_state = STATE_POSITION_ACTIVE;
   EnsureInitialSL();
   LogTradeCSV("main", "open", mainTicket, entry, lot, sl, tp, 0.0, "", (type==OP_BUY?"BUY OCO":"SELL OCO"));
   if(HedgeEnabled && !P_UseReversalChaser && g_hedgePendingTicket <= 0 && !g_hedgeClosed) PlaceHedgePending();
}

void ManageReversalChaser()
{
   if(!P_UseReversalChaser) return;
   if(g_reversalChaserTicket <= 0) return;
   if(!OrderSelect(g_reversalChaserTicket, SELECT_BY_TICKET))
   { g_reversalChaserTicket = -1; g_reversalChaserDir = 0; return; }
   if(!IsOurOrder()) { g_reversalChaserTicket = -1; g_reversalChaserDir = 0; return; }

   int otype = OrderType();
   if(otype == OP_BUY || otype == OP_SELL) { HandleChaserFlip(); return; }
   if(otype != OP_BUYSTOP && otype != OP_SELLSTOP) { g_reversalChaserTicket = -1; g_reversalChaserDir = 0; return; }

   RefreshRates();
   double curPrice = OrderOpenPrice();
   double minMovePrice = ChaserTrailMinMove;

   double effDist = ChaserDistance;
   if(UseTrendAdaptiveTrail && g_positionDirection != 0)
   {
      int trendNow = GetTrendDirection();
      double adxNow = iADX(Symbol(), Trend_Timeframe, ADX_Period, PRICE_CLOSE, MODE_MAIN, 1);
      bool trendIntact = (trendNow == g_positionDirection && adxNow >= P_MainEntryMinADX);
      effDist = ChaserDistance * (trendIntact ? ChaserDistance_TrendIntactMult : ChaserDistance_TrendWeakMult);
   }

   double stopLevelPtsChaser = MathMax(MarketInfo(Symbol(), MODE_STOPLEVEL), MarketInfo(Symbol(), MODE_FREEZELEVEL));
   double liveBufferChaser = (stopLevelPtsChaser + 3) * Point;
   if(effDist < liveBufferChaser) effDist = liveBufferChaser;

   if(otype == OP_BUYSTOP)
   {
      double idealPrice = NormalizePrice(Ask + effDist);
      if(idealPrice < curPrice - minMovePrice)
      {
         double newSL = NormalizePrice(idealPrice - ChaserSL_Dollar);
         ResetLastError();
         if(OrderModify(g_reversalChaserTicket, idealPrice, newSL, 0, 0, clrNONE))
            LogEvent("CHASER_TRAILED", StringFormat("ticket=%d old=%.2f new=%.2f dist=%.2f", g_reversalChaserTicket, curPrice, idealPrice, effDist));
         else { int err = GetLastError(); if(err != 1) LogEvent("CHASER_TRAIL_FAIL", StringFormat("err=%d idealPrice=%.5f stopLevel=%.0f", err, idealPrice, stopLevelPtsChaser)); ResetLastError(); }
      }
   }
   else
   {
      double idealPrice = NormalizePrice(Bid - effDist);
      if(idealPrice > curPrice + minMovePrice)
      {
         double newSL = NormalizePrice(idealPrice + ChaserSL_Dollar);
         ResetLastError();
         if(OrderModify(g_reversalChaserTicket, idealPrice, newSL, 0, 0, clrNONE))
            LogEvent("CHASER_TRAILED", StringFormat("ticket=%d old=%.2f new=%.2f dist=%.2f", g_reversalChaserTicket, curPrice, idealPrice, effDist));
         else { int err = GetLastError(); if(err != 1) LogEvent("CHASER_TRAIL_FAIL", StringFormat("err=%d idealPrice=%.5f stopLevel=%.0f", err, idealPrice, stopLevelPtsChaser)); ResetLastError(); }
      }
   }
}

void HandleChaserFlip()
{
   int newDir = (OrderType() == OP_BUY) ? 1 : -1;
   int newTicket = OrderTicket();
   double newEntry = OrderOpenPrice();
   double newLot = OrderLots();
   double newSL = OrderStopLoss();
   double newTP = OrderTakeProfit();

   LogEvent("REVERSAL_CHASER_TRIGGERED_FLIP", StringFormat("newDir=%s ticket=%d entry=%.2f lot=%.2f",
            (newDir==1?"BULL":"BEAR"), newTicket, newEntry, newLot));

   if(TimeCurrent() - g_chaserFlipWindowStart > 3600)
   { g_chaserFlipWindowStart = TimeCurrent(); g_chaserFlipsThisWindow = 0; }
   g_lastChaserFlipTime = TimeCurrent();
   g_chaserFlipsThisWindow++;

   CloseAllPositionsExcept(newTicket, "reversal_chaser_flip");
   double oldCyclePnL = GetRealizedPnLSinceCycleStart();
   RecordCycleResult(oldCyclePnL);
   LogEvent("CYCLE_RESET", StringFormat("oldState=%s realizedPnL=%.2f peak=%.2f worst=%.2f pyramid=%d consLosses=%d reason=chaser_flip",
            StateToString(g_state), oldCyclePnL, g_peakProfitMoney, g_worstProfitMoney, g_pyramidLevel, g_consecutiveLosses));

   g_positionDirection = newDir;
   g_firstEntryPrice = newEntry;
   g_cycleStartTime = TimeCurrent();
   g_cycleId++;
   for(int j=0;j<3;j++) { g_pyramidTickets[j] = -1; g_legPeakProfit[j] = 0.0; g_pyramidEntryPrices[j] = 0.0; }
   g_pyramidTickets[0] = newTicket;
   g_pyramidEntryPrices[0] = newEntry;
   g_pyramidLevel = 1;
   g_pyramidLot = newLot;
   g_isReversalFlipPosition = true;
   g_peakProfitMoney = MathMax(0.0, TotalActiveProfitMoney());
   g_worstProfitMoney = MathMin(0.0, TotalActiveProfitMoney());
   g_peakPriceMove = MathMax(0.0, FirstPositionMoveDollar());
   g_state = STATE_POSITION_ACTIVE;
   g_reversalChaserTicket = -1;
   g_reversalChaserDir = 0;
   EnsureInitialSL();
   LogTradeCSV("main", "open", newTicket, newEntry, newLot, newSL, newTP, 0.0, "", "REVERSAL_FLIP");
}

void RecoverOrphanedPosition()
{
   if(CountActivePositions() <= 0) return;
   if(g_positionDirection != 0) return;
   LogEvent("RECOVER_ORPHAN", StringFormat("active=%d pending=%d state=%s",
      CountActivePositions(), CountPendingOrders(), StateToString(g_state)));
   if(!SelectFirstPosition()) return;
   int ticket = g_pyramidTickets[0];
   if(ticket <= 0 || !OrderSelect(ticket, SELECT_BY_TICKET)) return;
   if(!IsOurOrder()) return;
   int type = OrderType();
   g_positionDirection = (type == OP_BUY) ? 1 : -1;
   g_firstEntryPrice = OrderOpenPrice();
   g_pyramidEntryPrices[0] = g_firstEntryPrice;
   g_pyramidLevel = 1;
   g_pyramidLot = OrderLots();
   string orphanComment = OrderComment();
   g_isReversalFlipPosition = (StringFind(orphanComment, "Counter") >= 0 || StringFind(orphanComment, "REVERSAL") >= 0 || StringFind(orphanComment, "reversal") >= 0);
   if(g_pyramidLot <= 0.0) g_pyramidLot = g_lastCalculatedLot;
   g_peakProfitMoney = MathMax(0.0, TotalActiveProfitMoney());
   g_worstProfitMoney = MathMin(0.0, TotalActiveProfitMoney());
   g_peakPriceMove = MathMax(0.0, FirstPositionMoveDollar());
   g_state = STATE_POSITION_ACTIVE;
   DeleteAllPending("orphan_cleanup");
   EnsureInitialSL();
   LogEvent("RECOVER_ORPHAN_OK", StringFormat("dir=%s ticket=%d entry=%.2f",
      (g_positionDirection==1?"BUY":"SELL"), ticket, g_firstEntryPrice));
   if(HedgeEnabled && g_hedgePendingTicket <= 0 && !g_hedgeClosed) PlaceHedgePending();
}

void EnsureInitialSL()
{
   if(!SelectFirstPosition()) return;
   for(int i = 0; i < 3; i++)
   {
      int ticket = g_pyramidTickets[i];
      if(ticket <= 0) continue;
      if(!OrderSelect(ticket, SELECT_BY_TICKET)) continue;
      double expectedSL = 0.0;
      double slDol = GetActiveSLDollar();
      if(OrderType() == OP_BUY) expectedSL = OrderOpenPrice() - slDol;
      if(OrderType() == OP_SELL) expectedSL = OrderOpenPrice() + slDol;
      expectedSL = NormalizePrice(expectedSL);
      if(OrderStopLoss() <= 0.0 || (OrderType()==OP_BUY && OrderStopLoss() < expectedSL - Point*2)
         || (OrderType()==OP_SELL && OrderStopLoss() > expectedSL + Point*2))
      {
         if(!ModifySL(ticket, expectedSL, "ensure_initial_sl"))
         { CloseAllPositions("initial_sl_failed"); g_state = STATE_RESET; return; }
      }
   }
}

bool IsReversalFlipPosition()
{
   if(!UseReversalFlipProtection) return false;
   if(!g_isReversalFlipPosition) return false;
   if(g_pyramidTickets[0] <= 0) return false;
   if(!OrderSelect(g_pyramidTickets[0], SELECT_BY_TICKET)) return false;
   if(OrderCloseTime() > 0) return false;
   return (OrderType() == OP_BUY || OrderType() == OP_SELL);
}

void UpdateProfitPeaks()
{
   double p = TotalActiveProfitMoney();
   double move = FirstPositionMoveDollar();
   if(p > g_peakProfitMoney) g_peakProfitMoney = p;
   if(p < g_worstProfitMoney) g_worstProfitMoney = p;
   if(move > g_peakPriceMove) g_peakPriceMove = move;
}

bool ApplyBreakEvenIfNeeded()
{
   double beStart = P_BE_Start_Dollar;
   double beLock = BE_Lock_Dollar;
   if(IsReversalFlipPosition())
   {
      beStart = ReversalBE_Start_Dollar;
      beLock = ReversalBE_Lock_Dollar;
   }

   if(g_peakProfitMoney < beStart) return false;
   bool modified = false;
   for(int i = 0; i < 3; i++)
   {
      int ticket = g_pyramidTickets[i];
      if(ticket <= 0) continue;
      if(!OrderSelect(ticket, SELECT_BY_TICKET)) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;

      double newSL = 0.0;
      if(OrderType() == OP_BUY) newSL = OrderOpenPrice() + beLock;
      else newSL = OrderOpenPrice() - beLock;

      if(OrderStopLoss() <= 0 || (OrderType() == OP_BUY ? OrderStopLoss() < newSL - Point*2 : OrderStopLoss() > newSL + Point*2))
      {
         if(ModifySL(ticket, newSL, "break_even_lock_leg_" + IntegerToString(i)))
            modified = true;
      }
   }
   return modified;
}

void ApplyReversalTightTrailSL()
{
   if(!IsReversalFlipPosition()) return;
   if(g_peakProfitMoney < ReversalTrailStart_Dollar) return;

   double lockMoney = g_peakProfitMoney - ReversalTrailRetrace_Dollar;
   if(lockMoney <= ReversalBE_Lock_Dollar) return;

   double mpp = MoneyPerPriceUnitPerLot();
   if(mpp <= 0.0) return;

   double totalLot = 0.0;
   for(int i=0; i<3; i++)
   {
      if(g_pyramidTickets[i] > 0 && OrderSelect(g_pyramidTickets[i], SELECT_BY_TICKET) &&
         (OrderType() == OP_BUY || OrderType() == OP_SELL))
         totalLot += OrderLots();
   }
   if(totalLot <= 0.0) return;

   double priceDistance = lockMoney / (mpp * totalLot);
   for(int i = 0; i < 3; i++)
   {
      int ticket = g_pyramidTickets[i];
      if(ticket <= 0) continue;
      if(!OrderSelect(ticket, SELECT_BY_TICKET)) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      double newSL = (OrderType() == OP_BUY)
                     ? NormalizePrice(OrderOpenPrice() + priceDistance)
                     : NormalizePrice(OrderOpenPrice() - priceDistance);
      ModifySL(ticket, newSL, "reversal_tight_trail_leg_" + IntegerToString(i));
   }
}

double GetAllowedRetraceDollar(double peak)
{
   // [V6.46 PATCH] Tiered Trail Adaptif (Skala Profit)
   double base;
   if(peak < 8.0)       base = 2.0;           // small profit: ketat
   else if(peak < 20.0) base = peak * 0.25;   // medium: 25% giveback
   else if(peak < 40.0) base = peak * 0.20;   // large: 20% giveback
   else                 base = peak * 0.15;   // very large: 15% giveback

   if(IsReversalFlipPosition() && g_peakProfitMoney >= ReversalTrailStart_Dollar)
   {
      double revRetrace = MathMax(0.20, ReversalTrailRetrace_Dollar);
      if(base > revRetrace) base = revRetrace;
   }

   if(!UseTrendAdaptiveTrail || g_positionDirection == 0) return base;
   int trendNow = GetTrendDirection();
   double adxNow = iADX(Symbol(), Trend_Timeframe, ADX_Period, PRICE_CLOSE, MODE_MAIN, 1);
   bool trendIntact = (trendNow == g_positionDirection && adxNow >= P_MainEntryMinADX);
   double mult = trendIntact ? TrendIntactTrailMult : TrendWeakTrailMult;
   return base * mult;
}

void ApplyProfitRatchetSL()
{
   if(!UseProfitRatchetSL) return;
   if(g_peakProfitMoney < TrailStart_Dollar) return;

   double floorMoney = (g_peakProfitMoney - GetAllowedRetraceDollar(g_peakProfitMoney)) * ProfitRatchetLockFraction;
   if(floorMoney <= g_ratchetLockedFloor) return;

   double mpp = MoneyPerPriceUnitPerLot();
   if(mpp <= 0.0) return;

   double totalLot = 0;
   for(int i=0; i<3; i++) {
      if(g_pyramidTickets[i] > 0 && OrderSelect(g_pyramidTickets[i], SELECT_BY_TICKET))
         totalLot += OrderLots();
   }
   if(totalLot <= 0) return;
   double priceDistance = floorMoney / (mpp * totalLot);

   for(int i = 0; i < 3; i++)
   {
      int ticket = g_pyramidTickets[i];
      if(ticket <= 0) continue;
      if(!OrderSelect(ticket, SELECT_BY_TICKET)) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;

      double newSL = (OrderType() == OP_BUY)
                     ? NormalizePrice(OrderOpenPrice() + priceDistance)
                     : NormalizePrice(OrderOpenPrice() - priceDistance);

      double curSL = OrderStopLoss();
      bool improves = (OrderType() == OP_BUY) ? (curSL <= 0 || newSL > curSL) : (curSL <= 0 || newSL < curSL);
      if(improves)
      {
         if(ModifySL(ticket, newSL, "profit_ratchet_lock_leg_" + IntegerToString(i)))
            g_ratchetLockedFloor = floorMoney;
      }
   }
   LogEvent("PROFIT_RATCHET_LOCKED", StringFormat("floor=%.2f peak=%.2f", floorMoney, g_peakProfitMoney));
}

void ApplyEarlyLossHardSL()
{
   if(!UseEarlyLossCut) return;
   double effectiveMaxLoss = P_EarlyLossCut_MaxLoss_WhileHedged;
   if(g_peakProfitMoney >= EarlyLossCut_NoPeakAbove) return;

   double mpp = MoneyPerPriceUnitPerLot();
   if(mpp <= 0.0) return;

   double totalLot = 0;
   for(int i=0; i<3; i++) {
      if(g_pyramidTickets[i] > 0 && OrderSelect(g_pyramidTickets[i], SELECT_BY_TICKET))
         totalLot += OrderLots();
   }
   if(totalLot <= 0) return;
   double priceDistance = effectiveMaxLoss / (mpp * totalLot);

   for(int i = 0; i < 3; i++)
   {
      int ticket = g_pyramidTickets[i];
      if(ticket <= 0) continue;
      if(!OrderSelect(ticket, SELECT_BY_TICKET)) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;

      double targetSL = (OrderType() == OP_BUY)
                        ? NormalizePrice(OrderOpenPrice() - priceDistance)
                        : NormalizePrice(OrderOpenPrice() + priceDistance);

      double curSL = OrderStopLoss();
      bool wouldTighten = (OrderType() == OP_BUY) ? (targetSL > curSL) : (targetSL < curSL);
      if(curSL <= 0 || wouldTighten)
      {
         ModifySL(ticket, targetSL, "early_loss_hard_sl_leg_" + IntegerToString(i));
      }
   }
}

void ManagePyramidLegProfit()
{
   if(!UsePyramidIndividualTrail) return;
   if(g_pyramidLevel < 2) return;
   for(int i = 1; i < 3; i++)
   {
      int ticket = g_pyramidTickets[i];
      if(ticket <= 0) continue;
      if(!OrderSelect(ticket, SELECT_BY_TICKET)) continue;
      if(!IsOurOrder()) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;

      double legProfit = OrderProfit() + OrderSwap() + OrderCommission();

      if(legProfit <= -PyramidLegMaxLoss)
      {
         if(CloseSinglePosition(ticket, "pyramid_leg_loss_cap"))
         {
            LogEvent("EXIT_PYRAMID_LEG_LOSS_CAP", StringFormat("level=%d ticket=%d profit=%.2f cap=%.2f", i + 1, ticket, legProfit, PyramidLegMaxLoss));
            g_pyramidTickets[i] = -1;
            g_legPeakProfit[i] = 0.0;
         }
         continue;
      }

      if(legProfit > g_legPeakProfit[i]) g_legPeakProfit[i] = legProfit;
      if(g_legPeakProfit[i] < PyramidLegTrailStart_Dollar) continue;

      double allowedRetrace = GetAllowedRetraceDollar(g_legPeakProfit[i]);
      if((g_legPeakProfit[i] - legProfit) >= allowedRetrace)
      {
         if(CloseSinglePosition(ticket, "pyramid_leg_trail"))
         {
            LogEvent("EXIT_PYRAMID_LEG_TRAIL", StringFormat("level=%d ticket=%d peak=%.2f profit=%.2f allowedRetrace=%.2f",
                     i + 1, ticket, g_legPeakProfit[i], legProfit, allowedRetrace));
            g_pyramidTickets[i] = -1;
            g_legPeakProfit[i] = 0.0;
         }
      }
   }
}

bool ExitDecisionEngine()
{
   if(CountActivePositions() <= 0) { g_exitRequested = false; return false; }
   double profit = TotalActiveProfitMoney();
   double move = FirstPositionMoveDollar();
   if(!SelectFirstPosition()) return false;
   if(!OrderSelect(g_pyramidTickets[0], SELECT_BY_TICKET)) return false;
   int heldMin = (int)((TimeCurrent() - OrderOpenTime()) / 60);
   UpdateProfitPeaks();
   UpdateRiskStatus();

   if(IsReversalFlipPosition() && heldMin >= ReversalFastLossExit_Minutes && profit <= -ReversalFastLossExit_Dollar)
   {
      g_exitRequested = true; g_exitReason = "reversal_fast_loss_exit";
      LogEvent("EXIT_REVERSAL_FAST_LOSS", StringFormat("held=%d profit=%.2f cap=%.2f", heldMin, profit, ReversalFastLossExit_Dollar));
      if(CloseAllPositions(g_exitReason)) { g_state = STATE_RESET; g_exitRequested = false; return true; }
   }

   // [V6.46 PATCH] Smart Early Exit (Soft SL + Momentum)
   if(UseSoftSL_Momentum && profit <= -SoftSL_USD) {
      double rsiNow = iRSI(Symbol(), PERIOD_M5, RSI_Period, PRICE_CLOSE, 0);
      bool momentumAgainst = (g_positionDirection == 1 && rsiNow < SoftSL_RSIThresh) ||
                             (g_positionDirection == -1 && rsiNow > (100 - SoftSL_RSIThresh));
      if(momentumAgainst) {
         g_exitRequested = true; g_exitReason = "soft_sl_momentum";
         LogEvent("EXIT_SOFT_SL_MOMENTUM", StringFormat("profit=%.2f rsi=%.1f dir=%d", profit, rsiNow, g_positionDirection));
         if(CloseAllPositions(g_exitReason)) { g_state = STATE_RESET; g_exitRequested = false; return true; }
      }
   }

   if(P_UseTrendFlipExit && g_positionDirection != 0 && g_peakProfitMoney < P_TrendFlipExit_MinPeakToIgnore)
   {
      int trendNowForExit = GetTrendDirection();
      if(trendNowForExit != 0 && trendNowForExit != g_positionDirection)
      {
         g_exitRequested = true; g_exitReason = "trend_flip_exit";
         LogEvent("EXIT_TREND_FLIP", StringFormat("posDir=%d trendNow=%d profit=%.2f peak=%.2f",
                  g_positionDirection, trendNowForExit, profit, g_peakProfitMoney));
         if(CloseAllPositions(g_exitReason)) { g_state = STATE_RESET; g_exitRequested = false; return true; }
      }
   }
   double mppNow   = MoneyPerPriceUnitPerLot();
   double slDistNow = GetActiveSLDollar();
   double baseLotNow = (g_pyramidLot > 0.0) ? g_pyramidLot : g_lastCalculatedLot;
   double technicalRiskMoney = (mppNow > 0.0 && baseLotNow > 0.0)
                               ? slDistNow * baseLotNow * mppNow
                               : P_MaxLossMoney;
   double emergencyBufferMult = 1.15;
   double scaledMaxLoss = technicalRiskMoney * emergencyBufferMult * MathMax(1.0, g_pyramidLevel * 0.8);
   double dynamicMaxLoss = scaledMaxLoss;
   if(UseV1DProfitLockGuard && g_peakProfitMoney >= V1D_MicroProfitStartMoney)
      dynamicMaxLoss = MathMin(dynamicMaxLoss, V1D_MaxLossAfterProfit);
   else if(UseV1DProfitLockGuard && g_peakProfitMoney >= V1D_MinProfitPeakForTightLoss)
      dynamicMaxLoss = MathMin(dynamicMaxLoss, V1D_TightLossAfterSmallPeak);

   double effectiveEarlyLossCap = P_EarlyLossCut_MaxLoss_WhileHedged;
   if(UseEarlyLossCut && g_peakProfitMoney < EarlyLossCut_NoPeakAbove && profit <= -effectiveEarlyLossCap)
   { g_exitRequested = true; g_exitReason = "early_loss_cut";
     LogEvent("EXIT_EARLY_LOSS_CUT", StringFormat("profit=%.2f peak=%.2f cap=%.2f", profit, g_peakProfitMoney, effectiveEarlyLossCap));
     if(CloseAllPositions(g_exitReason)) { g_state = STATE_RESET; g_exitRequested = false; return true; } }

   if(UseV1DProfitLockGuard && g_peakProfitMoney >= V1D_MicroProfitStartMoney && profit <= -V1D_ProfitToLossCutMoney)
   { g_exitRequested = true; g_exitReason = "v1d_profit_to_loss";
     LogEvent("EXIT_V1D_PROFIT_TO_LOSS", StringFormat("profit=%.2f peak=%.2f", profit, g_peakProfitMoney));
     if(CloseAllPositions(g_exitReason)) { g_state = STATE_RESET; g_exitRequested = false; return true; } }

   if(profit <= -dynamicMaxLoss)
   { g_exitRequested = true; g_exitReason = "emergency_loss";
     LogEvent("EXIT_EMERGENCY_LOSS", StringFormat("profit=%.2f max=%.2f", profit, dynamicMaxLoss));
     if(CloseAllPositions(g_exitReason)) { g_state = STATE_RESET; g_exitRequested = false; return true; } }

   if(g_peakProfitMoney >= TrailStart_Dollar)
   {
      double allowedRetrace = GetAllowedRetraceDollar(g_peakProfitMoney);
      if((g_peakProfitMoney - profit) >= allowedRetrace)
      { g_exitRequested = true; g_exitReason = "tiered_profit_trail";
        LogEvent("EXIT_TIERED_TRAIL", StringFormat("profit=%.2f peak=%.2f allowedRetrace=%.2f", profit, g_peakProfitMoney, allowedRetrace));
        if(CloseAllPositions(g_exitReason)) { g_state = STATE_RESET; g_exitRequested = false; return true; } }
   }

   if(UseV1DProfitLockGuard && g_peakProfitMoney >= V1D_MicroProfitStartMoney)
   { double microRetrace = g_peakProfitMoney - profit;
     double minMicroDrop = MathMax(0.50, GetAllowedRetraceDollar(g_peakProfitMoney));
     if(profit <= V1D_MicroProfitLockMoney && microRetrace >= minMicroDrop)
     { g_exitRequested = true; g_exitReason = "v1d_micro_profit_lock";
       LogEvent("EXIT_V1D_MICRO_LOCK", StringFormat("profit=%.2f peak=%.2f", profit, g_peakProfitMoney));
       if(CloseAllPositions(g_exitReason)) { g_state = STATE_RESET; g_exitRequested = false; return true; } } }

   if(heldMin >= MaxHoldMinutes && profit >= TimeExitMinProfit && profit <= TimeExitMaxProfit)
   { g_exitRequested = true; g_exitReason = "time_based";
     LogEvent("EXIT_TIME_BASED", StringFormat("held=%d profit=%.2f", heldMin, profit));
     if(CloseAllPositions(g_exitReason)) { g_state = STATE_RESET; g_exitRequested = false; return true; } }

   // [V6.46 PATCH] Time Loss Exit (Replaces small_opp_lost)
   if(heldMin >= TimeLossExitMinutes && profit <= -TimeLossExitUSD)
   { g_exitRequested = true; g_exitReason = "time_loss_exit";
     LogEvent("EXIT_TIME_LOSS", StringFormat("held=%d profit=%.2f", heldMin, profit));
     if(CloseAllPositions(g_exitReason)) { g_state = STATE_RESET; g_exitRequested = false; return true; } }

   g_exitRequested = false;
   return false;
}

void ManageActivePosition()
{
   if(CountActivePositions() <= 0) return;
   g_state = STATE_MANAGE_PROFIT;
   EnsureInitialSL();
   if(CountActivePositions() <= 0) return;
   if(g_exitRequested && g_exitReason != "")
   {
      if(TradeAllowedNow())
      { if(CloseAllPositions(g_exitReason + "_retry"))
        { g_state = STATE_RESET; g_exitRequested = false; g_exitReason = ""; return; } }
      LogEvent("EXIT_RETRY_PENDING", StringFormat("reason=%s profit=%.2f", g_exitReason, TotalActiveProfitMoney()));
      return;
   }
   bool pyramidJustAdded = false;
   if(UsePyramid && g_pyramidLevel < PyramidMaxPositions) pyramidJustAdded = AddPyramidPosition();
   if(pyramidJustAdded)
   { LogEvent("PYRAMID_SKIP_EXIT", ""); ApplyBreakEvenIfNeeded(); return; }
   if(HedgeEnabled && g_hedgePendingTicket <= 0 && g_hedgeTicket <= 0 && !g_hedgeClosed)
      PlaceHedgePending();
   if(HedgeEnabled) ManageHedge();
   ManageReversalChaser();
   ManagePyramidLegProfit();
   if(ExitDecisionEngine()) return;
   ApplyBreakEvenIfNeeded();
   ApplyReversalTightTrailSL();
   ApplyEarlyLossHardSL();
   ApplyProfitRatchetSL();
}

void TrailPendingIfNeeded()
{
   if(!TrailPendingOrders) return;
   if(g_pendingTrailCount >= PendingTrailMaxModifications) return;
   if(!TradeAllowedNow()) return;
   RefreshRates();
   double dist = CalculatePendingDistance();
   if(g_buyStopTicket > 0)
   {
      if(OrderSelect(g_buyStopTicket, SELECT_BY_TICKET) && IsOurOrder() && OrderType() == OP_BUYSTOP)
      {
         double idealBuyPrice = NormalizePrice(Ask + dist);
         double currentBuyPrice = OrderOpenPrice();
         if(idealBuyPrice < currentBuyPrice - PendingTrailMinMove)
         {
            double newBuySL = NormalizePrice(idealBuyPrice - P_InitialSL_Dollar);
            double newBuyTP = CalculateTakeProfit(idealBuyPrice, 1);
            ResetLastError();
            if(OrderModify(g_buyStopTicket, idealBuyPrice, newBuySL, newBuyTP, 0, clrNONE))
            { g_pendingTrailCount++; LogEvent("BUY_STOP_TRAILED", StringFormat("Old=%.2f New=%.2f", currentBuyPrice, idealBuyPrice)); }
            else { int err = GetLastError(); if(err != 1) LogEvent("BUY_STOP_TRAIL_FAIL", StringFormat("err=%d", err)); ResetLastError(); }
         }
      }
   }
   if(g_sellStopTicket > 0)
   {
      if(OrderSelect(g_sellStopTicket, SELECT_BY_TICKET) && IsOurOrder() && OrderType() == OP_SELLSTOP)
      {
         double idealSellPrice = NormalizePrice(Bid - dist);
         double currentSellPrice = OrderOpenPrice();
         if(idealSellPrice > currentSellPrice + PendingTrailMinMove)
         {
            double newSellSL = NormalizePrice(idealSellPrice + P_InitialSL_Dollar);
            double newSellTP = CalculateTakeProfit(idealSellPrice, -1);
            ResetLastError();
            if(OrderModify(g_sellStopTicket, idealSellPrice, newSellSL, newSellTP, 0, clrNONE))
            { g_pendingTrailCount++; LogEvent("SELL_STOP_TRAILED", StringFormat("Old=%.2f New=%.2f", currentSellPrice, idealSellPrice)); }
            else { int err = GetLastError(); if(err != 1) LogEvent("SELL_STOP_TRAIL_FAIL", StringFormat("err=%d", err)); ResetLastError(); }
         }
      }
   }
}

void ManagePendingOrders()
{
   if(CountPendingOrders() <= 0) return;
   int ageMin = (g_cycleStartTime > 0) ? (int)((TimeCurrent() - g_cycleStartTime) / 60) : 0;
   if(ageMin >= P_PendingExpireMinutes)
   { DeleteAllPending("pending_expired"); g_state = STATE_RESET; return; }
   if(SpreadPoints() > P_MaxSpreadPoints * 2)
   { DeleteAllPending("wide_spread"); g_state = STATE_RESET; return; }
   TrailPendingIfNeeded();
}

double GetRealizedPnLSinceCycleStart()
{
   double total = 0.0;
   int found = 0;
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL) continue;
      if(OrderCloseTime() == 0) continue;
      if(g_cycleStartTime > 0 && OrderCloseTime() < g_cycleStartTime) continue;
      total += OrderProfit() + OrderSwap() + OrderCommission();
      found++;
   }
   if(found == 0)
   {
      if(g_worstProfitMoney < -1.0) return g_worstProfitMoney;
      if(g_peakProfitMoney < 1.0) return 0.0;
      return g_peakProfitMoney * 0.5;
   }
   return total;
}

void RecordCycleResult(double cyclePnL)
{
   g_lastCyclePnL = cyclePnL;
   g_tradeHist[g_tradeHistIdx] = cyclePnL;
   g_tradeHistIdx = (g_tradeHistIdx + 1) % KELLY_MAX;
   if(g_tradeHistCount < KELLY_MAX) g_tradeHistCount++;

   if(cyclePnL < -1.0)
   {
      g_consecutiveLosses++;
      g_dailyLosses++;
      if(g_consecutiveLosses >= P_MaxConsecutiveCycleLosses && P_MaxConsecutiveCycleLosses > 0)
      {
         g_lossPauseUntil = TimeCurrent() + P_ConsecutiveLossPauseSec;
         LogEvent("CONSECUTIVE_LOSS_PAUSE", StringFormat("losses=%d pauseUntil=%s", g_consecutiveLosses,
                  TimeToString(g_lossPauseUntil, TIME_DATE | TIME_SECONDS)));
      }
      if(UseHardStopConsecutiveLosses &&
         g_consecutiveLosses >= HardStopConsecutiveLosses && HardStopConsecutiveLosses > 0)
      {
         g_lossPauseUntil = TimeCurrent() + HardStopPauseSec;
         LogEvent("CONSEC_LOSS_HARD_STOP", StringFormat("losses=%d threshold=%d pause=%ds",
                  g_consecutiveLosses, HardStopConsecutiveLosses, HardStopPauseSec));
      }
      if(UseHardStopFullDay && P_HardStopFullDayThreshold > 0 &&
         g_consecutiveLosses >= P_HardStopFullDayThreshold && !g_consecLossHardStopped)
      {
         g_consecLossHardStopped = true;
         GlobalVariableSet(GVKey("consecHardStop"), 1.0);
         LogEvent("CONSEC_LOSS_FULL_DAY_STOP", StringFormat(
                  "losses=%d threshold=%d — no new cycles until next calendar day",
                  g_consecutiveLosses, P_HardStopFullDayThreshold));
      }
   }
   else
   {
      if(cyclePnL > 1.0) g_dailyWins++;
      g_consecutiveLosses = 0;
   }
}

void ResetCycleIfClean()
{
   if(CountActivePositions() > 0 || CountPendingOrders() > 0) return;
   bool wasRunningCycle = (g_state != STATE_IDLE && g_state != STATE_BLOCKED_BY_FILTER);
   if(wasRunningCycle)
   {
      double cyclePnL = GetRealizedPnLSinceCycleStart();
      RecordCycleResult(cyclePnL);
      LogEvent("CYCLE_RESET", StringFormat("oldState=%s realizedPnL=%.2f peak=%.2f worst=%.2f pyramid=%d consLosses=%d",
               StateToString(g_state), cyclePnL, g_peakProfitMoney, g_worstProfitMoney, g_pyramidLevel, g_consecutiveLosses));
   }
   g_buyStopTicket=-1; g_sellStopTicket=-1;
   g_firstEntryPrice=0.0; g_positionDirection=0;
   g_peakProfitMoney=0.0; g_peakPriceMove=0.0; g_worstProfitMoney=0.0;
   g_pyramidLevel=0; g_pyramidLastAddTime=0; g_pyramidLot=0.0;
   g_exitRequested=false; g_exitReason="";
   g_pendingTrailCount=0;
   g_hedgePendingTicket=-1; g_hedgePendingTime=0;
   g_hedgeTicket=-1; g_hedgeDirection=0; g_hedgeLot=0.0;
   g_hedgeOpenTime=0; g_hedgePeakProfit=0.0; g_hedgeClosed=false; g_hedgeRearmCount=0;
   g_hedgeAdverseSince=0;
   g_ratchetLockedFloor=-999999.0;
   g_isReversalFlipPosition=false;
   for(int i=0;i<3;i++){g_pyramidTickets[i]=-1;g_pyramidEntryPrices[i]=0.0;g_legPeakProfit[i]=0.0;}
   g_risk=RISK_SAFE; g_state=STATE_IDLE;
   if(wasRunningCycle) g_lastResetTime=TimeCurrent();
   else if(g_lastResetTime<=0) g_lastResetTime=TimeCurrent()-P_RestartDelaySeconds-1;
}

//============================ SINGLE INSTANCE ==========================
bool AcquireSingleInstanceLock()
{
   if(!EnforceSingleInstance) return true;
   g_instanceOwnerKey=StringFormat("%s_%s_%d_owner",EA_Name,Symbol(),MagicNumber);
   g_instanceBeatKey=StringFormat("%s_%s_%d_beat",EA_Name,Symbol(),MagicNumber);
   double myOwner=(double)ChartID(), oldOwner=0.0, oldBeat=0.0;
   if(GlobalVariableCheck(g_instanceOwnerKey)) oldOwner=GlobalVariableGet(g_instanceOwnerKey);
   if(GlobalVariableCheck(g_instanceBeatKey)) oldBeat=GlobalVariableGet(g_instanceBeatKey);
   if(GlobalVariableCheck(g_instanceOwnerKey)&&oldOwner!=myOwner&&oldBeat>0.0&&(TimeCurrent()-(datetime)oldBeat)<60)
   { LogEvent("SINGLE_INSTANCE_BLOCK",StringFormat("existing=%.0f my=%.0f",oldOwner,myOwner)); return false; }
   GlobalVariableSet(g_instanceOwnerKey,myOwner); GlobalVariableSet(g_instanceBeatKey,(double)TimeCurrent()); return true;
}
void UpdateSingleInstanceHeartbeat()
{ if(!EnforceSingleInstance||g_instanceOwnerKey=="") return;
  if(GlobalVariableCheck(g_instanceOwnerKey)&&GlobalVariableGet(g_instanceOwnerKey)==(double)ChartID())
    GlobalVariableSet(g_instanceBeatKey,(double)TimeCurrent()); }
void ReleaseSingleInstanceLock()
{ if(!EnforceSingleInstance||g_instanceOwnerKey=="") return;
  if(GlobalVariableCheck(g_instanceOwnerKey)&&GlobalVariableGet(g_instanceOwnerKey)==(double)ChartID())
  { GlobalVariableDel(g_instanceOwnerKey);GlobalVariableDel(g_instanceBeatKey); } }

//============================ [V6-01] PRESETS ============================
void ApplyPreset()
{
   P_MaxLossMoney              = MaxLossMoney;
   P_InitialSL_Dollar          = InitialSL_Dollar;
   P_HedgeMaxNegDollar         = HedgeMaxNegDollar;
   P_HedgeLotRatio             = HedgeLotRatio;
   P_HedgeSL_Dollar            = HedgeSL_Dollar;
   P_HedgeBlockMinusMaxLossDollar = HedgeBlockMinusMaxLossDollar;
   P_MaxDailyDrawdownPct       = MaxDailyDrawdownPct;
   P_ADX_Threshold             = ADX_Threshold;
   P_RiskPercent               = RiskPercent;
   P_AutoLotPer1000            = AutoLotPer1000;
   P_MainEntryMinADX           = MainEntryMinADX;
   P_RSI_Oversold              = RSI_Oversold;
   P_RSI_Overbought            = RSI_Overbought;
   P_PyramidMinADX             = PyramidMinADX;
   P_PyramidMinATRMult         = PyramidMinATRMult;
   P_PyramidMaxATRMult         = PyramidMaxATRMult;
   P_AdaptiveADXStepPerLoss    = AdaptiveADXStepPerLoss;
   P_MaxAdaptiveADXAdd         = MaxAdaptiveADXAdd;
   P_RestartDelaySeconds       = RestartDelaySeconds;
   P_ConsecutiveLossPauseSec   = ConsecutiveLossPauseSec;
   P_MaxConsecutiveCycleLosses = MaxConsecutiveCycleLosses;
   P_TrendMinSepATRMult        = TrendMinSepATRMult;
   P_FastConfirm_MinSepATRMult = FastConfirm_MinSepATRMult;
   P_MinATR_Dollar             = MinATR_Dollar;
   P_MaxSpreadPoints           = MaxSpreadPoints;
   P_PendingExpireMinutes      = PendingExpireMinutes;
   P_BE_Start_Dollar           = BE_Start_Dollar;
   P_TrailDrop_SmallPeak       = TrailDrop_SmallPeak;
   P_TrailDrop_MedPeak         = TrailDrop_MedPeak;
   P_TrendFlipExit_MinPeakToIgnore = TrendFlipExit_MinPeakToIgnore;
   P_HardStopFullDayThreshold  = HardStopFullDayThreshold;
   P_UseAdaptiveADXOnLosses    = UseAdaptiveADXOnLosses;
   P_UseFastTrendConfirm       = UseFastTrendConfirm;
   P_UseReversalChaser         = UseReversalChaser;
   P_UseMeanReversionEntry     = UseMeanReversionEntry;
   P_UseRangeBoundEntry        = UseRangeBoundEntry;
   P_UseTrendFlipExit          = UseTrendFlipExit;
   P_EarlyLossCut_MaxLoss_WhileHedged = EarlyLossCut_MaxLoss_WhileHedged;

   // ===== CONSERVATIVE (PresetMode==1) =====
   if(PresetMode == 1)
   {
      P_MaxLossMoney=15.0; P_InitialSL_Dollar=12.0; P_HedgeMaxNegDollar=8.0;
      P_HedgeLotRatio=0.75; P_HedgeSL_Dollar=3.0; P_HedgeBlockMinusMaxLossDollar=8.0;
      P_MaxDailyDrawdownPct=2.0; P_ADX_Threshold=28.0;
      P_RiskPercent=0.75; P_AutoLotPer1000=0.07;
      P_MainEntryMinADX=25.0; P_RSI_Oversold=25.0; P_RSI_Overbought=75.0; 
      P_PyramidMinADX=25.0; P_PyramidMinATRMult=0.80; P_PyramidMaxATRMult=1.20;
      P_AdaptiveADXStepPerLoss=3.0; P_MaxAdaptiveADXAdd=6.0;
      P_RestartDelaySeconds=300; P_ConsecutiveLossPauseSec=900; P_MaxConsecutiveCycleLosses=2;
      P_TrendMinSepATRMult=0.20; P_FastConfirm_MinSepATRMult=0.20;
      P_MinATR_Dollar=2.0; P_MaxSpreadPoints=35; P_PendingExpireMinutes=15;
      P_BE_Start_Dollar=8.0; P_TrailDrop_SmallPeak=2.0; P_TrailDrop_MedPeak=5.0;
      P_TrendFlipExit_MinPeakToIgnore=10.0; P_HardStopFullDayThreshold=5;
      P_UseAdaptiveADXOnLosses=true; P_UseFastTrendConfirm=true;
      P_UseReversalChaser=false; P_UseMeanReversionEntry=false; P_UseRangeBoundEntry=false;
      P_UseTrendFlipExit=false;
      P_EarlyLossCut_MaxLoss_WhileHedged = 8.0;
   }
   // ===== BALANCED (PresetMode==2) =====
   else if(PresetMode == 2)
   {
      P_MaxLossMoney=30.0; P_InitialSL_Dollar=12.0; P_HedgeMaxNegDollar=10.0;
      P_HedgeLotRatio=1.00; P_HedgeSL_Dollar=3.0; P_HedgeBlockMinusMaxLossDollar=12.0;
      P_MaxDailyDrawdownPct=3.0; P_ADX_Threshold=25.0;
      P_RiskPercent=1.00; P_AutoLotPer1000=0.10;
      P_MainEntryMinADX=22.0; P_RSI_Oversold=20.0; P_RSI_Overbought=80.0; 
      P_PyramidMinADX=22.0; P_PyramidMinATRMult=0.55; P_PyramidMaxATRMult=1.30;
      P_AdaptiveADXStepPerLoss=2.0; P_MaxAdaptiveADXAdd=6.0;
      P_RestartDelaySeconds=300; P_ConsecutiveLossPauseSec=900; P_MaxConsecutiveCycleLosses=3;
      P_TrendMinSepATRMult=0.15; P_FastConfirm_MinSepATRMult=0.12;
      P_MinATR_Dollar=2.0; P_MaxSpreadPoints=50; P_PendingExpireMinutes=30;
      P_BE_Start_Dollar=8.0; P_TrailDrop_SmallPeak=2.0; P_TrailDrop_MedPeak=5.0;
      P_TrendFlipExit_MinPeakToIgnore=8.0; P_HardStopFullDayThreshold=6;
      P_UseAdaptiveADXOnLosses=true; P_UseFastTrendConfirm=true;
      P_UseReversalChaser=false; P_UseMeanReversionEntry=false; P_UseRangeBoundEntry=false;
      P_UseTrendFlipExit=false;
      P_EarlyLossCut_MaxLoss_WhileHedged = 8.0;
   }
   // ===== AGGRESSIVE (PresetMode==3) — FILTER RELAXATION =====
   else if(PresetMode == 3)
   {
      // Risk sizing
      P_MaxLossMoney=50.0; P_InitialSL_Dollar=12.0; P_HedgeMaxNegDollar=10.0;
      P_HedgeLotRatio=1.25; P_HedgeSL_Dollar=3.0; P_HedgeBlockMinusMaxLossDollar=16.0;
      P_MaxDailyDrawdownPct=4.0; P_ADX_Threshold=22.0;
      P_RiskPercent=1.50; P_AutoLotPer1000=0.15;

      // Entry gates - Relaxed
      P_MainEntryMinADX       = 20.0; 
      P_RSI_Oversold          = 15.0; 
      P_RSI_Overbought        = 85.0; 
      P_PyramidMinADX         = 20.0; 
      P_PyramidMinATRMult     = 0.80;
      P_PyramidMaxATRMult     = 1.60;
      P_AdaptiveADXStepPerLoss= 1.0;  
      P_MaxAdaptiveADXAdd     = 4.0;  

      // Frequency
      P_RestartDelaySeconds       = 300;
      P_ConsecutiveLossPauseSec   = 900;
      P_MaxConsecutiveCycleLosses = 3;

      P_TrendMinSepATRMult        = 0.15;
      P_FastConfirm_MinSepATRMult = 0.10;
      P_MinATR_Dollar             = 2.0;
      P_MaxSpreadPoints           = 50;
      P_PendingExpireMinutes      = 30;
      
      P_BE_Start_Dollar           = 8.0;  
      P_TrailDrop_SmallPeak       = 2.0;  
      P_TrailDrop_MedPeak         = 5.0;  
      P_TrendFlipExit_MinPeakToIgnore = 8.0; 
      P_HardStopFullDayThreshold  = 6;
      P_UseAdaptiveADXOnLosses    = true;
      P_UseFastTrendConfirm       = true;
      
      P_UseReversalChaser         = false;
      P_UseMeanReversionEntry     = false;
      P_UseRangeBoundEntry        = false;
      P_UseTrendFlipExit          = false;
      
      P_EarlyLossCut_MaxLoss_WhileHedged = 8.0;
   }
}

string PresetName()
{
   if(PresetMode == 1) return "CONSERVATIVE";
   if(PresetMode == 2) return "BALANCED";
   if(PresetMode == 3) return "AGGRESSIVE";
   return "MANUAL";
}

//============================ [V6-06] DASHBOARD ============================
void Dashboard_Destroy()
{
   for(int i = ObjectsTotal() - 1; i >= 0; i--)
   {
      string name = ObjectName(i);
      if(StringFind(name, g_dashPrefix) == 0) ObjectDelete(name);
   }
   g_dashLineCount = 0;
}

void Dash_Line(int lineNo, string text, color clr)
{
   string name = g_dashPrefix + IntegerToString(lineNo);
   if(ObjectFind(name) < 0)
   {
      ObjectCreate(name, OBJ_LABEL, 0, 0, 0);
      ObjectSet(name, OBJPROP_CORNER, 0);
      ObjectSet(name, OBJPROP_XDISTANCE, Dashboard_X);
      ObjectSet(name, OBJPROP_YDISTANCE, Dashboard_Y + lineNo * (Dashboard_FontSize + 5));
      ObjectSet(name, OBJPROP_BACK, false);
      ObjectSet(name, OBJPROP_SELECTABLE, false);
   }
   ObjectSetText(name, text, Dashboard_FontSize, Dashboard_Font, clr);
}

color Dash_ColorForPnL(double v)
{
   if(v > 0.01) return Dash_ColorProfit;
   if(v < -0.01) return Dash_ColorLoss;
   return Dash_ColorMuted;
}

void Dashboard_Update()
{
   if(!ShowDashboard) return;
   if(TimeCurrent() - g_dashLastUpdate < Dashboard_UpdateSec) return;
   g_dashLastUpdate = TimeCurrent();

   int line = 0;
   Dash_Line(line++, StringFormat("=== %s v7.0 | %s M%d ===", EA_Name, Symbol(), Period()), Dash_ColorText);
   Dash_Line(line++, StringFormat("Preset: %s   State: %s", PresetName(), StateToString(g_state)), Dash_ColorText);

   int spread = SpreadPoints();
   double atr = iATR(Symbol(), PERIOD_M5, ATR_Period, 0);
   color spColor = (spread > P_MaxSpreadPoints) ? Dash_ColorWarn : Dash_ColorMuted;
   Dash_Line(line++, StringFormat("Spread: %d pts   ATR: $%.2f", spread, atr), spColor);

   int active = CountActivePositions();
   double totalProfit = TotalActiveProfitMoney();
   if(active > 0 && SelectFirstPosition() && OrderSelect(g_pyramidTickets[0], SELECT_BY_TICKET))
   {
      int heldMin = (int)((TimeCurrent() - OrderOpenTime()) / 60);
      Dash_Line(line++, StringFormat("--- POSITION (Lv%d) ---", g_pyramidLevel), Dash_ColorText);
      Dash_Line(line++, StringFormat("Dir: %s  Lot: %.2f  Entry: %.2f",
                (g_positionDirection==1?"BUY":"SELL"), g_pyramidLot, g_firstEntryPrice), Dash_ColorText);
      Dash_Line(line++, StringFormat("SL: %.2f  TP: %.2f  Held: %dm",
                OrderStopLoss(), OrderTakeProfit(), heldMin), Dash_ColorMuted);
      Dash_Line(line++, StringFormat("P/L: $%.2f   Peak: $%.2f", totalProfit, g_peakProfitMoney),
                Dash_ColorForPnL(totalProfit));
   }
   else
   {
      Dash_Line(line++, "--- POSITION: none ---", Dash_ColorMuted);
      Dash_Line(line++, "", Dash_ColorMuted);
      Dash_Line(line++, "", Dash_ColorMuted);
      Dash_Line(line++, "", Dash_ColorMuted);
   }

   string hedgeStatus = "none";
   double hedgeProfit = 0.0;
   if(g_hedgePendingTicket > 0) hedgeStatus = "PENDING";
   else if(g_hedgeTicket > 0) { hedgeStatus = "ACTIVE"; hedgeProfit = HedgeProfitMoney(); }
   Dash_Line(line++, StringFormat("--- HEDGE: %s ---", hedgeStatus), Dash_ColorText);
   Dash_Line(line++, StringFormat("Lot: %.2f  P/L: $%.2f  Peak: $%.2f",
             g_hedgeLot, hedgeProfit, g_hedgePeakProfit), Dash_ColorForPnL(hedgeProfit));

   double dailyPnL = AccountEquity() - g_dailyStartEquity;
   double weeklyPnL = AccountEquity() - g_weeklyStartEquity;
   double kellyMult = GetKellyLiteMultiplier();
   Dash_Line(line++, "--- RISK METER ---", Dash_ColorText);
   Dash_Line(line++, StringFormat("Daily P/L: $%.2f  Weekly: $%.2f", dailyPnL, weeklyPnL),
             Dash_ColorForPnL(dailyPnL));
   Dash_Line(line++, StringFormat("ConsecLoss: %d  NextLot: %.2f (K=%.2f)",
             g_consecutiveLosses, g_lastCalculatedLot, kellyMult), Dash_ColorText);

   int totalTrades = g_dailyWins + g_dailyLosses;
   double wr = (totalTrades > 0) ? (100.0 * g_dailyWins / totalTrades) : 0.0;
   Dash_Line(line++, "--- CYCLE STATS ---", Dash_ColorText);
   Dash_Line(line++, StringFormat("Today: %d trades  W/L: %d/%d  WR: %.0f%%",
             totalTrades, g_dailyWins, g_dailyLosses, wr), Dash_ColorText);
   Dash_Line(line++, StringFormat("Cycle #%d  Session: %s", g_cycleId, SessionName()), Dash_ColorMuted);

   string warn = "";
   color warnColor = Dash_ColorMuted;
   if(spread > P_MaxSpreadPoints) { warn = "! HIGH SPREAD"; warnColor = Dash_ColorLoss; }
   else if(IsNewsWindow()) { warn = "! NEWS WINDOW"; warnColor = Dash_ColorWarn; }
   else if(g_dailyLossPaused && (UseDailyLossLimit || UseDailyDrawdownPct)) { warn = "! DAILY LIMIT HIT"; warnColor = Dash_ColorLoss; }
   else if(g_weeklyLossPaused && UseWeeklyLossLimit) { warn = "! WEEKLY LIMIT HIT"; warnColor = Dash_ColorLoss; }
   else if(g_consecLossHardStopped) { warn = StringFormat("! HARD STOP (%d losses)", g_consecutiveLosses); warnColor = Dash_ColorLoss; }
   else if(g_mrLossPauseUntil > 0 && TimeCurrent() < g_mrLossPauseUntil) { warn = StringFormat("MR PAUSED (%ds left)", (int)(g_mrLossPauseUntil - TimeCurrent())); warnColor = Dash_ColorWarn; }
   else if(g_state == STATE_BLOCKED_BY_FILTER) { warn = "BLOCKED: " + g_lastBlockReason; warnColor = Dash_ColorWarn; }
   else { warn = "OK"; warnColor = Dash_ColorProfit; }
   Dash_Line(line++, StringFormat("[%s]", warn), warnColor);

   g_dashLineCount = line;
   WindowRedraw();
}

//============================ MT4 EVENTS ==============================
int OnInit()
{
   g_state=STATE_IDLE;g_risk=RISK_SAFE;g_cycleId=(int)TimeCurrent();g_csvHandle=INVALID_HANDLE;
   g_tradeLogHandle=INVALID_HANDLE;g_lastBlockReason="";
   g_pyramidLevel=0;g_pyramidLastAddTime=0;g_positionDirection=0;
   g_exitRequested=false;g_exitReason="";
   g_consecutiveLosses=0;g_lossPauseUntil=0;g_lastCyclePnL=0.0;
   g_mrConsecutiveLosses=0;g_mrLossPauseUntil=0;
   g_hedgePendingTicket=-1; g_hedgePendingTime=0;
   g_hedgeTicket=-1; g_hedgeDirection=0; g_hedgeLot=0.0;
   g_hedgeOpenTime=0; g_hedgePeakProfit=0.0; g_hedgeClosed=false; g_hedgeRearmCount=0;
   g_hedgeLastCloseTime=0; g_hedgeAdverseSince=0;
   g_ratchetLockedFloor=-999999.0;
   g_isReversalFlipPosition=false;
   g_tradeHistCount=0; g_tradeHistIdx=0;
   g_dailyWins=0; g_dailyLosses=0;
   for(int i=0;i<3;i++){g_pyramidTickets[i]=-1;g_pyramidEntryPrices[i]=0.0;g_legPeakProfit[i]=0.0;}
   for(int i=0;i<KELLY_MAX;i++) g_tradeHist[i]=0.0;
   for(int i=0;i<50;i++){g_slFailTicket[i]=-1;g_slFailSince[i]=0;}

   g_mrTicket = -1; g_rangeTicket = -1;
   for(int mi = OrdersTotal() - 1; mi >= 0; mi--)
   { if(!OrderSelect(mi, SELECT_BY_POS, MODE_TRADES)) continue;
     if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
     if(StringFind(OrderComment(), "ISOBOX") < 0) continue;
     if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
     if(StringFind(OrderComment(), "RangeBound") >= 0) { if(g_rangeTicket <= 0) g_rangeTicket = OrderTicket(); }
     else { if(g_mrTicket <= 0) g_mrTicket = OrderTicket(); } }

   ApplyPreset();
   ParseNewsTimes();

   if(!AcquireSingleInstanceLock()) return(INIT_FAILED);

   LogEvent("EA_INIT", StringFormat("V7.1|Preset=%s|MaxLoss=$%.1f SL=$%.1f RiskPct=%.2f|HedgeMaxNeg=$%.1f LotRatio=%.2f ConfirmBars=%d Cooldown=%ds|DailyDD=%.1f%% WeeklyLim=$%.0f|AutoLotMode=%s|Session=%s NewsFilter=%s (%d times)",
      PresetName(), P_MaxLossMoney, P_InitialSL_Dollar, P_RiskPercent,
      P_HedgeMaxNegDollar, P_HedgeLotRatio, HedgeMinConfirmBars, HedgeCooldownSec,
      P_MaxDailyDrawdownPct, MaxWeeklyLossMoney,
      AutoLotModeToString(), SessionName(),
      UseNewsFilter?"ON":"OFF", g_newsCount));

   LoadOrInitDailyBaseline();
   LoadOrInitWeeklyBaseline();

   {
      int savedChaserTicket = (int)GlobalVariableGet(GVKey("chaserTicket"));
      if(savedChaserTicket > 0 && OrderSelect(savedChaserTicket, SELECT_BY_TICKET) &&
         IsOurOrder() && (OrderType() == OP_BUYSTOP || OrderType() == OP_SELLSTOP))
      {
         g_reversalChaserTicket = savedChaserTicket;
         g_reversalChaserDir = (int)GlobalVariableGet(GVKey("chaserDir"));
      }
      else
      { g_reversalChaserTicket = -1; g_reversalChaserDir = 0; }
   }

   if(ShowDashboard) Dashboard_Destroy();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   LogEvent("EA_DEINIT", StringFormat("reason=%d", reason));
   CloseCSV();
   CloseTradeLogger();
   Dashboard_Destroy();
   ReleaseSingleInstanceLock();
}

void ReconcileClosedTickets()
{
   for(int i = 0; i < 3; i++)
   {
      int tkt = g_pyramidTickets[i];
      if(tkt <= 0) continue;
      if(!OrderSelect(tkt, SELECT_BY_TICKET)) { g_pyramidTickets[i] = -1; g_legPeakProfit[i] = 0.0; continue; }
      if(OrderCloseTime() > 0)
      {
         double pnlHist = OrderProfit() + OrderSwap() + OrderCommission();
         string commentHist = OrderComment();
         string tradeTypeHist = DetectTradeType(commentHist, i);
         LogTradeCSV(tradeTypeHist, "close", tkt, OrderClosePrice(), OrderLots(), OrderStopLoss(), OrderTakeProfit(),
                     pnlHist, "broker_side_close(sl_or_tp_hit)", commentHist);
         LogEvent("RECONCILED_BROKER_CLOSE", StringFormat("ticket=%d type=%s pnl=%.2f", tkt, tradeTypeHist, pnlHist));
         g_pyramidTickets[i] = -1; g_legPeakProfit[i] = 0.0;
      }
   }
   if(g_hedgeTicket > 0)
   {
      if(!OrderSelect(g_hedgeTicket, SELECT_BY_TICKET)) { g_hedgeTicket = -1; g_hedgeClosed = true; }
      else if(OrderCloseTime() > 0)
      {
         double pnlHistH = OrderProfit() + OrderSwap() + OrderCommission();
         LogTradeCSV("hedge", "close", g_hedgeTicket, OrderClosePrice(), OrderLots(), OrderStopLoss(), OrderTakeProfit(),
                     pnlHistH, "broker_side_close(sl_or_tp_hit)", OrderComment());
         LogEvent("RECONCILED_BROKER_CLOSE", StringFormat("ticket=%d type=hedge pnl=%.2f", g_hedgeTicket, pnlHistH));
         g_hedgeTicket = -1; g_hedgeClosed = true;
      }
   }
}

bool EntryRSIFilterOK(int trend)
{
   if(!UseEntryRSIFilter || trend == 0) return true;

   double rsi = iRSI(Symbol(), PERIOD_M5, RSI_Period, PRICE_CLOSE, 1);
   if(EntryRSI_ExtremePauseSec > 0 && (rsi >= EntryRSI_ExtremeHigh || rsi <= EntryRSI_ExtremeLow))
   {
      datetime newPauseUntil = TimeCurrent() + EntryRSI_ExtremePauseSec;
      if(newPauseUntil > g_rsiExtremePauseUntil)
      {
         g_rsiExtremePauseUntil = newPauseUntil;
         LogEvent("FILTER_RSI_EXTREME_PAUSE", StringFormat("rsi=%.1f pause=%ds", rsi, EntryRSI_ExtremePauseSec));
      }
   }

   if(g_rsiExtremePauseUntil > TimeCurrent())
   {
      g_state = STATE_BLOCKED_BY_FILTER;
      g_lastBlockReason = StringFormat("RSI_EXTREME_PAUSE (%ds left rsi=%.1f)", (int)(g_rsiExtremePauseUntil - TimeCurrent()), rsi);
      LogEvent("FILTER_BLOCK_RSI_EXTREME_PAUSE", g_lastBlockReason);
      return false;
   }

   if(trend == 1 && rsi > EntryRSI_BuyMax)
   {
      g_state = STATE_BLOCKED_BY_FILTER;
      g_lastBlockReason = StringFormat("RSI_BUY_BLOCK (rsi=%.1f max=%.1f)", rsi, EntryRSI_BuyMax);
      LogEvent("FILTER_BLOCK_RSI_BUY", g_lastBlockReason);
      return false;
   }
   if(trend == -1 && rsi < EntryRSI_SellMin)
   {
      g_state = STATE_BLOCKED_BY_FILTER;
      g_lastBlockReason = StringFormat("RSI_SELL_BLOCK (rsi=%.1f min=%.1f)", rsi, EntryRSI_SellMin);
      LogEvent("FILTER_BLOCK_RSI_SELL", g_lastBlockReason);
      return false;
   }

   return true;
}

void OnTick()
{
   RefreshRates();
   UpdateSingleInstanceHeartbeat();
   ReconcileClosedTickets();
   ReconcileTradeLifecycleLogs();

   bool sessionOK = IsInTradeSession();
   bool sessionFilterOK = IsInSessionFilter();
   bool newsBlock = IsNewsWindow();

   if((!sessionOK || !sessionFilterOK) && CountActivePositions() == 0 && CountPendingOrders() == 0)
   { g_state = STATE_BLOCKED_BY_FILTER;
     if(!sessionFilterOK) g_lastBlockReason = "SESSION_FILTER (" + SessionName() + ")";
     Dashboard_Update(); return; }

   if(newsBlock && CountActivePositions() == 0 && CountPendingOrders() == 0)
   { g_state = STATE_BLOCKED_BY_FILTER;
     g_lastBlockReason = "NEWS_WINDOW";
     Dashboard_Update(); return; }

   CheckDailyLossLimit();
   CheckWeeklyLossLimit();
   bool dailyBlocking  = g_dailyLossPaused && (UseDailyLossLimit || UseDailyDrawdownPct);
   bool weeklyBlocking = g_weeklyLossPaused && UseWeeklyLossLimit;
   if((dailyBlocking || weeklyBlocking) && CountActivePositions() == 0 && CountPendingOrders() == 0)
   { Dashboard_Update(); return; }

   SyncTicketsAndState();
   UpdateRiskStatus();

   if(CountActivePositions() == 1 && (g_buyStopTicket > 0 || g_sellStopTicket > 0))
   { HandleOCOTriggered(); Dashboard_Update(); return; }

   if(CountActivePositions() >= 1 && g_positionDirection == 0)
   { RecoverOrphanedPosition(); Dashboard_Update(); return; }

   if(HedgeEnabled && g_hedgePendingTicket > 0)
   {
      if(OrderSelect(g_hedgePendingTicket, SELECT_BY_TICKET) && OrderCloseTime() == 0)
      {
         if(OrderType() == OP_BUY || OrderType() == OP_SELL)
         { g_hedgeTicket = g_hedgePendingTicket; g_hedgePendingTicket = -1; }
      }
      else { g_hedgePendingTicket = -1; }
      if(g_hedgePendingTicket > 0 && (TimeCurrent() - g_hedgePendingTime) > HedgePendingExpireSec)
      {
         DeleteOrderByTicket(g_hedgePendingTicket, "hedge_pending_expired");
         g_hedgePendingTicket = -1;
         if(g_hedgeRearmCount < 1)
         {
            g_hedgeRearmCount++;
            LogEvent("HEDGE_PENDING_EXPIRED", StringFormat("after=%ds rearm=%d/1", HedgePendingExpireSec, g_hedgeRearmCount));
         }
         else
         {
            g_hedgeClosed = true;
            LogEvent("HEDGE_PENDING_EXPIRED", StringFormat("after=%ds no_more_rearm", HedgePendingExpireSec));
         }
      }
   }

   if(HedgeEnabled && g_hedgePendingTicket > 0 && CountActivePositions() == 0)
   {
      DeleteOrderByTicket(g_hedgePendingTicket, "main_gone_hedge_pending");
      g_hedgePendingTicket = -1; g_hedgeClosed = true;
      LogEvent("HEDGE_PENDING_CLEANUP", "main_position_gone");
   }

   if(CountActivePositions() >= 1)
   { ManageActivePosition(); Dashboard_Update(); return; }

   if(CountPendingOrders() > 0)
   { ManagePendingOrders(); Dashboard_Update(); return; }

   CheckMeanReversionClosed();
   CheckRangeBoundClosed();

   ResetCycleIfClean();

   if(UseHardStopFullDay && g_consecLossHardStopped)
   {
      g_state = STATE_BLOCKED_BY_FILTER;
      g_lastBlockReason = "CONSEC_LOSS_FULL_DAY_STOP (resumes next calendar day)";
      Dashboard_Update();
      return;
   }

   if(g_lossPauseUntil > 0 && TimeCurrent() < g_lossPauseUntil)
   {
      g_state = STATE_BLOCKED_BY_FILTER;
      g_lastBlockReason = StringFormat("CONSEC_LOSS_PAUSE (%ds left)", (int)(g_lossPauseUntil - TimeCurrent()));
      Dashboard_Update();
      return;
   }

   int idleAge = (g_lastResetTime > 0) ? (int)(TimeCurrent() - g_lastResetTime) : 999999;
   if(!AutoRestartCycle) { Dashboard_Update(); return; }
   if(idleAge < P_RestartDelaySeconds) { Dashboard_Update(); return; }

   if(P_UseMeanReversionEntry && TryMeanReversionEntry()) { Dashboard_Update(); return; }
   if(P_UseRangeBoundEntry && TryRangeBoundEntry()) { Dashboard_Update(); return; }

   int trend = GetTrendDirection();
   if(!EntryRSIFilterOK(trend))
   { g_lastResetTime = TimeCurrent(); Dashboard_Update(); return; }

   if(UseTrendFilter && trend == 0)
   { g_state = STATE_BLOCKED_BY_FILTER;
     g_lastBlockReason = (TrendFilterMethod == 0) ? "TREND_NEUTRAL_EMA" : "TREND_WEAK_ADX";
     LogEvent("FILTER_BLOCK_TREND", g_lastBlockReason);     g_lastResetTime = TimeCurrent(); Dashboard_Update(); return; }

   double rsiAtDisagree = iRSI(Symbol(), PERIOD_M5, RSI_Period, PRICE_CLOSE, 1);
   if(trend != 0 && P_UseFastTrendConfirm)
   {
      int fastTrend = GetFastConfirmDirection();
      if(fastTrend != 0 && fastTrend != trend)
      {
         int revDir = 0;
         if(rsiAtDisagree < P_RSI_Oversold) revDir = 1;
         else if(rsiAtDisagree > P_RSI_Overbought) revDir = -1;

         if(revDir != 0)
         {
            double adxAtDisagree = iADX(Symbol(), Trend_Timeframe, ADX_Period, PRICE_CLOSE, MODE_MAIN, 1);
            PlaceIsolatedReversalOrder(revDir, rsiAtDisagree, adxAtDisagree, "Disagree-Reversal");
            g_lastResetTime = TimeCurrent(); Dashboard_Update(); return;
         }
         else
         {
            // [V6.46 PATCH] Allow pullback entry saat RSI extreme (RSI 40-48 for pullback buy)
            bool pullbackOK = false;
            if(trend == 1 && fastTrend == -1 && rsiAtDisagree < 45.0) pullbackOK = true; // Bullish pullback
            if(trend == -1 && fastTrend == 1 && rsiAtDisagree > 55.0) pullbackOK = true; // Bearish pullback
            
            if(!pullbackOK) 
            {
               g_state = STATE_BLOCKED_BY_FILTER;
               g_lastBlockReason = StringFormat("TREND_DISAGREE (main=%d fast=%d rsi=%.1f, no extreme)", trend, fastTrend, rsiAtDisagree);
               LogEvent("FILTER_BLOCK_TREND_DISAGREE", g_lastBlockReason);
               g_lastResetTime = TimeCurrent(); Dashboard_Update(); return;
            }
         }
      }
   }

   if(UseMainEntryADXFilter && trend != 0)
   {
      double adxMain = iADX(Symbol(), Trend_Timeframe, ADX_Period, PRICE_CLOSE, MODE_MAIN, 1);
      double effectiveMinADX = P_MainEntryMinADX;
      if(P_UseAdaptiveADXOnLosses && g_consecutiveLosses > 0)
         effectiveMinADX += MathMin(g_consecutiveLosses * P_AdaptiveADXStepPerLoss, P_MaxAdaptiveADXAdd);
      if(adxMain < effectiveMinADX)
      { g_state = STATE_BLOCKED_BY_FILTER;
        g_lastBlockReason = StringFormat("ADX_WEAK_MAIN (adx=%.1f min=%.1f%s)", adxMain, effectiveMinADX,
                             (g_consecutiveLosses > 0) ? StringFormat(" [streak=%d]", g_consecutiveLosses) : "");
        LogEvent("FILTER_BLOCK_ADX_WEAK_MAIN", g_lastBlockReason);
        g_lastResetTime = TimeCurrent(); Dashboard_Update(); return; }
   }

   if(UseRSIFilter && trend != 0)
   {
      double rsi = iRSI(Symbol(), PERIOD_M5, RSI_Period, PRICE_CLOSE, 1);
      if(trend == -1 && rsi < P_RSI_Oversold)
      { g_state = STATE_BLOCKED_BY_FILTER;
        g_lastBlockReason = StringFormat("RSI_VALLEY (rsi=%.1f)", rsi);
        LogEvent("FILTER_BLOCK_RSI_VALLEY", g_lastBlockReason);
        g_lastResetTime = TimeCurrent(); Dashboard_Update(); return; }
      if(trend == 1 && rsi > P_RSI_Overbought)
      { g_state = STATE_BLOCKED_BY_FILTER;
        g_lastBlockReason = StringFormat("RSI_PEAK (rsi=%.1f)", rsi);
        LogEvent("FILTER_BLOCK_RSI_PEAK", g_lastBlockReason);
        g_lastResetTime = TimeCurrent(); Dashboard_Update(); return; }
   }

   g_state = STATE_PLACE_PENDING;
   g_cycleId++;
   LogEvent("PLACE_PENDING_START", StringFormat("cycle=%d trend=%d consecLosses=%d preset=%s",
            g_cycleId, trend, g_consecutiveLosses, PresetName()));

   if(!UseTrendFilter)
   { if(!PlaceOCOOrders()) { g_state = STATE_IDLE; g_lastResetTime = TimeCurrent(); } }
   else
   { if(!PlaceDirectionalOCO(trend)) { g_state = STATE_IDLE; g_lastResetTime = TimeCurrent(); } }

   Dashboard_Update();
}
//+------------------------------------------------------------------+
