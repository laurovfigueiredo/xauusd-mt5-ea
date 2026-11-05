//+------------------------------------------------------------------+
//|                                    XAUUSD_ORB_MinRisk_Martingale.mq5|
//|                                  Adaptado da Day-Trader-Skill (ORB)|
//|                                        Foco: MINIMO RISCO - DEMO   |
//+------------------------------------------------------------------+
#property copyright "Adaptado do day-trader-skill"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\HistoryOrderInfo.mqh>

//--- Objetos
CTrade         trade;
CPositionInfo  posInfo;
CHistoryOrderInfo histOrder;

//--- Inputs - Horário
input group "=== HORARIO DE OPERACAO ==="
input int      InpStartHour   = 8;      // Hora inicio (BRT)
input int      InpStartMin   = 0;      // Minuto inicio
input int      InpEndHour     = 17;     // Hora fim (BRT)
input bool     InpUseServerTime = false; // Usar horario do servidor MT5

//--- Inputs - Opening Range
input group "=== OPENING RANGE (ORB) ==="
input int      InpRangeMinutes= 15;     // Minutos para calcular Range
input ENUM_TIMEFRAMES InpTF   = PERIOD_M1; // Timeframe

//--- Inputs - Gerenciamento
input group "=== GERENCIAMENTO RISCO ==="
input double   InpRiskPercentDaily = 3.0; // Limite perda diaria (% da conta)
input int      InpMaxSpreadPoints  = 30;  // Spread maximo em pontos
input bool     InpOnlyOneTrade     = true;// Apenas 1 operacao por vez

//--- Inputs - Martingale (MINIMO RISCO)
input group "=== MARTINGALE (CONFIGURACAO CONSERVADORA) ==="
input double   InpLotInitial      = 0.01;// Lote inicial
input double   InpMartingaleMult  = 1.5; // Multiplicador (1.5x mais conservador)
input int      InpMaxMartingale   = 2;   // Maximo niveis martingale (0 = sem martingale)
input double   InpMaxLot          = 0.0225;// Lote maximo absoluto
input bool     InpResetOnWin      = true;// Resetar lote ao ganhar

//--- Inputs - Saidas
input group "=== SAIDAS (SL/TP) ==="
input int      InpSLMode          = 0;   // 0=OR-Mid, 1=OR-Low
input double   InpTPR             = 1.0; // Take Profit em R (1.0 = 1R)

//--- Inputs - BreakEven
input group "=== BREAK EVEN ==="
input bool     InpUseBreakEven    = true;// Ativar BreakEven
input int      InpBETriggerPips   = 10;  // Pips em lucro para ativar BE
input int      InpBEPlusPips      = 1;   // Pips acima da entrada (+)

//--- Inputs - Outros
input group "=== OUTROS ==="
input ulong    InpMagic           = 20251025;// Magic Number
input string   InpComment         = "XAUUSD_ORB_MR"; // Comentario

//--- Variaveis globais
datetime g_lastBarTime = 0;
double   g_rangeHigh = 0;
double   g_rangeLow  = 0;
double   g_rangeMid  = 0;
bool     g_rangeCalculated = false;
datetime g_rangeCalcDate = 0;

// Martingale
double   g_currentLot = 0.01;
int      g_martingaleLevel = 0;
datetime g_lastTradeCloseTime = 0;

// Controle diario
double   g_dailyStartBalance = 0;
datetime g_lastDayReset = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFillingBySymbol(_Symbol);
   
   g_currentLot = InpLotInitial;
   g_martingaleLevel = 0;
   
   ResetDailyControl();
   
   Print("=== XAUUSD ORB MIN-RISK MARTINGALE INICIADO ===");
   Print("Ativo: ", _Symbol);
   Print("Timeframe: M1 | Range: ", InpRangeMinutes, " min");
   Print("Horario: ", InpStartHour, ":", InpStartMin, " - ", InpEndHour, ":00 BRT");
   Print("SL: ", (InpSLMode==0?"OR-MID":"OR-LOW"), " | TP: ", InpTPR, "R");
   Print("Martingale: Lote=", InpLotInitial, " Mult=", InpMartingaleMult, " MaxLevel=", InpMaxMartingale, " MaxLot=", InpMaxLot);
   Print("Limite perda diaria: ", InpRiskPercentDaily, "% | BreakEven: ", (InpUseBreakEven?"SIM":"NAO"));
   Print("ATENCAO: TESTAR APENAS EM CONTA DEMO!");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA Finalizado. Motivo: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Reset diario
   ResetDailyControl();
   
   // Verificar limite de perda diaria
   if(IsDailyLossLimitHit())
   {
      // Fechar todas posicoes se ainda houver
      CloseAllPositions();
      return;
   }
   
   // Verificar BreakEven
   if(InpUseBreakEven)
      CheckBreakEven();
   
   // Verificar se ja tem posicao aberta
   if(InpOnlyOneTrade && HasOpenPosition())
      return;
   
   // Verificar horario
   if(!IsTradingTime())
      return;
   
   // Verificar spread
   if(GetSpreadPoints() > InpMaxSpreadPoints)
      return;
   
   // Calcular/Resetar Range
   if(!IsSameDay(g_rangeCalcDate, TimeCurrent()) || !g_rangeCalculated)
   {
      CalculateOpeningRange();
   }
   
   // Procurar entrada
   if(g_rangeCalculated && g_rangeHigh > 0)
   {
      CheckForEntry();
   }
}

//+------------------------------------------------------------------+
//| Calcular Opening Range                                           |
//+------------------------------------------------------------------+
void CalculateOpeningRange()
{
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   
   // Definir inicio do range (hora configurada)
   datetime rangeStart = StructToTime(dt);
   // Ajustar para horario de inicio
   MqlDateTime rangeStartDt;
   TimeToStruct(rangeStart, rangeStartDt);
   rangeStartDt.hour = InpStartHour;
   rangeStartDt.min  = InpStartMin;
   rangeStartDt.sec  = 0;
   rangeStart = StructToTime(rangeStartDt);
   
   // Se ja passou do inicio do range hoje, calcular
   if(now >= rangeStart)
   {
      datetime rangeEnd = rangeStart + InpRangeMinutes * 60;
      
      // Buscar velas M1 do range
      double highArr[], lowArr[];
      ArraySetAsSeries(highArr, true);
      ArraySetAsSeries(lowArr, true);
      
      int copied = CopyHigh(_Symbol, InpTF, rangeStart, rangeEnd - rangeStart, highArr);
      int copiedLow = CopyLow(_Symbol, InpTF, rangeStart, rangeEnd - rangeStart, lowArr);
      
      if(copied > 0 && copiedLow > 0)
      {
         g_rangeHigh = highArr[0];
         g_rangeLow  = lowArr[0];
         
         for(int i=1; i<copied; i++)
         {
            if(highArr[i] > g_rangeHigh) g_rangeHigh = highArr[i];
            if(lowArr[i]  < g_rangeLow)  g_rangeLow  = lowArr[i];
         }
         
         g_rangeMid = (g_rangeHigh + g_rangeLow) / 2.0;
         g_rangeCalculated = true;
         g_rangeCalcDate = now;
         
         Print("RANGE CALCULADO [", TimeToString(rangeStart,TIME_MINUTES), " - ", TimeToString(rangeEnd,TIME_MINUTES), "] ");
         Print("Range High: ", DoubleToString(g_rangeHigh,_Digits), " | Range Low: ", DoubleToString(g_rangeLow,_Digits), " | Range Mid: ", DoubleToString(g_rangeMid,_Digits));
      }
   }
   else
   {
      g_rangeCalculated = false;
   }
}

//+------------------------------------------------------------------+
//| Verificar entrada                                                |
//+------------------------------------------------------------------+
void CheckForEntry()
{
   // Pegar ultima vela fechada
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, InpTF, 0, 2, rates) < 2) return;
   
   // So entra com vela FECHADA (rates[1])
   double close1 = rates[1].close;
   double close0 = rates[0].close; // vela atual ainda aberta
   
   // Verificar se ja entrou hoje com este range
   // Entrada apenas quando fechar ACIMA do Range High
   if(close1 > g_rangeHigh && close0 <= g_rangeHigh) // Acabou de romper
   {
      // Verificar se ja tivemos entrada valida neste range
      static datetime lastEntryAttempt = 0;
      if(lastEntryAttempt == g_rangeCalcDate) return;
      
      // Calcular SL e TP
      double sl = 0, tp = 0;
      double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double riskPips = 0;
      
      if(InpSLMode == 0)
      {
         // SL no OR-Mid
         sl = g_rangeMid;
      }
      else
      {
         // SL no OR-Low
         sl = g_rangeLow;
      }
      
      // Calcular risco em preco
      riskPips = entryPrice - sl;
      if(riskPips <= 0) return;
      
      // TP = entry + (risk * TP_R)
      tp = entryPrice + (riskPips * InpTPR);
      
      // Validar
      if(sl >= entryPrice) return;
      if(tp <= entryPrice) return;
      
      // Verificar spread
      if(GetSpreadPoints() > InpMaxSpreadPoints) return;
      
      // Calcular lote com martingale
      double lotToTrade = CalculateMartingaleLot();
      
      if(lotToTrade < SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN)) lotToTrade = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
      if(lotToTrade > InpMaxLot) lotToTrade = InpMaxLot;
      
      // Normalizar lote
      lotToTrade = NormalizeDouble(lotToTrade, 2);
      
      // Enviar ordem
      if(trade.Buy(lotToTrade, _Symbol, entryPrice, sl, tp, InpComment))
      {
         Print("=== ENTRADA COMPRA ===");
         Print("Preco: ", entryPrice, " | SL: ", sl, " (Risk: ", DoubleToString(riskPips/_Point,1), " pts) | TP: ", tp);
         Print("Lote: ", lotToTrade, " | Nivel Martingale: ", g_martingaleLevel);
         lastEntryAttempt = g_rangeCalcDate;
      }
      else
      {
         Print("ERRO AO ENTRAR: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
      }
   }
}

//+------------------------------------------------------------------+
//| Calcular lote com Martingale                                     |
//+------------------------------------------------------------------+
double CalculateMartingaleLot()
{
   if(InpMaxMartingale <= 0) return InpLotInitial;
   return NormalizeDouble(InpLotInitial * MathPow(InpMartingaleMult, g_martingaleLevel), 2);
}

//+------------------------------------------------------------------+
//| Verificar BreakEven                                              |
//+------------------------------------------------------------------+
void CheckBreakEven()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagic)
         {
            if(posInfo.PositionType() == POSITION_TYPE_BUY)
            {
               double openPrice = posInfo.PriceOpen();
               double currentSL = posInfo.StopLoss();
               double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
               
               // Calcular lucro em pips
               double profitPips = (bid - openPrice) / _Point;
               
               // Se ja tem SL >= openPrice, ja esta em BE
               if(currentSL >= openPrice) continue;
               
               // Ativar BE quando atingir trigger
               if(profitPips >= InpBETriggerPips)
               {
                  double newSL = openPrice + InpBEPlusPips * _Point;
                  if(newSL > currentSL)
                  {
                     if(trade.PositionModify(posInfo.Ticket(), newSL, posInfo.TakeProfit()))
                     {
                        Print("BREAK EVEN ATIVADO | Ticket: ", posInfo.Ticket(), " | SL movido para: ", newSL);
                     }
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Verificar se tem posicao aberta                                  |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagic)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Fechar todas posicoes                                           |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagic)
         {
            trade.PositionClose(posInfo.Ticket());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Verificar horario de operacao                                    |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   
   int currentHour = dt.hour;
   int currentMin  = dt.min;
   
   // Converter para minutos do dia
   int currentTimeMin = currentHour * 60 + currentMin;
   int startTimeMin   = InpStartHour * 60 + InpStartMin;
   int endTimeMin     = InpEndHour * 60;
   
   if(startTimeMin <= endTimeMin)
   {
      // Mesmo dia
      if(currentTimeMin >= startTimeMin && currentTimeMin < endTimeMin)
         return true;
   }
   else
   {
      // Atravessa meia noite (nao usado aqui)
      if(currentTimeMin >= startTimeMin || currentTimeMin < endTimeMin)
         return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Pegar spread em pontos                                          |
//+------------------------------------------------------------------+
long GetSpreadPoints()
{
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return spread;
}

//+------------------------------------------------------------------+
//| Reset controle diario                                           |
//+------------------------------------------------------------------+
void ResetDailyControl()
{
   datetime now = TimeCurrent();
   MqlDateTime dt, dtLast;
   TimeToStruct(now, dt);
   TimeToStruct(g_lastDayReset, dtLast);
   
   if(dt.day != dtLast.day || g_lastDayReset == 0)
   {
      g_dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_lastDayReset = now;
      g_rangeCalculated = false;
      g_rangeHigh = 0; g_rangeLow = 0; g_rangeMid = 0;
      
      // Reset martingale no inicio do dia (mais seguro)
      g_currentLot = InpLotInitial;
      g_martingaleLevel = 0;
      
      Print("=== NOVO DIA - CONTROLES RESETADOS ===");
      Print("Saldo inicial do dia: ", g_dailyStartBalance);
      Print("Martingale resetado para lote: ", g_currentLot);
   }
}

//+------------------------------------------------------------------+
//| Verificar limite perda diaria                                    |
//+------------------------------------------------------------------+
bool IsDailyLossLimitHit()
{
   if(g_dailyStartBalance <= 0) return false;
   
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   double drawdownPercent = ((g_dailyStartBalance - currentEquity) / g_dailyStartBalance) * 100.0;
   
   if(drawdownPercent >= InpRiskPercentDaily)
   {
      Print("!!! LIMITE DE PERDA DIARIA ATINGIDO !!!");
      Print("Drawdown: ", DoubleToString(drawdownPercent,2), "% | Limite: ", InpRiskPercentDaily, "%");
      Print("EA PARADO PARA O RESTO DO DIA POR SEGURANÇA");
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Verificar se mesmo dia                                          |
//+------------------------------------------------------------------+
bool IsSameDay(datetime d1, datetime d2)
{
   if(d1 == 0) return false;
   MqlDateTime dt1, dt2;
   TimeToStruct(d1, dt1);
   TimeToStruct(d2, dt2);
   return (dt1.day == dt2.day && dt1.mon == dt2.mon && dt1.year == dt2.year);
}

//+------------------------------------------------------------------+
//| Tratamento de fechamento de posicao (para martingale)           |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      HistoryDealSelect(trans.deal);
      long dealMagic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
      long dealEntry  = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
      
      if(dealMagic == InpMagic && dealEntry == DEAL_ENTRY_OUT)
      {
         // Posicao foi fechada
         double dealProfit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
         double dealCommission = HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
         double dealSwap = HistoryDealGetDouble(trans.deal, DEAL_SWAP);
         double totalProfit = dealProfit + dealCommission + dealSwap;
         
         if(totalProfit > 0)
         {
            // Operacao vencedora - resetar martingale
            if(InpResetOnWin)
            {
               g_martingaleLevel = 0;
               Print("LUCRO! Martingale RESETADO para nivel 0 | Lote proximo: ", InpLotInitial);
            }
         }
         else if(totalProfit < 0)
         {
            // Operacao perdedora - aumentar martingale
            if(InpMaxMartingale > 0 && g_martingaleLevel < InpMaxMartingale)
            {
               g_martingaleLevel++;
               double nextLot = CalculateMartingaleLot();
               if(nextLot > InpMaxLot) 
               {
                  g_martingaleLevel = InpMaxMartingale;
                  Print("LIMITE MAXIMO DE MARTINGALE ATINGIDO! Lote maximo: ", InpMaxLot);
               }
               else
               {
                  Print("PERDA! Martingale AUMENTADO para nivel ", g_martingaleLevel, " | Proximo lote: ", nextLot);
               }
            }
            else if(g_martingaleLevel >= InpMaxMartingale)
            {
               Print("PERDA! Maximo de niveis martingale atingido. Mantendo lote maximo ou parando para proximo ciclo.");
            }
         }
         // Se empate (raro), mantem nivel atual
      }
   }
}
//+------------------------------------------------------------------+