//+------------------------------------------------------------------+
//| T2R_LearnedZones.mq5  (v2.00)
//| Swing levels scored by a small model that learns, from the older
//| half of history, which conditions came before reversals.
//| v2: learned zones bright (star), other zones faint; on Boom & Crash
//| only the with-the-spike side (the proven T2R setup); the EA's trade
//| plan (Wide stop, 1:3) drawn on the nearest learned zone; live card.
//+------------------------------------------------------------------+
#property copyright "SELF-TAUGHT ZONES"
#property version   "2.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

enum ENUM_LBL_SIZE
  {
   SZ_TINY,     // Tiny
   SZ_SMALL,    // Small
   SZ_NORMAL,   // Normal
   SZ_LARGE     // Large
  };

input group "Timeframes scanned (must be above the chart timeframe)"
input bool            InpShow1        = true;        // Timeframe 1 - use
input ENUM_TIMEFRAMES InpTF1          = PERIOD_H1;   // Timeframe 1
input bool            InpShow2        = true;        // Timeframe 2 - use
input ENUM_TIMEFRAMES InpTF2          = PERIOD_H4;   // Timeframe 2
input bool            InpShow3        = true;        // Timeframe 3 - use
input ENUM_TIMEFRAMES InpTF3          = PERIOD_D1;   // Timeframe 3
input bool            InpShow4        = false;       // Timeframe 4 - use
input ENUM_TIMEFRAMES InpTF4          = PERIOD_W1;   // Timeframe 4

input group "Self-taught model"
input double          InpZoneATR      = 0.25;        // Zone height at each swing level (x ATR)
input int             InpRangeBars    = 480;         // Chart bars used for "where in the range"
input int             InpTrendBars    = 200;         // Chart bars used for trend
input double          InpPickScore    = 0.30;        // Score a level needs to be a model pick
input int             InpModelMinN    = 10;          // Older trades needed before a clue is trusted

input group "T2R proven setup (matches the EA and the Telegram TOP SIGNAL)"
input bool            InpSpikeOnly    = true;        // Boom & Crash: show only the with-the-spike side (Boom buys, Crash sells)
input bool            InpShowOthers   = true;        // Also show zones the model does NOT pick (faint)
input bool            InpPlan         = true;        // Draw the trade plan on the nearest learned zone
input double          InpWideATR      = 3.0;         // Wide stop: 1R = zone height, at least this x ATR (EA: 3.0)
input double          InpTargetR      = 3.0;         // Target in R (EA: 3)
input bool            InpCard         = true;        // Show the live Learned Zone card
input bool            InpCardBottom   = false;       // Card at the bottom right (off = top right)

input group "Zones on the chart"
input int             InpLookback     = 60;          // Candles a zone stays valid (per timeframe)
input int             InpZoneMax      = 3;           // Max zones drawn per side (nearest to price)
input color           InpBuyColor     = C'38,166,154'; // BUY zone colour
input color           InpSellColor    = C'239,83,80';  // SELL zone colour
input int             InpZoneTransp   = 78;          // Zone transparency % (0-100)
input bool            InpMidline      = true;        // Dashed middle line
input ENUM_LBL_SIZE   InpLblSize      = SZ_SMALL;    // Zone label size
input bool            InpAlert        = false;       // Alert when price enters a zone

input group "Panel and scorecard"
input bool            InpPanelShow    = true;        // Show the panel
input ENUM_BASE_CORNER InpPanelCorner = CORNER_LEFT_LOWER; // Panel corner
input int             InpScoreBars    = 20000;       // Scorecard: chart bars of history to test
input double          InpScoreMinRisk = 0.25;        // Scorecard: smallest zone height allowed (x ATR)
input int             InpScoreMinN    = 20;          // Scorecard: tests needed before a row is coloured
input int             InpScoreRows    = 8;           // Scorecard: combos listed per group (1-20)

//--- types -----------------------------------------------------------
struct ZGap
  {
   double            lo;
   double            hi;
   int               dir;        // 0 = buy zone, 1 = sell zone
   int               kind;
   int               set;        // timeframe slot
   datetime          t;
   datetime          tForm;      // scorecard: when the zone became known
   datetime          tExp;       // scorecard: when it expires
   int               state;      // scorecard: 0 waiting, 1 active, 2 finished
   double            aux1;
   double            aux2;
  };

struct ZBox
  {
   double            lo;
   double            hi;
   int               mask;
   datetime          t;
   int               dir;
   int               kind;
   double            aux1;
   double            aux2;
  };

struct ZTip
  {
   double            price;
   double            tol;
   int               dir;        // 1 = rejection high (sell side), 0 = rejection low (buy side)
   datetime          t;
   datetime          tKnown;
   datetime          tSwept;
  };

struct ZTest
  {
   int               dir;
   int               kind;
   double            entry;
   double            risk;       // 1x = zone height in price
   int               mask;
   bool              flag;       // counted in the second view
   int               half;       // 0 older half of history, 1 newer half
   int               reached[4];
   bool              done[4];
   int               fin2;       // bar on which the 1x-stop version finished (-1 = still open)
   int               f[6];
   double            score;
  };

struct ZStat
  {
   int               mask;
   int               n[32];      // [((view*2+dir)*2+half)*4+stop]
   int               h[128];     // [(((view*2+dir)*2+half)*4+stop)*4+target]
  };

struct PRow
  {
   int               kind;
   string            label;
   int               n;
   int               h0;
   int               h1;
   int               h2;
   int               h3;
  };

//--- globals ---------------------------------------------------------
ENUM_TIMEFRAMES g_tf[4];
bool     g_show[4];
int      g_act[4];
int      g_nAct       = 0;
datetime g_t0         = 0;
int      g_ps         = 60;
double   g_dpi        = 1.0;
int      g_chartH     = 0;
double   g_lev[4]={0.5,1.0,2.0,3.0};
double   g_sm[4]={0.2,0.5,1.0,2.0};
string   g_levName[4]={"0.5x","1x","2x","3x"};
string   g_smName[4]={"0.2x","0.5x","1x","2x"};
ZStat    g_stats[];
int      g_nStats     = 0;
bool     g_scoreOk    = false;
datetime g_scoreAt    = 0;
int      g_scoreN     = -1;
int      g_scoreBars  = 0;
bool     g_collapsed  = false;
int      g_view       = 0;
int      g_side       = 0;       // 0 both, 1 buys, 2 sells
int      g_stop       = 2;
int      g_half       = 0;       // 0 all history, 1 older half, 2 newer half
int      g_panelState = -1;
int      g_panelRows  = 0;
int      g_prevZones[2];
datetime g_lastAlert[2];
int      g_liveCnt[2];
int      g_liveFlag[2];

//--- what makes this indicator this indicator ------------------------
const string PFX            = "T2RLZ_";
const string GV             = "T2RLZ_";
const string TITLE          = "T2R LEARNED ZONES";
const int    PILL_SLOT      = 4;        // where the collapsed pill sits, so several indicators do not overlap
const int    KINDS          = 1;
const bool   HAS_VIEW       = true;
const bool   VIEW_EXCL      = false;
const int    LIVE_VIEW_MODE = 2;        // 0 draw all, 1 draw only the picked view, 2 draw only flagged zones in view 2
const bool   ALWAYS_SCORE   = true;
const string VIEW0_NAME     = "All levels";
const string VIEW1_NAME     = "Model picks";
const string CTX_FLAG       = "picked by the model";
const string FOOT3          = "Trust only: Model picks + Newer half (data it never saw).";

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
int Clamp(const int v,const int lo,const int hi)
  {
   if(v<lo) return lo;
   if(v>hi) return hi;
   return v;
  }

int Px(const int v)
  {
   return (int)MathRound(v*g_dpi);
  }

color Blend(const color fg,const int transpPercent)
  {
   color bg=(color)ChartGetInteger(0,CHART_COLOR_BACKGROUND);
   double a=1.0-Clamp(transpPercent,0,100)/100.0;
   int fr=(int)(fg&0xFF),      fgG=(int)((fg>>8)&0xFF), fb=(int)((fg>>16)&0xFF);
   int br=(int)(bg&0xFF),      bgG=(int)((bg>>8)&0xFF), bb=(int)((bg>>16)&0xFF);
   int r=(int)MathRound(fr*a+br*(1.0-a));
   int g=(int)MathRound(fgG*a+bgG*(1.0-a));
   int b=(int)MathRound(fb*a+bb*(1.0-a));
   return (color)(r|(g<<8)|(b<<16));
  }

int FontSize(const ENUM_LBL_SIZE s)
  {
   switch(s)
     {
      case SZ_TINY:   return 7;
      case SZ_SMALL:  return 8;
      case SZ_NORMAL: return 10;
      default:        return 13;
     }
  }

datetime BarX(const int barsAhead)
  {
   return (datetime)((long)g_t0+(long)barsAhead*(long)g_ps);
  }

string TFName(const ENUM_TIMEFRAMES tf)
  {
   int s=PeriodSeconds(tf);
   if(s<3600)
      return IntegerToString(s/60)+"m";
   if(s<86400)
      return IntegerToString(s/3600)+"H";
   if(tf==PERIOD_D1)
      return "1D";
   if(tf==PERIOD_W1)
      return "1W";
   return "1M";
  }

string MaskNames(const int mask)
  {
   string tfs="";
   for(int k=0;k<4;k++)
      if((mask&(1<<k))!=0)
         tfs+=(tfs=="" ? "" : " + ")+TFName(g_tf[k]);
   return tfs;
  }

int Bits(const int m)
  {
   int c=0;
   for(int k=0;k<4;k++)
      if((m&(1<<k))!=0)
         c++;
   return c;
  }

void SetRect(const string name,const datetime t1,const double p1,const datetime t2,const double p2,
             const color clr,const bool fill,const bool back)
  {
   if(ObjectFind(0,name)<0)
     {
      ObjectCreate(0,name,OBJ_RECTANGLE,0,t1,p1,t2,p2);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_SOLID);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
     }
   ObjectSetInteger(0,name,OBJPROP_TIME,0,t1);
   ObjectSetDouble(0,name,OBJPROP_PRICE,0,p1);
   ObjectSetInteger(0,name,OBJPROP_TIME,1,t2);
   ObjectSetDouble(0,name,OBJPROP_PRICE,1,p2);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FILL,fill);
   ObjectSetInteger(0,name,OBJPROP_BACK,back);
  }

void SetLine(const string name,const datetime t1,const double p1,const datetime t2,const double p2,
             const color clr,const ENUM_LINE_STYLE style,const int width)
  {
   if(ObjectFind(0,name)<0)
     {
      ObjectCreate(0,name,OBJ_TREND,0,t1,p1,t2,p2);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
      ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);
      ObjectSetInteger(0,name,OBJPROP_BACK,false);
     }
   ObjectSetInteger(0,name,OBJPROP_TIME,0,t1);
   ObjectSetDouble(0,name,OBJPROP_PRICE,0,p1);
   ObjectSetInteger(0,name,OBJPROP_TIME,1,t2);
   ObjectSetDouble(0,name,OBJPROP_PRICE,1,p2);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
  }

void SetText(const string name,const datetime t,const double p,const string txt,const color clr,
             const int fontSize,const ENUM_ANCHOR_POINT anchor)
  {
   if(ObjectFind(0,name)<0)
     {
      ObjectCreate(0,name,OBJ_TEXT,0,t,p);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetString(0,name,OBJPROP_FONT,"Segoe UI");
      ObjectSetInteger(0,name,OBJPROP_BACK,false);
     }
   ObjectSetInteger(0,name,OBJPROP_TIME,0,t);
   ObjectSetDouble(0,name,OBJPROP_PRICE,0,p);
   ObjectSetString(0,name,OBJPROP_TEXT,(txt=="" ? " " : txt));
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fontSize);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,anchor);
  }

void DelObj(const string name)
  {
   if(ObjectFind(0,name)>=0)
      ObjectDelete(0,name);
  }

//--- average true range of the 14 candles before candle k
double AtrAt(const MqlRates &r[],const int k)
  {
   if(k<15)
      return 0.0;
   double sum=0.0;
   for(int i=k-14;i<k;i++)
      sum+=MathMax(r[i].high,r[i-1].close)-MathMin(r[i].low,r[i-1].close);
   return sum/14.0;
  }

void AddGap(ZGap &gaps[],int &ng,const double lo,const double hi,const int dir,const int kind,const int set,
            const datetime t,const datetime tForm,const datetime tExp,const int state,const double aux1,const double aux2)
  {
   ArrayResize(gaps,ng+1,256);
   gaps[ng].lo=lo;
   gaps[ng].hi=hi;
   gaps[ng].dir=dir;
   gaps[ng].kind=kind;
   gaps[ng].set=set;
   gaps[ng].t=t;
   gaps[ng].tForm=tForm;
   gaps[ng].tExp=tExp;
   gaps[ng].state=state;
   gaps[ng].aux1=aux1;
   gaps[ng].aux2=aux2;
   ng++;
  }

//--- merge same-direction, same-kind zones that touch or overlap; mask = timeframes involved
int AppendZones(ZGap &gaps[],const int ng,const int dir,const int kind,ZBox &z[],const int nz0)
  {
   int nz=nz0;
   double eps=_Point/2.0;
   double e[];
   int ne=0;
   for(int g=0;g<ng;g++)
      if(gaps[g].dir==dir && gaps[g].kind==kind)
        {
         ArrayResize(e,ne+2,64);
         e[ne]=gaps[g].lo;
         e[ne+1]=gaps[g].hi;
         ne+=2;
        }
   if(ne<2)
      return nz;
   ArraySort(e);
   for(int i=0;i<ne-1;i++)
     {
      double a=e[i];
      double b=e[i+1];
      if(b-a<=eps)
         continue;
      double mid=(a+b)/2.0;
      int mask=0;
      datetime t=0;
      double x1=0.0,x2=0.0;
      for(int g=0;g<ng;g++)
        {
         if(gaps[g].dir!=dir || gaps[g].kind!=kind || gaps[g].lo>=mid || gaps[g].hi<=mid)
            continue;
         mask|=(1<<gaps[g].set);
         if(gaps[g].t>=t)
           {
            t=gaps[g].t;
            x1=gaps[g].aux1;
            x2=gaps[g].aux2;
           }
        }
      if(mask==0)
         continue;
      if(nz>nz0 && MathAbs(z[nz-1].hi-a)<=eps)
        {
         z[nz-1].hi=b;
         z[nz-1].mask|=mask;
         if(t>z[nz-1].t)
           {
            z[nz-1].t=t;
            z[nz-1].aux1=x1;
            z[nz-1].aux2=x2;
           }
        }
      else
        {
         ArrayResize(z,nz+1,32);
         z[nz].lo=a;
         z[nz].hi=b;
         z[nz].mask=mask;
         z[nz].t=t;
         z[nz].dir=dir;
         z[nz].kind=kind;
         z[nz].aux1=x1;
         z[nz].aux2=x2;
         nz++;
        }
     }
   return nz;
  }

//+------------------------------------------------------------------+
//| Self-taught zones.                                               |
//| Candidates: every swing high / low on the scanned timeframes.    |
//| For each one, six clues are recorded the moment price returns:   |
//|  0 where the level sits in the recent range                      |
//|  1 how big the rejection wick at the swing was                   |
//|  2 how old the level is                                          |
//|  3 how fast price is arriving                                    |
//|  4 time of day                                                   |
//|  5 with or against the trend                                     |
//| The model learns, from the OLDER half of history only, which     |
//| clue values came before winners (1x target before 1x stop), and  |
//| scores every level with them. The NEWER half is data it has      |
//| never seen, so "Model picks + Newer half" is the honest test.    |
//+------------------------------------------------------------------+
double   g_lift[18];
int      g_trainN     = 0;
double   g_lastScore  = 0.0;
//--- nearest learned zone per side, for the card and the plan
bool     g_pkOk[2];
double   g_pkLo[2];
double   g_pkHi[2];
double   g_pkSc[2];
double   g_pkD[2];
int      g_pkMask[2];
int      g_trainW     = 0;
bool     g_modelOk    = false;
MqlRates g_lcb[];
int      g_ln         = 0;
double   g_latr       = 0.0;

int FOff(const int q)
  {
   switch(q)
     {
      case 0: return 0;
      case 1: return 3;
      case 2: return 6;
      case 3: return 9;
      case 4: return 12;
      default: return 16;
     }
  }

void Features(const int dir,const double lo,const double hi,const double wick,const datetime tPiv,const double tfsec,
              const MqlRates &cb[],const int b,const double atr,int &f[])
  {
   for(int q=0;q<6;q++)
      f[q]=0;
   if(b<2)
      return;
//--- 0: position in the recent range (2 = at the extreme a fade would want)
   int from=MathMax(b-MathMax(InpRangeBars,20),0);
   double hh=cb[from].high;
   double ll=cb[from].low;
   for(int i=from+1;i<b;i++)
     {
      if(cb[i].high>hh)
         hh=cb[i].high;
      if(cb[i].low<ll)
         ll=cb[i].low;
     }
   double pos=0.5;
   if(hh>ll)
      pos=(((dir==1) ? hi : lo)-ll)/(hh-ll);
   if(pos<0.0)
      pos=0.0;
   if(pos>1.0)
      pos=1.0;
   if(dir==0)
      pos=1.0-pos;
   f[0]=(pos<0.34) ? 0 : ((pos<0.67) ? 1 : 2);
//--- 1: rejection wick at the swing
   f[1]=(wick<0.25) ? 0 : ((wick<0.5) ? 1 : 2);
//--- 2: age of the level, in candles of its own timeframe
   double age=(tfsec>0.0) ? (double)((long)cb[b].time-(long)tPiv)/tfsec : 0.0;
   f[2]=(age<10.0) ? 0 : ((age<30.0) ? 1 : 2);
//--- 3: speed of the approach over the last 10 chart bars
   double sp=0.0;
   if(b>=10 && atr>0.0)
      sp=((dir==1) ? (cb[b].open-cb[b-10].open) : (cb[b-10].open-cb[b].open))/atr;
   f[3]=(sp<1.0) ? 0 : ((sp<3.0) ? 1 : 2);
//--- 4: time of day, in six-hour blocks
   MqlDateTime dt;
   TimeToStruct(cb[b].time,dt);
   f[4]=Clamp(dt.hour/6,0,3);
//--- 5: with the trend (1) or against it (0)
   int m=MathMin(MathMax(InpTrendBars,10),b);
   double sum=0.0;
   for(int i=b-m;i<b;i++)
      sum+=cb[i].close;
   double sma=sum/m;
   f[5]=((dir==1 && cb[b].open<sma) || (dir==0 && cb[b].open>sma)) ? 1 : 0;
  }

double ModelScore(const int &f[])
  {
   double s=0.0;
   for(int q=0;q<6;q++)
      s+=g_lift[FOff(q)+f[q]];
   return s;
  }

bool IsPivot(const MqlRates &r[],const int i,const int dir)
  {
   if(dir==1)
      return (r[i].high>r[i-1].high && r[i].high>r[i-2].high && r[i].high>=r[i+1].high && r[i].high>=r[i+2].high);
   return (r[i].low<r[i-1].low && r[i].low<r[i-2].low && r[i].low<=r[i+1].low && r[i].low<=r[i+2].low);
  }

double WickShare(const MqlRates &r[],const int i,const int dir)
  {
   double rng=r[i].high-r[i].low;
   if(rng<=0.0)
      return 0.0;
   if(dir==1)
      return (r[i].high-MathMax(r[i].open,r[i].close))/rng;
   return (MathMin(r[i].open,r[i].close)-r[i].low)/rng;
  }

void PrepLive(const double price)
  {
   g_ln=CopyRates(_Symbol,_Period,0,MathMax(InpRangeBars,MathMax(InpTrendBars,20))+30,g_lcb);
   g_latr=(g_ln>20) ? AtrAt(g_lcb,g_ln-1) : 0.0;
  }

void GenLive(ZGap &gaps[],int &ng,const double price)
  {
   int look=MathMax(InpLookback,5);
   double eps=_Point/2.0;
   for(int d=0;d<g_nAct;d++)
     {
      int k=g_act[d];
      double tfsec=(double)PeriodSeconds(g_tf[k]);
      MqlRates r[];
      int got=CopyRates(_Symbol,g_tf[k],0,look+25,r);
      if(got<25)
         continue;
      for(int i=MathMax(17,got-1-look);i<=got-4;i++)
         for(int dir=0;dir<2;dir++)
           {
            if(!IsPivot(r,i,dir))
               continue;
            double z=MathMax(InpZoneATR,0.02)*AtrAt(r,i);
            if(z<=eps)
               continue;
            double lo=(dir==1) ? r[i].high-z : r[i].low;
            double hi=(dir==1) ? r[i].high : r[i].low+z;
            //--- still fresh? no closed candle since confirmation came back to it or closed through it
            bool dead=false;
            for(int j=i+3;j<got && !dead;j++)
              {
               bool closed=(j<=got-2);
               if(dir==1)
                 {
                  if(r[j].close>hi || (closed && r[j].high>=lo))
                     dead=true;
                 }
               else
                 {
                  if(r[j].close<lo || (closed && r[j].low<=hi))
                     dead=true;
                 }
              }
            if(!dead)
               AddGap(gaps,ng,lo,hi,dir,0,k,r[i].time,0,0,1,WickShare(r,i,dir),tfsec);
           }
     }
  }

bool LiveInfo(ZBox &z,const double price,string &note,double &lvl)
  {
   if(g_ln<30 || !g_modelOk)
      return false;
   int f[6];
   Features(z.dir,z.lo,z.hi,z.aux1,z.t,z.aux2,g_lcb,g_ln-1,g_latr,f);
   double s=ModelScore(f);
   g_lastScore=s;
   note="   score "+((s>=0.0) ? "+" : "")+DoubleToString(s,2);
   return (s>=InpPickScore);
  }

string ZoneName(const int dir,const int kind)
  {
   return (dir==0) ? "BUY LEVEL" : "SELL LEVEL";
  }

void PrepHistory(const datetime winStart,const datetime now)
  {
  }

void GenHistory(const datetime winStart,const datetime now,ZGap &gaps[],int &ng)
  {
   int look=MathMax(InpLookback,5);
   double eps=_Point/2.0;
   for(int d=0;d<g_nAct;d++)
     {
      int k=g_act[d];
      long tfs=PeriodSeconds(g_tf[k]);
      MqlRates r[];
      int got=CopyRates(_Symbol,g_tf[k],(datetime)((long)winStart-25*tfs),now,r);
      if(got<25)
         continue;
      for(int i=17;i<=got-4;i++)
        {
         if(r[i+3].time<winStart)
            continue;
         for(int dir=0;dir<2;dir++)
           {
            if(!IsPivot(r,i,dir))
               continue;
            double z=MathMax(InpZoneATR,0.02)*AtrAt(r,i);
            if(z<=eps)
               continue;
            double lo=(dir==1) ? r[i].high-z : r[i].low;
            double hi=(dir==1) ? r[i].high : r[i].low+z;
            AddGap(gaps,ng,lo,hi,dir,0,k,r[i].time,r[i+3].time,(datetime)((long)r[i+3].time+look*tfs),0,WickShare(r,i,dir),(double)tfs);
           }
        }
     }
  }

void TouchInfo(ZTest &t,ZBox &z,const MqlRates &cb[],const int b,const double atr,const datetime tb)
  {
   Features(z.dir,z.lo,z.hi,z.aux1,z.t,z.aux2,cb,b,atr,t.f);
  }

//--- learn from the older half only, then score every trade
void PostProcess(ZTest &outs[],const int nouts,const int midBar)
  {
   int w[18];
   int n[18];
   for(int q=0;q<18;q++)
     {
      w[q]=0;
      n[q]=0;
      g_lift[q]=0.0;
     }
   int W=0;
   int N=0;
   for(int o=0;o<nouts;o++)
     {
      if(outs[o].half!=0 || !outs[o].done[2] || outs[o].fin2<0 || outs[o].fin2>=midBar)
         continue;
      bool win=(outs[o].reached[2]>=2);
      N++;
      if(win)
         W++;
      for(int q=0;q<6;q++)
        {
         int idx=FOff(q)+outs[o].f[q];
         n[idx]++;
         if(win)
            w[idx]++;
        }
     }
   g_trainN=N;
   g_trainW=W;
   g_modelOk=(N>=50);
   if(g_modelOk)
     {
      double base=MathLog((W+1.0)/(N-W+1.0));
      for(int q=0;q<18;q++)
         if(n[q]>=MathMax(InpModelMinN,1))
            g_lift[q]=MathLog((w[q]+1.0)/(n[q]-w[q]+1.0))-base;
     }
   for(int o=0;o<nouts;o++)
     {
      outs[o].score=ModelScore(outs[o].f);
      outs[o].flag=(g_modelOk && outs[o].score>=InpPickScore);
     }
  }

string StatusLine()
  {
   if(!g_scoreOk)
      return "Model: loading history";
   if(!g_modelOk)
      return "Model: too few older trades to learn from yet";
   return "Model: learned from "+IntegerToString(g_trainN)+" older trades, base win "+
          IntegerToString((int)MathRound(100.0*g_trainW/MathMax(g_trainN,1)))+"%";
  }


//+------------------------------------------------------------------+
//| Live zones                                                       |
//+------------------------------------------------------------------+
void DrawZoneSide(const int dir,ZBox &zb[],const int nzb,const double price)
  {
   string p=PFX+"Z"+IntegerToString(dir)+"_";
   color solid=(dir==0) ? InpBuyColor : InpSellColor;
   datetime xr=BarX(4);
   int fs=FontSize(InpLblSize);
   int maxZ=MathMax(InpZoneMax,1);
   int cap=MathMax(nzb,1);
   bool used[];
   bool flg[];
   string note[];
   double lvl[];
   ArrayResize(used,cap);
   ArrayResize(flg,cap);
   ArrayResize(note,cap);
   ArrayResize(lvl,cap);
   g_liveCnt[dir]=0;
   g_liveFlag[dir]=0;
   for(int z=0;z<nzb;z++)
     {
      used[z]=true;
      flg[z]=false;
      note[z]="";
      lvl[z]=0.0;
      if(zb[z].dir!=dir)
         continue;
      string nn="";
      double lv=0.0;
      flg[z]=LiveInfo(zb[z],price,nn,lv);
      note[z]=nn;
      lvl[z]=lv;
      g_liveCnt[dir]++;
      if(flg[z])
         g_liveFlag[dir]++;
      if(!InpShowOthers && !flg[z])
         continue;
      if(LIVE_VIEW_MODE==1 && flg[z]!=(g_view==1))
         continue;
      if(LIVE_VIEW_MODE==2 && g_view==1 && !flg[z])
         continue;
      used[z]=false;
     }

   int drawn=0;
   while(drawn<maxZ)
     {
      int best=-1;
      double bestD=0.0;
      for(int z=0;z<nzb;z++)
        {
         if(used[z])
            continue;
         double d=0.0;
         if(price>zb[z].hi)
            d=price-zb[z].hi;
         else
            if(price<zb[z].lo)
               d=zb[z].lo-price;
         if(best<0 || d<bestD)
           {
            best=z;
            bestD=d;
           }
        }
      if(best<0)
         break;
      used[best]=true;

      double lo=zb[best].lo;
      double hi=zb[best].hi;
      double mid=(lo+hi)/2.0;
      bool strong=(flg[best] && LIVE_VIEW_MODE!=1);
      string tfs=MaskNames(zb[best].mask);
      string txt=(flg[best] ? Ch(0x2B50)+" LEARNED " : "")+ZoneName(dir,zb[best].kind)+"   "+tfs+note[best]+" ";
      if(flg[best])
        {
         double dd=(price>hi) ? price-hi : (price<lo) ? lo-price : 0.0;
         if(!g_pkOk[dir] || dd<g_pkD[dir])
           {
            g_pkOk[dir]=true;
            g_pkLo[dir]=lo;
            g_pkHi[dir]=hi;
            g_pkD[dir]=dd;
            g_pkMask[dir]=zb[best].mask;
            string sc=note[best];
            StringReplace(sc,"score","");
            StringTrimLeft(sc);
            g_pkSc[dir]=StringToDouble(sc);
           }
        }
      string id=StringFormat("%02d",drawn);
      datetime xl=zb[best].t;
      if(xl>=xr)
         xl=(datetime)((long)xr-(long)g_ps*10);

      SetRect(p+id+"B",xl,hi,xr,lo,Blend(solid,strong ? MathMax(InpZoneTransp-12,0) : MathMin(InpZoneTransp+14,95)),true,true);
      SetRect(p+id+"E",xl,hi,xr,lo,Blend(solid,strong ? 25 : 70),false,true);
      if(InpMidline)
         SetLine(p+id+"M",xl,mid,xr,mid,Blend(solid,30),STYLE_DOT,1);
      else
         DelObj(p+id+"M");
      if(lvl[best]>0.0)
         SetLine(p+id+"S",xl,lvl[best],xr,lvl[best],solid,STYLE_DASH,1);
      else
         DelObj(p+id+"S");
      if(dir==0)
         SetText(p+id+"T",xr,lo,txt,solid,fs,ANCHOR_RIGHT_UPPER);
      else
         SetText(p+id+"T",xr,hi,txt,solid,fs,ANCHOR_RIGHT_LOWER);

      if(InpAlert && price>=lo && price<=hi && g_lastAlert[dir]!=zb[best].t)
        {
         g_lastAlert[dir]=zb[best].t;
         Alert(_Symbol," ",ZoneName(dir,zb[best].kind)," touched (",tfs,")  ",
               DoubleToString(lo,_Digits)," - ",DoubleToString(hi,_Digits));
        }
      drawn++;
     }
   for(int i=drawn;i<g_prevZones[dir];i++)
      ObjectsDeleteAll(0,p+StringFormat("%02d",i));
   g_prevZones[dir]=drawn;
  }

void DrawZones(const double price)
  {
   PrepLive(price);
   ZGap gaps[];
   int ng=0;
   GenLive(gaps,ng,price);
   ZBox zb[];
   int nzb=0;
   for(int kd=0;kd<KINDS;kd++)
     {
      nzb=AppendZones(gaps,ng,0,kd,zb,nzb);
      nzb=AppendZones(gaps,ng,1,kd,zb,nzb);
     }
   for(int d=0;d<2;d++)
      g_pkOk[d]=false;
   int sd=SpikeSide();
   bool noBuy=(g_side==2) || (InpSpikeOnly && sd==2);
   bool noSell=(g_side==1) || (InpSpikeOnly && sd==1);
   DrawZoneSide(0,zb,noBuy ? 0 : nzb,price);
   DrawZoneSide(1,zb,noSell ? 0 : nzb,price);
   DrawPlan(price);
   DrawCard(price);
  }

string Ch(const int code)
  {
   return ShortToString((ushort)code);
  }

//--- Boom spikes up: buys are with the spike (1). Crash spikes down: sells (2). Other markets: 0
int SpikeSide()
  {
   if(StringFind(_Symbol,"Boom ")==0)
      return 1;
   if(StringFind(_Symbol,"Crash ")==0)
      return 2;
   return 0;
  }

//--- the nearest learned zone (either side), -1 = none
int PlanDir()
  {
   int d=-1;
   for(int k=0;k<2;k++)
      if(g_pkOk[k] && (d<0 || g_pkD[k]<g_pkD[d]))
         d=k;
   return d;
  }

void PlanLevels(const int d,double &ent,double &sl,double &tp,double &unit)
  {
   double h=g_pkHi[d]-g_pkLo[d];
   unit=MathMax(h,MathMax(InpWideATR,0.0)*g_latr);
   ent=(d==0) ? g_pkHi[d] : g_pkLo[d];
   sl=(d==0) ? ent-unit : ent+unit;
   tp=(d==0) ? ent+InpTargetR*unit : ent-InpTargetR*unit;
  }

void DrawPlan(const double price)
  {
   string p=PFX+"PL_";
   int d=PlanDir();
   if(!InpPlan || d<0 || g_latr<=0.0)
     {
      ObjectsDeleteAll(0,p);
      return;
     }
   double ent,sl,tp,unit;
   PlanLevels(d,ent,sl,tp,unit);
   datetime x1=(datetime)((long)BarX(4)-(long)g_ps*30);
   datetime x2=BarX(4);
   int fs=FontSize(InpLblSize);
   SetLine(p+"E",x1,ent,x2,ent,C'240,200,90',STYLE_SOLID,2);
   SetLine(p+"S",x1,sl,x2,sl,InpSellColor,STYLE_DASH,1);
   SetLine(p+"T",x1,tp,x2,tp,InpBuyColor,STYLE_DASH,1);
   SetText(p+"Et",x1,ent,"ENTRY "+DoubleToString(ent,_Digits),C'240,200,90',fs,ANCHOR_LEFT_LOWER);
   SetText(p+"St",x1,sl,"STOP -1R "+DoubleToString(sl,_Digits),InpSellColor,fs,ANCHOR_LEFT_LOWER);
   SetText(p+"Tt",x1,tp,"TARGET +"+DoubleToString(InpTargetR,0)+"R "+DoubleToString(tp,_Digits),InpBuyColor,fs,ANCHOR_LEFT_LOWER);
  }

//--- card building blocks (all placed from the chart's top-left corner, in pixels)
void CRect(const string name,const int x,const int y,const int w,const int h,const color bg,const color border)
  {
   if(ObjectFind(0,name)<0)
     {
      ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
     }
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,MathMax(w,1));
   ObjectSetInteger(0,name,OBJPROP_YSIZE,MathMax(h,1));
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_COLOR,border);
  }

void CText(const string name,const int x,const int y,const string txt,const color c,const int fsz,const bool bold,const bool right)
  {
   if(ObjectFind(0,name)<0)
     {
      ObjectCreate(0,name,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
     }
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,right ? ANCHOR_RIGHT_UPPER : ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetString(0,name,OBJPROP_TEXT,txt);
   ObjectSetString(0,name,OBJPROP_FONT,bold ? "Segoe UI Semibold" : "Segoe UI");
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fsz);
   ObjectSetInteger(0,name,OBJPROP_COLOR,c);
  }

void CButton(const string name,const int x,const int y,const int w,const int h,const string txt,const color bg,const color fg)
  {
   if(ObjectFind(0,name)<0)
     {
      ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetString(0,name,OBJPROP_FONT,"Segoe UI Semibold");
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
     }
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetString(0,name,OBJPROP_TEXT,txt);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_COLOR,fg);
   ObjectSetInteger(0,name,OBJPROP_STATE,false);
  }

bool g_cardMin=false;
string g_cardSig="";

void DrawCard(const double price)
  {
   string p=PFX+"CD_";
   if(!InpCard)
     {
      ObjectsDeleteAll(0,p);
      return;
     }
   color cBg=C'18,20,26', cHead=C'28,31,40', cLine=C'48,52,64', cTxt=C'222,225,232', cDim=C'128,133,146',
         cGold=C'232,190,92', cTrack=C'40,44,56';
   int cw=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0);
   int ch=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   int w=Px(268);
   int x=cw-w-Px(14);
   int d=PlanDir();
   int sd=SpikeSide();
   //--- collapsed: a small pill
   if(g_cardMin)
     {
      string sig="min";
      if(g_cardSig!=sig)
        {
         ObjectsDeleteAll(0,p);
         g_cardSig=sig;
        }
      int pw=Px(170), ph=Px(24);
      int px=cw-pw-Px(14), py=(InpCardBottom ? ch-ph-Px(14) : Px(26));
      CRect(p+"bg",px,py,pw,ph,cHead,cLine);
      CText(p+"t",px+Px(10),py+Px(5),Ch(0x2B50)+" LEARNED ZONE"+(d>=0 ? (d==0 ? "  BUY" : "  SELL") : ""),cGold,8,true,false);
      CButton(p+"btn",px+pw-Px(26),py+Px(3),Px(22),Px(18),"+",cLine,cTxt);
      return;
     }
   int h=Px(d>=0 ? 236 : 128);
   int y=InpCardBottom ? ch-h-Px(14) : Px(26);
   string sig="full"+IntegerToString(d>=0 ? 1 : 0);
   if(g_cardSig!=sig)
     {
      ObjectsDeleteAll(0,p);
      g_cardSig=sig;
     }
   color acc=(d==0) ? InpBuyColor : (d==1) ? InpSellColor : cGold;
   //--- frame, accent bar, header
   CRect(p+"bg",x,y,w,h,cBg,cLine);
   CRect(p+"acc",x,y,Px(3),h,acc,acc);
   CRect(p+"hd",x+Px(3),y,w-Px(3),Px(30),cHead,cHead);
   CText(p+"ttl",x+Px(14),y+Px(8),Ch(0x2B50)+"  T2R LEARNED ZONE",cGold,9,true,false);
   CText(p+"sym",x+w-Px(34),y+Px(9),_Symbol,cDim,7,false,true);
   CButton(p+"btn",x+w-Px(28),y+Px(6),Px(20),Px(18),"-",cLine,cTxt);
   int lx=x+Px(14), rx=x+w-Px(12), yy=y+Px(40);
   if(!g_modelOk || d<0)
     {
      CText(p+"m1",lx,yy,!g_modelOk ? "Model still learning this market" : "No learned zone in view",cTxt,9,true,false);
      CText(p+"m2",lx,yy+Px(20),!g_modelOk ? "Give it a few seconds" : "The card wakes up when the model picks one",cDim,8,false,false);
      CText(p+"m3",lx,yy+Px(48),StatusLine(),cDim,7,false,false);
      return;
     }
   double ent,sl,tp,unit;
   PlanLevels(d,ent,sl,tp,unit);
   bool isWith=(sd==1 && d==0) || (sd==2 && d==1);
   //--- row 1: side badge, timeframes, score pill
   CRect(p+"sb",lx,yy,Px(46),Px(22),acc,acc);
   CText(p+"st",lx+Px(23),yy+Px(4),(d==0) ? "BUY" : "SELL",C'255,255,255',9,true,false);
   ObjectSetInteger(0,p+"st",OBJPROP_ANCHOR,ANCHOR_UPPER);
   CText(p+"tf",lx+Px(56),yy+Px(4),MaskNames(g_pkMask[d]),cTxt,9,true,false);
   CRect(p+"sc",rx-Px(64),yy,Px(64),Px(22),cTrack,cLine);
   CText(p+"scv",rx-Px(32),yy+Px(4),"score "+((g_pkSc[d]>=0) ? "+" : "")+DoubleToString(g_pkSc[d],2),cGold,8,true,false);
   ObjectSetInteger(0,p+"scv",OBJPROP_ANCHOR,ANCHOR_UPPER);
   //--- row 2: spike side
   yy+=Px(32);
   string sp=(sd==0) ? "Not a spike market" : (isWith ? Ch(0x2714)+"  With the spike  "+Ch(0xB7)+"  proven T2R side" : Ch(0x26A0)+"  Against the spike  "+Ch(0xB7)+"  not the T2R setup");
   CText(p+"sp",lx,yy,sp,(sd==0) ? cDim : (isWith ? InpBuyColor : C'240,170,70'),8,true,false);
   //--- row 3: status + distance bar
   yy+=Px(24);
   bool inz=(price>=g_pkLo[d] && price<=g_pkHi[d]);
   double away=(g_latr>0.0) ? g_pkD[d]/g_latr : 0.0;
   CText(p+"ss",lx,yy,inz ? Ch(0x25CF)+"  PRICE IN THE ZONE" : "WAITING FOR PRICE",inz ? cGold : cTxt,8,true,false);
   CText(p+"sd",rx,yy,inz ? "entry now" : DoubleToString(away,1)+" ATR away",cDim,8,false,true);
   int bw=w-Px(26);
   double fill=inz ? 1.0 : MathMax(0.04,1.0-MathMin(away/4.0,1.0));
   CRect(p+"bt",lx,yy+Px(19),bw,Px(5),cTrack,cTrack);
   CRect(p+"bf",lx,yy+Px(19),(int)(bw*fill),Px(5),inz ? cGold : acc,inz ? cGold : acc);
   //--- row 4: the plan, three columns
   yy+=Px(36);
   CRect(p+"pl",lx,yy-Px(6),bw,Px(1),cLine,cLine);
   int col=bw/3;
   string lb[3];
   string vl[3];
   color vc[3];
   lb[0]="ENTRY";
   lb[1]="STOP  -1R";
   lb[2]="TARGET  +"+DoubleToString(InpTargetR,0)+"R";
   vl[0]=DoubleToString(ent,_Digits);
   vl[1]=DoubleToString(sl,_Digits);
   vl[2]=DoubleToString(tp,_Digits);
   vc[0]=cGold;
   vc[1]=InpSellColor;
   vc[2]=InpBuyColor;
   for(int i=0;i<3;i++)
     {
      CText(p+"pl"+IntegerToString(i),lx+i*col,yy,lb[i],cDim,7,false,false);
      CText(p+"pv"+IntegerToString(i),lx+i*col,yy+Px(14),vl[i],vc[i],8,true,false);
     }
   //--- footer
   yy+=Px(42);
   CRect(p+"fl",lx,yy-Px(6),bw,Px(1),cLine,cLine);
   CText(p+"f1",lx,yy,"Wide stop  "+Ch(0xB7)+"  1:"+DoubleToString(InpTargetR,0)+"  "+Ch(0xB7)+"  risk 0.25%",cDim,7,false,false);
   CText(p+"f2",lx,yy+Px(14),StatusLine(),cDim,7,false,false);
  }

//+------------------------------------------------------------------+
//| Scorecard: replay history bar by bar. The first time price       |
//| reaches a zone is a trade: entry at the near edge, and every     |
//| stop size is tried against every target. If one bar could have   |
//| hit stop or target first, the stop wins.                         |
//+------------------------------------------------------------------+
void AddStat(const int mask,const int dir,const bool flag,const int half,const int si,const int reached)
  {
   int idx=-1;
   for(int i=0;i<g_nStats;i++)
      if(g_stats[i].mask==mask)
        {
         idx=i;
         break;
        }
   if(idx<0)
     {
      ArrayResize(g_stats,g_nStats+1,16);
      idx=g_nStats;
      g_stats[idx].mask=mask;
      for(int q=0;q<32;q++)
         g_stats[idx].n[q]=0;
      for(int q=0;q<128;q++)
         g_stats[idx].h[q]=0;
      g_nStats++;
     }
   int d=(dir==1) ? 1 : 0;
   int hf=(half==1) ? 1 : 0;
   for(int v=0;v<2;v++)
     {
      if(VIEW_EXCL)
        {
         if((v==1)!=flag)
            continue;
        }
      else
         if(v==1 && !flag)
            continue;
      int base=((v*2+d)*2+hf)*4+si;
      g_stats[idx].n[base]++;
      for(int l=0;l<reached && l<4;l++)
         g_stats[idx].h[base*4+l]++;
     }
  }

//--- read stats for the direction and history half picked on the panel
int StatNs(const int i,const int view,const int si)
  {
   int v=0;
   for(int d=0;d<2;d++)
     {
      if((d==0 && g_side==2) || (d==1 && g_side==1))
         continue;
      for(int hf=0;hf<2;hf++)
        {
         if((hf==0 && g_half==2) || (hf==1 && g_half==1))
            continue;
         v+=g_stats[i].n[((view*2+d)*2+hf)*4+si];
        }
     }
   return v;
  }

int StatHs(const int i,const int view,const int si,const int lev)
  {
   int v=0;
   for(int d=0;d<2;d++)
     {
      if((d==0 && g_side==2) || (d==1 && g_side==1))
         continue;
      for(int hf=0;hf<2;hf++)
        {
         if((hf==0 && g_half==2) || (hf==1 && g_half==1))
            continue;
         v+=g_stats[i].h[(((view*2+d)*2+hf)*4+si)*4+lev];
        }
     }
   return v;
  }

int StatN(const int i,const int view)
  {
   return StatNs(i,view,g_stop);
  }

int StatH(const int i,const int view,const int lev)
  {
   return StatHs(i,view,g_stop,lev);
  }

void RunScore()
  {
   g_nStats=0;
   ArrayResize(g_stats,0);
   g_scoreOk=false;
   g_scoreBars=0;
   if(g_nAct==0)
      return;
   int want=MathMin(MathMax(InpScoreBars,200),Bars(_Symbol,_Period)-1);
   if(want<200)
      return;
   MqlRates cb[];
   int nb=CopyRates(_Symbol,_Period,1,want,cb);        // closed chart bars only
   if(nb<200)
      return;
   datetime winStart=cb[0].time;
   datetime now=TimeCurrent();
   double eps=_Point/2.0;

   PrepHistory(winStart,now);
   ZGap gaps[];
   int ng=0;
   GenHistory(winStart,now,gaps,ng);

   ZTest tests[];
   int ntests=0;
   ZTest outs[];
   int nouts=0;
   ZGap ag[];
   int aidx[];
   int na=0;
   ZBox zb[];
   int nzb=0;
   bool dirty=true;
   int warm=20;
   int midBar=warm+(nb-warm)/2;

   for(int b=warm;b<nb;b++)
     {
      datetime tb=cb[b].time;

      //--- 1. zones that became known / expired
      for(int g=0;g<ng;g++)
        {
         if(gaps[g].state==0 && gaps[g].tForm<=tb)
           {
            gaps[g].state=1;
            dirty=true;
           }
         if(gaps[g].state==1 && gaps[g].tExp<=tb)
           {
            gaps[g].state=2;
            dirty=true;
           }
        }

      //--- 2. zones as they stood when this bar opened
      if(dirty)
        {
         na=0;
         for(int g=0;g<ng;g++)
            if(gaps[g].state==1)
              {
               ArrayResize(ag,na+1,128);
               ArrayResize(aidx,na+1,128);
               ag[na]=gaps[g];
               aidx[na]=g;
               na++;
              }
         nzb=0;
         for(int kd=0;kd<KINDS;kd++)
           {
            nzb=AppendZones(ag,na,0,kd,zb,nzb);
            nzb=AppendZones(ag,na,1,kd,zb,nzb);
           }
         dirty=false;
        }

      //--- 3. open trades, once per stop size: stop first, then targets
      for(int t=ntests-1;t>=0;t--)
        {
         bool allDone=true;
         for(int si=0;si<4;si++)
           {
            if(tests[t].done[si])
               continue;
            bool fin=false;
            if(tests[t].dir==0)
              {
               if(cb[b].low<=tests[t].entry-g_sm[si]*tests[t].risk)
                  fin=true;
               else
                 {
                  while(tests[t].reached[si]<4 && cb[b].high>=tests[t].entry+g_lev[tests[t].reached[si]]*tests[t].risk)
                     tests[t].reached[si]++;
                  if(tests[t].reached[si]>=4)
                     fin=true;
                 }
              }
            else
              {
               if(cb[b].high>=tests[t].entry+g_sm[si]*tests[t].risk)
                  fin=true;
               else
                 {
                  while(tests[t].reached[si]<4 && cb[b].low<=tests[t].entry-g_lev[tests[t].reached[si]]*tests[t].risk)
                     tests[t].reached[si]++;
                  if(tests[t].reached[si]>=4)
                     fin=true;
                 }
              }
            if(fin)
              {
               tests[t].done[si]=true;
               if(si==2)
                  tests[t].fin2=b;
              }
            else
               allDone=false;
           }
         if(allDone)
           {
            ArrayResize(outs,nouts+1,512);
            outs[nouts]=tests[t];
            nouts++;
            tests[t]=tests[ntests-1];
            ntests--;
           }
        }

      //--- 4. first touch of a zone = new trade; the zone is then spent
      double atr=-1.0;
      for(int z=0;z<nzb;z++)
        {
         int dir=zb[z].dir;
         bool touch=(dir==0) ? (cb[b].low<=zb[z].hi) : (cb[b].high>=zb[z].lo);
         if(!touch)
            continue;
         for(int a=0;a<na;a++)
           {
            if(ag[a].dir!=dir || ag[a].kind!=zb[z].kind || ag[a].lo>=zb[z].hi || ag[a].hi<=zb[z].lo)
               continue;
            gaps[aidx[a]].state=2;
           }
         dirty=true;
         if(atr<0.0)
           {
            double sum=0.0;
            for(int i=b-14;i<b;i++)
               sum+=MathMax(cb[i].high,cb[i-1].close)-MathMin(cb[i].low,cb[i-1].close);
            atr=sum/14.0;
           }
         double minRisk=MathMax(InpScoreMinRisk,0.0)*atr;
         ZTest nt1;
         nt1.dir=dir;
         nt1.kind=zb[z].kind;
         nt1.mask=zb[z].mask;
         nt1.flag=false;
         nt1.half=(b<midBar) ? 0 : 1;
         nt1.fin2=-1;
         nt1.score=0.0;
         for(int q=0;q<6;q++)
            nt1.f[q]=0;
         bool gone=false;
         nt1.risk=MathMax(zb[z].hi-zb[z].lo,minRisk);
         if(dir==0)
           {
            nt1.entry=MathMin(zb[z].hi,cb[b].open);
            gone=(nt1.risk<=eps || nt1.entry<=zb[z].lo);
           }
         else
           {
            nt1.entry=MathMax(zb[z].lo,cb[b].open);
            gone=(nt1.risk<=eps || nt1.entry>=zb[z].hi);
           }
         TouchInfo(nt1,zb[z],cb,b,atr,tb);
         bool anyOpen=false;
         for(int si=0;si<4;si++)
           {
            nt1.reached[si]=0;
            bool lost=gone;
            if(!lost)
              {
               if(dir==0)
                  lost=(cb[b].low<=nt1.entry-g_sm[si]*nt1.risk);
               else
                  lost=(cb[b].high>=nt1.entry+g_sm[si]*nt1.risk);
              }
            nt1.done[si]=lost;
            if(lost)
              {
               if(si==2)
                  nt1.fin2=b;
              }
            else
               anyOpen=true;
           }
         if(anyOpen)
           {
            ArrayResize(tests,ntests+1,64);
            tests[ntests]=nt1;
            ntests++;
           }
         else
           {
            ArrayResize(outs,nouts+1,512);
            outs[nouts]=nt1;
            nouts++;
           }
        }
     }
//--- trades still open at the end: keep whatever already finished
   for(int t=0;t<ntests;t++)
     {
      ArrayResize(outs,nouts+1,512);
      outs[nouts]=tests[t];
      nouts++;
     }
   PostProcess(outs,nouts,midBar);
   for(int o=0;o<nouts;o++)
      for(int si=0;si<4;si++)
         if(outs[o].done[si])
            AddStat(outs[o].mask,outs[o].dir,outs[o].flag,outs[o].half,si,outs[o].reached[si]);

   g_scoreBars=nb-warm;
   g_scoreOk=true;
  }

//+------------------------------------------------------------------+
//| Panel                                                            |
//+------------------------------------------------------------------+
void PanelPos(const string name,const int x,const int y,const int pw,const int ph)
  {
   int m=Px(12);
   bool right=(InpPanelCorner==CORNER_RIGHT_UPPER || InpPanelCorner==CORNER_RIGHT_LOWER);
   bool lower=(InpPanelCorner==CORNER_LEFT_LOWER || InpPanelCorner==CORNER_RIGHT_LOWER);
   int yd=lower ? m+ph-y : m+y;
//--- taller than the chart: pin the TOP of the panel so the header and Hide button stay reachable
   if(lower && !g_collapsed && g_chartH>0 && m+ph>g_chartH-m)
      yd=g_chartH-m-y;
//--- collapsed pills of the different indicators stack instead of covering each other
   if(g_collapsed)
      yd+=PILL_SLOT*Px(28);
   ObjectSetInteger(0,name,OBJPROP_CORNER,InpPanelCorner);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,right ? m+pw-x : m+x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,yd);
  }

void PanelRect(const string name,const int x,const int y,const int w,const int h,const int pw,const int ph,
               const color bg,const color border)
  {
   if(ObjectFind(0,name)<0)
     {
      ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,name,OBJPROP_BACK,false);
      ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
     }
   PanelPos(name,x,y,pw,ph);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_COLOR,border);
  }

void PanelText(const string name,const int x,const int y,const int pw,const int ph,const string txt,
               const color clr,const int fs,const bool rightAlign,const bool bold)
  {
   if(ObjectFind(0,name)<0)
     {
      ObjectCreate(0,name,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,name,OBJPROP_BACK,false);
     }
   PanelPos(name,x,y,pw,ph);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,rightAlign ? ANCHOR_RIGHT_UPPER : ANCHOR_LEFT_UPPER);
   ObjectSetString(0,name,OBJPROP_FONT,bold ? "Segoe UI Semibold" : "Segoe UI");
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fs);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetString(0,name,OBJPROP_TEXT,(txt=="" ? " " : txt));
  }

void PanelButton(const string name,const int x,const int y,const int w,const int h,const int pw,const int ph,
                 const string txt,const color bg,const color border,const color clr,const int fs)
  {
   if(ObjectFind(0,name)<0)
     {
      ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,name,OBJPROP_BACK,false);
      ObjectSetInteger(0,name,OBJPROP_ZORDER,100);
      ObjectSetString(0,name,OBJPROP_FONT,"Segoe UI");
     }
   PanelPos(name,x,y,pw,ph);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetString(0,name,OBJPROP_TEXT,txt);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fs);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,border);
   ObjectSetInteger(0,name,OBJPROP_STATE,false);
  }

color CellColor(const int h,const int n,const int lev)
  {
   if(n<=0 || n<MathMax(InpScoreMinN,1))
      return C'96,100,112';
   double be=g_sm[g_stop]/(g_sm[g_stop]+g_lev[lev]);
   double rate=(double)h/n;
   if(rate>=be+0.05)
      return InpBuyColor;
   if(rate<=be-0.05)
      return InpSellColor;
   return C'214,217,224';
  }

string PctCell(const int h,const int n)
  {
   if(n<=0)
      return "-";
   return IntegerToString((int)MathRound(100.0*h/n))+"%";
  }

string BestCell(const int n,const int h0,const int h1,const int h2,const int h3,color &clr)
  {
   clr=C'96,100,112';
   if(n<=0)
      return "-";
   int hh[4];
   hh[0]=h0;
   hh[1]=h1;
   hh[2]=h2;
   hh[3]=h3;
   double best=-10.0;
   int bl=0;
   for(int l=0;l<4;l++)
     {
      double rate=(double)hh[l]/n;
      double ev=rate*(g_lev[l]/g_sm[g_stop])-(1.0-rate);
      if(ev>best)
        {
         best=ev;
         bl=l;
        }
     }
   if(n>=MathMax(InpScoreMinN,1))
     {
      if(best>0.05)
         clr=InpBuyColor;
      else
         if(best<-0.05)
            clr=InpSellColor;
         else
            clr=C'214,217,224';
     }
   return (best>=0.0 ? "+" : "")+DoubleToString(best,2)+"R @"+g_levName[bl];
  }

void AddRow(PRow &rows[],int &nr,const int kind,const string label,const int n,
            const int h0,const int h1,const int h2,const int h3)
  {
   ArrayResize(rows,nr+1,32);
   rows[nr].kind=kind;
   rows[nr].label=label;
   rows[nr].n=n;
   rows[nr].h0=h0;
   rows[nr].h1=h1;
   rows[nr].h2=h2;
   rows[nr].h3=h3;
   nr++;
  }

void DrawPanel()
  {
   string p=PFX+"P_";
   if(!InpPanelShow)
     {
      ObjectsDeleteAll(0,p);
      g_panelState=-1;
      return;
     }
   color cBg=C'22,24,30';
   color cHead=C'34,37,47';
   color cLine=C'52,56,68';
   color cDim=C'120,124,135';
   color cTxt=C'214,217,224';
   g_chartH=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);

   int cur=g_collapsed ? 1 : 0;
   if(g_panelState!=cur)
     {
      ObjectsDeleteAll(0,p);
      g_panelState=cur;
      g_panelRows=0;
     }
   if(g_collapsed)
     {
      int w=Px(170);
      int h=Px(24);
      PanelButton(p+"z_show",0,0,w,h,w,h,TITLE+"    show",cHead,cLine,cTxt,8);
      return;
     }

   int rowH=Px(18);
   int padX=Px(12);
   int headH=Px(28);
   int pw=Px(452);
   int colR=pw-padX;
   int cN=Px(186);
   int cL[4];
   cL[0]=Px(232);
   cL[1]=Px(274);
   cL[2]=Px(316);
   cL[3]=Px(358);
   int view=(HAS_VIEW && g_view==1) ? 1 : 0;
   string status=StatusLine();
   int nctx=(status=="") ? 2 : 3;

//--- scorecard rows, grouped by how many timeframes agree at the same price
   PRow rows[];
   int nr=0;
   int gN=0,gH0=0,gH1=0,gH2=0,gH3=0;
   int maxRows=Clamp(InpScoreRows,1,20);
   for(int grp=1;grp<=4;grp++)
     {
      int gi[];
      int ngi=0;
      int sN=0,sH0=0,sH1=0,sH2=0,sH3=0;
      for(int i=0;i<g_nStats;i++)
        {
         if(Bits(g_stats[i].mask)!=grp || StatN(i,view)<=0)
            continue;
         ArrayResize(gi,ngi+1,16);
         gi[ngi]=i;
         ngi++;
         sN+=StatN(i,view);
         sH0+=StatH(i,view,0);
         sH1+=StatH(i,view,1);
         sH2+=StatH(i,view,2);
         sH3+=StatH(i,view,3);
        }
      if(ngi==0)
         continue;
      for(int i=0;i<ngi-1;i++)
         for(int j=i+1;j<ngi;j++)
            if(StatN(gi[j],view)>StatN(gi[i],view))
              {
               int tmp=gi[i];
               gi[i]=gi[j];
               gi[j]=tmp;
              }
      AddRow(rows,nr,0,(grp==1) ? "1 TIMEFRAME" : IntegerToString(grp)+" TIMEFRAMES",sN,sH0,sH1,sH2,sH3);
      for(int i=0;i<ngi && i<maxRows;i++)
        {
         int q=gi[i];
         AddRow(rows,nr,1,MaskNames(g_stats[q].mask),StatN(q,view),StatH(q,view,0),StatH(q,view,1),StatH(q,view,2),StatH(q,view,3));
        }
      gN+=sN;
      gH0+=sH0;
      gH1+=sH1;
      gH2+=sH2;
      gH3+=sH3;
     }
   if(nr>0)
      AddRow(rows,nr,2,(g_side==1) ? "ALL BUY ZONES" : ((g_side==2) ? "ALL SELL ZONES" : "ALL ZONES"),gN,gH0,gH1,gH2,gH3);

//--- height; if the chart is too short, drop the grid, then the notes, then the detail rows
   int avail=(g_chartH>0) ? g_chartH-2*Px(12) : 100000;
   bool showGrid=true;
   bool showFoot=true;
   int ph=0;
   for(int pass=0;pass<4;pass++)
     {
      ph=headH+Px(8)+nctx*rowH;
      ph+=Px(6)+1+Px(8);
      ph+=Px(22)+3*Px(24)+rowH;
      if(nr==0)
         ph+=rowH;
      for(int i=0;i<nr;i++)
        {
         if(rows[i].kind==0)
            ph+=Px(5);
         if(rows[i].kind==2)
            ph+=Px(5)+1+Px(5);
         ph+=rowH;
        }
      if(nr>0 && showGrid)
         ph+=Px(8)+1+Px(8)+6*rowH;
      if(showFoot)
         ph+=Px(6)+3*Px(14);
      ph+=Px(8);
      if(ph<=avail)
         break;
      if(showGrid)
        {
         showGrid=false;
         continue;
        }
      if(showFoot)
        {
         showFoot=false;
         continue;
        }
      int w2=0;
      for(int i=0;i<nr;i++)
         if(rows[i].kind!=1)
           {
            rows[w2]=rows[i];
            w2++;
           }
      nr=w2;
     }

//--- frame + header
   PanelRect(p+"a_bg",0,0,pw,ph,pw,ph,cBg,cLine);
   PanelRect(p+"b_hd",1,1,pw-2,headH,pw,ph,cHead,cHead);
   PanelText(p+"c_t1",padX,Px(6),pw,ph,TITLE,cTxt,9,false,true);
   PanelText(p+"c_t2",padX+Px(150),Px(9),pw,ph,_Symbol+"  "+TFName(_Period),cDim,7,false,false);
   PanelButton(p+"y_hide",colR-Px(46),Px(5),Px(46),Px(18),pw,ph,"Hide",cBg,cLine,cDim,7);

//--- what is on the chart now
   int y=headH+Px(8);
   string fs1=(CTX_FLAG=="") ? "" : "   ("+IntegerToString(g_liveFlag[1])+" "+CTX_FLAG+")";
   string fs0=(CTX_FLAG=="") ? "" : "   ("+IntegerToString(g_liveFlag[0])+" "+CTX_FLAG+")";
   PanelText(p+"d_l0",padX,y,pw,ph,"Fresh SELL zones",cDim,8,false,false);
   PanelText(p+"d_v0",colR,y,pw,ph,IntegerToString(g_liveCnt[1])+fs1,(g_liveCnt[1]>0) ? InpSellColor : cDim,8,true,true);
   y+=rowH;
   PanelText(p+"d_l1",padX,y,pw,ph,"Fresh BUY zones",cDim,8,false,false);
   PanelText(p+"d_v1",colR,y,pw,ph,IntegerToString(g_liveCnt[0])+fs0,(g_liveCnt[0]>0) ? InpBuyColor : cDim,8,true,true);
   y+=rowH;
   if(status!="")
     {
      PanelText(p+"d_l2",padX,y,pw,ph,status,cDim,8,false,false);
      y+=rowH;
     }
   else
      DelObj(p+"d_l2");

//--- scorecard header + controls
   y+=Px(6);
   PanelRect(p+"e_dv1",padX,y,pw-2*padX,1,pw,ph,cLine,cLine);
   y+=1+Px(8);
   PanelText(p+"e_h1",padX,y+Px(1),pw,ph,"ZONE SCORECARD",cTxt,8,false,true);
   PanelText(p+"e_h2",padX+Px(112),y+Px(3),pw,ph,g_scoreOk ? "last "+IntegerToString(g_scoreBars)+" bars" : "loading history",cDim,7,false,false);
   y+=Px(22);

   int sw=Px(54);
   PanelButton(p+"y_sb",padX,y,sw,Px(18),pw,ph,"Both",(g_side==0) ? cLine : cBg,cLine,(g_side==0) ? cTxt : cDim,7);
   PanelButton(p+"y_sy",padX+sw,y,sw,Px(18),pw,ph,"Buys",(g_side==1) ? cLine : cBg,cLine,(g_side==1) ? InpBuyColor : cDim,7);
   PanelButton(p+"y_ss",padX+2*sw,y,sw,Px(18),pw,ph,"Sells",(g_side==2) ? cLine : cBg,cLine,(g_side==2) ? InpSellColor : cDim,7);
   if(HAS_VIEW)
     {
      int bw=Px(84);
      PanelButton(p+"y_all",colR-2*bw,y,bw,Px(18),pw,ph,VIEW0_NAME,(view==0) ? cLine : cBg,cLine,(view==0) ? cTxt : cDim,7);
      PanelButton(p+"y_flt",colR-bw,y,bw,Px(18),pw,ph,VIEW1_NAME,(view==1) ? cLine : cBg,cLine,(view==1) ? cTxt : cDim,7);
     }
   y+=Px(24);

   PanelText(p+"e_sl",padX,y+Px(3),pw,ph,"Stop size",cDim,7,false,false);
   int pwb=Px(44);
   for(int q=0;q<4;q++)
      PanelButton(p+"y_p"+IntegerToString(q),padX+Px(58)+q*pwb,y,pwb,Px(18),pw,ph,g_smName[q],
                  (g_stop==q) ? cLine : cBg,cLine,(g_stop==q) ? cTxt : cDim,7);
   PanelText(p+"e_sx",colR,y+Px(3),pw,ph,"x = zone height",cDim,7,true,false);
   y+=Px(24);

   PanelText(p+"e_hl",padX,y+Px(3),pw,ph,"History",cDim,7,false,false);
   int hw=Px(76);
   PanelButton(p+"y_h0",padX+Px(58),y,Px(44),Px(18),pw,ph,"All",(g_half==0) ? cLine : cBg,cLine,(g_half==0) ? cTxt : cDim,7);
   PanelButton(p+"y_h1",padX+Px(58)+Px(44),y,hw,Px(18),pw,ph,"Older half",(g_half==1) ? cLine : cBg,cLine,(g_half==1) ? cTxt : cDim,7);
   PanelButton(p+"y_h2",padX+Px(58)+Px(44)+hw,y,hw,Px(18),pw,ph,"Newer half",(g_half==2) ? cLine : cBg,cLine,(g_half==2) ? cTxt : cDim,7);
   PanelText(p+"e_hx",colR,y+Px(3),pw,ph,"Targets:",cDim,7,true,false);
   y+=Px(24);

   PanelText(p+"e_c0",padX,y,pw,ph,"Timeframes",cDim,7,false,false);
   PanelText(p+"e_c1",cN,y,pw,ph,"Tests",cDim,7,true,false);
   for(int l=0;l<4;l++)
      PanelText(p+"e_cc"+IntegerToString(l),cL[l],y,pw,ph,g_levName[l],cDim,7,true,false);
   PanelText(p+"e_c6",colR,y,pw,ph,"Best exit",cDim,7,true,false);
   y+=rowH;

   if(nr==0)
     {
      PanelText(p+"e_none",padX,y,pw,ph,g_scoreOk ? "No zone finished a test in this view" : "Waiting for history data",cDim,8,false,false);
      y+=rowH;
     }
   else
      DelObj(p+"e_none");

   bool haveTotal=false;
   for(int i=0;i<nr;i++)
     {
      string rn=p+"e_r"+StringFormat("%02d",i);
      bool bold=(rows[i].kind!=1);
      if(rows[i].kind==0)
         y+=Px(5);
      if(rows[i].kind==2)
        {
         y+=Px(5);
         PanelRect(p+"e_dvT",padX,y,pw-2*padX,1,pw,ph,cLine,cLine);
         y+=1+Px(5);
         haveTotal=true;
        }
      int n=rows[i].n;
      PanelText(rn+"a",(rows[i].kind==1) ? padX+Px(10) : padX,(rows[i].kind==0) ? y+Px(1) : y,pw,ph,rows[i].label,
                (rows[i].kind==0) ? cDim : cTxt,(rows[i].kind==0) ? 7 : 8,false,bold);
      PanelText(rn+"b",cN,y,pw,ph,IntegerToString(n),cDim,8,true,bold);
      PanelText(rn+"c",cL[0],y,pw,ph,PctCell(rows[i].h0,n),CellColor(rows[i].h0,n,0),8,true,bold);
      PanelText(rn+"d",cL[1],y,pw,ph,PctCell(rows[i].h1,n),CellColor(rows[i].h1,n,1),8,true,bold);
      PanelText(rn+"e",cL[2],y,pw,ph,PctCell(rows[i].h2,n),CellColor(rows[i].h2,n,2),8,true,bold);
      PanelText(rn+"f",cL[3],y,pw,ph,PctCell(rows[i].h3,n),CellColor(rows[i].h3,n,3),8,true,bold);
      color bc2=clrGray;
      string bt=BestCell(n,rows[i].h0,rows[i].h1,rows[i].h2,rows[i].h3,bc2);
      PanelText(rn+"g",colR,y,pw,ph,bt,bc2,8,true,bold);
      y+=rowH;
     }
   for(int i=nr;i<g_panelRows;i++)
      ObjectsDeleteAll(0,p+"e_r"+StringFormat("%02d",i));
   g_panelRows=nr;
   if(!haveTotal)
      DelObj(p+"e_dvT");

//--- every stop size against every target
   if(nr>0 && showGrid)
     {
      y+=Px(8);
      PanelRect(p+"e_dvG",padX,y,pw-2*padX,1,pw,ph,cLine,cLine);
      y+=1+Px(8);
      PanelText(p+"e_g0",padX,y,pw,ph,"STOP x TARGET GRID",cTxt,8,false,true);
      PanelText(p+"e_g1",colR,y+Px(2),pw,ph,"average R per trade, all rows above",cDim,7,true,false);
      y+=rowH;
      PanelText(p+"e_g2",padX,y,pw,ph,"Stop size",cDim,7,false,false);
      PanelText(p+"e_g3",cN,y,pw,ph,"Tests",cDim,7,true,false);
      for(int l=0;l<4;l++)
         PanelText(p+"e_g4"+IntegerToString(l),cL[l],y,pw,ph,"TP "+g_levName[l],cDim,7,true,false);
      y+=rowH;
      for(int si=0;si<4;si++)
        {
         int tn=0;
         int th[4];
         for(int l=0;l<4;l++)
            th[l]=0;
         for(int i=0;i<g_nStats;i++)
           {
            tn+=StatNs(i,view,si);
            for(int l=0;l<4;l++)
               th[l]+=StatHs(i,view,si,l);
           }
         string gn=p+"e_gr"+IntegerToString(si);
         bool sel=(si==g_stop);
         PanelText(gn+"a",padX,y,pw,ph,"SL "+g_smName[si],sel ? cTxt : cDim,8,false,sel);
         PanelText(gn+"b",cN,y,pw,ph,IntegerToString(tn),cDim,8,true,sel);
         for(int l=0;l<4;l++)
           {
            string gt="-";
            color gc=C'96,100,112';
            if(tn>0)
              {
               double rate=(double)th[l]/tn;
               double ev=rate*(g_lev[l]/g_sm[si])-(1.0-rate);
               gt=(ev>=0.0 ? "+" : "")+DoubleToString(ev,2);
               if(tn>=MathMax(InpScoreMinN,1))
                 {
                  if(ev>0.05)
                     gc=InpBuyColor;
                  else
                     if(ev<-0.05)
                        gc=InpSellColor;
                     else
                        gc=cTxt;
                 }
              }
            PanelText(gn+"c"+IntegerToString(l),cL[l],y,pw,ph,gt,gc,8,true,sel);
           }
         y+=rowH;
        }
     }
   else
     {
      ObjectsDeleteAll(0,p+"e_g");
      DelObj(p+"e_dvG");
     }

   if(showFoot)
     {
      y+=Px(6);
      PanelText(p+"e_f1",padX,y,pw,ph,"x = zone height (min "+DoubleToString(InpScoreMinRisk,2)+" ATR). Entry at the zone edge.",cDim,7,false,false);
      y+=Px(14);
      PanelText(p+"e_f2",padX,y,pw,ph,"% = target hit before stop. Green beats break-even.",cDim,7,false,false);
      y+=Px(14);
      PanelText(p+"e_f3",padX,y,pw,ph,FOOT3,cDim,7,false,false);
     }
   else
      ObjectsDeleteAll(0,p+"e_f");
  }

//+------------------------------------------------------------------+
//| Main redraw                                                      |
//+------------------------------------------------------------------+
void Redraw()
  {
   g_t0=iTime(_Symbol,_Period,0);
   if(g_t0==0)
      return;
   g_ps=PeriodSeconds();

//--- timeframes in use: above the chart timeframe, no repeats, lowest first
   g_nAct=0;
   for(int k=0;k<4;k++)
     {
      if(!g_show[k] || PeriodSeconds(g_tf[k])<=g_ps)
         continue;
      bool dup=false;
      for(int e=0;e<g_nAct;e++)
         if(g_tf[g_act[e]]==g_tf[k])
            dup=true;
      if(dup)
         continue;
      g_act[g_nAct]=k;
      g_nAct++;
     }
   for(int i=0;i<g_nAct-1;i++)
      for(int j=i+1;j<g_nAct;j++)
         if(PeriodSeconds(g_tf[g_act[j]])<PeriodSeconds(g_tf[g_act[i]]))
           {
            int tmp=g_act[i];
            g_act[i]=g_act[j];
            g_act[j]=tmp;
           }

   if(g_nAct==0)
     {
      ObjectsDeleteAll(0,PFX+"Z");
      for(int d=0;d<2;d++)
        {
         g_prevZones[d]=0;
         g_liveCnt[d]=0;
         g_liveFlag[d]=0;
        }
     }
   else
     {
      double price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      if(price<=0.0)
         price=iClose(_Symbol,_Period,0);
      bool wantScore=(ALWAYS_SCORE || (InpPanelShow && !g_collapsed));
      if(wantScore && (!g_scoreOk || g_scoreAt!=g_t0 || g_scoreN!=g_nAct))
        {
         RunScore();
         g_scoreAt=g_t0;
         g_scoreN=g_nAct;
        }
      DrawZones(price);
     }
   DrawPanel();
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Init / events                                                    |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_tf[0]=InpTF1;
   g_tf[1]=InpTF2;
   g_tf[2]=InpTF3;
   g_tf[3]=InpTF4;
   g_show[0]=InpShow1;
   g_show[1]=InpShow2;
   g_show[2]=InpShow3;
   g_show[3]=InpShow4;
   g_nAct=0;
   g_nStats=0;
   g_scoreOk=false;
   g_scoreAt=0;
   g_scoreN=-1;
   g_panelState=-1;
   g_panelRows=0;
   for(int d=0;d<2;d++)
     {
      g_prevZones[d]=0;
      g_lastAlert[d]=0;
      g_liveCnt[d]=0;
      g_liveFlag[d]=0;
     }
   g_cardMin=(GlobalVariableCheck(GV+"cardmin") && GlobalVariableGet(GV+"cardmin")>0.5);
   g_cardSig="";
   g_dpi=(double)TerminalInfoInteger(TERMINAL_SCREEN_DPI)/96.0;
   if(g_dpi<1.0)
      g_dpi=1.0;
   g_collapsed=(GlobalVariableCheck(GV+"collapsed") && GlobalVariableGet(GV+"collapsed")>0.5);
   g_view=(GlobalVariableCheck(GV+"view") && GlobalVariableGet(GV+"view")>0.5) ? 1 : 0;
   g_side=GlobalVariableCheck(GV+"side") ? Clamp((int)MathRound(GlobalVariableGet(GV+"side")),0,2) : 0;
   if(InpSpikeOnly && SpikeSide()>0)
      g_side=SpikeSide();                       // scorecard and zones: the with-the-spike side
   g_stop=2;                                    // 1x stop, as the EA
   g_stop=GlobalVariableCheck(GV+"stop") ? Clamp((int)MathRound(GlobalVariableGet(GV+"stop")),0,3) : 2;
   g_half=GlobalVariableCheck(GV+"half") ? Clamp((int)MathRound(GlobalVariableGet(GV+"half")),0,2) : 0;
   if(!HAS_VIEW)
      g_view=0;

   ObjectsDeleteAll(0,PFX);
   IndicatorSetString(INDICATOR_SHORTNAME,TITLE);
   EventSetTimer(1);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   ObjectsDeleteAll(0,PFX);
   ChartRedraw(0);
  }

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   Redraw();
   return rates_total;
  }

void OnTimer()
  {
   Redraw();
  }

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(id==CHARTEVENT_CHART_CHANGE)
      Redraw();
   if(id==CHARTEVENT_OBJECT_CLICK)
     {
      if(sparam==PFX+"CD_btn")
        {
         g_cardMin=!g_cardMin;
         GlobalVariableSet(GV+"cardmin",g_cardMin ? 1.0 : 0.0);
         g_cardSig="";
         Redraw();
         return;
        }
      string p=PFX+"P_";
      bool hit=false;
      if(sparam==p+"z_show")
        {
         g_collapsed=false;
         hit=true;
        }
      if(sparam==p+"y_hide")
        {
         g_collapsed=true;
         hit=true;
        }
      if(sparam==p+"y_all")
        {
         g_view=0;
         hit=true;
        }
      if(sparam==p+"y_flt")
        {
         g_view=1;
         hit=true;
        }
      if(sparam==p+"y_sb")
        {
         g_side=0;
         hit=true;
        }
      if(sparam==p+"y_sy")
        {
         g_side=1;
         hit=true;
        }
      if(sparam==p+"y_ss")
        {
         g_side=2;
         hit=true;
        }
      for(int q=0;q<4;q++)
         if(sparam==p+"y_p"+IntegerToString(q))
           {
            g_stop=q;
            hit=true;
           }
      for(int q=0;q<3;q++)
         if(sparam==p+"y_h"+IntegerToString(q))
           {
            g_half=q;
            hit=true;
           }
      if(hit)
        {
         GlobalVariableSet(GV+"collapsed",g_collapsed ? 1.0 : 0.0);
         GlobalVariableSet(GV+"view",(double)g_view);
         GlobalVariableSet(GV+"side",(double)g_side);
         GlobalVariableSet(GV+"stop",(double)g_stop);
         GlobalVariableSet(GV+"half",(double)g_half);
         Redraw();
        }
     }
  }
//+------------------------------------------------------------------+
