//+------------------------------------------------------------------+
//| PSAR Hedge EA -  Edition                                   |
//| v 1.0 © 2025                                                |
//+------------------------------------------------------------------+

#property copyright "Mangesh"
#property version   "1.0"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

// -------------------------------------------------------------------
// Input Parameters
// -------------------------------------------------------------------
input group "General Settings"
input ENUM_TIMEFRAMES Timeframe = PERIOD_H1;      // Timeframe (H1 default for )
input double InitialLotSize     = 0.1;            // Initial lot size
input double MaxSpreadPips      = 20.0;           // Maximum allowed spread (pips)

input group "PSAR Settings"
input double PSARStep           = 0.02;           // PSAR Step
input double PSARMaxStep        = 0.2;            // PSAR Maximum Step

input group "Risk Management"
input double HedgeLossThreshold = 0.25;           // X% of balance/equity to trigger hedging
input double HardStopLossPerc   = 5.0;            // Hard Stop-Loss (% of balance)
input double HappyTakeProfitPerc = 3.0;           // Happy Take-Profit (% of balance)

input group "Trading Hours (UTC)"
input int StartHour             = 23;             // Start trading hour (23:00 UTC)
input int EndHour               = 1;              // End trading hour (01:00 UTC)

// -------------------------------------------------------------------
// Global Variables
// -------------------------------------------------------------------
int psarHandle = INVALID_HANDLE;
double psarBuffer[];
double balance;
double equity;
double initialPnL = 0.0;
int hedgeLevel = 0; // Tracks hedge increments (0 = initial, 1 = first hedge, etc.)
ENUM_POSITION_TYPE initialDirection = POSITION_TYPE_BUY; // Tracks initial position direction
ENUM_POSITION_TYPE previousDirection = POSITION_TYPE_BUY;
datetime lastBar = 0;

// -------------------------------------------------------------------
// Utility Functions
// -------------------------------------------------------------------
double GetCurrentPnL()
{
   double totalPnL = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL) == _Symbol)
      {
         totalPnL += PositionGetDouble(POSITION_PROFIT);
      }
   }
   return totalPnL;
}

double CalculateLotSize()
{
   // For initial position (hedgeLevel == 0), use InitialLotSize
   // For hedge positions, increase by 1x per level (e.g., 1 lot → 2 lots → 3 lots)
   return InitialLotSize * (hedgeLevel + 1);
}

bool TradingWindowOpen()
{
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);
   int hour = tm.hour;
   if(StartHour < EndHour)
      return (hour >= StartHour && hour < EndHour);
   else
      return (hour >= StartHour || hour < EndHour);
}

bool IsNewBar()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, Timeframe, 0, 1, rates) != 1) return false;
   if(rates[0].time == lastBar) return false;
   lastBar = rates[0].time;
   return true;
}

bool LoadPSAR()
{
   ArraySetAsSeries(psarBuffer, true);
   if(CopyBuffer(psarHandle, 0, 0, 1, psarBuffer) != 1)
   {
      Print("Failed to load PSAR buffer: ", GetLastError());
      return false;
   }
   return true;
}

bool CheckTimeframeConstraints()
{
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);
   int hour = tm.hour;
   // H1 and lower: trade only between 23:00 and 01:00
   if(Timeframe <= PERIOD_H1)
   {
      if(hour < 23 && hour >= 1) return false;
   }
   // D1 and H4: check PSAR at 23:00 instead of 00:00
   if(Timeframe == PERIOD_D1 || Timeframe == PERIOD_H4)
   {
      return (hour == 23);
   }
   return true;
}

// -------------------------------------------------------------------
// Initialization
// -------------------------------------------------------------------
int OnInit()
{
   ChartSetInteger(0,CHART_SHOW_GRID,false);

   // Initialize PSAR indicator
   psarHandle = iSAR(_Symbol, Timeframe, PSARStep, PSARMaxStep);
   if(psarHandle == INVALID_HANDLE)
   {
      Print("Failed to initialize PSAR: ", GetLastError());
      return INIT_FAILED;
   }

   // Set array as timeseries
   ArraySetAsSeries(psarBuffer, true);

   // Initialize balance
   balance = AccountInfoDouble(ACCOUNT_EQUITY);
   equity = AccountInfoDouble(ACCOUNT_EQUITY);

   return INIT_SUCCEEDED;
}

// -------------------------------------------------------------------
// Deinitialization
// -------------------------------------------------------------------
void OnDeinit(const int reason)
{
   if(psarHandle != INVALID_HANDLE)
      IndicatorRelease(psarHandle);
}

// -------------------------------------------------------------------
// Main Trading Logic
// -------------------------------------------------------------------
void OnTick()
{
   // Update balance and equity
   balance = AccountInfoDouble(ACCOUNT_BALANCE);
   equity = AccountInfoDouble(ACCOUNT_EQUITY);

   // Check if trading is allowed (hours and timeframe constraints)
   if(!TradingWindowOpen() || !CheckTimeframeConstraints())
      return;
      

   // Only process on new bar
   if(!IsNewBar())
      return;

   // Load PSAR value
   if(!LoadPSAR())
      return;

   // Check spread
   double spreadPips = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
   double digitFactor = (SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 3 || SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 5) ? 10.0 : 1.0;
   spreadPips /= digitFactor;
   if(spreadPips > MaxSpreadPips)
   {
      Print("Spread too high (", spreadPips, " pips), skipping trade.");
      return;
   }

   // Get current price (close of last bar)
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, Timeframe, 1, 1, rates) != 1)
   {
      Print("Failed to load rates: ", GetLastError());
      return;
   }
   double closePrice = rates[0].close;
   double psarValue = psarBuffer[0];
// put back below this line
   // Calculate current PnL
   double currentPnL = GetCurrentPnL();

   // Check Hard Stop-Loss and Happy Take-Profit
   double hardStopLossValue = -balance * (HardStopLossPerc / 100.0);
   double happyTakeProfitValue = balance * (HappyTakeProfitPerc / 100.0);
   if(currentPnL <= hardStopLossValue)                                                          
   {
      Print("Hard Stop-Loss reached (", currentPnL, "). Closing all positions.");
      CloseAllPositions();
      hedgeLevel = 0; // Reset hedge level
      initialPnL = 0.0;
   }
   else if(currentPnL >= happyTakeProfitValue)
   {
      Print("Happy Take-Profit reached (", currentPnL, "). Closing all positions.");
      CloseAllPositions();
      hedgeLevel = 0; // Reset hedge level
      initialPnL = 0.0;
   }

   // Check if PSAR has flipped
   bool isPSARBelowPrice = psarValue < closePrice;
   bool hasPositions = PositionsTotal() > 0;

   // No positions: Enter initial position based on PSAR
   if(!hasPositions)
   {
      if(isPSARBelowPrice)
      {
         // PSAR below price: BUY
         trade.Buy(InitialLotSize, _Symbol, 0.0, 0.0, 0.0, "Initial BUY");
         initialDirection = POSITION_TYPE_BUY;
         previousDirection = POSITION_TYPE_BUY;
         initialPnL = 0.0;
         hedgeLevel = 0;
      }
      else                       
      {
         // PSAR above price: SELL
         trade.Sell(InitialLotSize, _Symbol, 0.0, 0.0, 0.0, "Initial SELL");
         initialDirection = POSITION_TYPE_SELL;
         previousDirection = POSITION_TYPE_SELL;
         initialPnL = 0.0;
         hedgeLevel = 0;
      }
      return;
   }

   // Check if PSAR direction matches initial position
//   bool psarMatchesInitial = (initialDirection == POSITION_TYPE_BUY && isPSARBelowPrice) ||
 //                            (initialDirection == POSITION_TYPE_SELL && !isPSARBelowPrice);
   bool psarMatchesPrevious= (previousDirection == POSITION_TYPE_BUY && isPSARBelowPrice) ||
                             (previousDirection == POSITION_TYPE_SELL && !isPSARBelowPrice);                              

   // If PSAR has flipped
   if(!psarMatchesPrevious)
   {
      if(currentPnL > 0)
      {
         // Positive PnL: Close all and enter new position
         Print("PSAR flipped, PnL positive (", currentPnL, "). Closing all and entering new position.");
         CloseAllPositions();
         if(isPSARBelowPrice)
         {
            trade.Buy(InitialLotSize, _Symbol, 0.0, 0.0, 0.0, "New BUY after flip");
            previousDirection = POSITION_TYPE_BUY;
         }
         else
         {
            trade.Sell(InitialLotSize, _Symbol, 0.0, 0.0, 0.0, "New SELL after flip");
            previousDirection = POSITION_TYPE_SELL;
         }
         hedgeLevel = 0;
         initialPnL = 0.0;
      }
      else
      {
         // Negative PnL: Check loss threshold
         double lossPerc = (currentPnL / balance) * 100.0;
         double thresholdPerc = -HedgeLossThreshold;
         if(lossPerc >= thresholdPerc)
         {
            // Loss is less than or equal to X%: Close all
            Print("PSAR flipped, loss (", lossPerc, "%) <= ", HedgeLossThreshold, "%. Closing all positions.");
            CloseAllPositions();
            hedgeLevel = 0;
            initialPnL = 0.0;
         }
         else              
         {
            // Loss > X%: Add hedge position
            hedgeLevel++;
            double lotSize = CalculateLotSize();
            Print("PSAR flipped, loss (", lossPerc, "%) > ", HedgeLossThreshold, "%. Adding hedge position, level ", hedgeLevel, ", lots: ", lotSize);
            if(isPSARBelowPrice)
            {
               trade.Buy(lotSize, _Symbol, 0.0, 0.0, 0.0, "Hedge BUY level " + IntegerToString(hedgeLevel));
               previousDirection = POSITION_TYPE_BUY;
            }
            else
            {
               trade.Sell(lotSize, _Symbol, 0.0, 0.0, 0.0, "Hedge SELL level " + IntegerToString(hedgeLevel));
               previousDirection = POSITION_TYPE_SELL;
            }
         }
      }
   }
}

void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL) == _Symbol)
      {
         trade.PositionClose(ticket);
      }
   }
}
//+------------------------------------------------------------------+