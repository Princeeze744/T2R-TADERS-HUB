//+------------------------------------------------------------------+
//| T2R_Edge.mq5                                                     |
//| Trade2Retire Academy - the proven setups, traded and signalled   |
//|  1. DRIFT BREAKOUT (Boom & Crash): the first 15-minute candle at |
//|     07:00 / 13:30 / 14:30 GMT. Price closes outside it within 3  |
//|     hours -> trade the break ONLY if it goes with the drift      |
//|     (sell Boom, buy Crash). Stop 0.5x the candle, target 5R,     |
//|     closed after 8 hours. Tested Jan-Oct 2026 on 20 markets.     |
//|  2. GOLD TREND (forward test): 4-hour 20-candle breakout, stop   |
//|     1x ATR, target 3R, closed after 5 days.                      |
//| Attach to ONE chart (any). It scans every market by itself.      |
//| On the chart: the opening-range box, the trade lines and a panel.|
//+------------------------------------------------------------------+
#property copyright   "Trade2Retire Academy"
#property version     "1.01"
#property description "T2R Edge: Drift Breakout on Boom & Crash + Gold Trend forward test. Demo trades, website and member signals."
#include <Trade\Trade.mqh>

input group "Drift Breakout - Boom & Crash"
input bool   InpDrift      = true;          // Trade the Drift Breakout
input string InpDriftMk    = "Boom,Crash";  // Markets whose name starts with these words and a number
input bool   InpLondon     = true;          // Session 07:00 GMT (best: +0.30R a trade)
input bool   InpNY1        = true;          // Session 13:30 GMT (+0.23R a trade)
input bool   InpNY2        = false;         // Session 14:30 GMT (+0.19R a trade)
input double InpStopX      = 0.5;           // Stop = this x the height of the first 15-minute candle
input double InpTargetR    = 5.0;           // Target, in R
input int    InpBreakHours = 3;             // The break must come within this many hours
input int    InpHoldHours  = 8;             // Close at market after this many hours
input int    InpGmtShift   = 0;             // Broker clock minus GMT, in hours (Deriv = 0)
input group "Gold Trend - forward test"
input bool   InpGold       = true;          // Follow the Gold Trend
input string InpGoldSym    = "XAUUSD";      // Gold market name
input int    InpDonN       = 20;            // Breakout of the last N 4-hour candles
input double InpGoldStop   = 1.0;           // Stop = this x ATR(20) on 4 hours
input double InpGoldTgtR   = 3.0;           // Target, in R
input int    InpGoldDays   = 5;             // Close at market after this many days
input group "Demo account trading (never trades a real account)"
input bool   InpTrade      = true;          // Place the trades on this demo account
input double InpRiskPct    = 0.25;          // Risk per trade, % of balance (tested at 0.25%)
input long   InpMagic      = 15260;         // Magic number
input group "Website + member signals (same as the T2R Lab)"
input string InpWebUrl     = "";            // https://t2r-traders-hub.vercel.app/api/ingest
input string InpWebKey     = "";            // The T2R_INGEST_KEY

#define DIRF "T2R_Edge\\"
CTrade tr;

struct ETrade
  {
   string   id;
   string   sym;
   string   strat;
   string   view;
   int      dir;          // +1 buy, -1 sell
   double   entry;
   double   stop;
   double   target;
   double   unit;
   double   lots;
   ulong    tk;
   datetime tIn;
   datetime tEnd;
   datetime tSeen;
  };

string   g_mk[];
int      g_nMk=0;
ETrade   g_t[];
int      g_nT=0;
string   g_done[];
int      g_nDone=0;
string   g_dq[];
int      g_nDq=0;
uint     g_dqLast=0;
bool     g_dqWarn=false;
datetime g_goldBar=0;
int      g_win=0,g_loss=0,g_flat=0;
double   g_sumR=0.0;
string   g_log[];                       // last lines for the panel

int    SH[3]={7,13,14};
int    SM[3]={0,30,30};
string SN[3]={"London 07:00","NY 13:30","NY 14:30"};
bool SessOn(const int s) { return (s==0) ? InpLondon : (s==1) ? InpNY1 : InpNY2; }

//+------------------------------------------------------------------+
void Log(const string s)
  {
   Print("T2R Edge: ",s);
   int n=ArraySize(g_log);
   if(n>=6) ArrayRemove(g_log,0,1);
   n=ArraySize(g_log);
   ArrayResize(g_log,n+1);
   g_log[n]=TimeToString(TimeCurrent(),TIME_MINUTES)+"  "+s;
  }
string JS(const string s) { string o=s; StringReplace(o,"\\","\\\\"); StringReplace(o,"\"","\\\""); return "\""+o+"\""; }
string JK(const string k) { return "\""+k+"\":"; }
string Clean(const string s) { string o=s; StringReplace(o," ","_"); StringReplace(o,"/","_"); return o; }

//--- spike direction: Boom spikes up (+1), Crash down (-1)
int SpikeDir(const string sym)
  {
   string u=sym; StringToUpper(u);
   if(StringFind(u,"BOOM")==0) return 1;
   if(StringFind(u,"CRASH")==0) return -1;
   return 0;
  }

bool IsDriftMarket(const string s)
  {
   string toks[];
   int n=StringSplit(InpDriftMk,',',toks);
   for(int i=0;i<n;i++)
     {
      string t=toks[i]; StringTrimLeft(t); StringTrimRight(t);
      if(t=="") continue;
      int L=StringLen(t);
      if(StringLen(s)>L+1 && StringSubstr(s,0,L)==t && StringGetCharacter(s,L)==' ')
        {
         ushort c=StringGetCharacter(s,L+1);
         if(c>='0' && c<='9') return true;
        }
     }
   return false;
  }

void FindMarkets()
  {
   g_nMk=0; ArrayResize(g_mk,0);
   int tot=SymbolsTotal(false);
   for(int i=0;i<tot;i++)
     {
      string s=SymbolName(i,false);
      if(!IsDriftMarket(s)) continue;
      SymbolSelect(s,true);
      ArrayResize(g_mk,g_nMk+1);
      g_mk[g_nMk]=s; g_nMk++;
     }
   if(InpGold) SymbolSelect(InpGoldSym,true);
  }

//--- done keys: one decision per market, session and day (survives a restart)
bool IsDone(const string k) { for(int i=0;i<g_nDone;i++) if(g_done[i]==k) return true; return false; }
void MarkDone(const string k)
  {
   if(IsDone(k)) return;
   ArrayResize(g_done,g_nDone+1,256); g_done[g_nDone]=k; g_nDone++;
   int h=FileOpen(DIRF+"done.csv",FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h!=INVALID_HANDLE) { FileSeek(h,0,SEEK_END); FileWriteString(h,k+"\r\n"); FileClose(h); }
  }
void LoadDone()
  {
   g_nDone=0; ArrayResize(g_done,0);
   int h=FileOpen(DIRF+"done.csv",FILE_READ|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE) return;
   string today=TimeToString(TimeCurrent()-86400,TIME_DATE);
   while(!FileIsEnding(h))
     {
      string s=FileReadString(h); StringTrimRight(s);
      if(s=="") continue;
      string p[]; if(StringSplit(s,'|',p)<3) continue;
      if(p[2]<today) continue;                    // older than yesterday: forget
      ArrayResize(g_done,g_nDone+1,256); g_done[g_nDone]=s; g_nDone++;
     }
   FileClose(h);
   h=FileOpen(DIRF+"done.csv",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h!=INVALID_HANDLE) { for(int i=0;i<g_nDone;i++) FileWriteString(h,g_done[i]+"\r\n"); FileClose(h); }
  }

//--- open trades file
void SaveOpen()
  {
   int h=FileOpen(DIRF+"open.csv",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE) return;
   for(int i=0;i<g_nT;i++)
      FileWriteString(h,g_t[i].id+";"+g_t[i].sym+";"+g_t[i].strat+";"+g_t[i].view+";"+IntegerToString(g_t[i].dir)+";"+
                      DoubleToString(g_t[i].entry,8)+";"+DoubleToString(g_t[i].stop,8)+";"+DoubleToString(g_t[i].target,8)+";"+
                      DoubleToString(g_t[i].unit,8)+";"+DoubleToString(g_t[i].lots,2)+";"+IntegerToString((long)g_t[i].tk)+";"+
                      IntegerToString((long)g_t[i].tIn)+";"+IntegerToString((long)g_t[i].tEnd)+";"+IntegerToString((long)g_t[i].tSeen)+"\r\n");
   FileClose(h);
  }
void LoadOpen()
  {
   g_nT=0; ArrayResize(g_t,0);
   int h=FileOpen(DIRF+"open.csv",FILE_READ|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE) return;
   while(!FileIsEnding(h))
     {
      string s=FileReadString(h); StringTrimRight(s);
      string p[]; if(StringSplit(s,';',p)<14) continue;
      ArrayResize(g_t,g_nT+1,32);
      g_t[g_nT].id=p[0]; g_t[g_nT].sym=p[1]; g_t[g_nT].strat=p[2]; g_t[g_nT].view=p[3]; g_t[g_nT].dir=(int)StringToInteger(p[4]);
      g_t[g_nT].entry=StringToDouble(p[5]); g_t[g_nT].stop=StringToDouble(p[6]); g_t[g_nT].target=StringToDouble(p[7]);
      g_t[g_nT].unit=StringToDouble(p[8]); g_t[g_nT].lots=StringToDouble(p[9]); g_t[g_nT].tk=(ulong)StringToInteger(p[10]);
      g_t[g_nT].tIn=(datetime)StringToInteger(p[11]); g_t[g_nT].tEnd=(datetime)StringToInteger(p[12]); g_t[g_nT].tSeen=(datetime)StringToInteger(p[13]);
      SymbolSelect(g_t[g_nT].sym,true);
      g_nT++;
     }
   FileClose(h);
  }
void LoadTotals()
  {
   int h=FileOpen(DIRF+"results.csv",FILE_READ|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE) return;
   while(!FileIsEnding(h))
     {
      string s=FileReadString(h); StringTrimRight(s);
      string p[]; if(StringSplit(s,';',p)<6) continue;
      double r=StringToDouble(p[5]);
      g_sumR+=r; if(r>0.05) g_win++; else if(r<-0.05) g_loss++; else g_flat++;
     }
   FileClose(h);
  }

//+------------------------------------------------------------------+
//| money                                                            |
double RiskPerLot(const string sym,const double dist)
  {
   double ts=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
   double tv=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tv<=0.0) tv=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE);
   if(ts<=0.0 || tv<=0.0) return 0.0;
   return dist/ts*tv;
  }
double LotsFor(const string sym,const double dist)
  {
   double rpl=RiskPerLot(sym,dist);
   if(rpl<=0.0) return 0.0;
   double money=AccountInfoDouble(ACCOUNT_BALANCE)*InpRiskPct/100.0;
   double st=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP), mn=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN), mx=SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
   if(st<=0.0) st=0.01;
   double l=MathFloor(money/rpl/st+1e-9)*st;
   if(l<mn) return 0.0;                         // the smallest lot would risk too much
   return MathMin(l,mx);
  }
bool DemoOk() { return InpTrade && AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO && TerminalInfoInteger(TERMINAL_TRADE_ALLOWED); }

//+------------------------------------------------------------------+
//| website events                                                   |
void Event(const int k,const string kind,const double price,const datetime at,const double r)
  {
   if(InpWebUrl=="" || InpWebKey=="") return;
   string sym=g_t[k].sym;
   int dg=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
   double ratio=(g_t[k].unit>0.0) ? MathAbs(g_t[k].target-g_t[k].entry)/g_t[k].unit : 0.0;
   string j="{"+JK("id")+JS(g_t[k].id)+","+JK("kind")+JS(kind)+","+JK("at")+IntegerToString((long)at)+","+
            JK("market")+JS(sym)+","+JK("strategy")+JS(g_t[k].strat)+","+JK("view")+JS(g_t[k].view)+","+
            JK("side")+JS(g_t[k].strat=="T2R Drift Breakout" ? "With the drift" : "Both")+","+
            JK("stop_class")+JS(g_t[k].strat=="T2R Drift Breakout" ? "Range" : "ATR")+","+JK("dir")+JS(g_t[k].dir>0 ? "buy" : "sell")+","+
            JK("order_type")+JS("market")+","+JK("entry")+DoubleToString(g_t[k].entry,dg)+","+JK("stop")+DoubleToString(g_t[k].stop,dg)+","+
            JK("target")+DoubleToString(g_t[k].target,dg)+","+JK("rr")+JS("1:"+DoubleToString(ratio,0))+","+
            JK("t_signal")+IntegerToString((long)g_t[k].tIn)+","+JK("t_fill")+IntegerToString((long)g_t[k].tIn)+","+
            JK("risk_per_lot")+DoubleToString(RiskPerLot(sym,g_t[k].unit),4)+","+JK("vol_min")+DoubleToString(SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN),4)+","+
            JK("vol_step")+DoubleToString(SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP),4)+","+JK("ccy")+JS(AccountInfoString(ACCOUNT_CURRENCY))+","+
            JK("lots")+DoubleToString(g_t[k].lots,2)+","+JK("tg")+"true";
   if(price>0.0) j+=","+JK("price")+DoubleToString(price,dg);
   if(kind=="target" || kind=="stop" || kind=="closed") j+=","+JK("r")+DoubleToString(r,3)+","+JK("r_t2r")+DoubleToString(r,3);
   if(kind=="sync") j+=","+JK("status")+JS("active");
   j+="}";
   ArrayResize(g_dq,g_nDq+1,64); g_dq[g_nDq]=j; g_nDq++;
   if(g_nDq>2000) { ArrayRemove(g_dq,0,g_nDq-2000); g_nDq=2000; }
  }
void Flush()
  {
   if(InpWebUrl=="" || InpWebKey=="" || g_nDq==0 || GetTickCount()-g_dqLast<5000) return;
   g_dqLast=GetTickCount();
   int n=MathMin(g_nDq,50);
   string body="{"+JK("events")+"[";
   for(int i=0;i<n;i++) body+=(i>0 ? "," : "")+g_dq[i];
   body+="]}";
   uchar post[],res[]; string hdr="";
   int len=StringToCharArray(body,post,0,WHOLE_ARRAY,CP_UTF8)-1;
   if(len<=0) return;
   ArrayResize(post,len);
   ResetLastError();
   int code=WebRequest("POST",InpWebUrl,"Content-Type: application/json\r\nx-t2r-key: "+InpWebKey+"\r\n",8000,post,res,hdr);
   if(code==200) { ArrayRemove(g_dq,0,n); g_nDq-=n; g_dqWarn=false; return; }
   if(!g_dqWarn)
     {
      Log("website not reached (code "+IntegerToString(code)+"). Tools > Options > Expert Advisors: allow WebRequest for your website.");
      g_dqWarn=true;
     }
   if(code==400 || code==401) { ArrayRemove(g_dq,0,n); g_nDq-=n; }
  }

//+------------------------------------------------------------------+
//| open a trade (signal + demo order)                               |
void Open(const string sym,const string strat,const string view,const int dir,const double unit,const double tgtR,const int holdH)
  {
   MqlTick tk;
   if(!SymbolInfoTick(sym,tk) || unit<=0.0) return;
   int dg=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
   double ent=(dir>0) ? tk.ask : tk.bid;
   double stop=NormalizeDouble(ent-dir*unit,dg), tgt=NormalizeDouble(ent+dir*tgtR*unit,dg);
   int k=g_nT;
   ArrayResize(g_t,g_nT+1,32);
   g_t[k].id="E_"+Clean(sym)+"_"+IntegerToString((long)TimeCurrent())+"_"+(dir>0 ? "b" : "s");
   g_t[k].sym=sym; g_t[k].strat=strat; g_t[k].view=view; g_t[k].dir=dir;
   g_t[k].entry=ent; g_t[k].stop=stop; g_t[k].target=tgt; g_t[k].unit=unit; g_t[k].lots=0.0; g_t[k].tk=0;
   g_t[k].tIn=TimeCurrent(); g_t[k].tEnd=TimeCurrent()+holdH*3600; g_t[k].tSeen=iTime(sym,PERIOD_M1,0)+60;      // paper check starts with the next minute
   g_nT++;
   if(DemoOk())
     {
      double lots=LotsFor(sym,unit);
      if(lots>0.0)
        {
         tr.SetExpertMagicNumber(InpMagic);
         tr.SetTypeFillingBySymbol(sym);
         tr.SetDeviationInPoints(1000);
         bool ok=(dir>0) ? tr.Buy(lots,sym,0.0,stop,tgt,strat) : tr.Sell(lots,sym,0.0,stop,tgt,strat);
         if(ok && (tr.ResultRetcode()==TRADE_RETCODE_DONE || tr.ResultRetcode()==TRADE_RETCODE_PLACED))
           {
            g_t[k].tk=tr.ResultOrder(); g_t[k].lots=lots;
            if(tr.ResultPrice()>0.0)
              {
               double fill=tr.ResultPrice();          // keep stop and target where they were placed; R is measured from the real fill
               g_t[k].entry=fill;
              }
           }
         else
            Log(sym+" demo order refused ("+IntegerToString((int)tr.ResultRetcode())+" "+tr.ResultComment()+"), followed on paper");
        }
      else
         Log(sym+": smallest lot risks more than "+DoubleToString(InpRiskPct,2)+"%, followed on paper");
     }
   Event(k,"signal",g_t[k].entry,g_t[k].tIn,0.0);
   SaveOpen();
   Log(strat+" "+(dir>0 ? "BUY " : "SELL ")+sym+" at "+DoubleToString(g_t[k].entry,dg)+(g_t[k].tk>0 ? "  (demo "+DoubleToString(g_t[k].lots,2)+" lots)" : ""));
  }

void Close(const int k,const double px,const string why)
  {
   double r=(g_t[k].unit>0.0) ? (px-g_t[k].entry)*g_t[k].dir/g_t[k].unit : 0.0;
   double tgtR=MathAbs(g_t[k].target-g_t[k].entry)/g_t[k].unit;
   string kind=(why=="time") ? "closed" : (r>=0.9*tgtR) ? "target" : (r<=-0.8) ? "stop" : "closed";
   Event(k,kind,px,TimeCurrent(),r);
   int h=FileOpen(DIRF+"results.csv",FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h!=INVALID_HANDLE)
     {
      FileSeek(h,0,SEEK_END);
      FileWriteString(h,TimeToString(g_t[k].tIn)+";"+g_t[k].sym+";"+g_t[k].strat+";"+g_t[k].view+";"+(g_t[k].dir>0 ? "buy" : "sell")+";"+DoubleToString(r,3)+";"+kind+"\r\n");
      FileClose(h);
     }
   g_sumR+=r; if(r>0.05) g_win++; else if(r<-0.05) g_loss++; else g_flat++;
   Log(g_t[k].sym+" "+kind+"  "+(r>=0 ? "+" : "")+DoubleToString(r,2)+"R");
   ObjectsDeleteAll(0,"T2RE_"+g_t[k].id);
   for(int i=k;i<g_nT-1;i++) g_t[i]=g_t[i+1];   // remove trade k
   g_nT--;
   ArrayResize(g_t,g_nT);
   SaveOpen();
  }

//--- every open trade: did the stop, target or time come?
void Manage()
  {
   for(int k=g_nT-1;k>=0;k--)
     {
      string sym=g_t[k].sym;
      //--- a real demo position: the broker's result is the truth
      if(g_t[k].tk>0)
        {
         if(PositionSelectByTicket(g_t[k].tk))
           {
            if(TimeCurrent()>=g_t[k].tEnd)
              {
               tr.SetExpertMagicNumber(InpMagic);
               if(tr.PositionClose(g_t[k].tk)) { Close(k,tr.ResultPrice()>0 ? tr.ResultPrice() : PositionGetDouble(POSITION_PRICE_CURRENT),"time"); }
              }
            continue;
           }
         double px=0.0;
         if(HistorySelectByPosition(g_t[k].tk))
            for(int i=HistoryDealsTotal()-1;i>=0;i--)
              {
               ulong d=HistoryDealGetTicket(i);
               if(d>0 && HistoryDealGetInteger(d,DEAL_ENTRY)==DEAL_ENTRY_OUT) { px=HistoryDealGetDouble(d,DEAL_PRICE); break; }
              }
         if(px<=0.0) { MqlTick t; SymbolInfoTick(sym,t); px=(g_t[k].dir>0) ? t.bid : t.ask; }
         Close(k,px,(TimeCurrent()>=g_t[k].tEnd) ? "time" : "broker");
         continue;
        }
      //--- on paper: every one-minute candle since the last look (catches spikes between checks)
      MqlRates m[];
      ArraySetAsSeries(m,false);
      int n=CopyRates(sym,PERIOD_M1,g_t[k].tSeen,TimeCurrent(),m);
      MqlTick t; SymbolInfoTick(sym,t);
      double spr=t.ask-t.bid;
      bool shut=false;
      for(int i=0;i<n && !shut;i++)
        {
         double hi=m[i].high+(g_t[k].dir<0 ? spr : 0.0), lo=m[i].low+(g_t[k].dir<0 ? spr : 0.0), op=m[i].open+(g_t[k].dir<0 ? spr : 0.0);
         if(g_t[k].dir>0)
           {
            if(lo<=g_t[k].stop) { Close(k,MathMin(op,g_t[k].stop),"paper"); shut=true; break; }
            if(hi>=g_t[k].target) { Close(k,MathMax(op,g_t[k].target),"paper"); shut=true; break; }
           }
         else
           {
            if(hi>=g_t[k].stop) { Close(k,MathMax(op,g_t[k].stop),"paper"); shut=true; break; }
            if(lo<=g_t[k].target) { Close(k,MathMin(op,g_t[k].target),"paper"); shut=true; break; }
           }
        }
      if(shut) continue;
      if(n>0) g_t[k].tSeen=m[n-1].time;           // the forming minute is checked again next time
      if(TimeCurrent()>=g_t[k].tEnd)
         Close(k,(g_t[k].dir>0) ? t.bid : t.ask,"time");
     }
  }

//+------------------------------------------------------------------+
//| strategy 1: Drift Breakout                                       |
void DriftScan()
  {
   if(!InpDrift) return;
   datetime now=TimeCurrent();
   MqlDateTime d; TimeToStruct(now,d); d.hour=0; d.min=0; d.sec=0;
   datetime day0=StructToTime(d);
   string ds=TimeToString(day0,TIME_DATE);
   for(int s=0;s<3;s++)
     {
      if(!SessOn(s)) continue;
      datetime t0=day0+(SH[s]+InpGmtShift)*3600+SM[s]*60;
      if(now<t0+900 || now>t0+900+InpBreakHours*3600+900) continue;
      for(int i=0;i<g_nMk;i++)
        {
         string sym=g_mk[i];
         string key=sym+"|"+SN[s]+"|"+ds;
         if(IsDone(key)) continue;
         MqlRates r[];
         ArraySetAsSeries(r,false);
         int n=CopyRates(sym,PERIOD_M15,t0,now,r);
         if(n<1) continue;
         if(r[0].time!=t0) { MarkDone(key); continue; }          // no candle at the session open
         double H=r[0].high, L=r[0].low, rng=H-L;
         if(rng<=0.0) { MarkDone(key); continue; }
         int maxB=InpBreakHours*4;
         int dir=0, kb=-1;
         for(int b=1;b<n && b<=maxB;b++)
           {
            if(r[b].time+900>now) break;                        // candle not closed yet
            if(r[b].close>H) { dir=1; kb=b; break; }
            if(r[b].close<L) { dir=-1; kb=b; break; }
           }
         if(dir==0)
           {
            if(now>=t0+900+maxB*900) MarkDone(key);            // no break in time
            continue;
           }
         MarkDone(key);
         if(now-(r[kb].time+900)>300) { Log(sym+" "+SN[s]+": break seen late, skipped"); continue; }
         if(dir==SpikeDir(sym)) { Log(sym+" "+SN[s]+": broke with the spike, skipped (tested negative)"); continue; }
         Open(sym,"T2R Drift Breakout",SN[s],dir,InpStopX*rng,InpTargetR,InpHoldHours);
         DrawBox(sym,t0,H,L);
        }
     }
  }

//+------------------------------------------------------------------+
//| strategy 2: Gold Trend (4-hour breakout)                         |
void GoldScan()
  {
   if(!InpGold) return;
   datetime bt=iTime(InpGoldSym,PERIOD_H4,0);
   if(bt==0 || bt==g_goldBar) return;
   MqlRates r[];
   ArraySetAsSeries(r,true);
   int need=InpDonN+25;
   if(CopyRates(InpGoldSym,PERIOD_H4,0,need,r)<need) return;
   g_goldBar=bt;
   if(TimeCurrent()-bt>600) return;                          // only act right after a 4-hour candle closes
   double hh1=-DBL_MAX, ll1=DBL_MAX, hh2=-DBL_MAX, ll2=DBL_MAX;
   for(int i=2;i<=InpDonN+1;i++) { hh1=MathMax(hh1,r[i].high); ll1=MathMin(ll1,r[i].low); }
   for(int i=3;i<=InpDonN+2;i++) { hh2=MathMax(hh2,r[i].high); ll2=MathMin(ll2,r[i].low); }
   double atr=0.0;
   for(int i=1;i<=20;i++)
      atr+=MathMax(r[i].high-r[i].low,MathMax(MathAbs(r[i].high-r[i+1].close),MathAbs(r[i].low-r[i+1].close)));
   atr/=20.0;
   int dir=0;
   if(r[1].close>hh1 && !(r[2].close>hh2)) dir=1;
   if(r[1].close<ll1 && !(r[2].close<ll2)) dir=-1;
   if(dir==0) return;
   Open(InpGoldSym,"T2R Trend Gold 4H",IntegerToString(InpDonN)+"-candle breakout",dir,InpGoldStop*atr,InpGoldTgtR,InpGoldDays*24);
  }

//+------------------------------------------------------------------+
//| the chart: box, trade lines, panel                               |
void DrawBox(const string sym,const datetime t0,const double H,const double L)
  {
   if(sym!=_Symbol) return;
   string nm="T2RB_"+TimeToString(t0);
   ObjectCreate(0,nm,OBJ_RECTANGLE,0,t0,H,t0+InpBreakHours*3600+900,L);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,clrSteelBlue);
   ObjectSetInteger(0,nm,OBJPROP_FILL,true);
   ObjectSetInteger(0,nm,OBJPROP_BACK,true);
  }
void DrawChart()
  {
   //--- today's boxes on this chart
   if(IsDriftMarket(_Symbol))
     {
      MqlDateTime d; TimeToStruct(TimeCurrent(),d); d.hour=0; d.min=0; d.sec=0;
      datetime day0=StructToTime(d);
      for(int s=0;s<3;s++)
        {
         if(!SessOn(s)) continue;
         datetime t0=day0+(SH[s]+InpGmtShift)*3600+SM[s]*60;
         MqlRates r[];
         if(TimeCurrent()>=t0+900 && CopyRates(_Symbol,PERIOD_M15,t0,1,r)==1 && r[0].time==t0)
            DrawBox(_Symbol,t0,r[0].high,r[0].low);
        }
     }
   for(int k=0;k<g_nT;k++)
     {
      if(g_t[k].sym!=_Symbol) continue;
      string b="T2RE_"+g_t[k].id;
      double lv[3]; lv[0]=g_t[k].entry; lv[1]=g_t[k].stop; lv[2]=g_t[k].target;
      color  cl[3]; cl[0]=clrDodgerBlue; cl[1]=clrTomato; cl[2]=clrLimeGreen;
      string nm[3]; nm[0]="_e"; nm[1]="_s"; nm[2]="_t";
      for(int q=0;q<3;q++)
        {
         if(ObjectFind(0,b+nm[q])<0) ObjectCreate(0,b+nm[q],OBJ_TREND,0,g_t[k].tIn,lv[q],g_t[k].tEnd,lv[q]);
         ObjectSetInteger(0,b+nm[q],OBJPROP_COLOR,cl[q]);
         ObjectSetInteger(0,b+nm[q],OBJPROP_WIDTH,2);
        }
     }
   //--- panel
   int closed=g_win+g_loss+g_flat;
   string s="T2R EDGE  -  the proven setups\n";
   s+="Drift Breakout: "+(InpDrift ? IntegerToString(g_nMk)+" Boom & Crash markets, sessions"+(InpLondon ? " 07:00" : "")+(InpNY1 ? " 13:30" : "")+(InpNY2 ? " 14:30" : "")+" GMT" : "off")+"\n";
   s+="Gold Trend (forward test): "+(InpGold ? InpGoldSym : "off")+"\n";
   s+="Demo trading: "+(DemoOk() ? "ON at "+DoubleToString(InpRiskPct,2)+"% risk" : "off (paper only)")+"   Website: "+((InpWebUrl!="" && InpWebKey!="") ? "ON" : "off")+"\n";
   s+="--------------------------------------------\n";
   s+="Open now: "+IntegerToString(g_nT)+"\n";
   for(int k=0;k<g_nT && k<12;k++)
     {
      MqlTick t; SymbolInfoTick(g_t[k].sym,t);
      double px=(g_t[k].dir>0) ? t.bid : t.ask;
      double r=(g_t[k].unit>0) ? (px-g_t[k].entry)*g_t[k].dir/g_t[k].unit : 0.0;
      s+="  "+(g_t[k].dir>0 ? "BUY  " : "SELL ")+g_t[k].sym+"  "+(r>=0 ? "+" : "")+DoubleToString(r,2)+"R  ("+g_t[k].view+")\n";
     }
   s+="Closed: "+IntegerToString(closed)+"   won "+IntegerToString(g_win)+"  lost "+IntegerToString(g_loss)+"   total "+(g_sumR>=0 ? "+" : "")+DoubleToString(g_sumR,1)+"R\n";
   s+="Backtest Jan-Oct 2026 (07:00): about +0.30R a trade, 1 in 4 wins, every month positive\n";
   s+="--------------------------------------------\n";
   for(int i=0;i<ArraySize(g_log);i++) s+=g_log[i]+"\n";
   Comment(s);
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   FolderCreate("T2R_Edge");
   FindMarkets();
   LoadDone();
   LoadOpen();
   LoadTotals();
   for(int k=0;k<g_nT;k++) Event(k,"sync",0.0,TimeCurrent(),0.0);
   Log("started: "+IntegerToString(g_nMk)+" Boom & Crash markets"+(InpGold ? " + "+InpGoldSym : "")+", "+IntegerToString(g_nT)+" open trades restored");
   if(g_nMk==0 && InpDrift) Log("no Boom or Crash market found - check the names in Market Watch");
   EventSetTimer(2);
   return INIT_SUCCEEDED;
  }
void OnDeinit(const int reason) { EventKillTimer(); Comment(""); }
void OnTimer()
  {
   Manage();
   DriftScan();
   GoldScan();
   Flush();
   DrawChart();
  }
void OnTick() { }
//+------------------------------------------------------------------+
