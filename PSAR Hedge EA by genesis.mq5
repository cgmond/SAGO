#property copyright "G"
#property version   "1.01"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

input ENUM_TIMEFRAMES inpTimeframe = PERIOD_D1;
input double   fixedLots         = 0.1;
input double   riskPercent       = 1.0; // % of balance
input bool     useRiskBasedLots  = false;
input double   lossThreshold     = 2.0; // % of balance to hedge
input double   forceCloseLoss    = 5.0; // % of balance to force close
input double   profitTarget      = 3.0; // % profit to close all
input double   hardStopLoss      = 5.0; // % loss to close all
input double   psarStep          = 0.02;
input double   psarMax           = 0.2;

int sarHandle;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   ChartSetInteger(0,CHART_SHOW_GRID,false);

   sarHandle = iSAR(_Symbol, inpTimeframe, psarStep, psarMax);
   if (sarHandle == INVALID_HANDLE)
   {
      Print("Failed to create iSAR handle");
      return INIT_FAILED;
   }
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Calculate lot size based on balance and risk                    |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPoints)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if (!useRiskBasedLots || slPoints <= 0)
      return fixedLots;

   double risk = balance * (riskPercent / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double pipValue = tickValue / tickSize;
   double lots = NormalizeDouble(risk / (slPoints * pipValue), 2);
   return MathMax(lots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
}

//+------------------------------------------------------------------+
//| Check time restriction                                          |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   datetime t = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(t, dt);
   int hour = dt.hour;
   return !(hour == 23 || hour == 0);
}

//+------------------------------------------------------------------+
//| Determine if PSAR flipped                                       |
//+------------------------------------------------------------------+
bool PSARFlipped(bool &bullishFlip)
{
   double psar[2];
   if (CopyBuffer(sarHandle, 0, 0, 2, psar) <= 0)
   {
      Print("CopyBuffer failed");
      return false;
   }
   double closeCurr = iClose(_Symbol, inpTimeframe, 0);
   double closePrev = iClose(_Symbol, inpTimeframe, 1);
   double psarCurr = psar[0];
   double psarPrev = psar[1];

   bool prevBelow = psarPrev < closePrev;
   bool currAbove = psarCurr > closeCurr;
   bool prevAbove = psarPrev > closePrev;
   bool currBelow = psarCurr < closeCurr;

   bullishFlip = (prevAbove && currBelow);
   return (prevBelow && currAbove) || bullishFlip;
}

//+------------------------------------------------------------------+
//| Determine trade direction based on PSAR                         |
//+------------------------------------------------------------------+
int GetTradeDirection()
{
   double psar[1];
   if (CopyBuffer(sarHandle, 0, 0, 1, psar) <= 0)
   {
      Print("CopyBuffer failed");
      return -1;
   }
   double close = iClose(_Symbol, inpTimeframe, 0);
   return (psar[0] < close) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
}

//+------------------------------------------------------------------+
//| Expert tick function                                            |
//+------------------------------------------------------------------+
void OnTick()
{
   if (!IsWithinTradingHours())
      return;

   bool bullishFlip;
   if (!PSARFlipped(bullishFlip))
      return;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   double totalPnL = 0.0;
   bool anyClosed = false;

   for (int i = PositionsTotal() - 1; i >= 0; --i)
   {
      if (PositionGetTicket(i) == 0)
         continue;
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         double pnl = PositionGetDouble(POSITION_PROFIT);
         double lossPercent = -pnl / balance * 100.0;
         double profitPercent = pnl / balance * 100.0;
         totalPnL += pnl;

         if (pnl >= 0)
         {
            trade.PositionClose(ticket);
            anyClosed = true;
         }
         else if (lossPercent > lossThreshold)
         {
            int hedgeDir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            double lots = CalculateLotSize(100);
            if (hedgeDir == ORDER_TYPE_BUY)
               trade.Buy(lots, _Symbol);
            else
               trade.Sell(lots, _Symbol);
         }
         else if (lossPercent >= forceCloseLoss)
         {
            trade.PositionClose(ticket);
            anyClosed = true;
         }
      }
   }

   double totalPercent = totalPnL / balance * 100.0;

   if (totalPercent >= profitTarget || totalPercent <= -hardStopLoss)
   {
      for (int i = PositionsTotal() - 1; i >= 0; --i)
      {
         ulong ticket = PositionGetTicket(i);
         if (PositionSelectByTicket(ticket))
            trade.PositionClose(ticket);
      }
      return;
   }

   // Open new trade after PSAR flip if no open positions
   if (PositionsTotal() == 0 || anyClosed)
   {
      int dir = GetTradeDirection();
      if (dir == ORDER_TYPE_BUY)
         trade.Buy(CalculateLotSize(100), _Symbol);
      else if (dir == ORDER_TYPE_SELL)
         trade.Sell(CalculateLotSize(100), _Symbol);
   }
}
//+------------------------------------------------------------------+
