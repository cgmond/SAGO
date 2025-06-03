//This is a test push to Github v1.4
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade/Trade.mqh>

CTrade            trade;
CPositionInfo     pos;
COrderInfo        ord;

   input group "=== Trade Settings ==="
   
//      enum  Timeframe{Daily=0, H4=1, H1=2, m15=3};
//      input Timeframe TFInput = 0;
      
      input double   RiskPercent    =  1;                         // Risk as % of Trading Capital
      input int      InpMagic = 3333;                             // EA identification no.
      input string   TradeComment   = "PSAR Hedge by CGMFX";      //Trade Comments 

      double handlePSAR;

   input group "=== PSAR Settings ==="
   
      input ENUM_TIMEFRAMES      Timeframe     =    PERIOD_CURRENT;    // Trade on this timeframe 
      input double               Step              =    0.2;               // PSAR Step                  
      input double               Maximum           =    0.2;               // PSAR Maximum



int OnInit() {

   trade.SetExpertMagicNumber(InpMagic);
   
   ChartSetInteger(0,CHART_SHOW_GRID,false);
   
   handlePSAR      =  iSAR(_Symbol,Timeframe,Step,Maximum);
   

   return(INIT_SUCCEEDED);
}


void OnDeinit(const int reason) {
}

void OnTick() {

   // Create a function to trade at 2300H instead of end of day


   
   if(!IsNewBar()) return;

   Print("Yes! It's a new bar!\n");

   double psar[];
   
   CopyBuffer(handlePSAR,0, 0, 1, psar);
   
   ArraySetAsSeries(psar, true);

   // Get the most recent PSAR value
   if(CopyBuffer(handlePSAR, 0, 0, 1, psar) <= 0L)
   {
      Print("Failed to get PSAR value");
      return;
   }

   double psarNow = psar[0];
   double priceClose = iClose(_Symbol, _Period, 0); // Current candle's close price

   if (psarNow < priceClose)
   {
      Print("BUYONLY");
   }
   else if (psarNow > priceClose)
   {
      Print("SELLONLY");
   }
   else
   {
      Print("No clear direction (PSAR = price)");
   }

   
}


bool IsNewBar(){
   static datetime previousTime = 0;
   datetime currentTime = iTime(_Symbol,Timeframe,0);
   if (previousTime!=currentTime){
      previousTime=currentTime;
      return true;
   }
   return false;
}
