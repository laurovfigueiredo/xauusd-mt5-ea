//+------------------------------------------------------------------+
//|                        XAUUSD_Trend_ATR_v11_UltraConservador.mq5 |
//|  Versao Ultra Conservadora: Entradas de alta precisao M15/H1     |
//|  Fechamento 100% MANUAL (sem SL/TP automatico pelo robo)         |
//+------------------------------------------------------------------+
#property copyright "v11"
#property link      ""
#property version   "11.00"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- Objects
CTrade         trade;
CPositionInfo  posInfo;

//--- Inputs
input group "=== FILTROS CONSERVADORES (M15 / H1) ==="
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M15;  // Timeframe principal (M15 reduz ruido)
input int      InpFastMA      = 9;            // EMA Rapida
input int      InpSlowMA      = 21;           // EMA Lenta
input ENUM_MA_METHOD InpMAMethod = MODE_EMA;
input ENUM_APPLIED_PRICE InpMAPrice = PRICE_CLOSE;

input ENUM_TIMEFRAMES InpTrendTF = PERIOD_H1;    // Filtro Macro (1 Hora)
input int      InpTrendMA     = 100;          // Media de tendencia forte (H1)
input int      InpATRPeriod   = 14;

input group "=== GESTAO DE RISCO & OPERACAO ==="
input double   InpLotSize          = 0.01;    // Lote fixo conservador
input int      InpMaxTradesDay     = 3;       // Maximo de 3 operacoes por dia para evitar overtrading
input double   InpMaxSpreadPoints  = 300.0;   // Nao entra se o spread for maior que 30 pips/300 pontos

input group "=== SAIDAS ==="
// Nota: Saidas automaticas desativadas. O encerramento e 100% MANUAL.

input group "=== OUTROS ==="
input ulong    InpMagic           = 20261104;
input string   InpComment         = "XAUUSD_ULTRA_CONSERVADOR";

//--- Global
int      handleFastMA;
int      handleSlowMA;
int      handleTrendMA;
int      handleATR;
datetime g_lastBarTime = 0;
int      g_tradesToday = 0;
datetime g_lastDayReset = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   if(InpFastMA >= InpSlowMA)
   {
      Print("ERRO: InpFastMA deve ser menor que InpSlowMA");
      return(INIT_PARAMETERS_INCORRECT);
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFillingBySymbol(_Symbol);

   handleFastMA  = iMA(_Symbol, InpTimeframe, InpFastMA,  0, InpMAMethod, InpMAPrice);
   handleSlowMA  = iMA(_Symbol, InpTimeframe, InpSlowMA,  0, InpMAMethod, InpMAPrice);
   handleTrendMA = iMA(_Symbol, InpTrendTF,   InpTrendMA, 0, InpMAMethod, InpMAPrice);
   handleATR     = iATR(_Symbol, InpTimeframe, InpATRPeriod);

   if(handleFastMA == INVALID_HANDLE || handleSlowMA == INVALID_HANDLE ||
      handleTrendMA == INVALID_HANDLE || handleATR == INVALID_HANDLE)
   {
      Print("ERRO AO CRIAR INDICADORES");
      return(INIT_FAILED);
   }

   ResetDailyControl();
   Print("=== XAUUSD ULTRA CONSERVADOR (V11) INICIADO ===");
   Print("Timeframe: M15 | Filtro Macro: H1 (EMA 100) | Saida: 100% MANUAL");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   IndicatorRelease(handleFastMA);
   IndicatorRelease(handleSlowMA);
   IndicatorRelease(handleTrendMA);
   IndicatorRelease(handleATR);
   Comment("");
}

void OnTick()
{
   ResetDailyControl();
   bool newBar = IsNewBar();

   if(HasOpenPosition())
   {
      if(newBar) ShowStatus("Posição em andamento. Aguardando FECHAMENTO MANUAL do usuário.");
      return;
   }

   if(!newBar) return;

   CheckForEntryTrend();
}

void CheckForEntryTrend()
{
   if(g_tradesToday >= InpMaxTradesDay)
   {
      ShowStatus("Limite diario de trades atingido (Max: " + IntegerToString(InpMaxTradesDay) + ")");
      return;
   }

   double fastMA[2], slowMA[2], trendMA[1];
   ArraySetAsSeries(fastMA, true);
   ArraySetAsSeries(slowMA, true);

   double trendClose = iClose(_Symbol, InpTrendTF, 1);
   double close1     = iClose(_Symbol, InpTimeframe, 1);

   if(CopyBuffer(handleFastMA,  0, 1, 2, fastMA)  < 2 ||
      CopyBuffer(handleSlowMA,  0, 1, 2, slowMA)  < 2 ||
      CopyBuffer(handleTrendMA, 0, 1, 1, trendMA) < 1 ||
      trendClose <= 0 || close1 <= 0)
   {
      ShowStatus("Aguardando carregamento de historico M15/H1...");
      return;
   }

   bool trendUpH1   = (trendClose > trendMA[0]);
   bool trendDownH1 = (trendClose < trendMA[0]);

   bool crossUp   = (fastMA[1] <= slowMA[1] && fastMA[0] > slowMA[0]);
   bool crossDown = (fastMA[1] >= slowMA[1] && fastMA[0] < slowMA[0]);

   bool buySignal  = crossUp && trendUpH1;
   bool sellSignal = crossDown && trendDownH1;

   if(!buySignal && !sellSignal)
   {
      string desc = "Sem sinal seguro | H1: " + (trendUpH1 ? "ALTA" : (trendDownH1 ? "BAIXA" : "NEUTRO"));
      ShowStatus(desc);
      return;
   }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spreadPoints = (ask - bid) / _Point;

   if(spreadPoints > InpMaxSpreadPoints)
   {
      Print("SINAL IGNORADO: Spread alto (", spreadPoints, " pontos). Limite: ", InpMaxSpreadPoints);
      ShowStatus("Sinal ignorado por spread elevado");
      return;
   }

   double lot = NormalizeLot(InpLotSize);

   if(buySignal)
   {
      if(trade.Buy(lot, _Symbol, ask, 0.0, 0.0, InpComment))
      {
         Print("COMPRA CONSERVADORA M15/H1 | Lote: ", lot, " | Entrada: ", ask);
         ShowStatus("COMPRA executada! Aguardando gerenciamento MANUAL.");
      }
      else
      {
         Print("FALHA NA COMPRA: ", trade.ResultRetcodeDescription());
      }
   }
   else if(sellSignal)
   {
      if(trade.Sell(lot, _Symbol, bid, 0.0, 0.0, InpComment))
      {
         Print("VENDA CONSERVADORA M15/H1 | Lote: ", lot, " | Entrada: ", bid);
         ShowStatus("VENDA executada! Aguardando gerenciamento MANUAL.");
      }
      else
      {
         Print("FALHA NA VENDA: ", trade.ResultRetcodeDescription());
      }
   }
}

void ShowStatus(string reason)
{
   Comment("=== XAUUSD ULTRA CONSERVADOR (V11) ===\n",
           "Status: ", reason, "\n",
           "Fechamento: 100% MANUAL pelo usuário\n",
           "Trades Hoje: ", g_tradesToday, "/", InpMaxTradesDay);
}

double NormalizeLot(double lot)
{
   double lotMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lot < lotMin) lot = lotMin;
   if(lot > lotMax) lot = lotMax;
   lot = MathFloor(lot / lotStep + 0.0000001) * lotStep;
   return NormalizeDouble(lot, 2);
}

bool HasOpenPosition()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(posInfo.SelectByIndex(i))
         if(posInfo.Symbol()==_Symbol && posInfo.Magic()==InpMagic) return true;
   }
   return false;
}

bool IsNewBar()
{
   datetime t = iTime(_Symbol, InpTimeframe, 0);
   if(t == 0 || t == g_lastBarTime) return false;
   g_lastBarTime = t;
   return true;
}

void ResetDailyControl()
{
   MqlDateTime dt, dtl;
   TimeToStruct(TimeCurrent(), dt);
   TimeToStruct(g_lastDayReset, dtl);
   if(dt.day != dtl.day || g_lastDayReset == 0)
   {
      g_lastDayReset = TimeCurrent();
      g_tradesToday = 0;
   }
}

void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != (long)InpMagic) return;

   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry == DEAL_ENTRY_IN)
   {
      g_tradesToday++;
   }
}
