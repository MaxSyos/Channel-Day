//+------------------------------------------------------------------+
//|                                                         MM10.mq5 |
//|                                  Copyright 2021, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+

#property copyright "Copyright 2021, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>
CTrade trade;

//+------------------------------------------------------------------+
//| INPUTS DE OPERAÇÃO                                               |
//+------------------------------------------------------------------+

input double                  lote        = 1;                          //Contratos
input double                  stopLoss    = 500;                        //Stop Loss Cross
input double                  takeProfit  = 200;                        //Stop Gain Cross
input double                  ValorParada = 38;                         //Valor de Gain
input double                  gatilhoBE   = 170;                        //Gatilho BreakEven
input double                  gatilhoTS   = 350;                        //Gatilho Trailling
input double                  stepTS      = 50;                         //Trailling Stop

input ulong                   magicNum    = 123456;                     //Magic Number

input int                     hAbertura   = 9;                          //Hora de Abertura
input int                     mAbertura   = 00;                         //Minuto de Aberura
input int                     hFechamento = 17;                         //Hora de Fechamento
input int                     mFechamento = 00;                         //Minuto de Fechamento

//+------------------------------------------------------------------+
//| VARIAVEIS                                                        |
//+------------------------------------------------------------------+


double                        MediaArray[];
double                        High[];
double                        Low[];
double                        Diferenca;

int                           Media_Handle;
int                           Negociacao;

static int                    CandleMaxima;
static int                    CandleMinima;
static int                    Contador_Barras;
static int                    Short;
static int                    Operacao;

static double                 LinhaAcima;
static double                 LinhaAbaixo;

static datetime               Marc_LastCheck;
static datetime               CurrentCandle;

static string                 Permicao;
static string                 CPermicao;
static string                 VPermicao;
static string                 BPermicao;
static string                 SPermicao;

bool                          posAberta;
bool                          ordPendente;
bool                          beAtivo;

MqlTick                       ultimoTick;
MqlRates                      candle[];

//+------------------------------------------------------------------+
//| Inicialização do sistema                                         |
//+------------------------------------------------------------------+

int OnInit()
  {
  
   Media_Handle = iMA(_Symbol, PERIOD_CURRENT, 200, 0, MODE_SMA, PRICE_CLOSE);
   if(Media_Handle==INVALID_HANDLE)
     {
        Print("Erro ao criar Média Móvel - erro", GetLastError());
        return(INIT_FAILED);
     }
     

   ArraySetAsSeries(candle, true);
   ArraySetAsSeries(High, true);
   ArraySetAsSeries(Low, true);
   ArraySetAsSeries(MediaArray, true);

   trade.SetExpertMagicNumber(magicNum);
  
   return(INIT_SUCCEEDED);
  }
  
void OnTick()
  {

//+------------------------------------------------------------------+
//| SINCRONIZA HORARIO SERVIDOR                                      |
//+------------------------------------------------------------------+

   MqlDateTime dt;
   TimeCurrent(dt);

//+------------------------------------------------------------------+
//| ATUALIZA VARIAVEIS DE HORARIOS                                   |
//+------------------------------------------------------------------+

   double loc_horarioAtual=dt.hour*60+dt.min;
   double loc_horarioAbertura=hAbertura*60+mAbertura;
   double loc_horarioFechamento=hFechamento*60+mFechamento-5;

//+------------------------------------------------------------------+
//| VERIFICA ABERTURA                                                |
//+------------------------------------------------------------------+

   if(loc_horarioAtual<loc_horarioAbertura)
     {
      Comment("[ROBO AGUARDANDO ABERTURA]");
      Contador_Barras = 0;
      Short           = 0;
      Operacao        = 0;        
      return;
     }
 
//+------------------------------------------------------------------+
//| VERIFICA FECHAMENTO                                              |
//+------------------------------------------------------------------+

   if(loc_horarioAtual>loc_horarioFechamento)
     {
      Comment("[ROBO ENCERROU O DIA]");
      Contador_Barras = 0;
      Short           = 0;
      Operacao        = 0;
      DeletarOrdens();
      FechaPosicao();
      return;
     }
        

   if(loc_horarioAtual<loc_horarioAbertura)
     {
      DeletarOrdens();
      return;
     }

   if(loc_horarioAtual>loc_horarioFechamento)
     {
      DeletarOrdens();
      return;
     }

//+------------------------------------------------------------------+
//| VERIFICA POSIÇÃO EM ABERTO                                       |
//+------------------------------------------------------------------+

      posAberta = false;
      for(int i = PositionsTotal()-1; i>=0; i--)
         {
            string symbol = PositionGetSymbol(i);
            ulong magic = PositionGetInteger(POSITION_MAGIC);
            if(symbol == _Symbol && magic==magicNum)
               {  
                  posAberta = true;
                  break;
               }
         }


      
      if(!posAberta)
         {
          beAtivo = false;
         }
         
      if(posAberta && !beAtivo)
         {
          BreakEven(ultimoTick.last);
         }
    
      if(posAberta && beAtivo)
         {
          TrailingStop(ultimoTick.last);
         }



   if(!SymbolInfoTick(Symbol(),ultimoTick))
     {
      Alert("Erro ao obter informações de Preços: ", GetLastError());
      return;
     }

   if(CopyRates(_Symbol, _Period, 0, 300, candle)<0)
     {
      Alert("Erro ao obter as informações do candle: ", GetLastError());
      return;
     }

   if(CopyHigh(_Symbol, _Period, 0, 20, High)<0)
     {
      Alert("Erro ao obter as informações do High: ", GetLastError());
      return;
     }

   if(CopyLow(_Symbol, _Period, 0, 20, Low)<0)
     {
      Alert("Erro ao obter as informações do Low: ", GetLastError());
      return;
     }

 
   if(CopyBuffer(Media_Handle, 0, 0, 200, MediaArray)<=0)
     {
      Alert("Erro ao copiar dados da Média Móvel: ", GetLastError());
      return;
     } 
 

//+------------------------------------------------------------------+
//| CAPTURA O PRIMEIRO CANDLE DO DIA                                 |
//+------------------------------------------------------------------+

   CurrentCandle = candle[0].time;

   if(CurrentCandle!=Marc_LastCheck)
     {
       Marc_LastCheck=CurrentCandle;
       Contador_Barras=Contador_Barras+1;               
     }
      
//+------------------------------------------------------------------+
//| CRIAÇÃO DE OBJETO                                                |
//+------------------------------------------------------------------+


     CandleMaxima = ArrayMaximum(High, 0, 12);
     CandleMinima = ArrayMinimum(Low, 0, 12);


   if(Contador_Barras==16)
     {
      LinhaAcima  = candle[CandleMaxima].high;
      LinhaAbaixo = candle[CandleMinima].low;
     }
     
     
   if((LinhaAcima+LinhaAbaixo)<1000)
    {
     Diferenca = ((LinhaAcima+LinhaAbaixo)*0.5);
    }

    
    
//Criação da Linha
 ObjectCreate(_Symbol, "LinhaAcima", OBJ_HLINE, 0, candle[CandleMaxima].time, candle[CandleMaxima].high);
 
//Cor da linha 
 ObjectSetInteger(0,"LinhaAcima", OBJPROP_COLOR, clrGreen);

//Espessura da linha 
 ObjectSetInteger(0, "LinhaAcima", OBJPROP_WIDTH, 3);
 
//Movimento da linha 
 if(Contador_Barras<=16)
   {
    ObjectMove(_Symbol, "LinhaAcima", 0, 0, candle[CandleMaxima].high);
   }


//Criação da Linha2
 ObjectCreate(_Symbol, "LinhaAbaixo", OBJ_HLINE, 0, candle[CandleMinima].time, candle[CandleMinima].low);
 
//Cor da linha2 
 ObjectSetInteger(0,"LinhaAbaixo", OBJPROP_COLOR, clrRed);

//Espessura da linha2 
 ObjectSetInteger(0, "LinhaAbaixo", OBJPROP_WIDTH, 3);

//Movimento da linha2 
 if(Contador_Barras<=16)
   {
    ObjectMove(_Symbol, "LinhaAbaixo", 0, 0, candle[CandleMinima].low);
   }


//+------------------------------------------------------------------+
//| FINANCEIRO                                                       |
//+------------------------------------------------------------------+

static double  Balance    = AccountInfoDouble(ACCOUNT_BALANCE);    
       double  Equity     = AccountInfoDouble(ACCOUNT_EQUITY);
       double  Valor      = (Equity-(Negociacao*lote));
       double  ValorReal  = (Valor-Balance);

//+------------------------------------------------------------------+
//| ESTRATEGIA  1                                                     |
//+------------------------------------------------------------------+

  

   Comment(               
           "Permição  : ", Permicao, "\n"
           "Permição de Compra : ", LinhaAcima, "\n"
           "Permição de Venda : ", LinhaAbaixo, "\n"
           "Número de Candles é : ", Contador_Barras, "\n"
           "Numero de Negociaões : ", Negociacao, "\n"
           "Operação : ", Operacao, "\n"                 
           "Short : ", Short, "\n"
           "Saldo : ", Equity, "\n"
           "Balanço Final : ", Balance, "\n"
           "Valor Liquido : ", (ValorReal-(ValorReal*0.2))
          );
   
//+------------------------------------------------------------------+
//| ORDENS DE COMPRA                                                 |
//+------------------------------------------------------------------+
 
 
   if( Permicao == "Sim" && Contador_Barras>16 && candle[1].close>candle[1].open && candle[2].close>candle[2].open && candle[2].close>LinhaAcima &&  Operacao==0 && !posAberta)
     {
      if(trade.Buy(lote, _Symbol, ultimoTick.ask, ultimoTick.ask-stopLoss, ultimoTick.ask+takeProfit, ""))
        {
         Print("Ordem de Compra - sem falha. ResultRetcode: ", trade.ResultRetcode(), ", RetcodeDescription: ", trade.ResultRetcodeDescription());
         Operacao = Operacao+1;
         Negociacao = Negociacao+1;                        
        }
      else
        {
         Print("Ordem de Compra - com falha. ResultRetcode: ", trade.ResultRetcode(), ", RetcodeDescription: ", trade.ResultRetcodeDescription());
        }
     }
     


//+------------------------------------------------------------------+
//|ORDEN DE VENDA                                                    |
//+------------------------------------------------------------------+

   if( Permicao == "Sim" && Contador_Barras>16 && candle[1].close<candle[1].open && candle[2].close<candle[2].open && candle[2].close<LinhaAbaixo &&  Short==0 && !posAberta)
     {
      if(trade.Sell(lote, _Symbol, ultimoTick.bid, ultimoTick.bid+stopLoss, ultimoTick.bid-takeProfit, ""))
        {
         Print("Ordem de Venda - sem falha. ResultRetcode: ", trade.ResultRetcode(), ", RetcodeDescription: ", trade.ResultRetcodeDescription());
         Short = Short+1;
         Negociacao = Negociacao+1;           
        }
      else
        {
         Print("Ordem de Venda - com falha. ResultRetcode: ", trade.ResultRetcode(), ", RetcodeDescription: ", trade.ResultRetcodeDescription());
        }
     }


  if((ValorReal-(ValorReal*0.2))>=ValorParada)
    {
     Permicao = "Não";
    }
    else
    {
     Permicao = "Sim";
    }



  }


//+------------------------------------------------------------------+
//|FUNÇÕES                                                           |
//+------------------------------------------------------------------+

void FechaPosicao()
  {
   for(int i = PositionsTotal()-1; i>=0; i--)
     {
      string symbol = PositionGetSymbol(i);
      if(symbol == _Symbol)
        {
         ulong PositionTicket = PositionGetInteger(POSITION_TICKET);
         if(trade.PositionClose(PositionTicket, NULL))
           {
            Print("Posição Fechada - sem falha. ResultRetcode: ", trade.ResultRetcode(), ", RetcodeDescription: ", trade.ResultRetcodeDescription());
           }
         else
           {
            Print("Posição Fechada - com falha. ResultRetcode: ", trade.ResultRetcode(), ", RetcodeDescription: ", trade.ResultRetcodeDescription());
           }
        }
     }
  }



void DeletarOrdens()
  {
   for(int i = PositionsTotal()-1; i>=0; i--)
     {
      ulong  ticket = OrderGetTicket(i);
      string symbol = OrderGetString(ORDER_SYMBOL);
      if(symbol == _Symbol)
        {
         ulong PositionTicket = PositionGetInteger(POSITION_TICKET);
         if(trade.OrderDelete(ticket))
           {
            Print("Ordem Deletada - sem falha. ResultRetcode: ", trade.ResultRetcode(), ", RetcodeDescription: ", trade.ResultRetcodeDescription());
           }
         else
           {
            Print("Ordem Deletada - com falha. ResultRetcode: ", trade.ResultRetcode(), ", RetcodeDescription: ", trade.ResultRetcodeDescription());
           }
        }
     }
  }



void TrailingStop(double preco)
   {
      for(int i = PositionsTotal()-1; i>=0; i--)
         {
            string symbol = PositionGetSymbol(i);
            ulong magic = PositionGetInteger(POSITION_MAGIC);
            if(symbol == _Symbol && magic==magicNum)
               {
                  ulong PositionTicket = PositionGetInteger(POSITION_TICKET);
                  double StopLossCorrente = PositionGetDouble(POSITION_SL);
                  double TakeProfitCorrente = PositionGetDouble(POSITION_TP);
                  if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                     {
                        if(preco >= (StopLossCorrente + gatilhoTS) )
                           {
                              double novoSL = NormalizeDouble(StopLossCorrente + stepTS, _Digits);
                              if(trade.PositionModify(PositionTicket, novoSL, TakeProfitCorrente))
                                 {
                                    Print("TrailingStop - sem falha. ResultRetcode: ", trade.ResultRetcode(), ", RetcodeDescription: ", trade.ResultRetcodeDescription());
                                 }
                              else
                                 {
                                    Print("TrailingStop - com falha. ResultRetcode: ", trade.ResultRetcode(), ", RetcodeDescription: ", trade.ResultRetcodeDescription());
                                 }
                           }
                     }
                  else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
                     {
                        if(preco <= (StopLossCorrente - gatilhoTS) )
                           {
                              double novoSL = NormalizeDouble(StopLossCorrente - stepTS, _Digits);
                              if(trade.PositionModify(PositionTicket, novoSL, TakeProfitCorrente))
                                 {
                                    Print("TrailingStop - sem falha. ResultRetcode: ", trade.ResultRetcode(), ", RetcodeDescription: ", trade.ResultRetcodeDescription());
                                 }
                              else
                                 {
                                    Print("TrailingStop - com falha. ResultRetcode: ", trade.ResultRetcode(), ", RetcodeDescription: ", trade.ResultRetcodeDescription());
                                 }
                           }
                     }
               }
         }
   }


//---
//---

void BreakEven(double preco)
   {
      for(int i = PositionsTotal()-1; i>=0; i--)
         {
            string symbol = PositionGetSymbol(i);
            ulong magic = PositionGetInteger(POSITION_MAGIC);
       //     int atv = 0;
            if(symbol == _Symbol && magic == magicNum)
               {
                  ulong PositionTicket = PositionGetInteger(POSITION_TICKET);
                  double PrecoEntrada = PositionGetDouble(POSITION_PRICE_OPEN);
                  double TakeProfitCorrente = PositionGetDouble(POSITION_TP);
                  if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                     {
                        if( preco >= (PrecoEntrada + gatilhoBE) )
                           {
                              if(trade.PositionModify(PositionTicket, PrecoEntrada+50, TakeProfitCorrente))
                                 {
                                    Print("BreakEven - sem falha. ResultRetcode: ", trade.ResultRetcode(), ", RetcodeDescription: ", trade.ResultRetcodeDescription());
                                    beAtivo = true;
                                 }
                              else
                                 {
                                    Print("BreakEven - com falha. ResultRetcode: ", trade.ResultRetcode(), ", RetcodeDescription: ", trade.ResultRetcodeDescription());
                                    
                                 }
                           }                           
                     }
                  else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
                     {
                        if( preco <= (PrecoEntrada - gatilhoBE) )
                           {
                              if(trade.PositionModify(PositionTicket, PrecoEntrada-50, TakeProfitCorrente))
                                 {
                                    Print("BreakEven - sem falha. ResultRetcode: ", trade.ResultRetcode(), ", RetcodeDescription: ", trade.ResultRetcodeDescription());
                                    beAtivo = true;
                                 }
                              else
                                 {
                                    Print("BreakEven - com falha. ResultRetcode: ", trade.ResultRetcode(), ", RetcodeDescription: ", trade.ResultRetcodeDescription());
                                 }  
                           }
                     }                           
               }
         }
   }
   
