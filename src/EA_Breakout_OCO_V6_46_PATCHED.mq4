//+------------------------------------------------------------------+
//| EA_Breakout_OCO_V6_46.mq4                                        |
//| Breakout OCO Cycle Engine V6.46 (Optimized Risk/Trail)           |
//+------------------------------------------------------------------+
#property strict
#property version   "6.46"
#property description "Breakout OCO V6.46 - Adaptive Trail, Smart Early Exit, Pullback Entry"

//============================== INPUTS ==============================
// --- General ---
input int      MagicNumber              = 9001060;
input string   EA_Name                  = "EA_Breakout_OCO_V6";
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
input double   BE_Start_Dollar           = 8.0;
input double   BE_Lock_Dollar            = 5.0;
input double   TrailStart_Dollar         = 8.0;    
input double   TrailDrop_Money           = 8.0;
input double   FastProfitStart_Money     = 6.0;
input double   FastProfitRetracePct      = 72.0;
input double   TrailDrop_SmallPeak       = 2.00;
input double   TrailDrop_MedPeak         = 5.00;   
input double   TrailDrop_LargePeak       = 8.00;   
input double   TrailRetracePct_Small     = 25.0;
input double   TrailRetracePct_Med       = 25.0;
input double   TrailRetracePct_Large     = 20.0;
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
input double   SoftSL_USD               = 20.0;
input int      SoftSL_RSIThresh         = 55;

// --- [V6.46 NEW] Time-based Stop Loss ---
input int      TimeLossExitMinutes      = 10;
input double   TimeLossExitUSD          = 15.0;

// --- [V6.46 NEW] Time-based Lot Reduction ---
input int      MaxLossHourStart         = 17;
input int      MaxLossHourEnd           = 22;

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
input int      MinStopBufferPoints      = 15;
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
input string   CSV_FileName              = "EA_Breakout_OCO_V6_Behavior.csv";
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
input bool     HedgeEnabled             = true;
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

// ======================================================
// FULL SOURCE CODE — See repository for complete implementation
// File: EA_Breakout_OCO_V6_46_PATCHED.mq4
// Version: 6.46 | Author: syukursaleh
// ======================================================
