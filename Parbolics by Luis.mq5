//+------------------------------------------------------------------+
//|                                           PSAR Hedge Strategy EA |
//|                                  Copyright 2025, Your Name Here |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Name Here"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Enums
enum ENUM_RISK_TYPE
{
    RISK_FIXED,      // Fixed Lot Size
    RISK_BALANCE,    // Percentage of Balance
    RISK_EQUITY      // Percentage of Equity
};

//--- Input parameters
input group "=== Trading Settings ==="
input ENUM_TIMEFRAMES TradingTimeframe = PERIOD_D1;    // Trading Timeframe
input double InitialLots = 0.1;                        // Initial Lot Size
input ENUM_RISK_TYPE RiskType = RISK_FIXED;           // Risk Management Type
input double RiskAmount = 0.1;                        // Risk Amount (lots/% based on type)

input group "=== PSAR Settings ==="
input double PSARStep = 0.02;                         // PSAR Step
input double PSARMaximum = 0.2;                       // PSAR Maximum

input group "=== Risk Management ==="
input double SmallLossThreshold = 2.0;                // Small Loss Threshold (% of equity/balance)
input bool UseEquityForCalculation = true;            // Use Equity (true) or Balance (false)
input double HardStopLoss = 10.0;                     // Hard Stop Loss (% of equity/balance)
input double HappyTakeProfit = 5.0;                   // Happy Take Profit (% of equity/balance)

input group "=== Trading Time Settings ==="
input bool EnableTimeFilter = true;                   // Enable Trading Time Filter
input int AvoidHoursBeforeClose = 1;                  // Hours to avoid before market close
input int AvoidHoursAfterOpen = 1;                    // Hours to avoid after market open

//--- Global variables
CTrade trade;
int psarHandle;
double psarBuffer[];
bool isInitialized = false;
datetime lastBarTime = 0;
int hedgeCount = 0;
string magicPrefix = "PSAR_HEDGE_";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{

   ChartSetInteger(0,CHART_SHOW_GRID,false);


    // Initialize PSAR indicator
    psarHandle = iSAR(_Symbol, TradingTimeframe, PSARStep, PSARMaximum);
    if(psarHandle == INVALID_HANDLE)
    {
        Print("Failed to create PSAR indicator handle");
        return INIT_FAILED;
    }
    
    // Set array as series
    ArraySetAsSeries(psarBuffer, true);
    
    // Set magic number based on symbol and timeframe
    int magic = GenerateMagicNumber();
    trade.SetExpertMagicNumber(magic);
    
    isInitialized = true;
    Print("PSAR Hedge Strategy EA initialized successfully");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(psarHandle != INVALID_HANDLE)
        IndicatorRelease(psarHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    if(!isInitialized) return;
    
    // Check if new bar formed
    if(!IsNewBar()) return;
    
    // Check trading time restrictions
    if(EnableTimeFilter && !IsTradingTimeAllowed()) return;
    
    // Update PSAR values
    if(!UpdatePSARValues()) return;
    
    // Check for hard stop loss or happy take profit
    if(CheckGlobalExitConditions()) return;
    
    // Main trading logic
    ExecuteTradingLogic();
}

//+------------------------------------------------------------------+
//| Check if new bar formed                                          |
//+------------------------------------------------------------------+
bool IsNewBar()
{
    datetime currentBarTime = iTime(_Symbol, TradingTimeframe, 0);
    if(currentBarTime != lastBarTime)
    {
        lastBarTime = currentBarTime;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Check if trading time is allowed                                 |
//+------------------------------------------------------------------+
bool IsTradingTimeAllowed()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    // For daily and H4 timeframes, check PSAR at 23:00
    if(TradingTimeframe >= PERIOD_H4)
    {
        return (dt.hour == 23);
    }
    
    // For H1 and lower timeframes, avoid trading between 23:00-01:00
    if(TradingTimeframe <= PERIOD_H1)
    {
        if(dt.hour >= 23 || dt.hour <= 1)
            return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Update PSAR values                                               |
//+------------------------------------------------------------------+
bool UpdatePSARValues()
{
    if(CopyBuffer(psarHandle, 0, 0, 3, psarBuffer) < 3)
    {
        Print("Failed to copy PSAR buffer");
        return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| Check global exit conditions                                     |
//+------------------------------------------------------------------+
bool CheckGlobalExitConditions()
{
    double totalProfit = GetTotalProfit();
    double accountValue = UseEquityForCalculation ? AccountInfoDouble(ACCOUNT_EQUITY) : AccountInfoDouble(ACCOUNT_BALANCE);
    
    double profitPercent = (totalProfit / accountValue) * 100.0;
    
    // Check hard stop loss
    if(profitPercent <= -HardStopLoss)
    {
        CloseAllPositions();
        Print("Hard Stop Loss triggered. Closing all positions. Loss: ", profitPercent, "%");
        hedgeCount = 0;
        return true;
    }
    
    // Check happy take profit
    if(profitPercent >= HappyTakeProfit)
    {
        CloseAllPositions();
        Print("Happy Take Profit triggered. Closing all positions. Profit: ", profitPercent, "%");
        hedgeCount = 0;
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Main trading logic execution                                     |
//+------------------------------------------------------------------+
void ExecuteTradingLogic()
{
    int totalPositions = CountPositionsByMagic();
    
    Print("Hedge count: ",hedgeCount);
    if(totalPositions == 0)
    {
        // No positions open, check for initial entry
        OpenInitialPosition();
        hedgeCount = 0;
        Print("THIS IS THE FIRST POSITION");
    }
    else
    {
        // Positions exist, check for hedge conditions
        CheckHedgeConditions();
         Print("THIS IS NOT THE FIRST POSITION");
    }
}

//+------------------------------------------------------------------+
//| Open initial position based on PSAR                             |
//+------------------------------------------------------------------+
void OpenInitialPosition()
{
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double currentPSAR = psarBuffer[2];
    
    double lotSize = CalculateLotSize(1);
    
    Print(currentPSAR);
    
    if(currentPrice > currentPSAR)
    {
        // PSAR below price - BUY signal
        if(trade.Buy(lotSize, _Symbol, 0, 0, 0, "PSAR Buy #1"))
        {
            Print("Initial BUY position opened. Lot size: ", lotSize," ", hedgeCount);
            hedgeCount++;
        }
    }
    else if(currentPrice < currentPSAR)
    {
        // PSAR above price - SELL signal
        if(trade.Sell(lotSize, _Symbol, 0, 0, 0, "PSAR Sell #1"))
        {
            Print("Initial SELL position opened. Lot size: ", lotSize," ", hedgeCount);
            hedgeCount++;
        }
    }
}

//+------------------------------------------------------------------+
//| Check hedge conditions                                           |
//+------------------------------------------------------------------+
void CheckHedgeConditions()
{
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double currentPSAR = psarBuffer[0];
    double previousPSAR = psarBuffer[1];
    
    bool psarFlipped = false;
    bool psarNowAbove = currentPSAR > currentPrice;
    bool psarPrevBelow = previousPSAR < SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Check if PSAR flipped
    if(psarNowAbove && psarPrevBelow)
    {
                     Print("PSAR Flipped above price");

        psarFlipped = true;
        ProcessPSARFlip(false); // PSAR flipped to above price

    }
    else if(!psarNowAbove && !psarPrevBelow)
    {
                             Print("PSAR Flipped below price");

        psarFlipped = true;
        ProcessPSARFlip(true); // PSAR flipped to below price

    }
}

//+------------------------------------------------------------------+
//| Process PSAR flip conditions                                     |
//+------------------------------------------------------------------+
void ProcessPSARFlip(bool psarBelowPrice)
{
    double totalProfit = GetTotalProfit();
    double accountValue = UseEquityForCalculation ? AccountInfoDouble(ACCOUNT_EQUITY) : AccountInfoDouble(ACCOUNT_BALANCE);
    double lossPercent = -(totalProfit / accountValue) * 100.0;
    
    // If profit is positive, close all positions
    if(totalProfit > 0)
    {
        CloseAllPositions();
        Print("Profitable position closed on PSAR flip. Profit: $", totalProfit);
        hedgeCount = 0;
        return;
    }
    
    // If loss is small (≤ threshold), close all positions
    if(lossPercent <= SmallLossThreshold)
    {
        CloseAllPositions();
        Print("Small loss position closed on PSAR flip. Loss: ", lossPercent, "%");
        hedgeCount = 0;
        return;
    }
    
    // Loss is significant, open hedge position
    hedgeCount++;
    double hedgeLots = CalculateLotSize(hedgeCount + 1);
    
    if(psarBelowPrice)
    {
        // PSAR flipped below price, open BUY hedge
        if(trade.Buy(hedgeLots, _Symbol, 0, 0, 0, "PSAR Hedge Buy #" + IntegerToString(hedgeCount + 1)))
        {
            Print("Hedge BUY position opened. Lot size: ", hedgeLots, " Hedge count: ", hedgeCount);
        }
    }
    else
    {
        // PSAR flipped above price, open SELL hedge
        if(trade.Sell(hedgeLots, _Symbol, 0, 0, 0, "PSAR Hedge Sell #" + IntegerToString(hedgeCount + 1)))
        {
            Print("Hedge SELL position opened. Lot size: ", hedgeLots, " Hedge count: ", hedgeCount);
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk management                      |
//+------------------------------------------------------------------+
double CalculateLotSize(int multiplier)
{
    double lotSize = InitialLots;
    
    switch(RiskType)
    {
        case RISK_FIXED:
            lotSize = InitialLots * multiplier;
            break;
            
        case RISK_BALANCE:
            lotSize = (AccountInfoDouble(ACCOUNT_BALANCE) * RiskAmount / 100.0) / 100000.0 * multiplier;
            break;
            
        case RISK_EQUITY:
            lotSize = (AccountInfoDouble(ACCOUNT_EQUITY) * RiskAmount / 100.0) / 100000.0 * multiplier;
            break;
    }
    
    // Normalize lot size
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    lotSize = MathMax(minLot, MathMin(maxLot, MathRound(lotSize / lotStep) * lotStep));
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Get total profit of all positions                                |
//+------------------------------------------------------------------+
double GetTotalProfit()
{
    double totalProfit = 0.0;
    int magic = GenerateMagicNumber();
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
               PositionGetInteger(POSITION_MAGIC) == magic)
            {
                totalProfit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
            }
        }
    }
    
    return totalProfit;
}

//+------------------------------------------------------------------+
//| Count positions by magic number                                  |
//+------------------------------------------------------------------+
int CountPositionsByMagic()
{
    int count = 0;
    int magic = GenerateMagicNumber();
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
               PositionGetInteger(POSITION_MAGIC) == magic)
            {
                count++;
            }
        }
    }
    
    return count;
}

//+------------------------------------------------------------------+
//| Close all positions                                              |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
    int magic = GenerateMagicNumber();
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
               PositionGetInteger(POSITION_MAGIC) == magic)
            {
                trade.PositionClose(ticket);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Generate magic number based on symbol and timeframe             |
//+------------------------------------------------------------------+
int GenerateMagicNumber()
{
    string symbolStr = _Symbol;
    int symbolHash = 0;
    for(int i = 0; i < StringLen(symbolStr); i++)
    {
        symbolHash += StringGetCharacter(symbolStr, i);
    }
    
    return 100000 + (symbolHash % 10000) + (int)TradingTimeframe;
}

//+------------------------------------------------------------------+
//| Display information on chart                                     |
//+------------------------------------------------------------------+
void DisplayInfo()
{
    string info = "";
    info += "PSAR Hedge Strategy EA\n";
    info += "====================\n";
    info += "Current PSAR: " + DoubleToString(psarBuffer[0], _Digits) + "\n";
    info += "Current Price: " + DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits) + "\n";
    info += "Total Positions: " + IntegerToString(CountPositionsByMagic()) + "\n";
    info += "Hedge Count: " + IntegerToString(hedgeCount) + "\n";
    info += "Total Profit: $" + DoubleToString(GetTotalProfit(), 2) + "\n";
    
    Comment(info);
}