//+------------------------------------------------------------------+
//|                                                      T2R_Lab.mq5 |
//| T2R LAB - one Expert Advisor that tests every zone strategy on   |
//| every asset in Market Watch, writes a dashboard page and data    |
//| files, and sends Telegram messages. It places NO trades.         |
//+------------------------------------------------------------------+
#property copyright "T2R Lab"
#property version   "1.63"
#property strict
#include <Trade\Trade.mqh>

input group "What to scan"
input bool            InpGrpBoomCrash = true;         // Boom and Crash indices
input bool            InpGrpVol       = true;         // Volatility indices
input bool            InpGrpSynth     = true;         // Other synthetics (Step, Jump, DEX, Range Break ...)
input bool            InpGrpForex     = true;         // Forex pairs
input bool            InpGrpMetals    = true;         // Metals (gold, silver ...)
input bool            InpGrpCrypto    = false;        // Crypto
input bool            InpGrpIndices   = false;        // Stock indices
input bool            InpGrpCommod    = false;        // Oil, gas and soft commodities
input bool            InpGrpStocks    = false;        // Shares, ETFs and everything else
input group "STUDY mode - only for a backtest on the laptop (never trades, never sends anything)"
input string          InpStudyOnly    = "";           // Study only markets whose name contains any of these, comma separated (empty = normal lab)
input datetime        InpStudyFrom    = D'2026.01.01 00:00';   // Study: keep trades from this date on
input group "What to scan (more)"
input string          InpSymbols      = "";           // Extra assets by exact name, comma separated (max ~250 characters)

//--- study mode state (declared early: used by the test engine)
bool     g_study      = false;
int      g_studyH     = INVALID_HANDLE;
long     g_studyN     = 0;
input ENUM_TIMEFRAMES InpChartTF      = PERIOD_M15;   // Chart timeframe the tests run on
input int             InpScoreBars    = 60000;        // Bars of history tested per asset
input double          InpSpreadMult   = 1.5;          // Spread charged per trade (x the candle's spread or today's typical, whichever is bigger)
input int             InpRescanHours  = 0;            // Re-run the whole scan every N hours (0 = never)

input group "Stop classes - every trade is tested at all three"
input double          InpRisk1        = 0.25;         // TIGHT: 1x stop is the zone height, at least this x ATR
input double          InpRisk2        = 1.0;          // MEDIUM: at least this x ATR
input double          InpRisk3        = 3.0;          // WIDE: at least this x ATR

input group "Finer check - the same tests again on a smaller chart"
input string          InpFineSymbols  = "Range Break 200 Index,Range Break 100 Index";   // Assets, comma separated (empty = off)
input ENUM_TIMEFRAMES InpFineTF       = PERIOD_M5;    // Chart timeframe for the finer check
input int             InpFineBars     = 100000;       // Bars of history for the finer check

input group "Pass mark - fixed BEFORE testing (1x stop, 2x target, AFTER spread)"
input int             InpPassMinN     = 100;          // Tests needed
input double          InpPassMinR     = 0.05;         // Average R needed in EACH of the three stages

input group "Pair strongholds - three-stage exam, any stop and target"
input int             InpStageMinN    = 40;           // Tests needed in each stage
input double          InpPickR        = 0.10;         // Stage 1 (pick): average R needed
input double          InpConfirmR     = 0.05;         // Stage 2 (confirm) and stage 3 (exam): average R needed

input group "Live demo test - the winners get signals and every signal is tracked to its result"
input int             InpWatchMax     = 300;          // Most strategy-and-asset combos to follow
input int             InpWatchPerAsset= 6;            // Most setups followed on any one market
input bool            InpWatchFreeze  = true;         // Keep the first list fixed (a fair test needs a fixed list)
input bool            InpScanOnStart  = true;         // Run the backtest scan when the EA starts (off = go straight to live, if a list exists)
input int             InpReplayDays   = 7;            // Replay: show what the followed setups would have signalled over the last N days (0 = off)
input bool            InpTgResults    = false;        // Telegram: also send a message when a tracked trade closes

input group "Telegram (leave empty to switch off)"
input string          InpTgToken      = "";           // Bot token from @BotFather
input string          InpTgChat       = "";           // Chat id
input bool            InpTgSignals    = true;         // Send the signals: pending orders, entries and cancels
input group "Demo account trading - the signals become real orders on THIS account, only if it is a demo"
input bool            InpTradeDemo    = true;         // Trade the signals on this demo account (never trades a real account)
input double          InpTradeRiskPct = 0.25;         // Risk per trade, % of the balance (tested at 0.25%)
input bool            InpBestOnly     = true;         // Demo trades ONLY the proven setup: Boom & Crash, Self-taught Zones, Model picks, with the spike, Wide, 1:3 (the rest stays a forward test on the website)
input long            InpTradeMagic   = 15253;        // Magic number of the lab's orders
input int             InpTradeMaxOpen = 60;           // Most lab positions open at once on the demo account
input bool            InpTradeBE      = false;        // Demo: at +1R bank half and move the stop to entry (off = hold the full trade to target or stop)
input double          InpTradeGuard   = 1.5;          // Close a demo trade at once if its loss passes this many times the planned risk

input group "Website Signal Desk (leave empty to switch off)"
input string          InpWebUrl       = "";           // Desk address, e.g. https://t2r-traders-hub.vercel.app/api/ingest
input string          InpWebKey       = "";           // The T2R_INGEST_KEY password set in Vercel

input group "Telegram (more)"
input bool            InpTgLifecycle  = true;         // Post updates under each signal: activated, +1R, target, stop, cancel
input double          InpTgLotRef     = 1000;         // Lot sizes in Telegram cards are worked out for this account size
input string          InpTgAllMarkets = "Boom,Crash,DEX,Vol over";   // Markets whose name contains any of these get EVERY signal on Telegram (no daily cap)
input int             InpTgMaxPerDay  = 2;            // Most Telegram signals per market per day (0 = no limit; the website shows all)
input string          InpSiteUrl      = "https://t2r-traders-hub.vercel.app";   // Website linked under each signal
input bool            InpTgHeadsUp    = false;         // Also send GET READY when a setup that needs a last check is close

input group "Timeframes scanned for zones (must be above the chart timeframe)"
input ENUM_TIMEFRAMES InpTF1          = PERIOD_H1;    // Timeframe 1
input ENUM_TIMEFRAMES InpTF2          = PERIOD_H4;    // Timeframe 2
input ENUM_TIMEFRAMES InpTF3          = PERIOD_D1;    // Timeframe 3
input ENUM_TIMEFRAMES InpTF4          = PERIOD_W1;    // Timeframe 4

input group "Trap zones"
input double          InpMinBodyATR   = 0.5;          // Breakout candle body must be at least (x ATR)

input group "Rejection stacks"
input int             InpStackMin     = 2;            // Separate rejections needed at one price
input double          InpWickMin      = 0.35;         // A rejection = wick at least this share of the candle
input double          InpStackTolATR  = 0.15;         // "Same price" tolerance (x ATR)
input int             InpStackLookback= 120;          // Candles searched for rejections

input group "Fair value gaps inside a trap"
input bool            InpGShow1       = true;         // Gap timeframe 1 - use
input ENUM_TIMEFRAMES InpGTF1         = PERIOD_M15;   // Gap timeframe 1
input bool            InpGShow2       = true;         // Gap timeframe 2 - use
input ENUM_TIMEFRAMES InpGTF2         = PERIOD_H1;    // Gap timeframe 2
input bool            InpGShow3       = true;         // Gap timeframe 3 - use
input ENUM_TIMEFRAMES InpGTF3         = PERIOD_H4;    // Gap timeframe 3
input int             InpGapMinTF     = 1;            // Gap timeframes that must overlap inside the trap (1-3)

input group "Untouched ground"
input int             InpWindow       = 150;          // Candles of history mapped (per timeframe)
input double          InpBinATR       = 0.25;         // Height of one price slice (x ATR)
input int             InpThinMax      = 1;            // "Untouched" = visited at most this many times
input int             InpThickMin     = 5;            // "Heavily traded" = visited at least this many times
input int             InpRunMin       = 2;            // Smallest zone, in slices
input int             InpRunMax       = 12;           // Largest zone, in slices

input group "Self-taught model and the learning layer"
input double          InpZoneATR      = 0.25;         // Zone height at each swing / flip level (x ATR)
input int             InpRangeBars    = 480;          // Chart bars used for "where in the range"
input int             InpTrendBars    = 200;          // Chart bars used for trend
input double          InpPickScore    = 0.30;         // Score needed to be a pick
input int             InpModelMinN    = 10;           // Stage-1 trades needed before a clue is trusted

input group "FVG confluence"
input double          InpFvgMinATR    = 0.10;         // Smallest gap counted (x ATR)

input group "Flip levels"
input double          InpFlipBodyATR  = 0.5;          // Breaking candle body must be at least (x ATR)

input group "Stretch bands"
input int             InpStretchBars  = 20;           // Candles in the average
input double          InpStretchATR   = 2.5;          // Band distance from the average (x ATR)
input double          InpStretchWidth = 0.5;          // Zone height (x ATR)

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
   int               half;       // stage of history: 0 learn, 1 confirm, 2 exam
   int               reached[4];
   bool              done[4];
   int               fin2;       // bar on which the 1x-stop version finished (-1 = still open)
   int               f[6];
   double            score;
   double            cost;       // spread as a share of the 1x risk
   int               scale;      // stop class: 0 tight, 1 medium, 2 wide
   bool              pick;       // chosen by the learning layer
   datetime          tIn;        // candle the trade was entered on
   datetime          tHit[16];   // when each target was reached [stop*4+target]
   datetime          tEnd[4];    // when each stop size finished
   double            gscore;
   int               gf[9];      // clues used by the learning layer
  };

struct ZStat
  {
   int               mask;
   int               n[72];      // [((view*2+dir)*3+stage)*4+stop]
   int               h[288];     // [(((view*2+dir)*3+stage)*4+stop)*4+target]
   double            c[18];      // spread cost summed, in R at a 1x stop: [(view*2+dir)*3+stage]
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
#define NSTRAT 9
#define NSC    3
#define NFAM   10
string   g_sName[NSTRAT]={"Trap Zones","Trap + Gap","Untouched Ground","Rejection Stacks","Self-taught Zones","Self-taught 4H+1D",
                          "FVG Confluence","Flip Levels","Stretch Bands"};
string   g_v0[NSTRAT]={"All traps","All traps","All zones","Bounce","All levels","All levels","All gaps","All flips","All bands"};
string   g_v1[NSTRAT]={"At a stack","With a gap","","Sweep","Model picks","Model picks","2+ timeframes","",""};
bool     g_hasView[NSTRAT]={true,true,false,true,true,true,true,false,false};
bool     g_hasPick[NSTRAT]={true,true,true,true,false,false,true,true,true};   // gets the learning layer ("Learned picks")
bool     g_excl[NSTRAT]={false,false,false,true,false,false,false,false,false};
int      g_kindsOf[NSTRAT]={1,1,1,2,1,1,1,1,1};
int      g_lookOf[NSTRAT]={40,40,40,60,60,60,40,40,40};
bool     g_use1[NSTRAT]={true,true,true,true,true,false,true,true,true};         // timeframe slot 1 (the lowest)
bool     g_use4[NSTRAT]={true,true,false,true,false,false,true,false,false};     // timeframe slot 4 (weekly)
string   g_scName[NSC]={"Tight","Medium","Wide"};
string   g_segName[3]={"learn","confirm","exam"};
string   g_famName[NFAM]={"Boom/Crash","Volatility","Other synthetics","Forex","Metals","Crypto","Stock indices","Commodities",
                          "Shares + other","ALL ASSETS"};
double   g_rk[NSC]={0.25,1.0,3.0};
int      g_curScale   = 0;
int      g_liveScale  = 0;
int      g_wantBars   = 60000;

//--- learning layer
double   g_gl[26];
bool     g_gOk        = false;
bool     g_repOn      = false;         // the test engine also hands its trades to the replay
//--- what each stop class learned on the last asset tested (kept so live signals need no re-learning)
datetime g_scoreT[4];            // last test: first candle, stage 2 start, stage 3 start, last candle
double   g_glAll[78];
double   g_liftAll[54];
bool     g_gOkAll[3];
bool     g_mOkAll[3];

//--- how the self-taught model's score bands did (1x stop), added up over every asset
//    index = (((model 0/1)*NSC + stop class)*5 + band)*3 + stage ; hits = that*4 + target
int      g_bandN[90];
int      g_bandH[360];
bool     g_bandOn     = false;
int      g_bandStrat  = 0;
string   g_bandName[5]={"below 0","0 to 0.15","0.15 to 0.30","0.30 to 0.50","0.50 and up"};

int BandOf(const double sc)
  {
   if(sc<0.0)
      return 0;
   if(sc<0.15)
      return 1;
   if(sc<0.30)
      return 2;
   if(sc<0.50)
      return 3;
   return 4;
  }
string   g_sideName[3]={"Both","Buys","Sells"};

//--- the asset / strategy being worked on right now
string   g_sym        = "";
ENUM_TIMEFRAMES g_per = PERIOD_M15;
double   g_pt         = 0.00001;
int      g_dig        = 5;
int      g_strat      = 0;
int      g_kinds      = 1;
bool     g_viewExcl   = false;
int      g_look       = 40;

ENUM_TIMEFRAMES g_tf[4];
bool     g_show[4];
int      g_act[4];
int      g_nAct       = 0;
datetime g_t0         = 0;
int      g_ps         = 60;
double   g_lev[4]={0.5,1.0,2.0,3.0};
double   g_sm[4]={0.2,0.5,1.0,2.0};
string   g_smName[4]={"0.2x","0.5x","1x","2x"};
string   g_levName[4]={"0.5x","1x","2x","3x"};
ZStat    g_stats[];
int      g_nStats     = 0;
bool     g_scoreOk    = false;
int      g_scoreBars  = 0;

//--- shared helpers ----------------------------------------------------
int Clamp(const int v,const int lo,const int hi)
  {
   if(v<lo) return lo;
   if(v>hi) return hi;
   return v;
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

int AppendZones(ZGap &gaps[],const int ng,const int dir,const int kind,ZBox &z[],const int nz0)
  {
   int nz=nz0;
   double eps=g_pt/2.0;
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
//| Rejection tips: candle highs / lows with a long wick that have   |
//| not been taken out since.                                        |
//+------------------------------------------------------------------+
void BuildTips(const MqlRates &r[],const int got,ZTip &tips[],int &nt)
  {
   nt=0;
   double eps=g_pt/2.0;
   datetime never=D'3000.01.01';
   for(int k=15;k<=got-2;k++)
     {
      double rng=r[k].high-r[k].low;
      if(rng<=eps)
         continue;
      double tol=MathMax(InpStackTolATR,0.0)*AtrAt(r,k);
      double up=r[k].high-MathMax(r[k].open,r[k].close);
      double dn=MathMin(r[k].open,r[k].close)-r[k].low;
      if(up>=InpWickMin*rng)
        {
         ArrayResize(tips,nt+1,256);
         tips[nt].price=r[k].high;
         tips[nt].tol=tol;
         tips[nt].dir=1;
         tips[nt].t=r[k].time;
         tips[nt].tKnown=r[k+1].time;
         tips[nt].tSwept=never;
         for(int j=k+1;j<got;j++)
            if(r[j].high>r[k].high+tol)
              {
               //--- known only once that candle has CLOSED (using its open time would peek one candle ahead)
               tips[nt].tSwept=(j+1<got) ? r[j+1].time : r[j].time;
               break;
              }
         nt++;
        }
      if(dn>=InpWickMin*rng)
        {
         ArrayResize(tips,nt+1,256);
         tips[nt].price=r[k].low;
         tips[nt].tol=tol;
         tips[nt].dir=0;
         tips[nt].t=r[k].time;
         tips[nt].tKnown=r[k+1].time;
         tips[nt].tSwept=never;
         for(int j=k+1;j<got;j++)
            if(r[j].low<r[k].low-tol)
              {
               //--- known only once that candle has CLOSED (using its open time would peek one candle ahead)
               tips[nt].tSwept=(j+1<got) ? r[j+1].time : r[j].time;
               break;
              }
         nt++;
        }
     }
  }

//--- one more trade into the table. key = timeframe mask + 16 x stop class
void AddStat(const int key,const int dir,const bool flag,const bool pick,const int seg,const int si,const int reached,const double cost1x)
  {
   int idx=-1;
   for(int i=0;i<g_nStats;i++)
      if(g_stats[i].mask==key)
        {
         idx=i;
         break;
        }
   if(idx<0)
     {
      ArrayResize(g_stats,g_nStats+1,64);
      idx=g_nStats;
      g_stats[idx].mask=key;
      for(int q=0;q<72;q++)
         g_stats[idx].n[q]=0;
      for(int q=0;q<288;q++)
         g_stats[idx].h[q]=0;
      for(int q=0;q<18;q++)
         g_stats[idx].c[q]=0.0;
      g_nStats++;
     }
   int d=(dir==1) ? 1 : 0;
   int sg=Clamp(seg,0,2);
   for(int v=0;v<3;v++)
     {
      bool use=false;
      if(v==0)
         use=(!g_viewExcl || !flag);
      if(v==1)
         use=flag;
      if(v==2)
         use=pick;
      if(!use)
         continue;
      int base=((v*2+d)*3+sg)*4+si;
      g_stats[idx].n[base]++;
      if(si==2)
         g_stats[idx].c[(v*2+d)*3+sg]+=cost1x;
      for(int l=0;l<reached && l<4;l++)
         g_stats[idx].h[base*4+l]++;
     }
  }

//--- the spread a trader pays today: middle value of the last 2000 candles
double TypicalSpread(const MqlRates &cb[],const int nb)
  {
   int m=MathMin(nb,2000);
   if(m<=0)
      return 0.0;
   double v[];
   ArrayResize(v,m);
   for(int i=0;i<m;i++)
      v[i]=(double)cb[nb-m+i].spread;
   ArraySort(v);
   return v[m/2];
  }

//+------------------------------------------------------------------+
//| Learning layer, shared by every strategy. Nine clues are noted   |
//| the moment price reaches a zone:                                 |
//|  0 where the zone sits in the recent range                       |
//|  1 how many timeframes agree on it                               |
//|  2 how tall the zone is                                          |
//|  3 how fast price is arriving                                    |
//|  4 time of day                                                   |
//|  5 with or against the trend                                     |
//|  6 the strategy's own extra condition (stack, gap, sweep ...)    |
//|  7 quiet or wild market                                          |
//|  8 how old the zone is                                           |
//| It learns from stage 1 of history ONLY which clue values came    |
//| before winners. Stages 2 and 3 are data it never saw.            |
//+------------------------------------------------------------------+
int GOff(const int q)
  {
   switch(q)
     {
      case 0: return 0;
      case 1: return 3;
      case 2: return 6;
      case 3: return 9;
      case 4: return 12;
      case 5: return 16;
      case 6: return 18;
      case 7: return 20;
      default: return 23;
     }
  }

void GenFeat(const int dir,const double lo,const double hi,const int mask,const datetime tz,const bool flag,
             const MqlRates &cb[],const int b,const double atr,int &f[])
  {
   for(int q=0;q<9;q++)
      f[q]=0;
   if(b<20)
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
//--- 1: timeframes that agree
   int nb=Bits(mask);
   f[1]=(nb<=1) ? 0 : ((nb==2) ? 1 : 2);
//--- 2: zone height
   double zh=(atr>0.0) ? (hi-lo)/atr : 0.0;
   f[2]=(zh<0.5) ? 0 : ((zh<1.5) ? 1 : 2);
//--- 3: speed of the approach over the last 10 chart bars
   double sp=0.0;
   if(atr>0.0)
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
//--- 6: the strategy's own extra condition
   f[6]=flag ? 1 : 0;
//--- 7: quiet or wild: the last 14 bars against the last 200
   int lm=MathMin(200,b-1);
   double ls=0.0;
   for(int i=b-lm;i<b;i++)
      ls+=MathMax(cb[i].high,cb[i-1].close)-MathMin(cb[i].low,cb[i-1].close);
   double latr=(lm>0) ? ls/lm : 0.0;
   double vr=(latr>0.0) ? atr/latr : 1.0;
   f[7]=(vr<0.8) ? 0 : ((vr<1.25) ? 1 : 2);
//--- 8: age of the zone, in chart bars
   double age=(g_ps>0) ? (double)((long)cb[b].time-(long)tz)/g_ps : 0.0;
   f[8]=(age<48.0) ? 0 : ((age<240.0) ? 1 : 2);
  }

double GenScore(const int &f[])
  {
   double s=0.0;
   for(int q=0;q<9;q++)
      s+=g_gl[GOff(q)+f[q]];
   return s;
  }

void GenLearn(ZTest &outs[],const int nouts,const int cut)
  {
   int w[26];
   int n[26];
   for(int q=0;q<26;q++)
     {
      w[q]=0;
      n[q]=0;
      g_gl[q]=0.0;
     }
   g_gOk=false;
   if(!g_hasPick[g_strat])
      return;
   int W=0;
   int N=0;
   for(int o=0;o<nouts;o++)
     {
      if(outs[o].half!=0 || !outs[o].done[2] || outs[o].fin2<0 || outs[o].fin2>=cut)
         continue;
      bool win=(outs[o].reached[2]>=2);
      N++;
      if(win)
         W++;
      for(int q=0;q<9;q++)
        {
         int idx=GOff(q)+outs[o].gf[q];
         n[idx]++;
         if(win)
            w[idx]++;
        }
     }
   g_gOk=(N>=60);
   if(g_gOk)
     {
      double base=MathLog((W+1.0)/(N-W+1.0));
      for(int q=0;q<26;q++)
         if(n[q]>=MathMax(InpModelMinN,1))
            g_gl[q]=MathLog((w[q]+1.0)/(n[q]-w[q]+1.0))-base;
     }
   for(int o=0;o<nouts;o++)
     {
      outs[o].gscore=GenScore(outs[o].gf);
      outs[o].pick=(g_gOk && outs[o].gscore>=InpPickScore);
     }
  }

//=== strategy code block 0 ==========================================

ZTip     S0_g_tips[];
int      S0_g_ntips      = 0;
ZTip     S0_g_ltips[];
int      S0_g_lnt        = 0;
long     S0_g_baseSec    = 3600;

//--- how many separate, still-standing rejections sit at / just beyond a zone at time tb
int S0_StackCount(ZTip &tips[],const int nt,const int dir,const double lo,const double hi,
               const datetime tb,const long baseSec,double &price)
  {
   int cnt=0;
   datetime lastT=0;
   price=0.0;
   long maxAge=(long)MathMax(InpStackLookback,10)*baseSec;
   double h=hi-lo;
   for(int i=0;i<nt;i++)
     {
      if(tips[i].dir!=dir || tips[i].tKnown>tb || tips[i].tSwept<=tb)
         continue;
      if((long)tb-(long)tips[i].t>maxAge)
         continue;
      double reach=MathMax(h,2.0*tips[i].tol);
      if(dir==1)
        {
         if(tips[i].price<lo-tips[i].tol || tips[i].price>hi+reach)
            continue;
        }
      else
        {
         if(tips[i].price>hi+tips[i].tol || tips[i].price<lo-reach)
            continue;
        }
      if(cnt>0 && (long)tips[i].t-(long)lastT<3*baseSec)
         continue;
      cnt++;
      lastT=tips[i].t;
      if(cnt==1 || (dir==1 && tips[i].price>price) || (dir==0 && tips[i].price<price))
         price=tips[i].price;
     }
   return cnt;
  }

//+------------------------------------------------------------------+
//| Trap = a failed breakout.                                        |
//|  SELL trap: candle A closes strongly ABOVE the previous high     |
//|  (breakout buyers pile in), then candle B closes back below A's  |
//|  open (the whole move is wiped out). Those buyers are stuck; the |
//|  area they bought in becomes a SELL zone. BUY trap is the mirror.|
//|  i = index of candle B (must be closed).                         |
//+------------------------------------------------------------------+
bool S0_DetectTrap(const MqlRates &r[],const int i,int &dir,double &lo,double &hi)
  {
   int a=i-1;
   int p=i-2;
   if(a<15)
      return false;
   double atr=AtrAt(r,a);
   if(atr<=0.0)
      return false;
   double eps=g_pt/2.0;
   double minBody=MathMax(InpMinBodyATR,0.0)*atr;
   if(r[a].close>r[a].open && r[a].close>r[p].high+eps && (r[a].close-r[a].open)>=minBody && r[i].close<r[a].open-eps)
     {
      dir=1;
      lo=MathMax(r[p].high,r[a].open);
      hi=r[a].close;
      if(hi-lo<=eps)
         lo=r[a].open;
      return (hi-lo>eps);
     }
   if(r[a].close<r[a].open && r[a].close<r[p].low-eps && (r[a].open-r[a].close)>=minBody && r[i].close>r[a].open+eps)
     {
      dir=0;
      hi=MathMin(r[p].low,r[a].open);
      lo=r[a].close;
      if(hi-lo<=eps)
         hi=r[a].open;
      return (hi-lo>eps);
     }
   return false;
  }

void S0_PrepLive(const double price)
  {
   S0_g_lnt=0;
   S0_g_baseSec=PeriodSeconds(g_tf[g_act[0]]);
   MqlRates br[];
   int got=CopyRates(g_sym,g_tf[g_act[0]],0,MathMax(InpStackLookback,10)+20,br);
   if(got>20)
      BuildTips(br,got,S0_g_ltips,S0_g_lnt);
  }

void S0_GenLive(ZGap &gaps[],int &ng,const double price)
  {
   int look=MathMax(g_look,5);
   for(int d=0;d<g_nAct;d++)
     {
      int k=g_act[d];
      MqlRates r[];
      int got=CopyRates(g_sym,g_tf[k],0,look+20,r);
      if(got<20)
         continue;
      for(int i=MathMax(16,got-1-look);i<=got-2;i++)
        {
         int dir=-1;
         double lo=0.0,hi=0.0;
         if(!S0_DetectTrap(r,i,dir,lo,hi))
            continue;
         //--- still fresh? no later closed candle came back to it, and price has not closed through it
         bool dead=false;
         for(int j=i+1;j<got && !dead;j++)
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
            AddGap(gaps,ng,lo,hi,dir,0,k,r[i-1].time,0,0,1,0.0,0.0);
        }
     }
  }

bool S0_LiveInfo(ZBox &z,const double price,string &note,double &lvl)
  {
   double sp=0.0;
   int sc=S0_StackCount(S0_g_ltips,S0_g_lnt,z.dir,z.lo,z.hi,TimeCurrent(),S0_g_baseSec,sp);
   if(sc>=MathMax(InpStackMin,1))
     {
      note="   + REJECTION x"+IntegerToString(sc);
      lvl=sp;
      return true;
     }
   return false;
  }

string S0_ZoneName(const int dir,const int kind)
  {
   return (dir==0) ? "BUY TRAP" : "SELL TRAP";
  }

void S0_PrepHistory(const datetime winStart,const datetime now)
  {
   S0_g_ntips=0;
   S0_g_baseSec=PeriodSeconds(g_tf[g_act[0]]);
   MqlRates br[];
   int got=CopyRates(g_sym,g_tf[g_act[0]],(datetime)((long)winStart-(MathMax(InpStackLookback,10)+20)*S0_g_baseSec),now,br);
   if(got>20)
      BuildTips(br,got,S0_g_tips,S0_g_ntips);
  }

void S0_GenHistory(const datetime winStart,const datetime now,ZGap &gaps[],int &ng)
  {
   int look=MathMax(g_look,5);
   for(int d=0;d<g_nAct;d++)
     {
      int k=g_act[d];
      long tfsec=PeriodSeconds(g_tf[k]);
      MqlRates r[];
      int got=CopyRates(g_sym,g_tf[k],(datetime)((long)winStart-(look+20)*tfsec),now,r);
      if(got<20)
         continue;
      for(int i=16;i<=got-2;i++)
        {
         int dir=-1;
         double lo=0.0,hi=0.0;
         if(!S0_DetectTrap(r,i,dir,lo,hi))
            continue;
         //--- already revisited before the window opened? then it is not a fresh zone
         bool spent=false;
         for(int j=i+1;j<got;j++)
           {
            if((long)r[j].time+tfsec>(long)winStart)
               break;
            if((dir==1 && r[j].high>=lo) || (dir==0 && r[j].low<=hi))
              {
               spent=true;
               break;
              }
           }
         if(!spent)
            AddGap(gaps,ng,lo,hi,dir,0,k,r[i-1].time,r[i+1].time,(datetime)((long)r[i+1].time+look*tfsec),0,0.0,0.0);
        }
     }
  }

void S0_TouchInfo(ZTest &t,ZBox &z,const MqlRates &cb[],const int b,const double atr,const datetime tb)
  {
   double sp=0.0;
   t.flag=(S0_StackCount(S0_g_tips,S0_g_ntips,z.dir,z.lo,z.hi,tb,S0_g_baseSec,sp)>=MathMax(InpStackMin,1));
  }

void S0_PostProcess(ZTest &outs[],const int nouts,const int midBar)
  {
  }

string S0_StatusLine()
  {
   return "";
  }

//=== strategy code block 1 ==========================================
//+------------------------------------------------------------------+
//| Trap = a failed breakout.                                        |
//|  SELL trap: candle A closes strongly ABOVE the previous high     |
//|  (breakout buyers pile in), then candle B closes back below A's  |
//|  open (the whole move is wiped out). Those buyers are stuck; the |
//|  area they bought in becomes a SELL zone. BUY trap is the mirror.|
//|  i = index of candle B (must be closed).                         |
//+------------------------------------------------------------------+
bool S1_DetectTrap(const MqlRates &r[],const int i,int &dir,double &lo,double &hi)
  {
   int a=i-1;
   int p=i-2;
   if(a<15)
      return false;
   double atr=AtrAt(r,a);
   if(atr<=0.0)
      return false;
   double eps=g_pt/2.0;
   double minBody=MathMax(InpMinBodyATR,0.0)*atr;
   if(r[a].close>r[a].open && r[a].close>r[p].high+eps && (r[a].close-r[a].open)>=minBody && r[i].close<r[a].open-eps)
     {
      dir=1;
      lo=MathMax(r[p].high,r[a].open);
      hi=r[a].close;
      if(hi-lo<=eps)
         lo=r[a].open;
      return (hi-lo>eps);
     }
   if(r[a].close<r[a].open && r[a].close<r[p].low-eps && (r[a].open-r[a].close)>=minBody && r[i].close>r[a].open+eps)
     {
      dir=0;
      hi=MathMin(r[p].low,r[a].open);
      lo=r[a].close;
      if(hi-lo<=eps)
         hi=r[a].open;
      return (hi-lo>eps);
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Fair value gaps left INSIDE a trap zone.                         |
//| Only gaps that formed from the trap's breakout candle onwards    |
//| count: they were left by the move that trapped people, and as    |
//| long as the trap is fresh, price has not been back to fill them. |
//| A SELL trap looks for bearish gaps, a BUY trap for bullish ones. |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES S1_g_gtf[3];
bool     S1_g_gshow[3];
ZGap     S1_g_fv[];             // history
int      S1_g_nfv        = 0;
ZGap     S1_g_lfv[];            // live
int      S1_g_nlfv       = 0;

void S1_GapSlots()
  {
   S1_g_gtf[0]=InpGTF1;
   S1_g_gtf[1]=InpGTF2;
   S1_g_gtf[2]=InpGTF3;
   S1_g_gshow[0]=InpGShow1;
   S1_g_gshow[1]=InpGShow2;
   S1_g_gshow[2]=InpGShow3;
  }

bool S1_GapSlotOk(const int s)
  {
   if(!S1_g_gshow[s])
      return false;
   for(int e=0;e<s;e++)
      if(S1_g_gshow[e] && S1_g_gtf[e]==S1_g_gtf[s])
         return false;
   return true;
  }

void S1_ScanGaps(const MqlRates &r[],const int got,const int slot,ZGap &out[],int &n)
  {
   double eps=g_pt/2.0;
//--- i = newest candle of the three; only closed candles form a gap
   for(int i=2;i<=got-2;i++)
     {
      if(r[i].low>r[i-2].high+eps)
         AddGap(out,n,r[i-2].high,r[i].low,0,0,slot,r[i-2].time,r[i+1].time,0,1,0.0,0.0);
      else
         if(r[i].high<r[i-2].low-eps)
            AddGap(out,n,r[i].high,r[i-2].low,1,0,slot,r[i-2].time,r[i+1].time,0,1,0.0,0.0);
     }
  }

//--- how many different gap timeframes cover one price inside the zone [lo,hi] at time tb
int S1_GapCount(ZGap &fv[],const int nfv,const int dir,const double lo,const double hi,const datetime tA,const datetime tb)
  {
   double eps=g_pt/2.0;
   double e[];
   int idx[];
   int ne=0;
   int ni=0;
   for(int g=0;g<nfv;g++)
     {
      if(fv[g].dir!=dir || fv[g].tForm>tb || fv[g].t<tA)
         continue;
      double a=MathMax(fv[g].lo,lo);
      double b=MathMin(fv[g].hi,hi);
      if(b-a<=eps)
         continue;
      ArrayResize(e,ne+2,32);
      e[ne]=a;
      e[ne+1]=b;
      ne+=2;
      ArrayResize(idx,ni+1,16);
      idx[ni]=g;
      ni++;
     }
   if(ni==0)
      return 0;
   ArraySort(e);
   int best=0;
   for(int i=0;i<ne-1;i++)
     {
      if(e[i+1]-e[i]<=eps)
         continue;
      double mid=(e[i]+e[i+1])/2.0;
      int mask=0;
      for(int q=0;q<ni;q++)
        {
         int g=idx[q];
         if(fv[g].lo<mid && fv[g].hi>mid)
            mask|=(1<<fv[g].set);
        }
      int c=0;
      for(int s=0;s<3;s++)
         if((mask&(1<<s))!=0)
            c++;
      if(c>best)
         best=c;
     }
   return best;
  }

void S1_PrepLive(const double price)
  {
   S1_GapSlots();
   S1_g_nlfv=0;
   for(int s=0;s<3;s++)
     {
      if(!S1_GapSlotOk(s))
         continue;
      MqlRates r[];
      int got=CopyRates(g_sym,S1_g_gtf[s],0,5000,r);
      if(got>3)
         S1_ScanGaps(r,got,s,S1_g_lfv,S1_g_nlfv);
     }
  }

void S1_GenLive(ZGap &gaps[],int &ng,const double price)
  {
   int look=MathMax(g_look,5);
   for(int d=0;d<g_nAct;d++)
     {
      int k=g_act[d];
      MqlRates r[];
      int got=CopyRates(g_sym,g_tf[k],0,look+20,r);
      if(got<20)
         continue;
      for(int i=MathMax(16,got-1-look);i<=got-2;i++)
        {
         int dir=-1;
         double lo=0.0,hi=0.0;
         if(!S1_DetectTrap(r,i,dir,lo,hi))
            continue;
         //--- still fresh? no later closed candle came back to it, and price has not closed through it
         bool dead=false;
         for(int j=i+1;j<got && !dead;j++)
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
            AddGap(gaps,ng,lo,hi,dir,0,k,r[i-1].time,0,0,1,0.0,0.0);
        }
     }
  }

bool S1_LiveInfo(ZBox &z,const double price,string &note,double &lvl)
  {
   int c=S1_GapCount(S1_g_lfv,S1_g_nlfv,z.dir,z.lo,z.hi,z.t,TimeCurrent());
   if(c>=MathMax(InpGapMinTF,1))
     {
      note="   + GAP x"+IntegerToString(c);
      return true;
     }
   return false;
  }

string S1_ZoneName(const int dir,const int kind)
  {
   return (dir==0) ? "BUY TRAP" : "SELL TRAP";
  }

void S1_PrepHistory(const datetime winStart,const datetime now)
  {
   S1_GapSlots();
   S1_g_nfv=0;
   for(int s=0;s<3;s++)
     {
      if(!S1_GapSlotOk(s))
         continue;
      long gsec=PeriodSeconds(S1_g_gtf[s]);
      MqlRates r[];
      int got=CopyRates(g_sym,S1_g_gtf[s],(datetime)((long)winStart-2000*gsec),now,r);
      if(got>3)
         S1_ScanGaps(r,got,s,S1_g_fv,S1_g_nfv);
     }
  }

void S1_GenHistory(const datetime winStart,const datetime now,ZGap &gaps[],int &ng)
  {
   int look=MathMax(g_look,5);
   for(int d=0;d<g_nAct;d++)
     {
      int k=g_act[d];
      long tfsec=PeriodSeconds(g_tf[k]);
      MqlRates r[];
      int got=CopyRates(g_sym,g_tf[k],(datetime)((long)winStart-(look+20)*tfsec),now,r);
      if(got<20)
         continue;
      for(int i=16;i<=got-2;i++)
        {
         int dir=-1;
         double lo=0.0,hi=0.0;
         if(!S1_DetectTrap(r,i,dir,lo,hi))
            continue;
         //--- already revisited before the window opened? then it is not a fresh zone
         bool spent=false;
         for(int j=i+1;j<got;j++)
           {
            if((long)r[j].time+tfsec>(long)winStart)
               break;
            if((dir==1 && r[j].high>=lo) || (dir==0 && r[j].low<=hi))
              {
               spent=true;
               break;
              }
           }
         if(!spent)
            AddGap(gaps,ng,lo,hi,dir,0,k,r[i-1].time,r[i+1].time,(datetime)((long)r[i+1].time+look*tfsec),0,0.0,0.0);
        }
     }
  }

void S1_TouchInfo(ZTest &t,ZBox &z,const MqlRates &cb[],const int b,const double atr,const datetime tb)
  {
   t.flag=(S1_GapCount(S1_g_fv,S1_g_nfv,z.dir,z.lo,z.hi,z.t,tb)>=MathMax(InpGapMinTF,1));
  }

void S1_PostProcess(ZTest &outs[],const int nouts,const int midBar)
  {
  }

string S1_StatusLine()
  {
   return "";
  }

//=== strategy code block 2 ==========================================
//+------------------------------------------------------------------+
//| Untouched ground: slice the last W candles into price slices and |
//| count how many candles traded in each one. A run of slices that  |
//| was barely visited, sitting BETWEEN heavily traded slices, is a  |
//| zone: price went through it once, fast, and never came back.     |
//| Returns the runs found on the candles up to and including c.     |
//+------------------------------------------------------------------+
int S2_ThinRuns(const MqlRates &r[],const int c,const int W,double &rl[],double &rh[])
  {
   int from=c-W+1;
   if(from<15)
      return 0;
   double atr=AtrAt(r,c);
   if(atr<=0.0)
      return 0;
   double hh=r[from].high;
   double ll=r[from].low;
   for(int i=from+1;i<=c;i++)
     {
      if(r[i].high>hh)
         hh=r[i].high;
      if(r[i].low<ll)
         ll=r[i].low;
     }
   double bin=MathMax(InpBinATR,0.05)*atr;
   int nbin=(int)MathCeil((hh-ll)/bin);
   if(nbin<6)
      return 0;
   if(nbin>400)
     {
      nbin=400;
      bin=(hh-ll)/400.0;
     }
   int v[];
   ArrayResize(v,nbin);
   ArrayInitialize(v,0);
   for(int i=from;i<=c;i++)
     {
      int b0=Clamp((int)MathFloor((r[i].low-ll)/bin),0,nbin-1);
      int b1=Clamp((int)MathFloor((r[i].high-ll)/bin),0,nbin-1);
      for(int q=b0;q<=b1;q++)
         v[q]++;
     }
   int thick=MathMax(InpThickMin,2);
   int thin=MathMax(InpThinMax,0);
   int firstT=-1;
   int lastT=-1;
   for(int q=0;q<nbin;q++)
      if(v[q]>=thick)
        {
         if(firstT<0)
            firstT=q;
         lastT=q;
        }
   if(firstT<0 || lastT<=firstT)
      return 0;
   int n=0;
   int minLen=MathMax(InpRunMin,1);
   int maxLen=MathMax(InpRunMax,minLen);
   int q=firstT+1;
   while(q<lastT)
     {
      if(v[q]<=thin)
        {
         int s=q;
         while(q<lastT && v[q]<=thin)
            q++;
         int len=q-s;
         if(len>=minLen && len<=maxLen)
           {
            ArrayResize(rl,n+1,16);
            ArrayResize(rh,n+1,16);
            rl[n]=ll+s*bin;
            rh[n]=ll+q*bin;
            n++;
           }
        }
      else
         q++;
     }
   return n;
  }

void S2_PrepLive(const double price)
  {
  }

void S2_GenLive(ZGap &gaps[],int &ng,const double price)
  {
   int W=MathMax(InpWindow,30);
   for(int d=0;d<g_nAct;d++)
     {
      int k=g_act[d];
      MqlRates r[];
      int got=CopyRates(g_sym,g_tf[k],0,W+40,r);
      if(got<W+20)
         continue;
      int c=got-2;
      double rl[],rh[];
      int n=S2_ThinRuns(r,c,W,rl,rh);
      for(int i=0;i<n;i++)
        {
         //--- the candle still forming must not already be inside it
         if(r[got-1].high>=rl[i] && r[got-1].low<=rh[i])
            continue;
         int dir=-1;
         if(rl[i]>price)
            dir=1;
         if(rh[i]<price)
            dir=0;
         if(dir<0)
            continue;
         AddGap(gaps,ng,rl[i],rh[i],dir,0,k,r[MathMax(c-20,0)].time,0,0,1,0.0,0.0);
        }
     }
  }

bool S2_LiveInfo(ZBox &z,const double price,string &note,double &lvl)
  {
   return false;
  }

string S2_ZoneName(const int dir,const int kind)
  {
   return (dir==0) ? "BUY UNTOUCHED" : "SELL UNTOUCHED";
  }

void S2_PrepHistory(const datetime winStart,const datetime now)
  {
  }

void S2_GenHistory(const datetime winStart,const datetime now,ZGap &gaps[],int &ng)
  {
   int W=MathMax(InpWindow,30);
   int look=MathMax(g_look,5);
   double eps=g_pt/2.0;
   for(int d=0;d<g_nAct;d++)
     {
      int k=g_act[d];
      long tfsec=PeriodSeconds(g_tf[k]);
      MqlRates r[];
      int got=CopyRates(g_sym,g_tf[k],(datetime)((long)winStart-(W+40)*tfsec),now,r);
      if(got<W+20)
         continue;
      double pl[],phh[];
      int pn=0;
      bool first=true;
      for(int c=W+15;c<=got-2;c++)
        {
         double rl[],rh[];
         int n=S2_ThinRuns(r,c,W,rl,rh);
         if(!first && r[c+1].time>=winStart)
            for(int i=0;i<n;i++)
              {
               //--- only a zone that was not there one candle earlier is a new event
               bool seen=false;
               for(int j=0;j<pn;j++)
                  if(pl[j]<rh[i]-eps && phh[j]>rl[i]+eps)
                    {
                     seen=true;
                     break;
                    }
               if(seen)
                  continue;
               int dir=-1;
               if(rl[i]>r[c].close)
                  dir=1;
               if(rh[i]<r[c].close)
                  dir=0;
               if(dir<0)
                  continue;
               AddGap(gaps,ng,rl[i],rh[i],dir,0,k,r[c].time,r[c+1].time,(datetime)((long)r[c+1].time+look*tfsec),0,0.0,0.0);
              }
         ArrayResize(pl,MathMax(n,1));
         ArrayResize(phh,MathMax(n,1));
         for(int i=0;i<n;i++)
           {
            pl[i]=rl[i];
            phh[i]=rh[i];
           }
         pn=n;
         first=false;
        }
     }
  }

void S2_TouchInfo(ZTest &t,ZBox &z,const MqlRates &cb[],const int b,const double atr,const datetime tb)
  {
  }

void S2_PostProcess(ZTest &outs[],const int nouts,const int midBar)
  {
  }

string S2_StatusLine()
  {
   return "";
  }

//=== strategy code block 3 ==========================================

//+------------------------------------------------------------------+
//| A stack = several separate rejections at (almost) the same price |
//| that price has not broken since. Every stack gives two zones:    |
//|  kind 0 "bounce": price reaches the stack and turns again         |
//|  kind 1 "sweep" : price pokes just past it (taking the stops     |
//|                    resting there) and turns from beyond it        |
//+------------------------------------------------------------------+
int S3_ClusterAt(ZTip &tips[],const int nt,const int a,const datetime ta,const long tfsec,double &minP,double &maxP)
  {
   int cnt=0;
   datetime lastT=0;
   long maxAge=(long)MathMax(InpStackLookback,10)*tfsec;
   minP=tips[a].price;
   maxP=tips[a].price;
   for(int i=0;i<nt;i++)
     {
      if(tips[i].dir!=tips[a].dir || tips[i].tKnown>ta || tips[i].tSwept<=ta)
         continue;
      if((long)ta-(long)tips[i].t>maxAge)
         continue;
      if(MathAbs(tips[i].price-tips[a].price)>tips[a].tol)
         continue;
      if(cnt>0 && (long)tips[i].t-(long)lastT<3*tfsec)
         continue;
      cnt++;
      lastT=tips[i].t;
      if(tips[i].price<minP)
         minP=tips[i].price;
      if(tips[i].price>maxP)
         maxP=tips[i].price;
     }
   return cnt;
  }

void S3_EmitStack(ZGap &gaps[],int &ng,const int k,const int dir,const double minP,const double maxP,const double tol,
               const datetime t,const datetime tForm,const datetime tExp,const int state)
  {
   double eps=g_pt/2.0;
   if(tol<=eps)
      return;
   if(dir==1)
     {
      AddGap(gaps,ng,minP-tol,maxP,1,0,k,t,tForm,tExp,state,0.0,0.0);
      AddGap(gaps,ng,maxP+tol,maxP+3.0*tol,1,1,k,t,tForm,tExp,state,0.0,0.0);
     }
   else
     {
      AddGap(gaps,ng,minP,maxP+tol,0,0,k,t,tForm,tExp,state,0.0,0.0);
      AddGap(gaps,ng,minP-3.0*tol,minP-tol,0,1,k,t,tForm,tExp,state,0.0,0.0);
     }
  }

void S3_PrepLive(const double price)
  {
  }

void S3_GenLive(ZGap &gaps[],int &ng,const double price)
  {
   datetime now=TimeCurrent();
   int need=MathMax(InpStackMin,1);
   for(int d=0;d<g_nAct;d++)
     {
      int k=g_act[d];
      long tfsec=PeriodSeconds(g_tf[k]);
      MqlRates r[];
      int got=CopyRates(g_sym,g_tf[k],0,MathMax(InpStackLookback,10)+20,r);
      if(got<=20)
         continue;
      ZTip tips[];
      int nt=0;
      BuildTips(r,got,tips,nt);
      for(int a=0;a<nt;a++)
        {
         if(tips[a].tSwept<=now)
            continue;
         double minP=0.0,maxP=0.0;
         if(S3_ClusterAt(tips,nt,a,now,tfsec,minP,maxP)<need)
            continue;
         //--- price must still be on the right side of the stack
         if((tips[a].dir==1 && price>maxP) || (tips[a].dir==0 && price<minP))
            continue;
         S3_EmitStack(gaps,ng,k,tips[a].dir,minP,maxP,tips[a].tol,tips[a].t,0,0,1);
        }
     }
  }

bool S3_LiveInfo(ZBox &z,const double price,string &note,double &lvl)
  {
   return (z.kind==1);
  }

string S3_ZoneName(const int dir,const int kind)
  {
   if(kind==1)
      return (dir==0) ? "BUY SWEEP" : "SELL SWEEP";
   return (dir==0) ? "BUY STACK" : "SELL STACK";
  }

void S3_PrepHistory(const datetime winStart,const datetime now)
  {
  }

void S3_GenHistory(const datetime winStart,const datetime now,ZGap &gaps[],int &ng)
  {
   int look=MathMax(g_look,5);
   int need=MathMax(InpStackMin,1);
   for(int d=0;d<g_nAct;d++)
     {
      int k=g_act[d];
      long tfsec=PeriodSeconds(g_tf[k]);
      MqlRates r[];
      int got=CopyRates(g_sym,g_tf[k],(datetime)((long)winStart-(MathMax(InpStackLookback,10)+20)*tfsec),now,r);
      if(got<=20)
         continue;
      ZTip tips[];
      int nt=0;
      BuildTips(r,got,tips,nt);
      for(int a=0;a<nt;a++)
        {
         datetime ta=tips[a].tKnown;
         if(ta<winStart || tips[a].tSwept<=ta)
            continue;
         double minP=0.0,maxP=0.0;
         if(S3_ClusterAt(tips,nt,a,ta,tfsec,minP,maxP)<need)
            continue;
         S3_EmitStack(gaps,ng,k,tips[a].dir,minP,maxP,tips[a].tol,tips[a].t,ta,(datetime)((long)ta+look*tfsec),0);
        }
     }
  }

void S3_TouchInfo(ZTest &t,ZBox &z,const MqlRates &cb[],const int b,const double atr,const datetime tb)
  {
   t.flag=(z.kind==1);
  }

void S3_PostProcess(ZTest &outs[],const int nouts,const int midBar)
  {
  }

string S3_StatusLine()
  {
   return "";
  }

//=== strategy code block 4 ==========================================
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
double   S4_g_lift[18];
int      S4_g_trainN     = 0;
int      S4_g_trainW     = 0;
bool     S4_g_modelOk    = false;
MqlRates S4_g_lcb[];
int      S4_g_ln         = 0;
double   S4_g_latr       = 0.0;

int S4_FOff(const int q)
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

void S4_Features(const int dir,const double lo,const double hi,const double wick,const datetime tPiv,const double tfsec,
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

double S4_ModelScore(const int &f[])
  {
   double s=0.0;
   for(int q=0;q<6;q++)
      s+=S4_g_lift[S4_FOff(q)+f[q]];
   return s;
  }

bool S4_IsPivot(const MqlRates &r[],const int i,const int dir)
  {
   if(dir==1)
      return (r[i].high>r[i-1].high && r[i].high>r[i-2].high && r[i].high>=r[i+1].high && r[i].high>=r[i+2].high);
   return (r[i].low<r[i-1].low && r[i].low<r[i-2].low && r[i].low<=r[i+1].low && r[i].low<=r[i+2].low);
  }

double S4_WickShare(const MqlRates &r[],const int i,const int dir)
  {
   double rng=r[i].high-r[i].low;
   if(rng<=0.0)
      return 0.0;
   if(dir==1)
      return (r[i].high-MathMax(r[i].open,r[i].close))/rng;
   return (MathMin(r[i].open,r[i].close)-r[i].low)/rng;
  }

void S4_PrepLive(const double price)
  {
   S4_g_ln=CopyRates(g_sym,g_per,0,MathMax(InpRangeBars,MathMax(InpTrendBars,20))+30,S4_g_lcb);
   S4_g_latr=(S4_g_ln>20) ? AtrAt(S4_g_lcb,S4_g_ln-1) : 0.0;
  }

void S4_GenLive(ZGap &gaps[],int &ng,const double price)
  {
   int look=MathMax(g_look,5);
   double eps=g_pt/2.0;
   for(int d=0;d<g_nAct;d++)
     {
      int k=g_act[d];
      double tfsec=(double)PeriodSeconds(g_tf[k]);
      MqlRates r[];
      int got=CopyRates(g_sym,g_tf[k],0,look+25,r);
      if(got<25)
         continue;
      for(int i=MathMax(17,got-1-look);i<=got-4;i++)
         for(int dir=0;dir<2;dir++)
           {
            if(!S4_IsPivot(r,i,dir))
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
               AddGap(gaps,ng,lo,hi,dir,0,k,r[i].time,0,0,1,S4_WickShare(r,i,dir),tfsec);
           }
     }
  }

bool S4_LiveInfo(ZBox &z,const double price,string &note,double &lvl)
  {
   if(S4_g_ln<30 || !S4_g_modelOk)
      return false;
   int f[6];
   S4_Features(z.dir,z.lo,z.hi,z.aux1,z.t,z.aux2,S4_g_lcb,S4_g_ln-1,S4_g_latr,f);
   double s=S4_ModelScore(f);
   note="   score "+((s>=0.0) ? "+" : "")+DoubleToString(s,2);
   return (s>=InpPickScore);
  }

string S4_ZoneName(const int dir,const int kind)
  {
   return (dir==0) ? "BUY LEVEL" : "SELL LEVEL";
  }

void S4_PrepHistory(const datetime winStart,const datetime now)
  {
  }

void S4_GenHistory(const datetime winStart,const datetime now,ZGap &gaps[],int &ng)
  {
   int look=MathMax(g_look,5);
   double eps=g_pt/2.0;
   for(int d=0;d<g_nAct;d++)
     {
      int k=g_act[d];
      long tfs=PeriodSeconds(g_tf[k]);
      MqlRates r[];
      int got=CopyRates(g_sym,g_tf[k],(datetime)((long)winStart-25*tfs),now,r);
      if(got<25)
         continue;
      for(int i=17;i<=got-4;i++)
        {
         if(r[i+3].time<winStart)
            continue;
         for(int dir=0;dir<2;dir++)
           {
            if(!S4_IsPivot(r,i,dir))
               continue;
            double z=MathMax(InpZoneATR,0.02)*AtrAt(r,i);
            if(z<=eps)
               continue;
            double lo=(dir==1) ? r[i].high-z : r[i].low;
            double hi=(dir==1) ? r[i].high : r[i].low+z;
            AddGap(gaps,ng,lo,hi,dir,0,k,r[i].time,r[i+3].time,(datetime)((long)r[i+3].time+look*tfs),0,S4_WickShare(r,i,dir),(double)tfs);
           }
        }
     }
  }

void S4_TouchInfo(ZTest &t,ZBox &z,const MqlRates &cb[],const int b,const double atr,const datetime tb)
  {
   S4_Features(z.dir,z.lo,z.hi,z.aux1,z.t,z.aux2,cb,b,atr,t.f);
  }

//--- learn from the older half only, then score every trade
void S4_PostProcess(ZTest &outs[],const int nouts,const int midBar)
  {
   int w[18];
   int n[18];
   for(int q=0;q<18;q++)
     {
      w[q]=0;
      n[q]=0;
      S4_g_lift[q]=0.0;
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
         int idx=S4_FOff(q)+outs[o].f[q];
         n[idx]++;
         if(win)
            w[idx]++;
        }
     }
   S4_g_trainN=N;
   S4_g_trainW=W;
   S4_g_modelOk=(N>=50);
   if(S4_g_modelOk)
     {
      double base=MathLog((W+1.0)/(N-W+1.0));
      for(int q=0;q<18;q++)
         if(n[q]>=MathMax(InpModelMinN,1))
            S4_g_lift[q]=MathLog((w[q]+1.0)/(n[q]-w[q]+1.0))-base;
     }
   for(int o=0;o<nouts;o++)
     {
      outs[o].score=S4_ModelScore(outs[o].f);
      outs[o].flag=(S4_g_modelOk && outs[o].score>=InpPickScore);
      if(g_bandOn && S4_g_modelOk && outs[o].done[2])
        {
         int bi=((g_bandStrat*NSC+g_curScale)*5+BandOf(outs[o].score))*3+Clamp(outs[o].half,0,2);
         g_bandN[bi]++;
         for(int l=0;l<outs[o].reached[2] && l<4;l++)
            g_bandH[bi*4+l]++;
        }
     }
  }

string S4_StatusLine()
  {
   if(!g_scoreOk)
      return "Model: loading history";
   if(!S4_g_modelOk)
      return "Model: too few older trades to learn from yet";
   return "Model: learned from "+IntegerToString(S4_g_trainN)+" older trades, base win "+
          IntegerToString((int)MathRound(100.0*S4_g_trainW/MathMax(S4_g_trainN,1)))+"%";
  }

//=== strategy code block 5 ==========================================
//+------------------------------------------------------------------+
//| Fair value gaps (the zones of the first indicator).              |
//| Three candles: if the third candle's low is above the first      |
//| candle's high, the space between them was never traded both ways |
//| = a BUY gap. The mirror is a SELL gap. Gaps on different         |
//| timeframes that overlap merge into one confluence zone.          |
//| i = index of the third candle (must be closed).                  |
//+------------------------------------------------------------------+
bool S5_DetectFvg(const MqlRates &r[],const int i,int &dir,double &lo,double &hi)
  {
   if(i<16)
      return false;
   double atr=AtrAt(r,i);
   if(atr<=0.0)
      return false;
   double eps=g_pt/2.0;
   double minH=MathMax(InpFvgMinATR,0.0)*atr;
   if(r[i].low>r[i-2].high+eps && (r[i].low-r[i-2].high)>=minH)
     {
      dir=0;
      lo=r[i-2].high;
      hi=r[i].low;
      return true;
     }
   if(r[i].high<r[i-2].low-eps && (r[i-2].low-r[i].high)>=minH)
     {
      dir=1;
      lo=r[i].high;
      hi=r[i-2].low;
      return true;
     }
   return false;
  }

void S5_PrepLive(const double price)
  {
  }

void S5_GenLive(ZGap &gaps[],int &ng,const double price)
  {
   int look=MathMax(g_look,5);
   for(int d=0;d<g_nAct;d++)
     {
      int k=g_act[d];
      MqlRates r[];
      int got=CopyRates(g_sym,g_tf[k],0,look+20,r);
      if(got<20)
         continue;
      for(int i=MathMax(16,got-1-look);i<=got-2;i++)
        {
         int dir=-1;
         double lo=0.0,hi=0.0;
         if(!S5_DetectFvg(r,i,dir,lo,hi))
            continue;
         bool dead=false;
         for(int j=i+1;j<got && !dead;j++)
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
            AddGap(gaps,ng,lo,hi,dir,0,k,r[i-1].time,0,0,1,0.0,0.0);
        }
     }
  }

bool S5_LiveInfo(ZBox &z,const double price,string &note,double &lvl)
  {
   if(Bits(z.mask)>=2)
     {
      note="   + CONFLUENCE";
      return true;
     }
   return false;
  }

string S5_ZoneName(const int dir,const int kind)
  {
   return (dir==0) ? "BUY GAP" : "SELL GAP";
  }

void S5_PrepHistory(const datetime winStart,const datetime now)
  {
  }

void S5_GenHistory(const datetime winStart,const datetime now,ZGap &gaps[],int &ng)
  {
   int look=MathMax(g_look,5);
   for(int d=0;d<g_nAct;d++)
     {
      int k=g_act[d];
      long tfsec=PeriodSeconds(g_tf[k]);
      MqlRates r[];
      int got=CopyRates(g_sym,g_tf[k],(datetime)((long)winStart-(look+20)*tfsec),now,r);
      if(got<20)
         continue;
      for(int i=16;i<=got-2;i++)
        {
         int dir=-1;
         double lo=0.0,hi=0.0;
         if(!S5_DetectFvg(r,i,dir,lo,hi))
            continue;
         //--- already revisited before the window opened? then it is not a fresh gap
         bool spent=false;
         for(int j=i+1;j<got;j++)
           {
            if((long)r[j].time+tfsec>(long)winStart)
               break;
            if((dir==1 && r[j].high>=lo) || (dir==0 && r[j].low<=hi))
              {
               spent=true;
               break;
              }
           }
         if(!spent)
            AddGap(gaps,ng,lo,hi,dir,0,k,r[i-1].time,r[i+1].time,(datetime)((long)r[i+1].time+look*tfsec),0,0.0,0.0);
        }
     }
  }

void S5_TouchInfo(ZTest &t,ZBox &z,const MqlRates &cb[],const int b,const double atr,const datetime tb)
  {
   t.flag=(Bits(z.mask)>=2);
  }

void S5_PostProcess(ZTest &outs[],const int nouts,const int midBar)
  {
  }

//=== strategy code block 6 ==========================================
//+------------------------------------------------------------------+
//| Flip levels: the opposite idea to every other strategy here.     |
//| A swing high that price then CLOSES above, with a strong candle, |
//| has flipped: old ceiling, new floor. The first return to it is a |
//| BUY (go with the break, do not fade it). A broken swing low      |
//| becomes a SELL zone the same way.                                |
//+------------------------------------------------------------------+
bool S6_FlipPivot(const MqlRates &r[],const int i,const int dir)
  {
   if(dir==1)
      return (r[i].high>r[i-1].high && r[i].high>r[i-2].high && r[i].high>=r[i+1].high && r[i].high>=r[i+2].high);
   return (r[i].low<r[i-1].low && r[i].low<r[i-2].low && r[i].low<=r[i+1].low && r[i].low<=r[i+2].low);
  }

//--- the first CLOSED candle that closes through swing i; -1 if none, or if that first break was a weak candle
int S6_BreakBar(const MqlRates &r[],const int got,const int i,const int dir,const int look)
  {
   double eps=g_pt/2.0;
   for(int j=i+3;j<=got-2 && j<=i+look;j++)
     {
      bool through=(dir==1) ? (r[j].close>r[i].high+eps) : (r[j].close<r[i].low-eps);
      if(!through)
         continue;
      double atr=AtrAt(r,j);
      if(atr<=0.0)
         return -1;
      if(MathAbs(r[j].close-r[j].open)<MathMax(InpFlipBodyATR,0.0)*atr)
         return -1;
      return j;
     }
   return -1;
  }

void S6_PrepLive(const double price)
  {
  }

void S6_GenLive(ZGap &gaps[],int &ng,const double price)
  {
   int look=MathMax(g_look,5);
   double eps=g_pt/2.0;
   for(int d=0;d<g_nAct;d++)
     {
      int k=g_act[d];
      MqlRates r[];
      int got=CopyRates(g_sym,g_tf[k],0,2*look+25,r);
      if(got<25)
         continue;
      for(int i=17;i<=got-5;i++)
         for(int pd=0;pd<2;pd++)
           {
            if(!S6_FlipPivot(r,i,pd))
               continue;
            int j=S6_BreakBar(r,got,i,pd,look);
            if(j<0 || got-2-j>look)
               continue;
            double z=MathMax(InpZoneATR,0.02)*AtrAt(r,j);
            if(z<=eps)
               continue;
            int dir=(pd==1) ? 0 : 1;                  // broken high = buy zone, broken low = sell zone
            double lo=(pd==1) ? r[i].high-z : r[i].low;
            double hi=(pd==1) ? r[i].high : r[i].low+z;
            bool dead=false;
            for(int m=j+1;m<got && !dead;m++)
              {
               bool closed=(m<=got-2);
               if(dir==1)
                 {
                  if(r[m].close>hi || (closed && r[m].high>=lo))
                     dead=true;
                 }
               else
                 {
                  if(r[m].close<lo || (closed && r[m].low<=hi))
                     dead=true;
                 }
              }
            if(!dead)
               AddGap(gaps,ng,lo,hi,dir,0,k,r[i].time,0,0,1,0.0,0.0);
           }
     }
  }

bool S6_LiveInfo(ZBox &z,const double price,string &note,double &lvl)
  {
   return false;
  }

string S6_ZoneName(const int dir,const int kind)
  {
   return (dir==0) ? "BUY FLIP" : "SELL FLIP";
  }

void S6_PrepHistory(const datetime winStart,const datetime now)
  {
  }

void S6_GenHistory(const datetime winStart,const datetime now,ZGap &gaps[],int &ng)
  {
   int look=MathMax(g_look,5);
   double eps=g_pt/2.0;
   for(int d=0;d<g_nAct;d++)
     {
      int k=g_act[d];
      long tfs=PeriodSeconds(g_tf[k]);
      MqlRates r[];
      int got=CopyRates(g_sym,g_tf[k],(datetime)((long)winStart-(look+25)*tfs),now,r);
      if(got<25)
         continue;
      for(int i=17;i<=got-5;i++)
         for(int pd=0;pd<2;pd++)
           {
            if(!S6_FlipPivot(r,i,pd))
               continue;
            int j=S6_BreakBar(r,got,i,pd,look);
            if(j<0 || r[j+1].time<winStart)
               continue;
            double z=MathMax(InpZoneATR,0.02)*AtrAt(r,j);
            if(z<=eps)
               continue;
            int dir=(pd==1) ? 0 : 1;
            double lo=(pd==1) ? r[i].high-z : r[i].low;
            double hi=(pd==1) ? r[i].high : r[i].low+z;
            AddGap(gaps,ng,lo,hi,dir,0,k,r[i].time,r[j+1].time,(datetime)((long)r[j+1].time+look*tfs),0,0.0,0.0);
           }
     }
  }

void S6_TouchInfo(ZTest &t,ZBox &z,const MqlRates &cb[],const int b,const double atr,const datetime tb)
  {
  }

void S6_PostProcess(ZTest &outs[],const int nouts,const int midBar)
  {
  }

//=== strategy code block 7 ==========================================
//+------------------------------------------------------------------+
//| Stretch bands: no chart pattern at all, only distance.           |
//| Each candle, measure the average price of the last N candles and |
//| the normal candle size (ATR). A band sits K normal candles above |
//| and below that average. Price reaching the upper band is         |
//| stretched far from normal = SELL zone; lower band = BUY zone.    |
//| The band is redrawn every candle, so each zone lives one candle. |
//+------------------------------------------------------------------+
bool S7_Band(const MqlRates &r[],const int c,double &sma,double &atr)
  {
   int n=MathMax(InpStretchBars,5);
   if(c<n+15)
      return false;
   double s=0.0;
   for(int i=c-n+1;i<=c;i++)
      s+=r[i].close;
   sma=s/n;
   atr=AtrAt(r,c+1);
   return (atr>0.0);
  }

void S7_EmitBands(ZGap &gaps[],int &ng,const MqlRates &r[],const int c,const int k,const datetime tForm,const datetime tExp,const int state)
  {
   double sma=0.0,atr=0.0;
   if(!S7_Band(r,c,sma,atr))
      return;
   double kk=MathMax(InpStretchATR,0.5);
   double w=MathMax(InpStretchWidth,0.05)*atr;
   double up=sma+kk*atr;
   double dn=sma-kk*atr;
//--- only bands price could reach within the next candle or two, and has not already closed beyond
   if(r[c].close<up && up-r[c].close<=2.0*atr)
      AddGap(gaps,ng,up,up+w,1,0,k,r[c].time,tForm,tExp,state,0.0,0.0);
   if(r[c].close>dn && r[c].close-dn<=2.0*atr)
      AddGap(gaps,ng,dn-w,dn,0,0,k,r[c].time,tForm,tExp,state,0.0,0.0);
  }

void S7_PrepLive(const double price)
  {
  }

void S7_GenLive(ZGap &gaps[],int &ng,const double price)
  {
   for(int d=0;d<g_nAct;d++)
     {
      int k=g_act[d];
      MqlRates r[];
      int need=MathMax(InpStretchBars,5)+40;
      int got=CopyRates(g_sym,g_tf[k],0,need,r);
      if(got<need-5)
         continue;
      S7_EmitBands(gaps,ng,r,got-2,k,0,0,1);
     }
  }

bool S7_LiveInfo(ZBox &z,const double price,string &note,double &lvl)
  {
   return false;
  }

string S7_ZoneName(const int dir,const int kind)
  {
   return (dir==0) ? "BUY STRETCH" : "SELL STRETCH";
  }

void S7_PrepHistory(const datetime winStart,const datetime now)
  {
  }

void S7_GenHistory(const datetime winStart,const datetime now,ZGap &gaps[],int &ng)
  {
   for(int d=0;d<g_nAct;d++)
     {
      int k=g_act[d];
      long tfs=PeriodSeconds(g_tf[k]);
      int pre=MathMax(InpStretchBars,5)+40;
      MqlRates r[];
      int got=CopyRates(g_sym,g_tf[k],(datetime)((long)winStart-pre*tfs),now,r);
      if(got<pre)
         continue;
      for(int c=MathMax(InpStretchBars,5)+15;c<=got-2;c++)
        {
         if(r[c+1].time<winStart)
            continue;
         S7_EmitBands(gaps,ng,r,c,k,r[c+1].time,(datetime)((long)r[c+1].time+tfs),0);
        }
     }
  }

void S7_TouchInfo(ZTest &t,ZBox &z,const MqlRates &cb[],const int b,const double atr,const datetime tb)
  {
  }

void S7_PostProcess(ZTest &outs[],const int nouts,const int midBar)
  {
  }

//--- route each call to the strategy being tested ------------------------
void PrepLive(const double price)
  {
   switch(g_strat)
     {
      case 0: S0_PrepLive(price); return;
      case 1: S1_PrepLive(price); return;
      case 2: S2_PrepLive(price); return;
      case 3: S3_PrepLive(price); return;
      case 4: S4_PrepLive(price); return;
      case 5: S4_PrepLive(price); return;
      case 6: S5_PrepLive(price); return;
      case 7: S6_PrepLive(price); return;
      case 8: S7_PrepLive(price); return;
     }
  }

void GenLive(ZGap &gaps[],int &ng,const double price)
  {
   switch(g_strat)
     {
      case 0: S0_GenLive(gaps,ng,price); return;
      case 1: S1_GenLive(gaps,ng,price); return;
      case 2: S2_GenLive(gaps,ng,price); return;
      case 3: S3_GenLive(gaps,ng,price); return;
      case 4: S4_GenLive(gaps,ng,price); return;
      case 5: S4_GenLive(gaps,ng,price); return;
      case 6: S5_GenLive(gaps,ng,price); return;
      case 7: S6_GenLive(gaps,ng,price); return;
      case 8: S7_GenLive(gaps,ng,price); return;
     }
  }

bool LiveInfo(ZBox &z,const double price,string &note,double &lvl)
  {
   switch(g_strat)
     {
      case 0: return S0_LiveInfo(z,price,note,lvl);
      case 1: return S1_LiveInfo(z,price,note,lvl);
      case 2: return S2_LiveInfo(z,price,note,lvl);
      case 3: return S3_LiveInfo(z,price,note,lvl);
      case 4: return S4_LiveInfo(z,price,note,lvl);
      case 5: return S4_LiveInfo(z,price,note,lvl);
      case 6: return S5_LiveInfo(z,price,note,lvl);
      case 7: return S6_LiveInfo(z,price,note,lvl);
      case 8: return S7_LiveInfo(z,price,note,lvl);
     }
   return false;
  }

string ZoneName(const int dir,const int kind)
  {
   switch(g_strat)
     {
      case 0: return S0_ZoneName(dir,kind);
      case 1: return S1_ZoneName(dir,kind);
      case 2: return S2_ZoneName(dir,kind);
      case 3: return S3_ZoneName(dir,kind);
      case 4: return S4_ZoneName(dir,kind);
      case 5: return S4_ZoneName(dir,kind);
      case 6: return S5_ZoneName(dir,kind);
      case 7: return S6_ZoneName(dir,kind);
      case 8: return S7_ZoneName(dir,kind);
     }
   return "";
  }

void PrepHistory(const datetime winStart,const datetime now)
  {
   switch(g_strat)
     {
      case 0: S0_PrepHistory(winStart,now); return;
      case 1: S1_PrepHistory(winStart,now); return;
      case 2: S2_PrepHistory(winStart,now); return;
      case 3: S3_PrepHistory(winStart,now); return;
      case 4: S4_PrepHistory(winStart,now); return;
      case 5: S4_PrepHistory(winStart,now); return;
      case 6: S5_PrepHistory(winStart,now); return;
      case 7: S6_PrepHistory(winStart,now); return;
      case 8: S7_PrepHistory(winStart,now); return;
     }
  }

void GenHistory(const datetime winStart,const datetime now,ZGap &gaps[],int &ng)
  {
   switch(g_strat)
     {
      case 0: S0_GenHistory(winStart,now,gaps,ng); return;
      case 1: S1_GenHistory(winStart,now,gaps,ng); return;
      case 2: S2_GenHistory(winStart,now,gaps,ng); return;
      case 3: S3_GenHistory(winStart,now,gaps,ng); return;
      case 4: S4_GenHistory(winStart,now,gaps,ng); return;
      case 5: S4_GenHistory(winStart,now,gaps,ng); return;
      case 6: S5_GenHistory(winStart,now,gaps,ng); return;
      case 7: S6_GenHistory(winStart,now,gaps,ng); return;
      case 8: S7_GenHistory(winStart,now,gaps,ng); return;
     }
  }

void TouchInfo(ZTest &t,ZBox &z,const MqlRates &cb[],const int b,const double atr,const datetime tb)
  {
   switch(g_strat)
     {
      case 0: S0_TouchInfo(t,z,cb,b,atr,tb); return;
      case 1: S1_TouchInfo(t,z,cb,b,atr,tb); return;
      case 2: S2_TouchInfo(t,z,cb,b,atr,tb); return;
      case 3: S3_TouchInfo(t,z,cb,b,atr,tb); return;
      case 4: S4_TouchInfo(t,z,cb,b,atr,tb); return;
      case 5: S4_TouchInfo(t,z,cb,b,atr,tb); return;
      case 6: S5_TouchInfo(t,z,cb,b,atr,tb); return;
      case 7: S6_TouchInfo(t,z,cb,b,atr,tb); return;
      case 8: S7_TouchInfo(t,z,cb,b,atr,tb); return;
     }
  }

void PostProcess(ZTest &outs[],const int nouts,const int midBar)
  {
   switch(g_strat)
     {
      case 0: S0_PostProcess(outs,nouts,midBar); return;
      case 1: S1_PostProcess(outs,nouts,midBar); return;
      case 2: S2_PostProcess(outs,nouts,midBar); return;
      case 3: S3_PostProcess(outs,nouts,midBar); return;
      case 4: S4_PostProcess(outs,nouts,midBar); return;
      case 5: S4_PostProcess(outs,nouts,midBar); return;
      case 6: S5_PostProcess(outs,nouts,midBar); return;
      case 7: S6_PostProcess(outs,nouts,midBar); return;
      case 8: S7_PostProcess(outs,nouts,midBar); return;
     }
  }

void RunScore()
  {
   g_nStats=0;
   ArrayResize(g_stats,0);
   g_scoreOk=false;
   g_scoreBars=0;
   if(g_nAct==0)
      return;
   int want=MathMin(MathMax(g_wantBars,200),Bars(g_sym,g_per)-1);
   if(want<200)
      return;
   MqlRates cb[];
   int nb=CopyRates(g_sym,g_per,1,want,cb);        // closed chart bars only
   if(nb<200)
      return;
   datetime winStart=cb[0].time;
   datetime now=TimeCurrent();
   double eps=g_pt/2.0;

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
   int cut1=warm+(nb-warm)/3;                      // stage 1 | stage 2
   int cut2=warm+2*(nb-warm)/3;                    // stage 2 | stage 3
   double typSpread=TypicalSpread(cb,nb);
   g_scoreT[0]=cb[warm].time;
   g_scoreT[1]=cb[cut1].time;
   g_scoreT[2]=cb[cut2].time;
   g_scoreT[3]=cb[nb-1].time;

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
         for(int kd=0;kd<g_kinds;kd++)
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
                    {
                     tests[t].tHit[si*4+tests[t].reached[si]]=tb;
                     tests[t].reached[si]++;
                    }
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
                    {
                     tests[t].tHit[si*4+tests[t].reached[si]]=tb;
                     tests[t].reached[si]++;
                    }
                  if(tests[t].reached[si]>=4)
                     fin=true;
                 }
              }
            if(fin)
              {
               tests[t].done[si]=true;
               tests[t].tEnd[si]=tb;
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
         double zh=zb[z].hi-zb[z].lo;
         ZTest nt1;
         nt1.dir=dir;
         nt1.kind=zb[z].kind;
         nt1.mask=zb[z].mask;
         nt1.flag=false;
         nt1.pick=false;
         nt1.half=(b<cut1) ? 0 : ((b<cut2) ? 1 : 2);
         nt1.fin2=-1;
         nt1.score=0.0;
         nt1.gscore=0.0;
         nt1.cost=0.0;
         nt1.scale=0;
         nt1.risk=zh;
         nt1.entry=0.0;
         nt1.tIn=tb;
         for(int q=0;q<16;q++)
            nt1.tHit[q]=0;
         for(int q=0;q<4;q++)
            nt1.tEnd[q]=0;
         for(int q=0;q<6;q++)
            nt1.f[q]=0;
         for(int q=0;q<9;q++)
            nt1.gf[q]=0;
         for(int q=0;q<4;q++)
           {
            nt1.reached[q]=0;
            nt1.done[q]=false;
           }
         bool gone0=false;
         if(dir==0)
           {
            nt1.entry=MathMin(zb[z].hi,cb[b].open);
            gone0=(nt1.entry<=zb[z].lo);
           }
         else
           {
            nt1.entry=MathMax(zb[z].lo,cb[b].open);
            gone0=(nt1.entry>=zb[z].hi);
           }
         TouchInfo(nt1,zb[z],cb,b,atr,tb);
         GenFeat(dir,zb[z].lo,zb[z].hi,zb[z].mask,zb[z].t,nt1.flag,cb,b,atr,nt1.gf);
         //--- the same touch is traded once per stop class: tight, medium, wide
         for(int sc=0;sc<NSC;sc++)
           {
            ZTest nt;
            nt=nt1;
            nt.scale=sc;
            nt.risk=MathMax(zh,MathMax(g_rk[sc],0.0)*atr);
            bool gone=(gone0 || nt.risk<=eps);
            if(nt.risk>0.0)
               nt.cost=MathMax(InpSpreadMult,0.0)*MathMax((double)cb[b].spread,typSpread)*g_pt/nt.risk;
            bool anyOpen=false;
            for(int si=0;si<4;si++)
              {
               nt.reached[si]=0;
               bool lost=gone;
               if(!lost)
                 {
                  if(dir==0)
                     lost=(cb[b].low<=nt.entry-g_sm[si]*nt.risk);
                  else
                     lost=(cb[b].high>=nt.entry+g_sm[si]*nt.risk);
                 }
               nt.done[si]=lost;
               if(lost)
                  nt.tEnd[si]=tb;
               if(lost)
                 {
                  if(si==2)
                     nt.fin2=b;
                 }
               else
                  anyOpen=true;
              }
            if(anyOpen)
              {
               ArrayResize(tests,ntests+1,256);
               tests[ntests]=nt;
               ntests++;
              }
            else
              {
               ArrayResize(outs,nouts+1,1024);
               outs[nouts]=nt;
               nouts++;
              }
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
//--- each stop class is learned and judged on its own
   for(int kk=0;kk<NSC;kk++)
     {
      int sc=(g_liveScale+1+kk)%NSC;
      ZTest sub[];
      int sidx[];
      int ns=0;
      for(int o=0;o<nouts;o++)
         if(outs[o].scale==sc)
           {
            ArrayResize(sub,ns+1,1024);
            ArrayResize(sidx,ns+1,1024);
            sub[ns]=outs[o];
            sidx[ns]=o;
            ns++;
           }
      g_curScale=sc;
      PostProcess(sub,ns,cut1);
      GenLearn(sub,ns,cut1);
      for(int q=0;q<26;q++)
         g_glAll[sc*26+q]=g_gl[q];
      g_gOkAll[sc]=g_gOk;
      for(int q=0;q<18;q++)
         g_liftAll[sc*18+q]=S4_g_lift[q];
      g_mOkAll[sc]=S4_g_modelOk;
      for(int i=0;i<ns;i++)
         outs[sidx[i]]=sub[i];
     }
   for(int o=0;o<nouts;o++)
      for(int si=0;si<4;si++)
         if(outs[o].done[si])
            AddStat(outs[o].mask+16*outs[o].scale,outs[o].dir,outs[o].flag,outs[o].pick,outs[o].half,si,outs[o].reached[si],outs[o].cost);

   if(g_repOn)
      ReplayCollect(outs,nouts);
   if(g_study && g_studyH!=INVALID_HANDLE)
      for(int o=0;o<nouts;o++)
        {
         if(outs[o].tIn<InpStudyFrom)
            continue;
         string ln=g_sym+","+g_sName[g_strat]+","+(((!g_viewExcl || !outs[o].flag)) ? "1" : "0")+","+(outs[o].flag ? "1" : "0")+","+(outs[o].pick ? "1" : "0")+","+
                   ((outs[o].dir==0) ? "buy" : "sell")+","+g_scName[outs[o].scale]+","+IntegerToString(outs[o].mask)+","+
                   TimeToString(outs[o].tIn,TIME_DATE|TIME_MINUTES)+","+DoubleToString(outs[o].cost,4);
         for(int q=0;q<4;q++)
            ln+=","+IntegerToString(outs[o].reached[q])+","+(outs[o].done[q] ? "1" : "0");
         FileWriteString(g_studyH,ln+"\r\n");
         g_studyN++;
        }

   g_scoreBars=nb-warm;
   g_scoreOk=true;
  }

//+------------------------------------------------------------------+
//| The lab itself                                                   |
//+------------------------------------------------------------------+
struct LabRow
  {
   string            sym;        // name shown (with the chart timeframe when it is a finer check)
   int               symIdx;
   int               fam;
   int               strat;
   int               view;       // 0 everything, 1 the strategy's own extra condition, 2 learned picks
   int               side;
   int               scale;      // stop class
   int               n;
   int               ns[3];      // tests per stage (1x stop)
   double            ev[3];      // 1x stop, 2x target, after spread, per stage
   double            evA;
   double            ev11;
   double            ev13;
   double            c[3];       // spread cost summed (R at 1x stop) per stage
   int               gn[12];     // tests [stage*4+stop]
   int               gh[48];     // hits  [(stage*4+stop)*4+target]
   bool              pass;
   bool              gOk;
   bool              mOk;
   double            gl[26];     // learning-layer weights for this asset / strategy / stop class
   double            lift[18];   // self-taught model weights
  };

string   g_syms[];
ENUM_TIMEFRAMES g_symTF[];
int      g_symBars[];
int      g_symNb[];              // candles actually tested
datetime g_symT0[];              // first candle tested
datetime g_symT1[];              // stage 2 starts
datetime g_symT2[];              // stage 3 starts
datetime g_symT3[];              // last candle tested
int      g_symState[];           // 1 = history is loaded and ready
long     g_symLast[];
int      g_symStable[];
uint     g_symAt[];
int      g_nSym       = 0;
int      g_done[];               // per job: 0 waiting, 1 done, 2 no data
int      g_try[];
uint     g_tryAt[];              // when the job was last attempted (history may still be downloading)
int      g_job        = 0;
bool     g_scanning   = false;
datetime g_scanStart  = 0;
datetime g_scanEnd    = 0;
LabRow   g_rows[];
int      g_nRows      = 0;
int      g_jobsDone   = 0;
uint     g_lastHtml   = 0;
datetime g_lastSig    = 0;
string   g_alerted[];
int      g_nAlerted   = 0;
string   g_modelKey   = "";
int      g_curSym     = 0;
string   DIR_OUT      = "T2R_Lab\\";
bool StudyMatch(const string sy)
  {
   string toks[];
   int n=StringSplit(InpStudyOnly,',',toks);
   string up=sy;
   StringToUpper(up);
   for(int i=0;i<n;i++)
     {
      string t=toks[i];
      StringTrimLeft(t);
      StringTrimRight(t);
      StringToUpper(t);
      if(t!="" && StringFind(up,t)>=0)
         return true;
     }
   return false;
  }

string SymLabel(const int i)
  {
   return g_syms[i]+((g_symTF[i]!=InpChartTF) ? " ["+TFName(g_symTF[i])+"]" : "");
  }

bool SetCtx(const string sym,const ENUM_TIMEFRAMES tf,const int bars)
  {
   g_sym=sym;
   g_per=tf;
   g_wantBars=bars;
   if(!SymbolSelect(g_sym,true))
      return false;
   g_pt=SymbolInfoDouble(g_sym,SYMBOL_POINT);
   g_dig=(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);
   if(g_pt<=0.0)
      return false;
   g_ps=PeriodSeconds(g_per);
   g_t0=iTime(g_sym,g_per,0);
   g_rk[0]=InpRisk1;
   g_rk[1]=InpRisk2;
   g_rk[2]=InpRisk3;
   return true;
  }

bool SetContext(const int i)
  {
   g_curSym=i;
   return SetCtx(g_syms[i],g_symTF[i],g_symBars[i]);
  }

void SetStrategy(const int s)
  {
   g_strat=s;
   g_kinds=g_kindsOf[s];
   g_viewExcl=g_excl[s];
   g_look=g_lookOf[s];
   g_tf[0]=InpTF1;
   g_tf[1]=InpTF2;
   g_tf[2]=InpTF3;
   g_tf[3]=InpTF4;
   g_show[0]=g_use1[s];
   g_show[1]=true;
   g_show[2]=true;
   g_show[3]=g_use4[s];
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
  }

bool ViewOn(const int st,const int v)
  {
   if(v==0)
      return !(st==1);                               // Trap + Gap "All traps" is the same test as Trap Zones: not counted twice
   if(v==1)
      return g_hasView[st];
   return g_hasPick[st];
  }

string ViewName(const int st,const int v)
  {
   if(v==0)
      return g_v0[st];
   if(v==1)
      return g_v1[st];
   return "Learned picks";
  }

//--- tests, target hits and spread cost for one view / side / stage / stop class, summed over every timeframe combo
int CellN(const int view,const int side,const int seg,const int si,const int scale)
  {
   int v=0;
   for(int i=0;i<g_nStats;i++)
     {
      if((g_stats[i].mask>>4)!=scale)
         continue;
      for(int d=0;d<2;d++)
        {
         if((d==0 && side==2) || (d==1 && side==1))
            continue;
         v+=g_stats[i].n[((view*2+d)*3+seg)*4+si];
        }
     }
   return v;
  }

int CellH(const int view,const int side,const int seg,const int si,const int lev,const int scale)
  {
   int v=0;
   for(int i=0;i<g_nStats;i++)
     {
      if((g_stats[i].mask>>4)!=scale)
         continue;
      for(int d=0;d<2;d++)
        {
         if((d==0 && side==2) || (d==1 && side==1))
            continue;
         v+=g_stats[i].h[(((view*2+d)*3+seg)*4+si)*4+lev];
        }
     }
   return v;
  }

double CellC(const int view,const int side,const int seg,const int scale)
  {
   double v=0.0;
   for(int i=0;i<g_nStats;i++)
     {
      if((g_stats[i].mask>>4)!=scale)
         continue;
      for(int d=0;d<2;d++)
        {
         if((d==0 && side==2) || (d==1 && side==1))
            continue;
         v+=g_stats[i].c[(view*2+d)*3+seg];
        }
     }
   return v;
  }

//--- average R per trade AFTER the spread, from a block of counts.
//    pn = tests [p*12 + stage*4 + stop], ph = hits [that*4 + target], pc = cost [p*3 + stage]. seg 3 = all stages.
double PEV(const int &pn[],const int &ph[],const double &pc[],const int p,const int seg,const int si,const int lv,int &nOut)
  {
   int n=0;
   int hh=0;
   int n1=0;
   double c=0.0;
   for(int sg=0;sg<3;sg++)
     {
      if(seg<3 && sg!=seg)
         continue;
      n+=pn[p*12+sg*4+si];
      hh+=ph[(p*12+sg*4+si)*4+lv];
      n1+=pn[p*12+sg*4+2];
      c+=pc[p*3+sg];
     }
   nOut=n;
   if(n<=0)
      return 0.0;
   double rate=(double)hh/n;
   double cost=(n1>0) ? c/n1/g_sm[si] : 0.0;
   return rate*(g_lev[lv]/g_sm[si])-(1.0-rate)-cost;
  }

void DropRows(const int symIdx,const int strat)
  {
   int w=0;
   for(int i=0;i<g_nRows;i++)
      if(!(g_rows[i].symIdx==symIdx && g_rows[i].strat==strat))
        {
         if(w!=i)
            g_rows[w]=g_rows[i];
         w++;
        }
   g_nRows=w;
  }

void Summarise()
  {
   DropRows(g_curSym,g_strat);
   for(int v=0;v<3;v++)
     {
      if(!ViewOn(g_strat,v))
         continue;
      for(int sc=0;sc<NSC;sc++)
         for(int sd=0;sd<3;sd++)
           {
            int n=0;
            for(int sg=0;sg<3;sg++)
               n+=CellN(v,sd,sg,2,sc);
            if(n<=0)
               continue;
            ArrayResize(g_rows,g_nRows+1,4096);
            int r=g_nRows;
            g_rows[r].sym=SymLabel(g_curSym);
            g_rows[r].symIdx=g_curSym;
            g_rows[r].fam=GroupOf(g_sym);
            g_rows[r].strat=g_strat;
            g_rows[r].view=v;
            g_rows[r].side=sd;
            g_rows[r].scale=sc;
            g_rows[r].n=n;
            for(int sg=0;sg<3;sg++)
              {
               g_rows[r].c[sg]=CellC(v,sd,sg,sc);
               for(int si=0;si<4;si++)
                 {
                  g_rows[r].gn[sg*4+si]=CellN(v,sd,sg,si,sc);
                  for(int lv=0;lv<4;lv++)
                     g_rows[r].gh[(sg*4+si)*4+lv]=CellH(v,sd,sg,si,lv,sc);
                 }
              }
            int nn=0;
            for(int sg=0;sg<3;sg++)
              {
               g_rows[r].ev[sg]=PEV(g_rows[r].gn,g_rows[r].gh,g_rows[r].c,0,sg,2,2,nn);
               g_rows[r].ns[sg]=nn;
              }
            g_rows[r].evA=PEV(g_rows[r].gn,g_rows[r].gh,g_rows[r].c,0,3,2,2,nn);
            g_rows[r].ev11=PEV(g_rows[r].gn,g_rows[r].gh,g_rows[r].c,0,3,2,1,nn);
            g_rows[r].ev13=PEV(g_rows[r].gn,g_rows[r].gh,g_rows[r].c,0,3,2,3,nn);
            g_rows[r].gOk=g_gOkAll[sc];
            g_rows[r].mOk=g_mOkAll[sc];
            for(int q=0;q<26;q++)
               g_rows[r].gl[q]=g_glAll[sc*26+q];
            for(int q=0;q<18;q++)
               g_rows[r].lift[q]=g_liftAll[sc*18+q];
            int need=MathMax(InpPassMinN,1);
            g_rows[r].pass=(n>=need && g_rows[r].ns[0]>=need/6 && g_rows[r].ns[1]>=need/6 && g_rows[r].ns[2]>=need/6 &&
                            g_rows[r].ev[0]>=InpPassMinR && g_rows[r].ev[1]>=InpPassMinR && g_rows[r].ev[2]>=InpPassMinR);
            g_nRows++;
           }
     }
  }

//--- data files. One line = one asset / strategy / view / direction / stop class / stage, with all 4 stops across.
string CsvCols()
  {
   string s="";
   for(int si=0;si<4;si++)
     {
      s+=",n_stop"+g_smName[si];
      for(int lv=0;lv<4;lv++)
         s+=",hit"+g_levName[lv]+"_stop"+g_smName[si];
     }
   return s;
  }

void CsvHeader()
  {
   int h=FileOpen(DIR_OUT+"results.csv",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE)
      return;
   FileWriteString(h,"asset,family,chart_tf,strategy,timeframes,view,direction,stop_class,stage,cost_R_1x"+CsvCols()+"\r\n");
   FileClose(h);
  }

//--- full detail: every timeframe combo
void CsvAppend()
  {
   int h=FileOpen(DIR_OUT+"results.csv",FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE)
      return;
   FileSeek(h,0,SEEK_END);
   string fam=g_famName[GroupOf(g_sym)];
   for(int i=0;i<g_nStats;i++)
      for(int v=0;v<3;v++)
        {
         if(!ViewOn(g_strat,v))
            continue;
         for(int d=0;d<2;d++)
            for(int sg=0;sg<3;sg++)
              {
               int b0=((v*2+d)*3+sg)*4;
               if(g_stats[i].n[b0]+g_stats[i].n[b0+1]+g_stats[i].n[b0+2]+g_stats[i].n[b0+3]<=0)
                  continue;
               int n1=g_stats[i].n[b0+2];
               string line=g_sym+","+fam+","+TFName(g_per)+","+g_sName[g_strat]+","+MaskNames(g_stats[i].mask&15)+","+ViewName(g_strat,v)+","+
                           ((d==0) ? "buy" : "sell")+","+g_scName[Clamp(g_stats[i].mask>>4,0,NSC-1)]+","+g_segName[sg]+","+
                           DoubleToString((n1>0) ? g_stats[i].c[(v*2+d)*3+sg]/n1 : 0.0,4);
               for(int si=0;si<4;si++)
                 {
                  line+=","+IntegerToString(g_stats[i].n[b0+si]);
                  for(int lv=0;lv<4;lv++)
                     line+=","+IntegerToString(g_stats[i].h[(b0+si)*4+lv]);
                 }
               FileWriteString(h,line+"\r\n");
              }
        }
   FileClose(h);
  }

//--- the short file: timeframe combos added together. This is the one to send for analysis.
void WriteSummary()
  {
   int h=FileOpen(DIR_OUT+"summary.csv",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE)
      return;
   FileWriteString(h,"asset,family,strategy,view,direction,stop_class,stage,cost_R_1x"+CsvCols()+"\r\n");
   for(int r=0;r<g_nRows;r++)
     {
      if(g_rows[r].side==0)
         continue;
      for(int sg=0;sg<3;sg++)
        {
         int n1=g_rows[r].gn[sg*4+2];
         if(g_rows[r].gn[sg*4]+g_rows[r].gn[sg*4+1]+n1+g_rows[r].gn[sg*4+3]<=0)
            continue;
         string line=g_rows[r].sym+","+g_famName[g_rows[r].fam]+","+g_sName[g_rows[r].strat]+","+ViewName(g_rows[r].strat,g_rows[r].view)+","+
                     ((g_rows[r].side==1) ? "buy" : "sell")+","+g_scName[g_rows[r].scale]+","+g_segName[sg]+","+
                     DoubleToString((n1>0) ? g_rows[r].c[sg]/n1 : 0.0,4);
         for(int si=0;si<4;si++)
           {
            line+=","+IntegerToString(g_rows[r].gn[sg*4+si]);
            for(int lv=0;lv<4;lv++)
               line+=","+IntegerToString(g_rows[r].gh[(sg*4+si)*4+lv]);
           }
         FileWriteString(h,line+"\r\n");
        }
     }
   FileClose(h);
  }

//+------------------------------------------------------------------+
//| Dashboard page                                                   |
//+------------------------------------------------------------------+
string RTxt(const double v)
  {
   return ((v>=0.0) ? "+" : "")+DoubleToString(v,2);
  }

string RCls(const double v)
  {
   if(v>0.05)
      return "g";
   if(v<-0.05)
      return "r";
   return "n";
  }

//--- chance that a standard bell curve lands above z
double NormTail(const double z)
  {
   double x=MathAbs(z);
   double t=1.0/(1.0+0.2316419*x);
   double poly=t*(0.319381530+t*(-0.356563782+t*(1.781477937+t*(-1.821255978+t*1.330274429))));
   double tail=MathExp(-0.5*x*x)/2.5066282746*poly;
   return (z>=0.0) ? tail : 1.0-tail;
  }

string Num(const long v)
  {
   string s=IntegerToString(v);
   string o="";
   int n=StringLen(s);
   for(int i=0;i<n;i++)
     {
      o+=StringSubstr(s,i,1);
      int left=n-1-i;
      if(left>0 && left%3==0 && StringSubstr(s,i,1)!="-")
         o+=",";
     }
   return o;
  }

string DateS(const datetime t)
  {
   return (t>0) ? TimeToString(t,TIME_DATE) : "-";
  }

//--- 1:15, 1:6, 1:2.5 ...
string RRText(const int si,const int lv)
  {
   double r=g_lev[lv]/g_sm[si];
   string s=DoubleToString(r,2);
   if(StringFind(s,".")>=0)
     {
      while(StringLen(s)>1 && StringSubstr(s,StringLen(s)-1,1)=="0")
         s=StringSubstr(s,0,StringLen(s)-1);
      if(StringSubstr(s,StringLen(s)-1,1)==".")
         s=StringSubstr(s,0,StringLen(s)-1);
     }
   return "1:"+s;
  }

//--- which target index is "1 to 1" for a stop size (-1 = the grid has no such target)
int Tp1Level(const int si)
  {
   if(si==1)
      return 0;
   if(si==2)
      return 1;
   if(si==3)
      return 2;
   return -1;
  }

//--- average R, then win rate and number of trades
string Cell3(const double e,const int n,const int w)
  {
   if(n<=0)
      return "<td>-</td>";
   return "<td class='"+RCls(e)+"'>"+RTxt(e)+"R <small>"+IntegerToString((int)MathRound(100.0*w/n))+"% of "+IntegerToString(n)+"</small></td>";
  }

//--- everything the "full story" pop-up needs about one backtest row
string RowData(const int i,const int si,const int lv)
  {
   string s="";
   int t1=Tp1Level(si);
   for(int sg=0;sg<3;sg++)
      s+=IntegerToString(g_rows[i].gn[sg*4+si])+","+IntegerToString(g_rows[i].gh[(sg*4+si)*4+lv])+",";
   s+=DoubleToString(g_lev[lv]/g_sm[si],2);
   for(int sg=0;sg<3;sg++)
      s+=","+((t1>=0) ? IntegerToString(g_rows[i].gh[(sg*4+si)*4+t1]) : "-1");
   int x=g_rows[i].symIdx;
   s+=","+DateS(g_symT0[x])+","+DateS(g_symT1[x])+","+DateS(g_symT2[x])+","+DateS(g_symT3[x]);
   s+=","+DoubleToString((double)((long)g_symT3[x]-(long)g_symT0[x])/604800.0,1);
   for(int sg=0;sg<3;sg++)
     {
      int nn=0;
      s+=","+DoubleToString(PEV(g_rows[i].gn,g_rows[i].gh,g_rows[i].c,0,sg,si,lv,nn),3);
     }
   return s;
  }

string RowKey(const int i,const int si,const int lv)
  {
   return g_rows[i].sym+"|"+g_sName[g_rows[i].strat]+"|"+ViewName(g_rows[i].strat,g_rows[i].view)+"|"+g_sideName[g_rows[i].side]+"|"+
          g_scName[g_rows[i].scale]+"|"+g_smName[si]+"|"+g_levName[lv];
  }

//--- which assets were tested on full history
void WriteCoverage()
  {
   int h=FileOpen(DIR_OUT+"coverage.csv",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE)
      return;
   FileWriteString(h,"asset,chart_tf,bars_wanted,bars_tested,first_candle,last_candle,status\r\n");
   for(int i=0;i<g_nSym;i++)
      FileWriteString(h,g_syms[i]+","+TFName(g_symTF[i])+","+IntegerToString(g_symBars[i])+","+IntegerToString(g_symNb[i])+","+DateS(g_symT0[i])+","+
                      DateS(g_symT3[i])+","+((g_symNb[i]<=0) ? "no data" : ((g_symNb[i]>=0.95*g_symBars[i]) ? "full" : "short"))+"\r\n");
   FileClose(h);
  }

void WriteHtml()
  {
   int h=FileOpen(DIR_OUT+"dashboard.html",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE)
      return;
   int total=g_nSym*NSTRAT;
   int nPass=0;
   long nTests=0;
   for(int i=0;i<g_nRows;i++)
     {
      if(g_rows[i].pass)
         nPass++;
      if(g_rows[i].view==0 && g_rows[i].side==0 && g_rows[i].scale==0)
         nTests+=g_rows[i].n;
     }
   int nFull=0;
   int nShort=0;
   datetime tMin=0;
   datetime tMax=0;
   for(int i=0;i<g_nSym;i++)
     {
      if(g_symNb[i]<=0)
         continue;
      if(g_symNb[i]>=0.95*g_symBars[i])
         nFull++;
      else
         nShort++;
      if(tMin==0 || g_symT0[i]<tMin)
         tMin=g_symT0[i];
      if(g_symT3[i]>tMax)
         tMax=g_symT3[i];
     }

   string s="<!doctype html><html><head><meta charset='utf-8'>";
   s+="<meta name='viewport' content='width=device-width,initial-scale=1'><title>T2R Lab</title><style>";
   FileWriteString(h,s);
   FileWriteString(h,":root{--bg:#0e1014;--p1:#161920;--p2:#1d212a;--ln:#2a2f3b;--tx:#e4e7ee;--dim:#8a90a0;--g:#26a69a;--r:#ef5350;-");
   FileWriteString(h,"-gold:#d8b46a}\n*{box-sizing:border-box}body{margin:0;background:radial-gradient(1200px 600px at 20% -10%,#1a1f");
   FileWriteString(h,"2b,#0e1014);color:var(--tx);font:14px/1.55 'Segoe UI',system-ui,sans-serif;padding:28px 16px}\n.w{max-width:132");
   FileWriteString(h,"0px;margin:0 auto}h1{font:600 30px Georgia,'Times New Roman',serif;margin:0;letter-spacing:.3px}h2{font:600 19");
   FileWriteString(h,"px Georgia,serif;margin:0 0 10px}\nh3{font:600 15px Georgia,serif;margin:18px 0 6px;color:var(--gold)}.sub{colo");
   FileWriteString(h,"r:var(--dim);margin:4px 0 22px}\n.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));g");
   FileWriteString(h,"ap:12px;margin-bottom:18px}\n.c{background:linear-gradient(180deg,var(--p2),var(--p1));border:1px solid var(--l");
   FileWriteString(h,"n);border-radius:14px;padding:14px 16px;box-shadow:0 10px 30px rgba(0,0,0,.35)}\n.c b{display:block;font:600 24");
   FileWriteString(h,"px Georgia,serif}.c span{color:var(--dim);font-size:12px;text-transform:uppercase;letter-spacing:.8px}\n.box{ba");
   FileWriteString(h,"ckground:var(--p1);border:1px solid var(--ln);border-radius:16px;padding:18px;margin-bottom:18px;box-shadow:0 ");
   FileWriteString(h,"14px 40px rgba(0,0,0,.4)}\n.note{color:var(--dim);font-size:13px;margin:0 0 12px}.lead{font-size:15px;margin:0 ");
   FileWriteString(h,"0 14px}.tools{display:flex;gap:10px;flex-wrap:wrap;margin-bottom:12px}\ninput[type=text]{flex:1;min-width:200px");
   FileWriteString(h,";background:var(--p2);border:1px solid var(--ln);color:var(--tx);border-radius:10px;padding:9px 12px}\ninput[ty");
   FileWriteString(h,"pe=number]{width:80px;background:var(--p2);border:1px solid var(--ln);color:var(--tx);border-radius:8px;paddin");
   FileWriteString(h,"g:4px 8px;font:inherit}\nlabel{color:var(--dim);display:flex;align-items:center;gap:6px}.sc{overflow:auto;max-h");
   FileWriteString(h,"eight:640px}table{width:100%;border-collapse:collapse;white-space:nowrap}\nth{position:sticky;top:0;background:");
   FileWriteString(h,"var(--p1);color:var(--dim);font-weight:500;font-size:12px;text-transform:uppercase;letter-spacing:.6px;text-al");
   FileWriteString(h,"ign:right;padding:8px 10px;border-bottom:1px solid var(--ln)}\ntd{text-align:right;padding:7px 10px;border-bott");
   FileWriteString(h,"om:1px solid #20242e}th.l,td.l{text-align:left}tr[data-d]{cursor:pointer}tr[data-d]:hover td{background:rgba(2");
   FileWriteString(h,"55,255,255,.04)}\n.g{color:var(--g)}.r{color:var(--r)}.n{color:var(--tx)}.few td{color:#5d6373}.few .g,.few .r{");
   FileWriteString(h,"color:#5d6373}small{color:var(--dim)}\n.tag{display:inline-block;border-radius:999px;padding:2px 10px;font-size");
   FileWriteString(h,":12px;border:1px solid var(--ln);color:var(--dim)}\n.tag.ok{border-color:var(--gold);color:var(--gold)}tr.p td{");
   FileWriteString(h,"background:rgba(216,180,106,.06)}.empty{color:var(--dim);padding:26px;text-align:center}\n.big{font:600 22px Ge");
   FileWriteString(h,"orgia,serif;color:var(--gold)}.steps{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap");
   FileWriteString(h,":10px}\n.steps div{background:var(--p2);border:1px solid var(--ln);border-radius:12px;padding:10px 12px;color:v");
   FileWriteString(h,"ar(--dim)}\n.steps b{display:inline-block;width:22px;height:22px;line-height:22px;text-align:center;border-radi");
   FileWriteString(h,"us:50%;background:var(--gold);color:#14161b;margin-right:8px;font-size:12px}\n.faq{display:grid;grid-template-c");
   FileWriteString(h,"olumns:repeat(auto-fit,minmax(380px,1fr));gap:12px}.faq div{background:var(--p2);border:1px solid var(--ln);bo");
   FileWriteString(h,"rder-radius:12px;padding:12px 14px}\n.faq b{display:block;margin-bottom:4px;color:var(--tx)}.faq div{color:#b9b");
   FileWriteString(h,"fcc;font-size:13px}.faq table{white-space:normal;margin-top:6px}.faq td,.faq th{padding:3px 8px;position:stati");
   FileWriteString(h,"c;background:none}\n.mo{display:none;position:fixed;inset:0;background:rgba(5,6,9,.78);z-index:9;overflow:auto;");
   FileWriteString(h,"padding:30px 14px}\n.mc{max-width:980px;margin:0 auto;background:var(--p1);border:1px solid var(--gold);border-");
   FileWriteString(h,"radius:18px;padding:24px 26px;box-shadow:0 30px 80px rgba(0,0,0,.6);position:relative}\n.mx{position:absolute;t");
   FileWriteString(h,"op:14px;right:18px;color:var(--dim);cursor:pointer;border:1px solid var(--ln);border-radius:999px;padding:2px ");
   FileWriteString(h,"12px}\n.mc ul{margin:6px 0 0;padding-left:20px}.mc li{margin:4px 0}.mc p{margin:6px 0}.st{white-space:normal;ma");
   FileWriteString(h,"rgin-top:6px}.st th{position:static}\n.st tr.tot td{border-top:1px solid var(--gold);font-weight:600}.vd{backgr");
   FileWriteString(h,"ound:var(--p2);border-left:3px solid var(--gold);padding:10px 14px;border-radius:8px;margin:12px 0}\n");
   s="</style></head><body><div class='w'>";
   s+="<h1>T2R Lab</h1><div class='sub'>"+IntegerToString(NSTRAT)+" strategies tested on "+TFName(InpChartTF)+" charts &middot; updated "+
      TimeToString(TimeLocal(),TIME_DATE|TIME_MINUTES)+" &middot; this page refreshes itself &middot; <b>click any row for its full story in plain words</b></div>";
   s+="<div class='cards'><div class='c'><b>"+IntegerToString(g_nSym)+"</b><span>Markets</span></div>";
   s+="<div class='c'><b>"+IntegerToString(g_jobsDone)+" / "+IntegerToString(total)+"</b><span>"+(g_scanning ? "Scanning" : "Scan complete")+"</span></div>";
   s+="<div class='c'><b>"+Num(nTests)+"</b><span>Test trades taken</span></div>";
   s+="<div class='c'><b style='color:var(--gold)'>"+IntegerToString(nPass)+"</b><span>Passed all 3 stages</span></div>";
   s+="<div class='c'><b>"+IntegerToString(g_nWatch)+"</b><span>Followed live on demo</span></div></div>";
   FileWriteString(h,s);

//--- plain-words summary
   s="<div class='box'><h2>What this page is, in plain words</h2><p class='lead'>A computer went back through "+
     ((tMin>0) ? "history from <b>"+DateS(tMin)+"</b> to <b>"+DateS(tMax)+"</b>" : "the price history")+" on <b>"+IntegerToString(g_nSym)+
     " markets</b> and took every trade that each of our <b>"+IntegerToString(NSTRAT)+" strategies</b> would have signalled: <b>"+
     Num(nTests)+" test trades</b>. It kept score honestly, after trading costs. The winners are now being followed live on a demo "+
     "account, and every live signal is tracked to its result. Nothing here is a promise: it is a record of what was tested and how it is doing now.</p>"+
     "<div class='steps'><div><b>1</b>Read <i>Live demo test</i> first: real signals on fresh prices.</div><div><b>2</b><i>Pair strongholds</i> and "+
     "<i>Market by market</i> show which strategy worked on which market in the backtest.</div><div><b>3</b>Click any row: a window opens with wins, "+
     "losses, dates, money and what to expect.</div><div><b>4</b>Stuck on a word? See <i>Questions people ask</i> at the bottom.</div></div>"+
     "<p class='note' style='margin-top:12px'>Money examples on this page use <b>$<input id='risk' type='number' min='1' value='10'></b> risked per trade. "+
     "Change it and every example follows.</p></div>";
   FileWriteString(h,s);

   WriteLiveHtml(h);
   WriteReplayHtml(h);

//--- pooled counts: [family][strategy][view][side][stop class]
   int np=NFAM*NSTRAT*27;
   int pn[];
   int ph[];
   double pc[];
   int pa[];
   ArrayResize(pn,np*12);
   ArrayResize(ph,np*48);
   ArrayResize(pc,np*3);
   ArrayResize(pa,np);
   ArrayInitialize(pn,0);
   ArrayInitialize(ph,0);
   ArrayInitialize(pc,0.0);
   ArrayInitialize(pa,0);
   for(int i=0;i<g_nRows;i++)
     {
      if(g_symTF[g_rows[i].symIdx]!=InpChartTF)
         continue;                                   // finer-check rows are the same assets again: not pooled twice
      for(int pass=0;pass<2;pass++)
        {
         int fam=(pass==0) ? g_rows[i].fam : NFAM-1;
         int p=(((fam*NSTRAT+g_rows[i].strat)*3+g_rows[i].view)*3+g_rows[i].side)*3+g_rows[i].scale;
         pa[p]++;
         for(int q=0;q<12;q++)
            pn[p*12+q]+=g_rows[i].gn[q];
         for(int q=0;q<48;q++)
            ph[p*48+q]+=g_rows[i].gh[q];
         for(int q=0;q<3;q++)
            pc[p*3+q]+=g_rows[i].c[q];
        }
     }

//--- PAIR STRONGHOLDS: pick on stage 1, confirm on stage 2, exam on stage 3
   int fi[];
   int fsi[];
   int flv[];
   double fe[];
   int fnn[];
   bool fok[];
   int nf=0;
   int nStrong=0;
   int nExam=0;
   double lucky=0.0;
   int minN=MathMax(InpStageMinN,5);
   for(int i=0;i<g_nRows;i++)
     {
      if(g_rows[i].n<3*minN)
         continue;
      int bs=-1;
      int bl=-1;
      double best=-1e9;
      for(int si=0;si<4;si++)
         for(int lv=0;lv<4;lv++)
           {
            int m1=0;
            int m2=0;
            double x1=PEV(g_rows[i].gn,g_rows[i].gh,g_rows[i].c,0,0,si,lv,m1);
            if(m1<minN || x1<InpPickR)
               continue;
            double x2=PEV(g_rows[i].gn,g_rows[i].gh,g_rows[i].c,0,1,si,lv,m2);
            if(m2<minN || x2<InpConfirmR)
               continue;
            if(MathMin(x1,x2)>best)
              {
               best=MathMin(x1,x2);
               bs=si;
               bl=lv;
              }
           }
      if(bs<0)
         continue;
      int n1=0;
      int n2=0;
      int n3=0;
      double e1=PEV(g_rows[i].gn,g_rows[i].gh,g_rows[i].c,0,0,bs,bl,n1);
      double e2=PEV(g_rows[i].gn,g_rows[i].gh,g_rows[i].c,0,1,bs,bl,n2);
      double e3=PEV(g_rows[i].gn,g_rows[i].gh,g_rows[i].c,0,2,bs,bl,n3);
      bool ok=(n3>=minN && e3>=InpConfirmR);
      if(n3>=minN)
        {
         nExam++;
         //--- how often would a strategy with NO edge pass this exam by luck?
         int nx=g_rows[i].gn[2*4+2];
         double cost3=(nx>0) ? g_rows[i].c[2]/nx/g_sm[bs] : 0.0;
         double ratio=g_lev[bl]/g_sm[bs];
         double p0=1.0/(1.0+ratio);
         double sd=MathSqrt(p0*(1.0-p0))*(ratio+1.0);
         if(sd>0.0)
            lucky+=NormTail((InpConfirmR+cost3)/(sd/MathSqrt((double)n3)));
        }
      if(ok)
         nStrong++;
      ArrayResize(fi,nf+1,256);
      ArrayResize(fsi,nf+1,256);
      ArrayResize(flv,nf+1,256);
      ArrayResize(fe,(nf+1)*3,768);
      ArrayResize(fnn,(nf+1)*3,768);
      ArrayResize(fok,nf+1,256);
      fi[nf]=i;
      fsi[nf]=bs;
      flv[nf]=bl;
      fe[nf*3]=e1;
      fe[nf*3+1]=e2;
      fe[nf*3+2]=e3;
      fnn[nf*3]=n1;
      fnn[nf*3+1]=n2;
      fnn[nf*3+2]=n3;
      fok[nf]=ok;
      nf++;
     }
   s="<div class='box fb' id='b1'><h2>Pair strongholds</h2><p class='note'>The hunt for &quot;this strategy on this market&quot;. For every market, "+
     "strategy, view, side and stop class, the best stop and target mix is PICKED on stage 1 (at least "+RTxt(InpPickR)+"R a trade), must CONFIRM on "+
     "stage 2 (at least "+RTxt(InpConfirmR)+"R), and is then examined ONCE on stage 3, which played no part in choosing it. At least "+
     IntegerToString(minN)+" trades per stage. Each cell shows: average result per trade, then win rate and number of trades.</p>";
   s+="<p class='note'><span class='big'>"+IntegerToString(nStrong)+"</span> passed the exam, out of "+IntegerToString(nExam)+" finalists that sat it. "+
      "Strategies with no edge at all would be expected to pass about <b>"+DoubleToString(lucky,1)+"</b> by luck. The bigger the gap between those two "+
      "numbers, the more of these rows are real. Rows overlap (Both includes Buys and Sells; a micro contract is the same market), so count markets, not rows.</p>";
   if(nf==0)
      s+="<div class='empty'>"+(g_scanning ? "Scanning..." : "No finalists.")+"</div></div>";
   FileWriteString(h,s);
   if(nf>0)
     {
      double fk[][2];
      ArrayResize(fk,nf);
      for(int q=0;q<nf;q++)
        {
         fk[q][0]=-(fe[q*3+2]+(fok[q] ? 100.0 : 0.0));
         fk[q][1]=q;
        }
      ArraySort(fk);
      FileWriteString(h,"<div class='tools'><input class='q' type='text' placeholder='Filter: market, strategy, buys, wide ...'>"+
                      "<label><input class='po' type='checkbox'> passed only</label></div><div class='sc'><table><thead><tr><th class='l'>Market</th>"+
                      "<th class='l'>Strategy</th><th class='l'>View</th><th class='l'>Side</th><th class='l'>Stop class</th><th>Stop</th><th>Target</th>"+
                      "<th>Risk : reward</th><th>1 Pick</th><th>2 Confirm</th><th>3 Exam</th><th>Verdict</th></tr></thead><tbody>");
      for(int q=0;q<nf && q<500;q++)
        {
         int f=(int)fk[q][1];
         int i=fi[f];
         int b=fsi[f];
         int l=flv[f];
         string line="<tr class='"+(fok[f] ? "p" : "")+"' data-k='"+RowKey(i,b,l)+"' data-d='"+RowData(i,b,l)+"'><td class='l'>"+g_rows[i].sym+
                     "</td><td class='l'>"+g_sName[g_rows[i].strat]+"</td><td class='l'>"+ViewName(g_rows[i].strat,g_rows[i].view)+"</td><td class='l'>"+
                     g_sideName[g_rows[i].side]+"</td><td class='l'>"+g_scName[g_rows[i].scale]+"</td><td>"+g_smName[b]+"</td><td>"+g_levName[l]+
                     "</td><td>"+RRText(b,l)+"</td>"+Cell3(fe[f*3],fnn[f*3],g_rows[i].gh[(0*4+b)*4+l])+Cell3(fe[f*3+1],fnn[f*3+1],g_rows[i].gh[(1*4+b)*4+l])+
                     Cell3(fe[f*3+2],fnn[f*3+2],g_rows[i].gh[(2*4+b)*4+l])+"<td><span class='tag"+
                     (fok[f] ? " ok'>STRONGHOLD" : ((fnn[f*3+2]<minN) ? "'>too few" : "'>failed exam"))+"</span></td></tr>";
         FileWriteString(h,line);
        }
      FileWriteString(h,"</tbody></table></div></div>");
     }

//--- by family
   s="<div class='box fb' id='b2'><h2>By market family</h2><p class='note'>Every market of a family added together (1x stop, 2x target = risk 1 to make 2, "+
     "after costs; break-even win rate 33%). Big samples, so luck matters far less here. Buys and Sells are shown for ALL ASSETS; families show both "+
     "directions together.</p><div class='tools'><input class='q' type='text' placeholder='Filter: forex, wide, learned ...'>"+
     "<label><input class='po' type='checkbox'> passed only</label></div>"+
     "<div class='sc'><table><thead><tr><th class='l'>Family</th><th class='l'>Strategy</th><th class='l'>View</th><th class='l'>Side</th><th class='l'>Stop class</th>"+
     "<th>Markets</th><th>Stage 1</th><th>Stage 2</th><th>Stage 3</th><th>Verdict</th></tr></thead><tbody>";
   FileWriteString(h,s);
   for(int ff=0;ff<NFAM;ff++)
     {
      int fam=(ff==0) ? NFAM-1 : ff-1;                 // ALL ASSETS first
      for(int st=0;st<NSTRAT;st++)
         for(int v=0;v<3;v++)
            for(int sc=0;sc<NSC;sc++)
               for(int sd=0;sd<3;sd++)
                 {
                  if(sd>0 && fam!=NFAM-1)
                     continue;
                  int p=(((fam*NSTRAT+st)*3+v)*3+sd)*3+sc;
                  if(pa[p]==0)
                     continue;
                  int n1=0;
                  int n2=0;
                  int n3=0;
                  double e1=PEV(pn,ph,pc,p,0,2,2,n1);
                  double e2=PEV(pn,ph,pc,p,1,2,2,n2);
                  double e3=PEV(pn,ph,pc,p,2,2,2,n3);
                  if(n1+n2+n3<=0)
                     continue;
                  bool thin=(n1<100 || n2<100 || n3<100);
                  bool ok=(!thin && e1>=InpPassMinR && e2>=InpPassMinR && e3>=InpPassMinR);
                  FileWriteString(h,"<tr class='"+(ok ? "p" : "")+"'><td class='l'>"+g_famName[fam]+"</td><td class='l'>"+g_sName[st]+"</td><td class='l'>"+
                                  ViewName(st,v)+"</td><td class='l'>"+g_sideName[sd]+"</td><td class='l'>"+g_scName[sc]+"</td><td>"+IntegerToString(pa[p])+
                                  "</td>"+Cell3(e1,n1,ph[(p*12+0*4+2)*4+2])+Cell3(e2,n2,ph[(p*12+1*4+2)*4+2])+Cell3(e3,n3,ph[(p*12+2*4+2)*4+2])+
                                  "<td><span class='tag"+(ok ? " ok'>PASS" : (thin ? "'>too few" : "'>no"))+"</span></td></tr>");
                 }
     }
   FileWriteString(h,"</tbody></table></div></div>");

//--- every stop size against every target, all assets, both directions
   s="<div class='box fb' id='b3'><h2>Every stop against every target</h2><p class='note'>All markets together, both directions, all 16 stop and target mixes "+
     "for each stop class, after costs. Each cell shows the average result per trade in stage 1 / stage 2 / stage 3. A cell only means something if ALL "+
     "three are green.</p><div class='tools'><input class='q' type='text' placeholder='Filter: strategy, view, wide ...'></div>"+
     "<div class='sc'><table><thead><tr><th class='l'>Strategy</th><th class='l'>View</th><th class='l'>Stop class</th><th>Stop</th><th>Trades</th>"+
     "<th>Target 0.5x</th><th>Target 1x</th><th>Target 2x</th><th>Target 3x</th></tr></thead><tbody>";
   FileWriteString(h,s);
   for(int st=0;st<NSTRAT;st++)
      for(int v=0;v<3;v++)
         for(int sc=0;sc<NSC;sc++)
           {
            int p=((((NFAM-1)*NSTRAT+st)*3+v)*3+0)*3+sc;
            if(pa[p]==0)
               continue;
            for(int si=0;si<4;si++)
              {
               int nAll=pn[p*12+si]+pn[p*12+4+si]+pn[p*12+8+si];
               if(nAll<=0)
                  continue;
               string line="<tr><td class='l'>"+g_sName[st]+"</td><td class='l'>"+ViewName(st,v)+"</td><td class='l'>"+g_scName[sc]+"</td><td>"+
                           g_smName[si]+"</td><td>"+IntegerToString(nAll)+"</td>";
               for(int lv=0;lv<4;lv++)
                 {
                  int nn=0;
                  double e1=PEV(pn,ph,pc,p,0,si,lv,nn);
                  double e2=PEV(pn,ph,pc,p,1,si,lv,nn);
                  double e3=PEV(pn,ph,pc,p,2,si,lv,nn);
                  line+="<td class='"+RCls(MathMin(e1,MathMin(e2,e3)))+"'>"+RTxt(e1)+" / "+RTxt(e2)+" / "+RTxt(e3)+"</td>";
                 }
               FileWriteString(h,line+"</tr>");
              }
           }
   FileWriteString(h,"</tbody></table></div></div>");

//--- does a higher model score really mean a better level?
   for(int m=0;m<2;m++)
     {
      int tot=0;
      for(int q=0;q<45;q++)
         tot+=g_bandN[m*45+q];
      if(tot<=0)
         continue;
      string bt="<div class='box'><h2>Model score bands - "+g_sName[4+m]+"</h2><p class='note'>Every level the model scored, grouped by score "+
                "(risk 1 to make 2, before costs, break-even win rate 33%). If the model has really learned something, the win rate in stages 2 and 3 "+
                "should climb as the score rises. Stage 1 is what it learned from.</p><div class='sc'><table><thead><tr><th class='l'>Stop class</th>"+
                "<th class='l'>Score</th><th>Stage 1</th><th>Stage 2</th><th>Stage 3</th></tr></thead><tbody>";
      for(int sc=0;sc<NSC;sc++)
         for(int b=0;b<5;b++)
           {
            bt+="<tr><td class='l'>"+g_scName[sc]+"</td><td class='l'>"+g_bandName[b]+"</td>";
            for(int sg=0;sg<3;sg++)
              {
               int bi=((m*NSC+sc)*5+b)*3+sg;
               double e=(g_bandN[bi]>0) ? 3.0*g_bandH[bi*4+2]/g_bandN[bi]-1.0 : 0.0;
               bt+=Cell3(e,g_bandN[bi],g_bandH[bi*4+2]);
              }
            bt+="</tr>";
           }
      bt+="</tbody></table></div></div>";
      FileWriteString(h,bt);
     }

//--- asset by asset: passed first, then by the weakest stage
   FileWriteString(h,"<div class='box fb' id='b4'><h2>Market by market</h2><p class='note'>One standard setup for every row: 1x stop, 2x target "+
                   "(risk 1 to make 2; break-even win rate 33%), after costs. Each cell shows the average result per trade, then win rate and number of "+
                   "trades. The best 3000 rows are listed; every row is in summary.csv. Click a row for its full story.</p><div class='tools'>"+
                   "<input class='q' type='text' placeholder='Filter: market, strategy, buys, wide ...'>"+
                   "<label><input class='po' type='checkbox'> passed only</label></div>");
   if(g_nRows==0)
      FileWriteString(h,"<div class='empty'>"+(g_scanning ? "Scanning... results appear here as each market finishes." : "No results yet.")+"</div>");
   else
     {
      double rk[][2];
      ArrayResize(rk,g_nRows);
      for(int i=0;i<g_nRows;i++)
        {
         rk[i][0]=-(MathMin(g_rows[i].ev[0],MathMin(g_rows[i].ev[1],g_rows[i].ev[2]))+(g_rows[i].pass ? 100.0 : 0.0)-((g_rows[i].n<60) ? 50.0 : 0.0));
         rk[i][1]=i;
        }
      ArraySort(rk);
      FileWriteString(h,"<div class='sc'><table><thead><tr><th class='l'>Market</th><th class='l'>Strategy</th><th class='l'>View</th><th class='l'>Side</th>"+
                      "<th class='l'>Stop class</th><th>Stage 1</th><th>Stage 2</th><th>Stage 3</th><th>Whole test</th><th>If 1:1</th><th>If 1:3</th>"+
                      "<th>Verdict</th></tr></thead><tbody>");
      for(int q=0;q<g_nRows && q<3000;q++)
        {
         int i=(int)rk[q][1];
         bool few=(g_rows[i].n<60);
         string line="<tr class='"+(g_rows[i].pass ? "p" : (few ? "few" : ""))+"' data-k='"+RowKey(i,2,2)+"' data-d='"+RowData(i,2,2)+"'><td class='l'>"+
                     g_rows[i].sym+"</td><td class='l'>"+g_sName[g_rows[i].strat]+"</td><td class='l'>"+ViewName(g_rows[i].strat,g_rows[i].view)+
                     "</td><td class='l'>"+g_sideName[g_rows[i].side]+"</td><td class='l'>"+g_scName[g_rows[i].scale]+"</td>"+
                     Cell3(g_rows[i].ev[0],g_rows[i].ns[0],g_rows[i].gh[(0*4+2)*4+2])+Cell3(g_rows[i].ev[1],g_rows[i].ns[1],g_rows[i].gh[(1*4+2)*4+2])+
                     Cell3(g_rows[i].ev[2],g_rows[i].ns[2],g_rows[i].gh[(2*4+2)*4+2]);
         line+="<td class='"+RCls(g_rows[i].evA)+"'>"+RTxt(g_rows[i].evA)+"R</td>";
         line+="<td class='"+RCls(g_rows[i].ev11)+"'>"+RTxt(g_rows[i].ev11)+"R</td>";
         line+="<td class='"+RCls(g_rows[i].ev13)+"'>"+RTxt(g_rows[i].ev13)+"R</td>";
         line+="<td><span class='tag"+(g_rows[i].pass ? " ok'>PASS" : (few ? "'>too few" : "'>no"))+"</span></td></tr>";
         FileWriteString(h,line);
        }
      FileWriteString(h,"</tbody></table></div>");
     }
   FileWriteString(h,"</div>");

//--- was every market tested on its full history?
   s="<div class='box fb' id='b5'><h2>Data check</h2><p class='note'>A result is only as good as the history behind it. <b>"+IntegerToString(nFull)+
     "</b> markets were tested on their full history"+((nShort>0) ? " and <b>"+IntegerToString(nShort)+
     "</b> on a shorter one because the broker has no more (their results rest on fewer trades)" : "")+
     ". The test waits for each market's history to finish loading before it starts.</p><div class='tools'><input class='q' type='text' "+
     "placeholder='Filter: market, short ...'></div><div class='sc' style='max-height:320px'><table><thead><tr><th class='l'>Market</th><th class='l'>Chart</th>"+
     "<th>Candles tested</th><th>From</th><th>Stage 2 starts</th><th>Stage 3 starts</th><th>To</th><th>Status</th></tr></thead><tbody>";
   FileWriteString(h,s);
   for(int i=0;i<g_nSym;i++)
     {
      if(g_symNb[i]<=0)
         continue;
      bool full=(g_symNb[i]>=0.95*g_symBars[i]);
      FileWriteString(h,"<tr><td class='l'>"+g_syms[i]+"</td><td class='l'>"+TFName(g_symTF[i])+"</td><td>"+IntegerToString(g_symNb[i])+"</td><td>"+
                      DateS(g_symT0[i])+"</td><td>"+DateS(g_symT1[i])+"</td><td>"+DateS(g_symT2[i])+"</td><td>"+DateS(g_symT3[i])+
                      "</td><td><span class='tag"+(full ? " ok'>full" : "'>short")+"</span></td></tr>");
     }
   FileWriteString(h,"</tbody></table></div></div>");

   FileWriteString(h,"<div class='box'><h2>Questions people ask</h2><div class='faq'>\n<div><b>What is R?</b>R is the amount of money");
   FileWriteString(h," risked on one trade. If you risk $10, then 1R is $10. A loss costs 1R. A result of +0.30R a trade means that,");
   FileWriteString(h," on average, every trade made 30% of whatever was risked on it.</div>\n<div><b>How do I read a cell like \"+0.32");
   FileWriteString(h,"R 19% of 104\"?</b>104 trades were taken in that period. 19% of them won. After wins, losses and costs, the ave");
   FileWriteString(h,"rage trade made 0.32 times the risk. Green is profit, red is loss.</div>\n<div><b>What is risk to reward, and t");
   FileWriteString(h,"he break-even win rate?</b>Risk to reward 1:6 means a win pays six times what a loss costs. The bigger the rew");
   FileWriteString(h,"ard, the fewer wins are needed just to break even:\n<table><tr><th class='l'>Risk : reward</th><th>Wins needed ");
   FileWriteString(h,"in 100 to break even</th></tr><tr><td class='l'>1:1</td><td>50</td></tr><tr><td class='l'>1:2</td><td>33</td><");
   FileWriteString(h,"/tr><tr><td class='l'>1:3</td><td>25</td></tr><tr><td class='l'>1:6</td><td>14</td></tr><tr><td class='l'>1:15");
   FileWriteString(h,"</td><td>6</td></tr></table></div>\n<div><b>How can something that loses most of its trades make money?</b>Beca");
   FileWriteString(h,"use each win is much bigger than each loss. Lose $10 eight times and win $60 twice: that is $80 lost and $120 ");
   FileWriteString(h,"won, a $40 profit from ten trades with only two winners. The price is long losing runs, so the risk on each tr");
   FileWriteString(h,"ade must stay small.</div>\n<div><b>What are stage 1, stage 2 and stage 3?</b>The test history is cut into thre");
   FileWriteString(h,"e equal periods, oldest first. Stage 1 is where a strategy learns or where its best settings are chosen. Stage");
   FileWriteString(h,"s 2 and 3 are periods it has never seen, with completely new trades. Only the lesson is carried forward, never");
   FileWriteString(h," the trades. A result that only works in stage 1 is worthless; one that works in all three is worth testing li");
   FileWriteString(h,"ve.</div>\n<div><b>What do \"stop 0.5x\" and \"target 3x\" mean?</b>Every zone has a size, called 1x. Stop 0.5x put");
   FileWriteString(h,"s the stop half a zone away from the entry. Target 3x puts the target three zones away. Together that is a ris");
   FileWriteString(h,"k to reward of 1:6.</div>\n<div><b>What is a stop class (Tight, Medium, Wide)?</b>It sets how big 1x is. Tight ");
   FileWriteString(h,"uses the zone's own height. Medium makes it at least one normal 15-minute candle range. Wide makes it at least");
   FileWriteString(h," three. Wider stops survive more noise and make trading costs a smaller share of the risk, but the target is f");
   FileWriteString(h,"urther away too.</div>\n<div><b>What do Buys, Sells and Both mean?</b>Buys counts only the buy signals, Sells o");
   FileWriteString(h,"nly the sell signals, Both counts them together. On spike markets one side often behaves very differently from");
   FileWriteString(h," the other.</div>\n<div><b>What is a view?</b>A filter on a strategy. The first view takes every signal. Others");
   FileWriteString(h," take only signals with something extra, such as a second reason at the same price. \"Learned picks\" and \"Model");
   FileWriteString(h," picks\" take only the signals a learning step liked after studying stage 1.</div>\n<div><b>What do PASS and STR");
   FileWriteString(h,"ONGHOLD mean?</b>PASS: with one standard setup (risk 1 to make 2), the row made money in all three stages on e");
   FileWriteString(h,"nough trades. STRONGHOLD: the best stop and target for that row was picked in stage 1, confirmed in stage 2 an");
   FileWriteString(h,"d still made money in the stage 3 exam. Both mean \"worth testing live\", not \"guaranteed\".</div>\n<div><b>What i");
   FileWriteString(h,"s the \"by luck\" number?</b>When thousands of combinations are tested, some will look good by chance, like a fe");
   FileWriteString(h,"w people in a big crowd flipping ten heads in a row. The page works out how many rows would pass with no real ");
   FileWriteString(h,"edge at all. The further the real count is above that number, the more of the rows are genuine.</div>\n<div><b>");
   FileWriteString(h,"The nine strategies in one line each</b>Trap Zones: failed breakouts. Trap + Gap: a failed breakout with a pri");
   FileWriteString(h,"ce gap inside. Untouched Ground: price the market rushed through and never revisited. Rejection Stacks: a pric");
   FileWriteString(h,"e that has turned the market several times. Self-taught Zones: swing levels scored by a model. Self-taught 4H+");
   FileWriteString(h,"1D: the same on higher timeframes. FVG Confluence: price gaps that overlap across timeframes. Flip Levels: a b");
   FileWriteString(h,"roken ceiling that becomes a floor. Stretch Bands: price stretched far from its average.</div>\n<div><b>How do ");
   FileWriteString(h,"the signals arrive?</b>By Telegram. BUY LIMIT or SELL LIMIT: place a pending order now at the entry price, wit");
   FileWriteString(h,"h the stop and targets given, and wait. BUY NOW or SELL NOW: price has reached the zone, enter at market. GET ");
   FileWriteString(h,"READY: a setup may be coming, wait for the confirmation. CANCEL: the zone is no longer valid, delete the pendi");
   FileWriteString(h,"ng order. TP1 is the 1:1 point where part of the profit can be taken; TP2 is the full target.</div>\n<div><b>Wh");
   FileWriteString(h,"at is the live demo test, and why does it matter most?</b>A backtest looks backwards. The live demo test follo");
   FileWriteString(h,"ws the winners forwards, on prices nobody has seen yet, with real fills and real costs but no real money. If a");
   FileWriteString(h," setup keeps winning there, it has passed the only test that cannot be fooled by hindsight.</div>\n<div><b>How ");
   FileWriteString(h,"much should be risked on a trade?</b>1% of the account or less. Many of these setups lose 8 or 9 trades in 10 ");
   FileWriteString(h,"and make it back on the tenth. Click any row: its story shows the losing run to expect.</div>\n<div><b>Is any o");
   FileWriteString(h,"f this guaranteed?</b>No. Markets change, a backtest can flatter, and on spike markets a stop can be jumped so");
   FileWriteString(h," that a loss is bigger than planned. That is why nothing here goes to real money until it has held up on the l");
   FileWriteString(h,"ive demo test.</div>\n</div></div>\n");
   s="<div class='sub'>Data files in the same folder: summary.csv (every row), results.csv (every timeframe combination), bands.csv, coverage.csv, "+
     "watchlist.csv (what is followed live), forward.csv (every live demo trade).</div></div>";
   s+="<div id='mo' class='mo'><div class='mc'><span id='mx' class='mx'>close</span><div id='mb'></div></div></div>";
   FileWriteString(h,s);
   FileWriteString(h,"<script>var PICKSCORE="+DoubleToString(InpPickScore,2)+",SCAN="+(g_scanning ? "1" : "0")+";\n");
   FileWriteString(h,"var RISK=10,MOD=0;\ntry{var rs0=sessionStorage.getItem('t2r_risk');if(rs0)RISK=parseFloat(rs0)||10;}catch(e){}\n");
   FileWriteString(h,"var WHAT={\n'Trap Zones':'A failed breakout. Price breaks a level with a strong candle, traders jump in, then t");
   FileWriteString(h,"he very next candle wipes the move out. Those traders are now stuck, and the area they entered becomes a zone ");
   FileWriteString(h,"to trade against them.',\n'Trap + Gap':'A trap zone (a failed breakout) that also has a fair value gap inside i");
   FileWriteString(h,"t, so two reasons point to the same place.',\n'Untouched Ground':'A strip of price that the market rushed throu");
   FileWriteString(h,"gh once and has not been back to, sitting between two busy areas. The idea is that price reacts when it finall");
   FileWriteString(h,"y returns.',\n'Rejection Stacks':'A price where the market has been pushed back several separate times. Bounce ");
   FileWriteString(h,"trades the next push back from it. Sweep trades the turn after price pokes just past it to take out the stops ");
   FileWriteString(h,"resting there.',\n'Self-taught Zones':'Every recent swing high and low is a candidate. The computer studied whi");
   FileWriteString(h,"ch ones worked in stage 1 (by position, age, speed of approach, time of day and trend) and scores each new one");
   FileWriteString(h,".',\n'Self-taught 4H+1D':'The same self-taught model, using only swing highs and lows from the 4-hour and daily");
   FileWriteString(h," charts.',\n'FVG Confluence':'Fair value gaps: three candles where the market moved so fast it left a gap that ");
   FileWriteString(h,"was never traded both ways. When gaps on different timeframes overlap, they merge into one zone.',\n'Flip Level");
   FileWriteString(h,"s':'Going with a break instead of against it. A swing high that price closes above with a strong candle turns ");
   FileWriteString(h,"from ceiling to floor, and the first return to it is a buy. The mirror gives sells.',\n'Stretch Bands':'No char");
   FileWriteString(h,"t pattern, only distance. When price is stretched far above its recent average it is a sell zone; far below is");
   FileWriteString(h," a buy zone.'};\nvar VIEW={\n'Learned picks':'only the setups a learning step liked. It studied stage 1 and lear");
   FileWriteString(h,"ned which conditions the winners shared; stages 2 and 3 test that on trades it never saw.',\n'Model picks':'onl");
   FileWriteString(h,"y the levels the self-taught model scored highly.',\n'At a stack':'only traps that sit at a rejection stack.',\n");
   FileWriteString(h,"'With a gap':'only traps with a fair value gap inside.',\n'2+ timeframes':'only gaps where two or more timefram");
   FileWriteString(h,"es overlap.',\n'Bounce':'the bounce version.',\n'Sweep':'the sweep version.'};\nvar CLS={'Tight':'the stop unit i");
   FileWriteString(h,"s the height of the zone (small stops)','Medium':'the stop unit is at least one normal 15-minute candle range'");
   FileWriteString(h,",'Wide':'the stop unit is at least three normal 15-minute candle ranges'};\nfunction f2(x){return (x>=0?'+':'')");
   FileWriteString(h,"+x.toFixed(2);}\nfunction mny(r){var v=Math.round(r*RISK);return (v>=0?'+':'-')+'$'+Math.abs(v).toString().repl");
   FileWriteString(h,"ace(/\\B(?=(\\d{3})+(?!\\d))/g,',');}\nfunction pc(w,n){return n>0?Math.round(100*w/n)+'%':'-';}\nfunction cl(x){re");
   FileWriteString(h,"turn x>0.005?'g':(x<-0.005?'r':'n');}\nfunction showStory(tr){\nvar d=tr.getAttribute('data-d').split(','),k=tr.");
   FileWriteString(h,"getAttribute('data-k').split('|');\nvar n=[+d[0],+d[2],+d[4]],w=[+d[1],+d[3],+d[5]],ratio=+d[6],t1=[+d[7],+d[8]");
   FileWriteString(h,",+d[9]],dt=[d[10],d[11],d[12],d[13]],weeks=+d[14],e=[+d[15],+d[16],+d[17]];\nvar N=n[0]+n[1]+n[2],W=w[0]+w[1]+w");
   FileWriteString(h,"[2],L=N-W,be=100/(1+ratio),rt=Math.round(ratio*100)/100;\nvar un=n[1]+n[2],uw=w[1]+w[2];\nvar R=[e[0]*n[0],e[1]*");
   FileWriteString(h,"n[1],e[2]*n[2]],RT=R[0]+R[1]+R[2];\nvar nm=['Stage 1 (learning)','Stage 2 (first unseen test)','Stage 3 (final ");
   FileWriteString(h,"exam)'];\nvar good=e[1]>0&&e[2]>0&&n[1]>0&&n[2]>0,strong=good&&Math.min(n[1],n[2])>=100;\nvar h='<h2>'+k[0]+'</h");
   FileWriteString(h,"2><div class=\"sub\">'+k[1]+' &middot; '+k[2]+' &middot; '+k[3]+' &middot; '+k[4]+' stop class &middot; stop '+k");
   FileWriteString(h,"[5]+', target '+k[6]+'</div>';\nh+='<p class=\"vd\"><b>Bottom line:</b> in the backtest this '+(strong?'made mone");
   FileWriteString(h,"y in both unseen stages on a decent number of trades. A serious candidate; the live demo test decides.':(good?");
   FileWriteString(h,"'made money in both unseen stages, but on a small number of trades. Promising, not proven.':'did not make mone");
   FileWriteString(h,"y in both unseen stages. Not something to trade as it stands.'))+'</p>';\nh+='<h3>What the strategy does</h3><p");
   FileWriteString(h,">'+(WHAT[k[1]]||'')+(VIEW[k[2]]?' This row takes '+VIEW[k[2]]:'')+'</p>';\nh+='<p>Side: '+(k[3]=='Both'?'buy an");
   FileWriteString(h,"d sell signals together':(k[3]=='Buys'?'buy signals only':'sell signals only'))+'. Stop class '+k[4]+': '+(CLS");
   FileWriteString(h,"[k[4]]||'')+'.</p>';\nh+='<h3>The trade</h3><ul><li><b>Risk to reward 1:'+rt+'.</b> A losing trade costs 1R (th");
   FileWriteString(h,"e amount risked). A winning trade pays '+rt+'R.</li>';\nh+='<li><b>Break-even win rate: '+be.toFixed(0)+'%.</b>");
   FileWriteString(h," Win more often than that and it makes money; win less often and it loses.</li>';\nh+='<li><b>Win rate on histo");
   FileWriteString(h,"ry it never saw (stages 2 and 3): '+pc(uw,un)+'</b> ('+uw+' wins in '+un+' trades).</li></ul>';\nh+='<h3>What h");
   FileWriteString(h,"appened in the test</h3><table class=\"st\"><tr><th class=\"l\">Period</th><th class=\"l\">Dates</th><th>Trades</th>");
   FileWriteString(h,"<th>Won</th><th>Lost</th><th>Win rate</th><th>Average per trade</th><th>Total</th><th>With $'+RISK+' risked pe");
   FileWriteString(h,"r trade</th></tr>';\nfor(var s=0;s<3;s++){h+='<tr><td class=\"l\">'+nm[s]+'</td><td class=\"l\">'+dt[s]+' to '+dt[s");
   FileWriteString(h,"+1]+'</td><td>'+n[s]+'</td><td>'+w[s]+'</td><td>'+(n[s]-w[s])+'</td><td>'+pc(w[s],n[s])+'</td><td class=\"'+cl(");
   FileWriteString(h,"e[s])+'\">'+f2(e[s])+'R</td><td class=\"'+cl(R[s])+'\">'+f2(R[s])+'R</td><td class=\"'+cl(R[s])+'\">'+mny(R[s])+'</");
   FileWriteString(h,"td></tr>';}\nh+='<tr class=\"tot\"><td class=\"l\">Whole test</td><td class=\"l\">'+dt[0]+' to '+dt[3]+'</td><td>'+N+");
   FileWriteString(h,"'</td><td>'+W+'</td><td>'+L+'</td><td>'+pc(W,N)+'</td><td class=\"'+cl(RT)+'\">'+(N>0?f2(RT/N):'-')+'R</td><td c");
   FileWriteString(h,"lass=\"'+cl(RT)+'\">'+f2(RT)+'R</td><td class=\"'+cl(RT)+'\">'+mny(RT)+'</td></tr></table>';\nh+='<p class=\"note\">W");
   FileWriteString(h,"ins and losses are counted exactly. The averages and totals are after trading costs (the spread on every trade");
   FileWriteString(h,"). Stage 1 is where the strategy learned or was picked, so only stages 2 and 3 are a fair test.</p>';\nvar pw=w");
   FileWriteString(h,"eeks>0?N/weeks:0,wr=N>0?W/N:0;\nvar streak=(wr>0&&wr<1&&N>1)?Math.round(Math.log(N)/Math.log(1/(1-wr))):0;\nh+='");
   FileWriteString(h,"<h3>What to expect if you follow it</h3><ul><li>About <b>'+(pw>=1?pw.toFixed(1)+' signals a week':(pw*4.3).toF");
   FileWriteString(h,"ixed(1)+' signals a month')+'</b>.</li>';\nh+='<li>It loses about <b>'+Math.round(100*(1-wr))+' trades in every");
   FileWriteString(h," 100</b>. A run of about <b>'+streak+' losses in a row</b> is normal for a record like this and should be expe");
   FileWriteString(h,"cted.</li>';\nh+='<li>Risking 1% of the account per trade, that losing run costs about '+streak+'% of the accou");
   FileWriteString(h,"nt before the next win. This is why the risk on each trade must stay small.</li>';\nif(t1[1]>=0&&ratio>1){var u");
   FileWriteString(h,"1=t1[1]+t1[2];h+='<li><b>Taking profit early:</b> on unseen history '+pc(u1,un)+' of trades reached 1:1 (a pro");
   FileWriteString(h,"fit equal to the risk) before the stop. The full target was reached '+pc(uw,un)+' of the time.</li>';}\nelse if");
   FileWriteString(h,"(ratio>1){h+='<li>How often it reaches 1:1 before the stop was not measured for this stop size in the backtest");
   FileWriteString(h,". The live demo test measures it.</li>';}\nh+='</ul>';\nif(d.length>=26){var lw=+d[18],ll=+d[19],lr=+d[20],l1=+d");
   FileWriteString(h,"[21],lr2=+d[22],lp=+d[23],lo=+d[24],lc=+d[25],ld=lw+ll;\nh+='<h3>Live demo test so far</h3>';\nif(ld+lp+lo==0){h");
   FileWriteString(h,"+='<p>No signal yet.'+(lc>0?' '+lc+' pending orders were cancelled before price reached them.':'')+'</p>';}\nel");
   FileWriteString(h,"se{h+='<ul><li>Pending orders waiting: '+lp+'. Trades open now: '+lo+'. Cancelled before filling: '+lc+'.</li>");
   FileWriteString(h,"';\nif(ld>0){h+='<li>Closed trades: '+ld+' ('+lw+' won, '+ll+' lost, win rate '+pc(lw,ld)+').</li><li>Reached 1");
   FileWriteString(h,":1 before the stop: '+pc(l1,ld)+'.</li>';\nh+='<li>Holding every trade to the full target: <b class=\"'+cl(lr)+'");
   FileWriteString(h,"\">'+f2(lr)+'R</b> ('+mny(lr)+' with $'+RISK+' risked per trade).</li><li>Taking half off at 1:1: <b class=\"'+c");
   FileWriteString(h,"l(lr2)+'\">'+f2(lr2)+'R</b> ('+mny(lr2)+').</li>';\nh+='<li>'+(ld<20?'Too early to judge: wait for at least 20 c");
   FileWriteString(h,"losed trades.':(lr/ld>=0.05?'Holding up on fresh trades so far.':'Not holding up on fresh trades so far.'))+'<");
   FileWriteString(h,"/li>';}\nh+='</ul>';}}\nvar notes=[];\nif(Math.min(n[1],n[2])<60)notes.push('Small sample: one of the unseen stag");
   FileWriteString(h,"es has fewer than 60 trades. A handful of trades going the other way would change the picture.');\nif(ratio>=6)");
   FileWriteString(h,"notes.push('Long-shot payoff: it wins rarely and big. Results like this swing a lot, and '+uw+' wins is all th");
   FileWriteString(h,"at stands between profit and loss on unseen history.');\nif(/Boom|Crash|Jump|Range Break/.test(k[0]))notes.push");
   FileWriteString(h,"('This market spikes. A spike can jump over a stop, making a real loss bigger than planned. The backtest does ");
   FileWriteString(h,"not include that; the live demo test does.');\nif(k[2]=='Learned picks'||k[2]=='Model picks')notes.push('Stage ");
   FileWriteString(h,"1 flatters this row, because the model learned from stage 1. Judge it on stages 2 and 3.');\nnotes.push('Thousa");
   FileWriteString(h,"nds of combinations were tested. Some look good by luck alone, which is why every winner is re-tested live on ");
   FileWriteString(h,"demo before real money.');\nh+='<h3>Honest notes</h3><ul>';for(var i=0;i<notes.length;i++){h+='<li>'+notes[i]+'");
   FileWriteString(h,"</li>';}h+='</ul>';\ndocument.getElementById('mb').innerHTML=h;document.getElementById('mo').style.display='blo");
   FileWriteString(h,"ck';MOD=1;}\ndocument.addEventListener('click',function(ev){var t=ev.target;if(t.id=='mx'||t.id=='mo'){document");
   FileWriteString(h,".getElementById('mo').style.display='none';MOD=0;return;}\nvar tr=t.closest?t.closest('tr[data-d]'):null;if(tr)");
   FileWriteString(h,"{showStory(tr);}});\nfunction paintMoney(){var ms=document.querySelectorAll('.mn');for(var i=0;i<ms.length;i++)");
   FileWriteString(h,"{ms[i].textContent=mny(parseFloat(ms[i].getAttribute('data-r'))||0);}}\nvar ri=document.getElementById('risk');");
   FileWriteString(h,"\nif(ri){ri.value=RISK;ri.oninput=function(){var v=parseFloat(ri.value);if(v>0){RISK=v;try{sessionStorage.setIt");
   FileWriteString(h,"em('t2r_risk',v);}catch(e){}paintMoney();}};}\npaintMoney();\nvar bs=document.querySelectorAll('.fb');\nfor(var b");
   FileWriteString(h,"=0;b<bs.length;b++){(function(bx){var q=bx.querySelector('.q'),po=bx.querySelector('.po'),t=bx.querySelector('");
   FileWriteString(h,"table');if(!q||!t)return;var key='t2r_'+bx.id;\nfunction f(){var ws=q.value.toLowerCase().split(' ');var rs=t.t");
   FileWriteString(h,"Bodies[0].rows;\nfor(var i=0;i<rs.length;i++){var x=rs[i].textContent.toLowerCase(),ok=true;for(var j=0;j<ws.le");
   FileWriteString(h,"ngth;j++){if(ws[j]&&x.indexOf(ws[j])<0)ok=false;}\nif(po&&po.checked&&rs[i].className!='p')ok=false;rs[i].style");
   FileWriteString(h,".display=ok?'':'none';}\ntry{sessionStorage.setItem(key,q.value);sessionStorage.setItem(key+'p',(po&&po.checked");
   FileWriteString(h,")?'1':'');}catch(e){}}\ntry{q.value=sessionStorage.getItem(key)||'';if(po)po.checked=!!sessionStorage.getItem(k");
   FileWriteString(h,"ey+'p');}catch(e){}\nq.oninput=f;if(po)po.onchange=f;f();})(bs[b]);}\nsetInterval(function(){var a=document.acti");
   FileWriteString(h,"veElement;if(!MOD&&!(a&&a.tagName=='INPUT'))location.reload();},90000);\n");
   FileWriteString(h,"</script></body></html>");
   FileClose(h);
   g_lastHtml=GetTickCount();
  }

//+------------------------------------------------------------------+
//| Telegram                                                         |
//+------------------------------------------------------------------+
string UrlEnc(const string txt)
  {
   uchar b[];
   int n=StringToCharArray(txt,b,0,WHOLE_ARRAY,CP_UTF8)-1;
   string out="";
   for(int i=0;i<n;i++)
     {
      uchar c=b[i];
      if((c>='a' && c<='z') || (c>='A' && c<='Z') || (c>='0' && c<='9') || c=='-' || c=='_' || c=='.')
         out+=CharToString(c);
      else
         out+=StringFormat("%%%02X",c);
     }
   return out;
  }

bool Tg(const string text)
  {
   if(g_study || InpTgToken=="" || InpTgChat=="")
      return false;
   string url="https://api.telegram.org/bot"+InpTgToken+"/sendMessage";
   string body="chat_id="+UrlEnc(InpTgChat)+"&text="+UrlEnc(text);
   uchar post[];
   uchar res[];
   string hdr="";
   int len=StringToCharArray(body,post,0,WHOLE_ARRAY,CP_UTF8)-1;
   if(len<=0)
      return false;
   ArrayResize(post,len);
   ResetLastError();
   int code=WebRequest("POST",url,"Content-Type: application/x-www-form-urlencoded\r\n",5000,post,res,hdr);
   if(code!=200)
     {
      Print("T2R Lab: Telegram not sent (code ",code,", error ",GetLastError(),
            "). In MT5: Tools > Options > Expert Advisors > allow WebRequest for https://api.telegram.org");
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Scan                                                             |
//+------------------------------------------------------------------+
bool StartsWith(const string s,const string p)
  {
   return (StringFind(s,p)==0);
  }

bool IsCcy(const string c)
  {
   return (StringLen(c)==3 && StringFind("USD,EUR,GBP,JPY,CHF,CAD,AUD,NZD,NOK,SEK,PLN,MXN,ZAR,CNH,SGD,HKD,THB",c)>=0);
  }

//--- which family an asset belongs to, judged from its name
//    0 Boom/Crash  1 Volatility  2 other synthetics  3 forex  4 metals  5 crypto  6 stock indices  7 commodities  8 the rest
int GroupOf(const string s)
  {
   if(StartsWith(s,"Boom ") || StartsWith(s,"Crash "))
      return 0;
   if(StartsWith(s,"Volatility ") || StartsWith(s,"High Frequency Vol"))
      return 1;
   string syn[12]={"Step Index","Jump ","DEX ","Multi Step","Skew Step","Range Break","Drift Switch","VolSwitch","Spot Up",
                   "Exponential Growth","Trek ","Vol over "};
   for(int i=0;i<12;i++)
      if(StartsWith(s,syn[i]))
         return 2;
   if(StringFind(s,".")>=0)
      return 8;
   if(StartsWith(s,"XAU") || StartsWith(s,"XAG") || StartsWith(s,"XPT") || StartsWith(s,"XPD") || StartsWith(s,"XCU"))
      return 4;
   string idx[18]={"Australia 200","China H Shares","Europe 50","France 40","Germany 40","Hong Kong 50","Japan 225","Netherlands 25",
                   "Spain 35","Swiss 20","UK 100","US Mid Cap 400","US SP 500","US Small Cap 2000","US Tech 100","Wall Street 30",
                   "VIXUSD","DXYUSD"};
   for(int i=0;i<18;i++)
      if(s==idx[i])
         return 6;
   string com[8]={"NGAS","UK Brent Oil","US Oil","CoffeeRobu","CoffeeArab","Cocoa","Sugar","Cotton"};
   for(int i=0;i<8;i++)
      if(s==com[i])
         return 7;
   if(StringLen(s)==6 && IsCcy(StringSubstr(s,0,3)) && IsCcy(StringSubstr(s,3,3)))
      return 3;
   if(StringLen(s)==6 && (StringSubstr(s,3,3)=="USD" || StartsWith(s,"BTC")))
      return 5;
   return 8;
  }

void AddSymbol(const string sy,const ENUM_TIMEFRAMES tf,const int bars)
  {
   for(int i=0;i<g_nSym;i++)
      if(g_syms[i]==sy && g_symTF[i]==tf)
         return;
   int n=g_nSym+1;
   ArrayResize(g_syms,n,64);
   ArrayResize(g_symTF,n,64);
   ArrayResize(g_symBars,n,64);
   ArrayResize(g_symNb,n,64);
   ArrayResize(g_symT0,n,64);
   ArrayResize(g_symT1,n,64);
   ArrayResize(g_symT2,n,64);
   ArrayResize(g_symT3,n,64);
   ArrayResize(g_symState,n,64);
   ArrayResize(g_symLast,n,64);
   ArrayResize(g_symStable,n,64);
   ArrayResize(g_symAt,n,64);
   g_syms[g_nSym]=sy;
   g_symTF[g_nSym]=tf;
   g_symBars[g_nSym]=bars;
   g_symNb[g_nSym]=0;
   g_symT0[g_nSym]=0;
   g_symT1[g_nSym]=0;
   g_symT2[g_nSym]=0;
   g_symT3[g_nSym]=0;
   g_symState[g_nSym]=0;
   g_symLast[g_nSym]=-1;
   g_symStable[g_nSym]=0;
   g_symAt[g_nSym]=0;
   g_nSym++;
  }

//--- has MT5 finished loading this market's history? A test on half-loaded history gives a different answer every run.
//    Ready = everything asked for is there, or the amount on offer has stopped growing (the broker has no more).
bool HistoryReady(const int i)
  {
   if(g_symState[i]==1)
      return true;
   if(g_symAt[i]!=0 && GetTickCount()-g_symAt[i]<15000)
      return false;                                  // asked a moment ago: give the download time
   g_symAt[i]=GetTickCount();
   if(g_symAt[i]==0)
      g_symAt[i]=1;
   string sy=g_syms[i];
   int want=MathMax(g_symBars[i],200);
   int ps=PeriodSeconds(g_symTF[i]);
   MqlRates tmp[];
   bool full=true;
   int got=CopyRates(sy,g_symTF[i],0,want+50,tmp);
   long sum=MathMax(got,0);
   if(got<(int)(0.98*want))
      full=false;
   ENUM_TIMEFRAMES hi[4];
   hi[0]=InpTF1;
   hi[1]=InpTF2;
   hi[2]=InpTF3;
   hi[3]=InpTF4;
   for(int k=0;k<4;k++)
     {
      int hs=PeriodSeconds(hi[k]);
      if(hs<=ps)
         continue;
      int need=(int)((long)want*ps/hs)+10;
      int g2=CopyRates(sy,hi[k],0,need,tmp);
      sum+=MathMax(g2,0);
      if(g2<(int)(0.98*need))
         full=false;
     }
   if(full)
     {
      g_symState[i]=1;
      return true;
     }
   if(sum>0 && sum==g_symLast[i])
      g_symStable[i]++;
   else
      g_symStable[i]=0;
   g_symLast[i]=sum;
   if(g_symStable[i]>=3)
      g_symState[i]=1;                               // nothing more is coming: test what there is
   return (g_symState[i]==1);
  }

void BuildSymbols()
  {
   g_nSym=0;
   ArrayResize(g_syms,0);
   ArrayResize(g_symTF,0);
   ArrayResize(g_symBars,0);
   ArrayResize(g_symNb,0);
   ArrayResize(g_symState,0);
   bool on[9];
   on[0]=InpGrpBoomCrash;
   on[1]=InpGrpVol;
   on[2]=InpGrpSynth;
   on[3]=InpGrpForex;
   on[4]=InpGrpMetals;
   on[5]=InpGrpCrypto;
   on[6]=InpGrpIndices;
   on[7]=InpGrpCommod;
   on[8]=InpGrpStocks;
   if(g_study)
     {
      int na=SymbolsTotal(false);
      for(int i=0;i<na;i++)
        {
         string sy=SymbolName(i,false);
         if(sy!="" && StudyMatch(sy) && SymbolSelect(sy,true))
            AddSymbol(sy,InpChartTF,InpScoreBars);
        }
      Print("T2R Lab STUDY: ",g_nSym," markets match \"",InpStudyOnly,"\"");
      return;
     }
//--- everything in Market Watch that belongs to a ticked family
   int n=SymbolsTotal(true);
   for(int i=0;i<n;i++)
     {
      string sy=SymbolName(i,true);
      if(sy!="" && on[GroupOf(sy)])
         AddSymbol(sy,InpChartTF,InpScoreBars);
     }
//--- plus any extras typed in by name
   if(InpSymbols!="")
     {
      string parts[];
      int np=StringSplit(InpSymbols,',',parts);
      for(int i=0;i<np;i++)
        {
         string sy=parts[i];
         StringTrimLeft(sy);
         StringTrimRight(sy);
         if(sy!="" && SymbolSelect(sy,true))
            AddSymbol(sy,InpChartTF,InpScoreBars);
        }
     }
//--- the finer check: the same assets again on a smaller chart
   if(InpFineSymbols!="" && InpFineTF!=InpChartTF)
     {
      string parts[];
      int np=StringSplit(InpFineSymbols,',',parts);
      for(int i=0;i<np;i++)
        {
         string sy=parts[i];
         StringTrimLeft(sy);
         StringTrimRight(sy);
         if(sy!="" && SymbolSelect(sy,true))
            AddSymbol(sy,InpFineTF,InpFineBars);
        }
     }
  }

void StartScan()
  {
   BuildSymbols();
   int jobs=g_nSym*NSTRAT;
   ArrayResize(g_done,MathMax(jobs,1));
   ArrayResize(g_try,MathMax(jobs,1));
   ArrayResize(g_tryAt,MathMax(jobs,1));
   ArrayInitialize(g_tryAt,0);
   ArrayInitialize(g_done,0);
   ArrayInitialize(g_try,0);
   g_job=0;
   g_jobsDone=0;
   g_nRows=0;
   g_liveScale=0;
   ArrayInitialize(g_bandN,0);
   ArrayInitialize(g_bandH,0);
   g_scanning=(jobs>0);
   g_scanStart=TimeLocal();
   CsvHeader();
   WriteHtml();
   Print("T2R Lab: scan started, ",g_nSym," assets x ",NSTRAT," strategies");
  }

void WriteBands()
  {
   int h=FileOpen(DIR_OUT+"bands.csv",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE)
      return;
   FileWriteString(h,"model,stop_class,score_band,stage,tests,hit_0.5x,hit_1x,hit_2x,hit_3x\r\n");
   for(int m=0;m<2;m++)
      for(int sc=0;sc<NSC;sc++)
         for(int b=0;b<5;b++)
            for(int sg=0;sg<3;sg++)
              {
               int i=((m*NSC+sc)*5+b)*3+sg;
               FileWriteString(h,g_sName[4+m]+","+g_scName[sc]+","+g_bandName[b]+","+g_segName[sg]+","+IntegerToString(g_bandN[i])+","+
                               IntegerToString(g_bandH[i*4])+","+IntegerToString(g_bandH[i*4+1])+","+IntegerToString(g_bandH[i*4+2])+","+
                               IntegerToString(g_bandH[i*4+3])+"\r\n");
              }
   FileClose(h);
  }

void FinishScan()
  {
   if(g_study)
     {
      g_scanning=false;
      if(g_studyH!=INVALID_HANDLE)
         FileClose(g_studyH);
      g_studyH=INVALID_HANDLE;
      int h=FileOpen(DIR_OUT+"study_views.csv",FILE_WRITE|FILE_TXT|FILE_ANSI);
      if(h!=INVALID_HANDLE)
        {
         FileWriteString(h,"strategy,view_all,view_second\r\n");
         for(int st=0;st<NSTRAT;st++)
            FileWriteString(h,g_sName[st]+","+g_v0[st]+","+g_v1[st]+"\r\n");
         FileClose(h);
        }
      Comment("T2R Lab STUDY done: ",g_studyN," trades from ",g_nSym," markets. File: MQL5\\Files\\",DIR_OUT,"study.csv");
      Print("T2R Lab STUDY done: ",g_studyN," trades written to MQL5\\Files\\",DIR_OUT,"study.csv");
      return;
     }
   g_scanning=false;
   g_scanEnd=TimeLocal();
   BuildWatch();
   EnsureBest();
   ReplayStart();
   WriteHtml();
   WriteBands();
   WriteSummary();
   WriteCoverage();
   int nPass=0;
   string top="";
   for(int i=0;i<g_nRows;i++)
      if(g_rows[i].pass)
        {
         nPass++;
         if(nPass<=8)
            top+="\n"+g_rows[i].sym+" | "+g_sName[g_rows[i].strat]+" | "+ViewName(g_rows[i].strat,g_rows[i].view)+" | "+g_sideName[g_rows[i].side]+
                 " | "+g_scName[g_rows[i].scale]+" stop | stages "+RTxt(g_rows[i].ev[0])+" / "+RTxt(g_rows[i].ev[1])+" / "+RTxt(g_rows[i].ev[2])+
                 "R, "+IntegerToString(g_rows[i].n)+" tests";
        }
   string msg="T2R Lab scan complete ("+TFName(InpChartTF)+")\n"+IntegerToString(g_nSym)+" assets, "+IntegerToString(g_nRows)+
              " rows tested, "+IntegerToString(nPass)+" passed all three stages.";
   if(nPass>0)
      msg+="\n\nPassed (demo-test these next, not proof):"+top;
   Tg(msg);
   Print("T2R Lab: scan complete, ",g_nRows," rows, ",nPass," passed. Dashboard: MQL5\\Files\\",DIR_OUT,"dashboard.html");
  }

//--- one asset x strategy; returns false when the data is not ready yet
bool RunJob(const int job)
  {
   int si=job/NSTRAT;
   int st=job%NSTRAT;
   if(!SetContext(si))
      return false;
   if(!HistoryReady(si))
      return false;
   SetStrategy(st);
   if(g_nAct==0)
      return true;                                   // nothing above the chart timeframe: nothing to test
   g_modelKey="";
   g_liveScale=0;
//--- ask MT5 for the history first, so assets without an open chart start downloading
   MqlRates warm[];
   CopyRates(g_sym,g_per,0,10,warm);
   for(int d=0;d<g_nAct;d++)
      CopyRates(g_sym,g_tf[g_act[d]],0,10,warm);
   g_bandOn=((st==4 || st==5) && g_per==InpChartTF);
   g_bandStrat=st-4;
   RunScore();
   g_bandOn=false;
   if(!g_scoreOk)
      return false;
   g_symNb[si]=g_scoreBars+20;
   g_symT0[si]=g_scoreT[0];
   g_symT1[si]=g_scoreT[1];
   g_symT2[si]=g_scoreT[2];
   g_symT3[si]=g_scoreT[3];
   Summarise();
   CsvAppend();
   return true;
  }

void ScanStep()
  {
   int jobs=g_nSym*NSTRAT;
   uint t0=GetTickCount();
   int looked=0;
   while(looked<jobs && GetTickCount()-t0<600)
     {
      int j=g_job;
      g_job=(g_job+1)%jobs;
      looked++;
      if(g_done[j]!=0)
         continue;
      if(g_try[j]>0 && GetTickCount()-g_tryAt[j]<20000)
         continue;                                   // give MT5 time to download this asset's history
      g_tryAt[j]=GetTickCount();
      if(RunJob(j))
        {
         g_done[j]=1;
         g_jobsDone++;
        }
      else
        {
         g_try[j]++;
         if(g_try[j]>=40)
           {
            g_done[j]=2;                              // no usable history for this asset
            g_jobsDone++;
           }
        }
     }
   Comment("T2R Lab: scanning ",g_jobsDone," / ",jobs,"   rows ",g_nRows);
   if(g_jobsDone>=jobs)
     {
      FinishScan();
      Comment("T2R Lab: scan complete. ",g_nRows," rows. Open MQL5\\Files\\",DIR_OUT,"dashboard.html");
      return;
     }
   if(GetTickCount()-g_lastHtml>45000)
      WriteHtml();
  }

//+------------------------------------------------------------------+
//| Live demo test                                                   |
//+------------------------------------------------------------------+
struct Watch
  {
   string            sym;
   int               strat;
   int               view;
   int               side;
   int               scale;
   int               si;         // stop size index
   int               lv;         // target index
   double            bt[3];      // backtest average R in stages 1, 2, 3 for this stop and target
   int               btN;
   bool              house;      // followed because its whole asset family passed
   bool              gOk;
   bool              mOk;
   double            wr;         // backtest win rate on unseen history (stages 2 and 3)
   double            tp1;        // backtest share of trades that reached 1:1 before the stop (-1 = not measured)
   double            perWeek;    // signals a week in the backtest
   int               bn[3];      // backtest trades per stage
   int               bw[3];      // backtest wins per stage
   int               b1[3];      // backtest trades that reached 1:1, per stage (-1 = not measured)
   datetime          tt[4];      // test start, stage 2 start, stage 3 start, test end
   double            gl[26];
   double            lift[18];
   int               nSig;       // demo trades entered
   int               nWin;
   int               nLoss;
   int               nOpen;
   int               nPend;
   int               nCancel;
   int               nTp1;       // closed trades that reached 1:1 first
   double            sumR;       // result holding everything to the full target
   double            sumR2;      // result taking half off at 1:1
  };

struct LiveTrade
  {
   int               w;
   int               dir;
   int               state;      // 0 = pending order waiting, 1 = in the trade
   double            entry;
   double            stop;
   double            target;
   double            unit;       // 1R in price = the stop distance
   double            tp1;        // the 1:1 price
   bool              hit1;
   bool              be;
   long              msg;
   ulong             tk;         // the real demo order / position ticket (0 = not traded)
   double            lots;       // lots used on the demo account        // Telegram message id of the signal (0 = not posted)         // after +1R price came back to entry (T2R rule: the second half closed at entry)
   datetime          tIn;        // when the signal was given
   datetime          tFill;
   datetime          tSeen;      // last one-minute candle already checked
   string            zkey;       // which zone this order belongs to
  };

Watch    g_watch[];
int      g_nWatch     = 0;
bool     g_watchFrozen= false;
LiveTrade g_open[];
int      g_nOpen      = 0;
bool     g_openDirty  = false;
//--- strategies whose zones stay put, so a pending order can be placed ahead of time
bool     g_pendOK[NSTRAT]={true,true,false,true,true,true,true,true,false};

bool WasAlerted(const string key)
  {
   for(int i=0;i<g_nAlerted;i++)
      if(g_alerted[i]==key)
         return true;
   if(g_nAlerted>=8000)
      g_nAlerted=0;
   ArrayResize(g_alerted,g_nAlerted+1,1024);
   g_alerted[g_nAlerted]=key;
   g_nAlerted++;
   return false;
  }

string WatchLabel(const int w)
  {
   return g_watch[w].sym+" | "+g_sName[g_watch[w].strat]+" | "+ViewName(g_watch[w].strat,g_watch[w].view)+" | "+g_sideName[g_watch[w].side]+
          " | "+g_scName[g_watch[w].scale]+" | stop "+g_smName[g_watch[w].si]+", target "+g_levName[g_watch[w].lv];
  }

double WatchRatio(const int w)
  {
   return g_lev[g_watch[w].lv]/g_sm[g_watch[w].si];
  }

//--- the track record lines every signal message carries
string RecordText(const int w)
  {
   double ratio=WatchRatio(w);
   int done=g_watch[w].nWin+g_watch[w].nLoss;
   string s="Risk to reward "+RRText(g_watch[w].si,g_watch[w].lv)+". Backtest on unseen history: won about "+
            IntegerToString((int)MathRound(100.0*g_watch[w].wr))+" in 100 (break-even is "+IntegerToString((int)MathRound(100.0/(1.0+ratio)))+" in 100)";
   if(g_watch[w].tp1>=0.0 && ratio>1.0)
      s+=", reached 1:1 first about "+IntegerToString((int)MathRound(100.0*g_watch[w].tp1))+" in 100";
   s+=". About "+DoubleToString(g_watch[w].perWeek,1)+" signals a week.\nLive demo so far: "+IntegerToString(g_watch[w].nWin)+" wins, "+
      IntegerToString(g_watch[w].nLoss)+" losses"+((done>0) ? ", "+RTxt(g_watch[w].sumR)+"R" : "")+".";
   return s;
  }

//--- the list is kept in a file so it survives restarts and stays the same list
void SaveWatch()
  {
   int h=FileOpen(DIR_OUT+"watchlist.csv",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE)
      return;
   FileWriteString(h,"T2R_WATCH_150\r\n");
   for(int i=0;i<g_nWatch;i++)
     {
      string line=g_watch[i].sym+";"+IntegerToString(g_watch[i].strat)+";"+IntegerToString(g_watch[i].view)+";"+IntegerToString(g_watch[i].side)+";"+
                  IntegerToString(g_watch[i].scale)+";"+IntegerToString(g_watch[i].si)+";"+IntegerToString(g_watch[i].lv)+";"+
                  DoubleToString(g_watch[i].bt[0],4)+";"+DoubleToString(g_watch[i].bt[1],4)+";"+DoubleToString(g_watch[i].bt[2],4)+";"+
                  IntegerToString(g_watch[i].btN)+";"+(g_watch[i].house ? "1" : "0")+";"+(g_watch[i].gOk ? "1" : "0")+";"+(g_watch[i].mOk ? "1" : "0")+";"+
                  DoubleToString(g_watch[i].wr,4)+";"+DoubleToString(g_watch[i].tp1,4)+";"+DoubleToString(g_watch[i].perWeek,3);
      for(int q=0;q<3;q++)
         line+=";"+IntegerToString(g_watch[i].bn[q]);
      for(int q=0;q<3;q++)
         line+=";"+IntegerToString(g_watch[i].bw[q]);
      for(int q=0;q<3;q++)
         line+=";"+IntegerToString(g_watch[i].b1[q]);
      for(int q=0;q<4;q++)
         line+=";"+IntegerToString((long)g_watch[i].tt[q]);
      for(int q=0;q<26;q++)
         line+=";"+DoubleToString(g_watch[i].gl[q],6);
      for(int q=0;q<18;q++)
         line+=";"+DoubleToString(g_watch[i].lift[q],6);
      FileWriteString(h,line+"\r\n");
     }
   FileClose(h);
  }

void ZeroLive(const int w)
  {
   g_watch[w].nSig=0;
   g_watch[w].nWin=0;
   g_watch[w].nLoss=0;
   g_watch[w].nOpen=0;
   g_watch[w].nPend=0;
   g_watch[w].nCancel=0;
   g_watch[w].nTp1=0;
   g_watch[w].sumR=0.0;
   g_watch[w].sumR2=0.0;
  }

void LoadWatch()
  {
   g_nWatch=0;
   g_watchFrozen=false;
   ArrayResize(g_watch,0);
   if(!FileIsExist(DIR_OUT+"watchlist.csv"))
      return;
   int h=FileOpen(DIR_OUT+"watchlist.csv",FILE_READ|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE)
      return;
   string head=FileReadString(h);
   StringTrimRight(head);
   if(head!="T2R_WATCH_150")
     {
      FileClose(h);                                  // a list from an older version: a new one is built after the scan
      return;
     }
   while(!FileIsEnding(h))
     {
      string line=FileReadString(h);
      StringTrimRight(line);
      string p[];
      if(StringSplit(line,';',p)<74)
         continue;
      int st=(int)StringToInteger(p[1]);
      if(st<0 || st>=NSTRAT || !SymbolSelect(p[0],true))
         continue;
      ArrayResize(g_watch,g_nWatch+1,64);
      int w=g_nWatch;
      g_watch[w].sym=p[0];
      g_watch[w].strat=st;
      g_watch[w].view=Clamp((int)StringToInteger(p[2]),0,2);
      g_watch[w].side=Clamp((int)StringToInteger(p[3]),0,2);
      g_watch[w].scale=Clamp((int)StringToInteger(p[4]),0,NSC-1);
      g_watch[w].si=Clamp((int)StringToInteger(p[5]),0,3);
      g_watch[w].lv=Clamp((int)StringToInteger(p[6]),0,3);
      g_watch[w].bt[0]=StringToDouble(p[7]);
      g_watch[w].bt[1]=StringToDouble(p[8]);
      g_watch[w].bt[2]=StringToDouble(p[9]);
      g_watch[w].btN=(int)StringToInteger(p[10]);
      g_watch[w].house=(p[11]=="1");
      g_watch[w].gOk=(p[12]=="1");
      g_watch[w].mOk=(p[13]=="1");
      g_watch[w].wr=StringToDouble(p[14]);
      g_watch[w].tp1=StringToDouble(p[15]);
      g_watch[w].perWeek=StringToDouble(p[16]);
      for(int q=0;q<3;q++)
        {
         g_watch[w].bn[q]=(int)StringToInteger(p[17+q]);
         g_watch[w].bw[q]=(int)StringToInteger(p[20+q]);
         g_watch[w].b1[q]=(int)StringToInteger(p[23+q]);
        }
      for(int q=0;q<4;q++)
         g_watch[w].tt[q]=(datetime)StringToInteger(p[26+q]);
      for(int q=0;q<26;q++)
         g_watch[w].gl[q]=StringToDouble(p[30+q]);
      for(int q=0;q<18;q++)
         g_watch[w].lift[q]=StringToDouble(p[56+q]);
      ZeroLive(w);
      g_nWatch++;
     }
   FileClose(h);
   g_watchFrozen=(g_nWatch>0);
  }

//--- closed live trades so far
void LoadLedger()
  {
   if(!FileIsExist(DIR_OUT+"forward.csv"))
      return;
   int h=FileOpen(DIR_OUT+"forward.csv",FILE_READ|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE)
      return;
   FileReadString(h);                                // header
   while(!FileIsEnding(h))
     {
      string line=FileReadString(h);
      StringTrimRight(line);
      string p[];
      if(StringSplit(line,',',p)<18)
         continue;
      int w=(int)StringToInteger(p[3]);
      if(w<0 || w>=g_nWatch)
         continue;
      double r=StringToDouble(p[15]);
      g_watch[w].nSig++;
      g_watch[w].sumR+=r;
      g_watch[w].sumR2+=StringToDouble(p[17]);
      if(p[16]=="yes")
         g_watch[w].nTp1++;
      if(r>0.0)
         g_watch[w].nWin++;
      else
         g_watch[w].nLoss++;
     }
   FileClose(h);
  }

void SaveOpen()
  {
   int h=FileOpen(DIR_OUT+"open.csv",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE)
      return;
   for(int k=0;k<g_nOpen;k++)
      FileWriteString(h,IntegerToString(g_open[k].w)+";"+IntegerToString(g_open[k].dir)+";"+IntegerToString(g_open[k].state)+";"+
                      DoubleToString(g_open[k].entry,8)+";"+DoubleToString(g_open[k].stop,8)+";"+DoubleToString(g_open[k].target,8)+";"+
                      DoubleToString(g_open[k].unit,8)+";"+DoubleToString(g_open[k].tp1,8)+";"+(g_open[k].hit1 ? "1" : "0")+";"+
                      IntegerToString((long)g_open[k].tIn)+";"+IntegerToString((long)g_open[k].tFill)+";"+IntegerToString((long)g_open[k].tSeen)+";"+
                      g_open[k].zkey+";"+(g_open[k].be ? "1" : "0")+";"+IntegerToString(g_open[k].msg)+";"+IntegerToString((long)g_open[k].tk)+";"+DoubleToString(g_open[k].lots,2)+"\r\n");
   FileClose(h);
   g_openDirty=false;
  }

void LoadOpen()
  {
   g_nOpen=0;
   ArrayResize(g_open,0);
   if(!FileIsExist(DIR_OUT+"open.csv"))
      return;
   int h=FileOpen(DIR_OUT+"open.csv",FILE_READ|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE)
      return;
   while(!FileIsEnding(h))
     {
      string line=FileReadString(h);
      StringTrimRight(line);
      string p[];
      if(StringSplit(line,';',p)<13)
         continue;
      int w=(int)StringToInteger(p[0]);
      if(w<0 || w>=g_nWatch)
         continue;
      ArrayResize(g_open,g_nOpen+1,64);
      g_open[g_nOpen].w=w;
      g_open[g_nOpen].dir=(int)StringToInteger(p[1]);
      g_open[g_nOpen].state=(int)StringToInteger(p[2]);
      g_open[g_nOpen].entry=StringToDouble(p[3]);
      g_open[g_nOpen].stop=StringToDouble(p[4]);
      g_open[g_nOpen].target=StringToDouble(p[5]);
      g_open[g_nOpen].unit=StringToDouble(p[6]);
      g_open[g_nOpen].tp1=StringToDouble(p[7]);
      g_open[g_nOpen].hit1=(p[8]=="1");
      g_open[g_nOpen].tIn=(datetime)StringToInteger(p[9]);
      g_open[g_nOpen].tFill=(datetime)StringToInteger(p[10]);
      g_open[g_nOpen].tSeen=(datetime)StringToInteger(p[11]);
      g_open[g_nOpen].zkey=p[12];
      g_open[g_nOpen].be=(ArraySize(p)>13 && p[13]=="1");
      g_open[g_nOpen].msg=(ArraySize(p)>14) ? StringToInteger(p[14]) : 0;
      g_open[g_nOpen].tk=(ArraySize(p)>15) ? (ulong)StringToInteger(p[15]) : 0;
      g_open[g_nOpen].lots=(ArraySize(p)>16) ? StringToDouble(p[16]) : 0.0;
      if(g_open[g_nOpen].state==1)
        {
         g_watch[w].nSig++;
         g_watch[w].nOpen++;
        }
      else
         g_watch[w].nPend++;
      //--- never repeat a signal for a zone already acted on
      WasAlerted(g_open[g_nOpen].zkey+"|"+IntegerToString(w)+"|in");
      WasAlerted(g_open[g_nOpen].zkey+"|"+IntegerToString(w)+"|p");
      g_nOpen++;
     }
   FileClose(h);
  }

//--- choose what to follow: every combo that held up in all three stages, strongest evidence first,
//    one setup per market / strategy / view / side, and only a few per market so no market crowds the list
//--- the proven setup (Boom & Crash, Self-taught Zones, Model picks, with the spike, Wide stop)
int BestSide(const string sy)
  {
   if(StringFind(sy,"Boom ")==0)  return 1;      // Boom spikes up: buys
   if(StringFind(sy,"Crash ")==0) return 2;      // Crash spikes down: sells
   return 0;
  }
bool IsBestW(const int w)
  {
   int sd=BestSide(g_watch[w].sym);
   return sd>0 && g_watch[w].strat==4 && g_watch[w].view==1 && g_watch[w].scale==2 && g_watch[w].side==sd;
  }
void FillWatch(const int w,const int i,const int si,const int lv)
  {
   int t1=Tp1Level(si);
   int nn=0;
   g_watch[w].sym=g_syms[g_rows[i].symIdx];
   g_watch[w].strat=g_rows[i].strat;
   g_watch[w].view=g_rows[i].view;
   g_watch[w].side=g_rows[i].side;
   g_watch[w].scale=g_rows[i].scale;
   g_watch[w].si=si;
   g_watch[w].lv=lv;
   for(int sg=0;sg<3;sg++)
     {
      g_watch[w].bt[sg]=PEV(g_rows[i].gn,g_rows[i].gh,g_rows[i].c,0,sg,si,lv,nn);
      g_watch[w].bn[sg]=g_rows[i].gn[sg*4+si];
      g_watch[w].bw[sg]=g_rows[i].gh[(sg*4+si)*4+lv];
      g_watch[w].b1[sg]=(t1>=0) ? g_rows[i].gh[(sg*4+si)*4+t1] : -1;
     }
   g_watch[w].btN=g_watch[w].bn[0]+g_watch[w].bn[1]+g_watch[w].bn[2];
   int un=g_watch[w].bn[1]+g_watch[w].bn[2];
   g_watch[w].wr=(un>0) ? (double)(g_watch[w].bw[1]+g_watch[w].bw[2])/un : 0.0;
   g_watch[w].tp1=(t1>=0 && un>0) ? (double)(g_watch[w].b1[1]+g_watch[w].b1[2])/un : -1.0;
   int x=g_rows[i].symIdx;
   g_watch[w].tt[0]=g_symT0[x];
   g_watch[w].tt[1]=g_symT1[x];
   g_watch[w].tt[2]=g_symT2[x];
   g_watch[w].tt[3]=g_symT3[x];
   double weeks=(double)((long)g_symT3[x]-(long)g_symT0[x])/604800.0;
   g_watch[w].perWeek=(weeks>0.0) ? g_watch[w].btN/weeks : 0.0;
   g_watch[w].house=false;
   g_watch[w].gOk=g_rows[i].gOk;
   g_watch[w].mOk=g_rows[i].mOk;
   for(int k=0;k<26;k++)
      g_watch[w].gl[k]=g_rows[i].gl[k];
   for(int k=0;k<18;k++)
      g_watch[w].lift[k]=g_rows[i].lift[k];
  }
//--- after every scan: make sure every Boom and Crash market follows the proven setup at 1x stop, 3x target
void EnsureBest()
  {
   if(!InpBestOnly)
      return;
   int added=0,fixed=0;
   for(int i=0;i<g_nRows;i++)
     {
      if(g_rows[i].strat!=4 || g_rows[i].view!=1 || g_rows[i].scale!=2 || g_symTF[g_rows[i].symIdx]!=InpChartTF)
         continue;
      string sy=g_syms[g_rows[i].symIdx];
      int sd=BestSide(sy);
      if(sd==0 || g_rows[i].side!=sd)
         continue;
      int w=-1;
      for(int e=0;e<g_nWatch;e++)
         if(g_watch[e].sym==sy && g_watch[e].strat==4 && g_watch[e].view==1 && g_watch[e].side==sd && g_watch[e].scale==2)
            w=e;
      if(w>=0)
        {
         if(g_watch[w].si!=2 || g_watch[w].lv!=3)
           {
            FillWatch(w,i,2,3);
            fixed++;
           }
         continue;
        }
      ArrayResize(g_watch,g_nWatch+1,64);
      w=g_nWatch;
      FillWatch(w,i,2,3);
      ZeroLive(w);
      g_nWatch++;
      added++;
     }
   SaveWatch();
   g_watchFrozen=(g_nWatch>0);
   Print("T2R Lab: proven Boom & Crash setup followed on every Boom and Crash market (",added," added, ",fixed," set to 1:3). Demo trades only take these.");
  }

void BuildWatch()
  {
   if(g_watchFrozen && InpWatchFreeze)
      return;
//--- whole families that passed at 1x stop, 2x target (both directions)
   int nfp=NFAM*NSTRAT*3*NSC;
   int fn[];
   int fh[];
   double fc[];
   ArrayResize(fn,nfp*3);
   ArrayResize(fh,nfp*3);
   ArrayResize(fc,nfp*3);
   ArrayInitialize(fn,0);
   ArrayInitialize(fh,0);
   ArrayInitialize(fc,0.0);
   for(int i=0;i<g_nRows;i++)
     {
      if(g_rows[i].side!=0 || g_symTF[g_rows[i].symIdx]!=InpChartTF)
         continue;
      int p=((g_rows[i].fam*NSTRAT+g_rows[i].strat)*3+g_rows[i].view)*NSC+g_rows[i].scale;
      for(int sg=0;sg<3;sg++)
        {
         fn[p*3+sg]+=g_rows[i].gn[sg*4+2];
         fh[p*3+sg]+=g_rows[i].gh[(sg*4+2)*4+2];
         fc[p*3+sg]+=g_rows[i].c[sg];
        }
     }
   int ci[];
   int cs[];
   int cl[];
   bool ch[];
   double ck[][2];
   int nc=0;
   int minN=MathMax(InpStageMinN,5);
   for(int i=0;i<g_nRows;i++)
     {
      if(g_symTF[g_rows[i].symIdx]!=InpChartTF)
         continue;
      int bs=-1;
      int bl=-1;
      double bz=-1e9;
      bool house=false;
      if(g_rows[i].side==0 && g_rows[i].n>=30)
        {
         int p=((g_rows[i].fam*NSTRAT+g_rows[i].strat)*3+g_rows[i].view)*NSC+g_rows[i].scale;
         house=true;
         for(int sg=0;sg<3;sg++)
           {
            int n=fn[p*3+sg];
            if(n<100 || 3.0*fh[p*3+sg]/n-1.0-fc[p*3+sg]/n<InpPassMinR)
               house=false;
           }
         if(house)
           {
            bs=2;
            bl=2;
            bz=1000.0;
           }
        }
      if(!house)
         for(int si=0;si<4;si++)
            for(int lv=0;lv<4;lv++)
              {
               int n1=0;
               int n2=0;
               int n3=0;
               double e1=PEV(g_rows[i].gn,g_rows[i].gh,g_rows[i].c,0,0,si,lv,n1);
               if(n1<minN || e1<InpConfirmR)
                  continue;
               double e2=PEV(g_rows[i].gn,g_rows[i].gh,g_rows[i].c,0,1,si,lv,n2);
               if(n2<minN || e2<InpConfirmR)
                  continue;
               double e3=PEV(g_rows[i].gn,g_rows[i].gh,g_rows[i].c,0,2,si,lv,n3);
               if(n3<minN || e3<InpConfirmR)
                  continue;
               //--- strength of evidence: size of the edge against how wildly this stop / target mix swings
               double ratio=g_lev[lv]/g_sm[si];
               double p0=1.0/(1.0+ratio);
               double sd=MathSqrt(p0*(1.0-p0))*(ratio+1.0);
               double z=MathMin(e2*MathSqrt((double)n2),e3*MathSqrt((double)n3))/sd;
               if(z>bz)
                 {
                  bz=z;
                  bs=si;
                  bl=lv;
                 }
              }
      if(bs<0)
         continue;
      ArrayResize(ci,nc+1,512);
      ArrayResize(cs,nc+1,512);
      ArrayResize(cl,nc+1,512);
      ArrayResize(ch,nc+1,512);
      ArrayResize(ck,nc+1,512);
      ci[nc]=i;
      cs[nc]=bs;
      cl[nc]=bl;
      ch[nc]=house;
      ck[nc][0]=-bz;
      ck[nc][1]=nc;
      nc++;
     }
   if(nc>0)
      ArraySort(ck);
   g_nWatch=0;
   ArrayResize(g_watch,0);
   int cap=MathMax(InpWatchMax,1);
   int perAsset=MathMax(InpWatchPerAsset,1);
   for(int q=0;q<nc && g_nWatch<cap;q++)
     {
      int c=(int)ck[q][1];
      int i=ci[c];
      string sy=g_syms[g_rows[i].symIdx];
      //--- fair share: a few per market, and never the same setup twice at different stop sizes
      int have=0;
      bool twin=false;
      for(int e=0;e<g_nWatch;e++)
        {
         if(g_watch[e].sym!=sy)
            continue;
         have++;
         if(g_watch[e].strat==g_rows[i].strat && g_watch[e].view==g_rows[i].view && g_watch[e].side==g_rows[i].side)
            twin=true;
        }
      if(twin || have>=perAsset)
         continue;
      ArrayResize(g_watch,g_nWatch+1,64);
      int w=g_nWatch;
      int si=cs[c];
      int lv=cl[c];
      int t1=Tp1Level(si);
      int nn=0;
      g_watch[w].sym=sy;
      g_watch[w].strat=g_rows[i].strat;
      g_watch[w].view=g_rows[i].view;
      g_watch[w].side=g_rows[i].side;
      g_watch[w].scale=g_rows[i].scale;
      g_watch[w].si=si;
      g_watch[w].lv=lv;
      for(int sg=0;sg<3;sg++)
        {
         g_watch[w].bt[sg]=PEV(g_rows[i].gn,g_rows[i].gh,g_rows[i].c,0,sg,si,lv,nn);
         g_watch[w].bn[sg]=g_rows[i].gn[sg*4+si];
         g_watch[w].bw[sg]=g_rows[i].gh[(sg*4+si)*4+lv];
         g_watch[w].b1[sg]=(t1>=0) ? g_rows[i].gh[(sg*4+si)*4+t1] : -1;
        }
      g_watch[w].btN=g_watch[w].bn[0]+g_watch[w].bn[1]+g_watch[w].bn[2];
      int un=g_watch[w].bn[1]+g_watch[w].bn[2];
      g_watch[w].wr=(un>0) ? (double)(g_watch[w].bw[1]+g_watch[w].bw[2])/un : 0.0;
      g_watch[w].tp1=(t1>=0 && un>0) ? (double)(g_watch[w].b1[1]+g_watch[w].b1[2])/un : -1.0;
      int x=g_rows[i].symIdx;
      g_watch[w].tt[0]=g_symT0[x];
      g_watch[w].tt[1]=g_symT1[x];
      g_watch[w].tt[2]=g_symT2[x];
      g_watch[w].tt[3]=g_symT3[x];
      double weeks=(double)((long)g_symT3[x]-(long)g_symT0[x])/604800.0;
      g_watch[w].perWeek=(weeks>0.0) ? g_watch[w].btN/weeks : 0.0;
      g_watch[w].house=ch[c];
      g_watch[w].gOk=g_rows[i].gOk;
      g_watch[w].mOk=g_rows[i].mOk;
      for(int k=0;k<26;k++)
         g_watch[w].gl[k]=g_rows[i].gl[k];
      for(int k=0;k<18;k++)
         g_watch[w].lift[k]=g_rows[i].lift[k];
      ZeroLive(w);
      g_nWatch++;
     }
//--- a new list starts a new record
   g_nOpen=0;
   ArrayResize(g_open,0);
   g_nAlerted=0;
   FileDelete(DIR_OUT+"forward.csv");
   FileDelete(DIR_OUT+"open.csv");
   SaveWatch();
   g_watchFrozen=(g_nWatch>0);
   Print("T2R Lab: live demo test now follows ",g_nWatch," setups (",nc," qualified). List saved to watchlist.csv");
  }

//+------------------------------------------------------------------+
//| Website Signal Desk                                              |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Lot sizes and demo-account trading                               |
//+------------------------------------------------------------------+
CTrade   g_trade;

//--- money lost on 1.0 lot if the stop (dist away in price) is hit
double RiskPerLot(const string sym,const double dist)
  {
   double p=SymbolInfoDouble(sym,SYMBOL_BID);
   double pl=0.0;
   if(p>0.0 && dist>0.0 && dist<p && OrderCalcProfit(ORDER_TYPE_BUY,sym,1.0,p,p-dist,pl) && pl<0.0)
      return -pl;
   double tv=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tv<=0.0)
      tv=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE);
   double ts=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
   if(tv<=0.0 || ts<=0.0 || dist<=0.0)
      return 0.0;
   return dist/ts*tv;
  }

int VolDigits(const string sym)
  {
   double st=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
   int d=0;
   while(d<4 && st>0.0 && MathAbs(st*MathPow(10,d)-MathRound(st*MathPow(10,d)))>1e-9)
      d++;
   return d;
  }

//--- lots that risk this much money; 0 when even the smallest lot risks more
double LotsFor(const string sym,const double money,const double dist)
  {
   double rpl=RiskPerLot(sym,dist);
   double st=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
   double mn=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
   double mx=SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
   if(rpl<=0.0 || st<=0.0)
      return 0.0;
   double v=MathFloor(money/rpl/st+1e-9)*st;
   if(v<mn)
      return 0.0;
   if(mx>0.0 && v>mx)
      v=mx;
   return NormalizeDouble(v,VolDigits(sym));
  }

//--- one cell of the lot table in the Telegram card
string LotCell(const string sym,const double pct,const double dist)
  {
   double money=InpTgLotRef*pct/100.0;
   double v=LotsFor(sym,money,dist);
   if(v>0.0)
      return "<code>"+DoubleToString(v,VolDigits(sym))+"</code>";
   double mn=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
   double rpl=RiskPerLot(sym,dist);
   if(rpl<=0.0 || InpTgLotRef<=0.0)
      return "-";
   return "<i>min "+DoubleToString(mn,VolDigits(sym))+" = "+DoubleToString(100.0*mn*rpl/InpTgLotRef,1)+"%</i>";
  }

string LotLine(const int k)
  {
   string sym=g_watch[g_open[k].w].sym;
   double dist=g_open[k].unit;
   if(RiskPerLot(sym,dist)<=0.0 || InpTgLotRef<=0.0)
      return "";
   return U(0x1F4D0)+" Lot size for a "+AccountInfoString(ACCOUNT_CURRENCY)+" "+DoubleToString(InpTgLotRef,0)+" account\n"+
          "     0.5% "+LotCell(sym,0.5,dist)+"   "+U(0xB7)+"   1% "+LotCell(sym,1.0,dist)+"   "+U(0xB7)+"   2% "+LotCell(sym,2.0,dist)+"\n"+
          "     <i>Bigger account? Scale up: 2x the balance = 2x the lot.</i>\n";
  }

bool TradeOk()
  {
   return (!g_study && InpTradeDemo && AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO &&
           TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)!=0 && MQLInfoInteger(MQL_TRADE_ALLOWED)!=0);
  }

void TradeSetup(const string sym)
  {
   g_trade.SetExpertMagicNumber((ulong)InpTradeMagic);
   g_trade.SetDeviationInPoints(100);
   g_trade.SetTypeFillingBySymbol(sym);
   g_trade.SetAsyncMode(false);
  }

//--- the position that came from this order (hedging accounts keep the order ticket as the position id)
bool PosOf(const ulong order,ulong &pos)
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong t=PositionGetTicket(i);
      if(t==0)
         continue;
      if((ulong)PositionGetInteger(POSITION_IDENTIFIER)==order || t==order)
        {
         pos=t;
         return true;
        }
     }
   return false;
  }

bool PendingAlive(const ulong order)
  {
   return (order>0 && OrderSelect(order));
  }

//--- place the signal on the demo account
void TradeOpen(const int k)
  {
   if(g_open[k].state==0)            // a waiting order is traded when it activates, not parked at the broker
      return;
   g_open[k].tk=0;
   g_open[k].lots=0.0;
   if(InpBestOnly && !IsBestW(g_open[k].w))     // forward test only: signal and website, no demo trade
      return;
   if(!TradeOk())
      return;
   int nOpen=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
      if(PositionGetTicket(i)>0 && PositionGetInteger(POSITION_MAGIC)==InpTradeMagic)
         nOpen++;
   if(nOpen>=InpTradeMaxOpen)
     {
      Print("T2R Lab demo: ",g_watch[g_open[k].w].sym," skipped, ",nOpen," lab positions already open (limit ",InpTradeMaxOpen,")");
      return;
     }
   int w=g_open[k].w;
   string sym=g_watch[w].sym;
   SymbolSelect(sym,true);
   for(int j=0;j<g_nOpen;j++)
      if(j!=k && g_open[j].tk>0 && g_watch[g_open[j].w].sym==sym && g_open[j].dir==g_open[k].dir &&
         MathAbs(g_open[j].entry-g_open[k].entry)<=0.35*g_open[k].unit)
        {
         Print("T2R Lab demo: ",sym," not doubled, the same trade is already on the account");
         return;
        }
   double money=AccountInfoDouble(ACCOUNT_BALANCE)*InpTradeRiskPct/100.0;
   double lots=LotsFor(sym,money,g_open[k].unit);
   if(lots<=0.0)
     {
      double mn=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
      double rpl=RiskPerLot(sym,g_open[k].unit);
      if(rpl<=0.0 || mn*rpl>1.1*money)
        {
         Print("T2R Lab demo: ",sym," skipped, the smallest lot (",DoubleToString(mn,2),") would risk ",
               DoubleToString(100.0*mn*rpl/MathMax(AccountInfoDouble(ACCOUNT_BALANCE),1.0),2),"%, more than the ",DoubleToString(InpTradeRiskPct,2),"% plan");
         return;
        }
      lots=mn;
     }
   int dg=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
   double e=NormalizeDouble(g_open[k].entry,dg);
   double sl=NormalizeDouble(g_open[k].stop,dg);
   double tp=NormalizeDouble(g_open[k].target,dg);
   string c="T2R "+IntegerToString(w);
   TradeSetup(sym);
   bool ok=false;
   if(g_open[k].state==0)
      ok=(g_open[k].dir==0) ? g_trade.BuyLimit(lots,e,sym,sl,tp,ORDER_TIME_GTC,0,c) : g_trade.SellLimit(lots,e,sym,sl,tp,ORDER_TIME_GTC,0,c);
   else
     {
      ok=(g_open[k].dir==0) ? g_trade.Buy(lots,sym,0.0,sl,tp,c) : g_trade.Sell(lots,sym,0.0,sl,tp,c);   // no stop accepted = no trade
     }
   uint rc=g_trade.ResultRetcode();
   if(ok && (rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_PLACED || rc==TRADE_RETCODE_DONE_PARTIAL))
     {
      g_open[k].tk=g_trade.ResultOrder();
      g_open[k].lots=lots;
      g_openDirty=true;
     }
   else
      Print("T2R Lab demo: order not placed on ",sym," (",rc," ",g_trade.ResultRetcodeDescription(),")");
  }

//--- +1R: bank half and move the stop to entry (the T2R rule)
void TradeTp1(const int k)
  {
   if(!InpTradeBE || g_open[k].tk==0 || !TradeOk())
      return;
   ulong pos=0;
   if(!PosOf(g_open[k].tk,pos) || !PositionSelectByTicket(pos))
      return;
   string sym=PositionGetString(POSITION_SYMBOL);
   double vol=PositionGetDouble(POSITION_VOLUME);
   double st=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
   double mn=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
   double tp=PositionGetDouble(POSITION_TP);
   TradeSetup(sym);
   if(st>0.0)
     {
      double half=NormalizeDouble(MathFloor(vol/2.0/st+1e-9)*st,VolDigits(sym));
      if(half>=mn && vol-half>=mn-1e-9)
         g_trade.PositionClosePartial(pos,half);
     }
   int dg=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
   if(PositionSelectByTicket(pos))
      g_trade.PositionModify(pos,NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN),dg),tp);
  }

//--- every second: any lab position losing more than InpTradeGuard x its planned risk is closed straight away
datetime g_sweep=0;
void TradeGuard()
  {
   if(!TradeOk())
      return;
   //--- every 5 minutes: close lab positions (and delete lab orders) the lab no longer tracks
   if(TimeCurrent()-g_sweep>=300 && g_nWatch>0)
     {
      g_sweep=TimeCurrent();
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong t=PositionGetTicket(i);
         if(t==0 || PositionGetInteger(POSITION_MAGIC)!=InpTradeMagic)
            continue;
         ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
         bool known=false;
         for(int k=0;k<g_nOpen && !known;k++)
            if(g_open[k].tk>0 && (g_open[k].tk==id || g_open[k].tk==t))
               known=true;
         if(!known)
           {
            string sym=PositionGetString(POSITION_SYMBOL);
            TradeSetup(sym);
            if(g_trade.PositionClose(t))
               Print("T2R Lab demo: closed ",sym," position the lab no longer tracks");
           }
        }
      for(int i=OrdersTotal()-1;i>=0;i--)
        {
         ulong t=OrderGetTicket(i);
         if(t==0 || OrderGetInteger(ORDER_MAGIC)!=InpTradeMagic)
            continue;
         bool known=false;
         for(int k=0;k<g_nOpen && !known;k++)
            if(g_open[k].tk==t)
               known=true;
         if(!known)
            g_trade.OrderDelete(t);
        }
     }
   if(InpTradeGuard<=0.0)
      return;
   for(int k=0;k<g_nOpen;k++)
     {
      if(g_open[k].tk==0 || g_open[k].state!=1)
         continue;
      ulong pos=0;
      if(!PosOf(g_open[k].tk,pos) || !PositionSelectByTicket(pos))
         continue;
      string sym=PositionGetString(POSITION_SYMBOL);
      double plan=PositionGetDouble(POSITION_VOLUME)*RiskPerLot(sym,g_open[k].unit);
      double pl=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      if(plan>0.0 && pl<-InpTradeGuard*plan)
        {
         TradeSetup(sym);
         if(g_trade.PositionClose(pos))
            Print("T2R Lab demo: guard closed ",sym," at ",DoubleToString(pl,2)," (plan was -",DoubleToString(plan,2),")");
        }
     }
  }

//--- the lab closed or cancelled the trade: make the demo account match
void TradeEnd(const int k)
  {
   if(g_open[k].tk==0 || !TradeOk())
      return;
   TradeSetup(g_watch[g_open[k].w].sym);
   if(PendingAlive(g_open[k].tk))
      g_trade.OrderDelete(g_open[k].tk);
   ulong pos=0;
   if(PosOf(g_open[k].tk,pos))
      g_trade.PositionClose(pos);
  }

//+------------------------------------------------------------------+
//| Telegram cards (HTML)                                            |
//+------------------------------------------------------------------+
string   g_capSym[];
int      g_capDay[];
int      g_capN[];
int      g_nCap       = 0;

//--- a character from its Unicode number (emoji live above 0xFFFF and need two UTF-16 halves)
string U(const int cp)
  {
   if(cp<0x10000)
      return ShortToString((ushort)cp);
   int v=cp-0x10000;
   return ShortToString((ushort)(0xD800+(v>>10)))+ShortToString((ushort)(0xDC00+(v&0x3FF)));
  }

string H(const string v)
  {
   string o=v;
   StringReplace(o,"&","&amp;");
   StringReplace(o,"<","&lt;");
   StringReplace(o,">","&gt;");
   return o;
  }

string Px(const string sym,const double p)
  {
   return DoubleToString(p,(int)SymbolInfoInteger(sym,SYMBOL_DIGITS));
  }

string Dur(const long secs)
  {
   long m=secs/60;
   if(m<60)
      return IntegerToString(m)+" min";
   long h=m/60;
   if(h<48)
      return IntegerToString(h)+"h "+IntegerToString(m%60)+"m";
   return IntegerToString(h/24)+" days";
  }

string RNum(const double r)
  {
   return ((r>=0.0) ? "+" : U(0x2212))+DoubleToString(MathAbs(r),2)+"R";
  }

//--- send one HTML message; replyTo puts it under an earlier message. Returns the new message id (0 = failed)
long TgSend(const string html,const long replyTo)
  {
   if(g_study || InpTgToken=="" || InpTgChat=="")
      return 0;
   string url="https://api.telegram.org/bot"+InpTgToken+"/sendMessage";
   string body="chat_id="+UrlEnc(InpTgChat)+"&parse_mode=HTML&disable_web_page_preview=true&text="+UrlEnc(html);
   if(replyTo>0)
      body+="&reply_to_message_id="+IntegerToString(replyTo)+"&allow_sending_without_reply=true";
   uchar post[];
   uchar res[];
   string hdr="";
   int len=StringToCharArray(body,post,0,WHOLE_ARRAY,CP_UTF8)-1;
   if(len<=0)
      return 0;
   ArrayResize(post,len);
   int code=0;
   for(int att=0;att<3;att++)                       // a network blip gets two more tries
     {
      ResetLastError();
      code=WebRequest("POST",url,"Content-Type: application/x-www-form-urlencoded\r\n",5000,post,res,hdr);
      if(code==200 || (code>=400 && code<500))
         break;
      Sleep(1500);
     }
   string ans=CharArrayToString(res,0,WHOLE_ARRAY,CP_UTF8);
   if(code!=200)
     {
      Print("T2R Lab: Telegram not sent (code ",code,", error ",GetLastError(),") ",StringSubstr(ans,0,200),
            " In MT5: Tools > Options > Expert Advisors > allow WebRequest for https://api.telegram.org");
      return 0;
     }
   int i=StringFind(ans,"\"message_id\":");
   if(i<0)
      return 1;
   return StringToInteger(StringSubstr(ans,i+13,20));
  }

//--- at most InpTgMaxPerDay Telegram signals per market per day (the website still shows every one)
bool CapOk(const string sym)
  {
   if(InpTgMaxPerDay<=0)
      return true;
   string toks[];
   string up=sym;
   StringToUpper(up);
   int nt=StringSplit(InpTgAllMarkets,',',toks);
   for(int i=0;i<nt;i++)
     {
      string t=toks[i];
      StringTrimLeft(t);
      StringTrimRight(t);
      StringToUpper(t);
      if(t!="" && StringFind(up,t)>=0)
         return true;
     }
   int d=(int)(TimeCurrent()/86400);
   for(int i=0;i<g_nCap;i++)
      if(g_capSym[i]==sym && g_capDay[i]==d)
         return (g_capN[i]<InpTgMaxPerDay);
   return true;
  }

void CapAdd(const string sym)
  {
   int d=(int)(TimeCurrent()/86400);
   for(int i=0;i<g_nCap;i++)
      if(g_capSym[i]==sym)
        {
         if(g_capDay[i]!=d)
           {
            g_capDay[i]=d;
            g_capN[i]=0;
           }
         g_capN[i]++;
         return;
        }
   ArrayResize(g_capSym,g_nCap+1,64);
   ArrayResize(g_capDay,g_nCap+1,64);
   ArrayResize(g_capN,g_nCap+1,64);
   g_capSym[g_nCap]=sym;
   g_capDay[g_nCap]=d;
   g_capN[g_nCap]=1;
   g_nCap++;
  }

//--- the record line of a setup, in plain words
string RecordHtml(const int w)
  {
   double ratio=WatchRatio(w);
   string s=U(0x1F4CA)+" Unseen history: won <b>"+IntegerToString((int)MathRound(100.0*g_watch[w].wr))+"%</b> (needs "+
            IntegerToString((int)MathRound(100.0/(1.0+ratio)))+"%)";
   if(g_watch[w].tp1>=0.0 && ratio>1.0)
      s+=", reached TP1 first <b>"+IntegerToString((int)MathRound(100.0*g_watch[w].tp1))+"%</b>";
   s+="\n"+U(0x1F501)+" Live so far: "+IntegerToString(g_watch[w].nWin)+" won "+U(0xB7)+" "+IntegerToString(g_watch[w].nLoss)+" lost";
   if(g_watch[w].nWin+g_watch[w].nLoss>0)
      s+=" "+U(0xB7)+" "+RNum(g_watch[w].sumR);
   return s;
  }

//--- a new signal, as a card. Skipped when the daily cap is reached or the same trade was just posted by another setup
void TgSignal(const int k,const string why,const bool now)
  {
   int w=g_open[k].w;
   string sym=g_watch[w].sym;
   for(int j=0;j<g_nOpen;j++)
      if(j!=k && g_open[j].msg>0 && g_watch[g_open[j].w].sym==sym && g_open[j].dir==g_open[k].dir &&
         MathAbs(g_open[j].entry-g_open[k].entry)<=0.35*g_open[k].unit)
         return;
   if(!CapOk(sym))
      return;
   double ratio=WatchRatio(w);
   bool buy=(g_open[k].dir==0);
   string d=buy ? "BUY" : "SELL";
   //--- which kind of signal: the proven top setup (traded on demo) or a lab test (website only)
   string m=IsBestW(w) ? U(0x2B50)+" <b>T2R TOP SIGNAL</b>  "+U(0xB7)+"  "+U(0x26A1)+" Spike Zone "+U(0xB7)+" model pick  "+U(0xB7)+"  traded on demo\n"
                       : U(0x1F9EA)+" <i>Lab test  "+U(0xB7)+"  website only, not traded</i>\n";
   m+=(buy ? U(0x1F7E2) : U(0x1F534))+" <b>"+d+(now ? " NOW" : " LIMIT")+"</b>  "+U(0xB7)+"  <b>"+H(sym)+"</b>\n";
   m+=now ? "<i>Price is in the zone. Enter at market now.</i>\n\n" : "<i>Place this pending order now. It only fills if price comes back to the zone.</i>\n\n";
   m+=U(0x1F4CD)+" Entry    <code>"+Px(sym,g_open[k].entry)+"</code>\n";
   m+=U(0x1F6D1)+" Stop     <code>"+Px(sym,g_open[k].stop)+"</code>   "+U(0x2212)+"1R\n";
   if(ratio>1.0)
      m+=U(0x1F4B0)+" TP1      <code>"+Px(sym,g_open[k].tp1)+"</code>   +1R "+U(0x2192)+" bank half, stop to entry\n";
   m+=U(0x1F3AF)+" Target   <code>"+Px(sym,g_open[k].target)+"</code>   +"+DoubleToString(ratio,(ratio==MathRound(ratio)) ? 0 : 1)+"R\n\n";
   m+=U(0x2696)+U(0xFE0F)+" Risk : reward  <b>"+RRText(g_watch[w].si,g_watch[w].lv)+"</b>\n";
   m+=LotLine(k);
   m+=RecordHtml(w)+"\n";
   string wy=why;
   StringReplace(wy," - ","  "+U(0xB7)+"  ");
   m+=U(0x1F9E0)+" "+H(wy)+"\n\n";
   m+="<blockquote>Risk 1% of your account or less. Losing runs are normal. Demo-test signal, not financial advice.";
   if(!now)
      m+=" We post CANCEL if the zone breaks first.";
   m+="</blockquote>\n";
   m+=U(0x23F1)+" "+TimeToString(g_open[k].tIn,TIME_MINUTES)+" GMT";
   if(InpSiteUrl!="")
      m+="  "+U(0xB7)+"  <a href=\""+InpSiteUrl+"/desk\">Live record</a>";
   long id=TgSend(m,0);
   if(id>0)
     {
      g_open[k].msg=id;
      g_openDirty=true;
      CapAdd(sym);
      DeskEvent(k,"update",0.0,TimeCurrent(),0.0,0.0,false);   // marks it as a Telegram signal on the website
     }
  }

//--- a heads-up for setups that are only confirmed when price arrives, with the planned levels
void TgHeads(const int w,const int dir,const double edge,const double risk,const string why)
  {
   string sym=g_watch[w].sym;
   if(!CapOk(sym))
      return;
   double unit=g_sm[g_watch[w].si]*risk;
   double stop=(dir==0) ? edge-unit : edge+unit;
   double tgt=(dir==0) ? edge+g_lev[g_watch[w].lv]*risk : edge-g_lev[g_watch[w].lv]*risk;
   string wy=why;
   StringReplace(wy," - ","  "+U(0xB7)+"  ");
   string m=U(0x23F3)+" <b>GET READY</b>  "+U(0xB7)+"  possible "+((dir==0) ? "BUY" : "SELL")+"  "+U(0xB7)+"  <b>"+H(sym)+"</b>\n";
   m+="<i>Not a trade yet. Only take it if we send "+((dir==0) ? "BUY" : "SELL")+" NOW. No message means skip it.</i>\n\n";
   m+="Planned entry  <code>"+Px(sym,edge)+"</code>\nPlanned stop   <code>"+Px(sym,stop)+"</code>\nPlanned target <code>"+Px(sym,tgt)+"</code>  ("+
      RRText(g_watch[w].si,g_watch[w].lv)+")\n\n"+U(0x1F9E0)+" "+H(wy);
   TgSend(m,0);
  }

//--- updates, posted as replies under the signal they belong to
void TgLife(const int k,const string kind,const double price,const datetime at,const double r,const double r2)
  {
   if(!InpTgLifecycle || g_open[k].msg<=0)
      return;
   int w=g_open[k].w;
   string sym=g_watch[w].sym;
   string d=(g_open[k].dir==0) ? "BUY" : "SELL";
   string m="";
   if(kind=="activated")
      m=U(0x26A1)+" <b>ACTIVATED</b>  "+U(0xB7)+"  "+d+" "+H(sym)+"\nFilled at <code>"+Px(sym,price)+"</code>. Stop <code>"+Px(sym,g_open[k].stop)+
        "</code>  "+U(0xB7)+"  Target <code>"+Px(sym,g_open[k].target)+"</code>"+
        ((WatchRatio(w)>1.0) ? "\nAt TP1 <code>"+Px(sym,g_open[k].tp1)+"</code> bank half and move the stop to entry." : "");
   if(kind=="tp1")
      m=U(0x1F4B0)+" <b>+1R REACHED</b>  "+U(0xB7)+"  "+d+" "+H(sym)+"\nTP1 <code>"+Px(sym,g_open[k].tp1)+"</code> hit. Bank half now and move your stop to entry <code>"+
        Px(sym,g_open[k].entry)+"</code>.\nFrom here this trade cannot lose.";
   if(kind=="target")
      m=U(0x2705)+" <b>TARGET HIT  "+RNum(r)+"</b>  "+U(0xB7)+"  "+d+" "+H(sym)+"\nClosed at <code>"+Px(sym,price)+"</code> after "+Dur((long)(at-g_open[k].tFill))+
        ".\nWith the T2R rule (half at TP1): <b>"+RNum(r2)+"</b>";
   if(kind=="stop")
     {
      if(g_open[k].hit1 && WatchRatio(w)>1.0)
         m=U(0x1F6E1)+" <b>STOPPED, BUT PROTECTED</b>  "+U(0xB7)+"  "+d+" "+H(sym)+"\nTP1 was reached first. With the T2R rule you banked half and moved the stop to entry: <b>"+
           RNum(r2)+"</b>.\nHeld to the full stop it would be "+RNum(r)+".";
      else
         m=U(0x1F6D1)+" <b>STOPPED  "+RNum(r)+"</b>  "+U(0xB7)+"  "+d+" "+H(sym)+"\nClosed at <code>"+Px(sym,price)+"</code> after "+Dur((long)(at-g_open[k].tFill))+
           ".\nLosses are part of the plan. On to the next one.";
     }
   if(kind=="cancel")
      m=U(0x274C)+" <b>CANCEL</b>  "+U(0xB7)+"  "+d+" LIMIT "+H(sym)+"\nDelete the pending order at <code>"+Px(sym,g_open[k].entry)+
        "</code>. The zone broke before price came back, so this trade is off.";
   if(m!="")
      TgSend(m,g_open[k].msg);
  }

string   g_dq[];
int      g_nDq        = 0;
uint     g_dqLast     = 0;
datetime g_dqFloat    = 0;
bool     g_dqWarned   = false;

string JStr(const string v)
  {
   string o=v;
   StringReplace(o,CharToString(92),CharToString(92)+CharToString(92));
   StringReplace(o,CharToString(34),CharToString(92)+CharToString(34));
   return CharToString(34)+o+CharToString(34);
  }

string JKey(const string k)
  {
   return CharToString(34)+k+CharToString(34)+":";
  }

string FamName(const string sym)
  {
   int g=GroupOf(sym);
   if(g==0)
      return "Boom and Crash";
   if(g==1)
      return "Volatility";
   if(g==3)
      return "Forex";
   if(g==4)
      return "Metals";
   return "Synthetics";
  }

//--- the T2R rule result: half off at 1:1 and stop to entry
double T2RResult(const int k,const double r)
  {
   if(WatchRatio(g_open[k].w)<=1.0 || !(g_open[k].hit1 || r>=1.0))
      return r;
   if(g_open[k].be || r<=0.0)
      return 0.5;
   return 0.5+0.5*r;
  }

//--- one event, with every field, so the website can build the signal from any single event
void DeskEvent(const int k,const string kind,const double price,const datetime at,const double r,const double r2,const bool hasR)
  {
   if(kind=="activated" || kind=="tp1" || kind=="target" || kind=="stop" || kind=="cancel")
      TgLife(k,kind,price,at,r,r2);
   if(kind=="activated" && g_open[k].tk==0)
      TradeOpen(k);
   if(kind=="tp1")
      TradeTp1(k);
   if(kind=="target" || kind=="stop" || kind=="cancel")
      TradeEnd(k);
   if(InpWebUrl=="" || InpWebKey=="")
      return;
   int w=g_open[k].w;
   string sym=g_watch[w].sym;
   int dg=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
   string id=IntegerToString(w)+"_"+IntegerToString((long)g_open[k].tIn)+"_"+IntegerToString(g_open[k].dir);
   string j="{"+JKey("id")+JStr(id)+","+JKey("kind")+JStr(kind)+","+JKey("at")+IntegerToString((long)at)+","+
            JKey("market")+JStr(sym)+","+JKey("family")+JStr(FamName(sym))+","+JKey("strategy")+JStr(g_sName[g_watch[w].strat])+","+
            JKey("view")+JStr(ViewName(g_watch[w].strat,g_watch[w].view))+","+JKey("side")+JStr(g_sideName[g_watch[w].side])+","+
            JKey("stop_class")+JStr(g_scName[g_watch[w].scale])+","+JKey("dir")+JStr((g_open[k].dir==0) ? "buy" : "sell")+","+
            JKey("entry")+DoubleToString(g_open[k].entry,dg)+","+JKey("stop")+DoubleToString(g_open[k].stop,dg)+","+
            JKey("tp1")+DoubleToString(g_open[k].tp1,dg)+","+JKey("target")+DoubleToString(g_open[k].target,dg)+","+
            JKey("rr")+JStr(RRText(g_watch[w].si,g_watch[w].lv))+","+JKey("t_signal")+IntegerToString((long)g_open[k].tIn)+","+
            JKey("risk_per_lot")+DoubleToString(RiskPerLot(sym,g_open[k].unit),4)+","+JKey("vol_min")+DoubleToString(SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN),4)+","+
            JKey("vol_step")+DoubleToString(SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP),4)+","+JKey("ccy")+JStr(AccountInfoString(ACCOUNT_CURRENCY))+","+
            JKey("lots")+DoubleToString(g_open[k].lots,2)+","+JKey("tg")+((g_open[k].msg>0) ? "true" : "false");
   if(g_open[k].tFill>0)
      j+=","+JKey("t_fill")+IntegerToString((long)g_open[k].tFill);
   if(price>0.0)
      j+=","+JKey("price")+DoubleToString(price,dg);
   if(hasR)
      j+=","+JKey("r")+DoubleToString(r,3)+","+JKey("r_t2r")+DoubleToString(r2,3);
   if(kind=="sync")
      j+=","+JKey("status")+JStr((g_open[k].state==1) ? "active" : "pending")+","+JKey("hit_tp1")+(g_open[k].hit1 ? "true" : "false");
   if(kind=="update")
      j+=","+JKey("r_float")+DoubleToString(FloatR(k),3);
   j+="}";
   ArrayResize(g_dq,g_nDq+1,256);
   g_dq[g_nDq]=j;
   g_nDq++;
   if(g_nDq>3000)                                   // the website has been down for very long: keep the newest
     {
      ArrayRemove(g_dq,0,g_nDq-3000);
      g_nDq=3000;
     }
  }

void DeskSignal(const int k)
  {
   if(InpWebUrl=="" || InpWebKey=="")
      return;
   string j_order=(g_open[k].state==1) ? "market" : "limit";
   DeskEvent(k,"signal",g_open[k].entry,g_open[k].tIn,0.0,0.0,false);
   //--- add the order type to the event just queued
   StringReplace(g_dq[g_nDq-1],JKey("kind")+JStr("signal"),JKey("kind")+JStr("signal")+","+JKey("order_type")+JStr(j_order));
  }

//--- every trade and pending order already on the book, sent once at start (safe to repeat)
void DeskSyncAll()
  {
   for(int k=0;k<g_nOpen;k++)
      DeskEvent(k,"sync",0.0,TimeCurrent(),0.0,0.0,false);
  }

//--- post the queue, at most every 5 seconds; floating results of open trades every 5 minutes
void DeskFlush()
  {
   if(g_study || InpWebUrl=="" || InpWebKey=="")
      return;
   if(TimeCurrent()-g_dqFloat>=300)
     {
      g_dqFloat=TimeCurrent();
      int npos=0,nord=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
         if(PositionGetTicket(i)>0 && PositionGetInteger(POSITION_MAGIC)==InpTradeMagic)
            npos++;
      for(int i=OrdersTotal()-1;i>=0;i--)
         if(OrderGetTicket(i)>0 && OrderGetInteger(ORDER_MAGIC)==InpTradeMagic)
            nord++;
      string aj="{"+JKey("id")+JStr("account")+","+JKey("kind")+JStr("account")+","+JKey("at")+IntegerToString((long)TimeCurrent())+","+
                JKey("balance")+DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2)+","+JKey("equity")+DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2)+","+
                JKey("profit")+DoubleToString(AccountInfoDouble(ACCOUNT_PROFIT),2)+","+JKey("positions")+IntegerToString(npos)+","+
                JKey("orders")+IntegerToString(nord)+","+JKey("ccy")+JStr(AccountInfoString(ACCOUNT_CURRENCY))+","+
                JKey("demo")+((AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO) ? "true" : "false")+","+
                JKey("risk_pct")+DoubleToString(InpTradeRiskPct,2)+"}";
      ArrayResize(g_dq,g_nDq+1,256);
      g_dq[g_nDq]=aj;
      g_nDq++;
      for(int k=0;k<g_nOpen;k++)
         if(g_open[k].state==1)
            DeskEvent(k,"update",0.0,TimeCurrent(),0.0,0.0,false);
     }
   if(g_nDq==0 || GetTickCount()-g_dqLast<5000)
      return;
   g_dqLast=GetTickCount();
   int n=MathMin(g_nDq,60);
   string body="{"+JKey("events")+"[";
   for(int i=0;i<n;i++)
      body+=(i>0 ? "," : "")+g_dq[i];
   body+="]}";
   uchar post[];
   uchar res[];
   string hdr="";
   int len=StringToCharArray(body,post,0,WHOLE_ARRAY,CP_UTF8)-1;
   if(len<=0)
      return;
   ArrayResize(post,len);
   ResetLastError();
   int code=WebRequest("POST",InpWebUrl,"Content-Type: application/json\r\nx-t2r-key: "+InpWebKey+"\r\n",8000,post,res,hdr);
   if(code==200)
     {
      ArrayRemove(g_dq,0,n);
      g_nDq-=n;
      g_dqWarned=false;
      return;
     }
   if(!g_dqWarned)
     {
      Print("T2R Lab: website desk not reached (code ",code,", error ",GetLastError(),", answer ",CharArrayToString(res,0,WHOLE_ARRAY,CP_UTF8),
            "). In MT5: Tools > Options > Expert Advisors > allow WebRequest for your website address. ",g_nDq," events waiting, will retry.");
      g_dqWarned=true;
     }
   if(code==401 || code==400)                       // wrong key or a broken event: do not retry forever
     {
      ArrayRemove(g_dq,0,n);
      g_nDq-=n;
     }
  }

void CloseTrade(const int k,const double exitPrice,const datetime tOut)
  {
   int w=g_open[k].w;
   double r=0.0;
   if(g_open[k].unit>0.0)
      r=(g_open[k].dir==0) ? (exitPrice-g_open[k].entry)/g_open[k].unit : (g_open[k].entry-exitPrice)/g_open[k].unit;
   double ratio=WatchRatio(w);
   bool hit1=g_open[k].hit1;
   double r2=r;
   if(ratio>1.0)
     {
      if(r>=1.0)
         hit1=true;
      if(hit1)
         r2=0.5+0.5*r;                               // half the position banked at 1:1, the other half ran to the end
     }
   else
      hit1=(r>0.0);
   g_watch[w].sumR+=r;
   g_watch[w].sumR2+=r2;
   if(hit1)
      g_watch[w].nTp1++;
   if(r>0.0)
      g_watch[w].nWin++;
   else
      g_watch[w].nLoss++;
   g_watch[w].nOpen=MathMax(g_watch[w].nOpen-1,0);
   bool isNew=!FileIsExist(DIR_OUT+"forward.csv");
   int h=FileOpen(DIR_OUT+"forward.csv",FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h!=INVALID_HANDLE)
     {
      FileSeek(h,0,SEEK_END);
      if(isNew)
         FileWriteString(h,"time_signal,time_in,time_out,watch_id,asset,strategy,view,side,stop_class,stop,target,direction,entry,exit,"+
                         "risk_to_reward,R,reached_1to1,R_half_off_at_1to1\r\n");
      int dg=(int)SymbolInfoInteger(g_watch[w].sym,SYMBOL_DIGITS);
      FileWriteString(h,TimeToString(g_open[k].tIn,TIME_DATE|TIME_MINUTES)+","+TimeToString(g_open[k].tFill,TIME_DATE|TIME_MINUTES)+","+
                      TimeToString(tOut,TIME_DATE|TIME_MINUTES)+","+IntegerToString(w)+","+g_watch[w].sym+","+g_sName[g_watch[w].strat]+","+
                      ViewName(g_watch[w].strat,g_watch[w].view)+","+g_sideName[g_watch[w].side]+","+g_scName[g_watch[w].scale]+","+
                      g_smName[g_watch[w].si]+","+g_levName[g_watch[w].lv]+","+((g_open[k].dir==0) ? "buy" : "sell")+","+
                      DoubleToString(g_open[k].entry,dg)+","+DoubleToString(exitPrice,dg)+","+RRText(g_watch[w].si,g_watch[w].lv)+","+
                      DoubleToString(r,3)+","+(hit1 ? "yes" : "no")+","+DoubleToString(r2,3)+"\r\n");
      FileClose(h);
     }
   DeskEvent(k,(r>0.0) ? "target" : "stop",exitPrice,tOut,r,T2RResult(k,r),true);
   g_open[k]=g_open[g_nOpen-1];
   g_nOpen--;
   g_openDirty=true;
  }

void CancelPending(const int k)
  {
   int w=g_open[k].w;
   g_watch[w].nPend=MathMax(g_watch[w].nPend-1,0);
   g_watch[w].nCancel++;
   DeskEvent(k,"cancel",0.0,TimeCurrent(),0.0,0.0,false);
   g_open[k]=g_open[g_nOpen-1];
   g_nOpen--;
   g_openDirty=true;
  }

void FillPending(const int k,const double price,const datetime t)
  {
   int w=g_open[k].w;
   g_open[k].state=1;
   g_open[k].entry=price;
   g_open[k].tFill=t;
   DeskEvent(k,"activated",price,t,0.0,0.0,false);
   g_watch[w].nPend=MathMax(g_watch[w].nPend-1,0);
   g_watch[w].nSig++;
   g_watch[w].nOpen++;
   g_openDirty=true;
  }

//--- follow every demo order: pending orders until they fill, trades until stop or target, all at the price they would
//    really have been filled at. A stop that price jumps over is filled where price landed, so that loss is bigger than 1R.
void UpdateTrades(const bool withBars)
  {
   for(int k=g_nOpen-1;k>=0;k--)
     {
      int w=g_open[k].w;
      string sym=g_watch[w].sym;
      MqlTick tk;
      if(!SymbolInfoTick(sym,tk) || tk.bid<=0.0 || tk.ask<=0.0)
         continue;
      bool closed=false;
      if(withBars)
        {
         //--- finished one-minute candles since the last look (covers time the EA was busy or switched off)
         double pt=SymbolInfoDouble(sym,SYMBOL_POINT);
         MqlRates m[];
         int got=CopyRates(sym,PERIOD_M1,g_open[k].tSeen,TimeCurrent(),m);
         for(int j=0;j<got-1 && !closed;j++)
           {
            if(m[j].time<=g_open[k].tSeen)
               continue;
            double sp=m[j].spread*pt;
            datetime tj=m[j].time;
            bool justFilled=false;
            if(g_open[k].state==0)
              {
               if(g_open[k].dir==0 && m[j].low+sp<=g_open[k].entry)
                 {
                  FillPending(k,MathMin(g_open[k].entry,m[j].open+sp),tj);
                  justFilled=true;
                 }
               if(g_open[k].dir==1 && m[j].high>=g_open[k].entry)
                 {
                  FillPending(k,MathMax(g_open[k].entry,m[j].open),tj);
                  justFilled=true;
                 }
               if(!justFilled)
                 {
                  g_open[k].tSeen=tj;
                  g_openDirty=true;
                  continue;
                 }
              }
            if(g_open[k].dir==0)
              {
               if(m[j].open<=g_open[k].stop && !justFilled)
                 {
                  CloseTrade(k,m[j].open,tj);
                  closed=true;
                 }
               else
                  if(m[j].low<=g_open[k].stop)
                    {
                     CloseTrade(k,g_open[k].stop,tj);
                     closed=true;
                    }
                  else
                     if(!justFilled)
                       {
                        if(g_open[k].hit1 && !g_open[k].be && m[j].low<=g_open[k].entry)
                           g_open[k].be=true;
                        if(m[j].high>=g_open[k].tp1 && !g_open[k].hit1)
                          {
                           g_open[k].hit1=true;
                           DeskEvent(k,"tp1",g_open[k].tp1,tj,0.0,0.0,false);
                          }
                        if(m[j].high>=g_open[k].target)
                          {
                           CloseTrade(k,g_open[k].target,tj);
                           closed=true;
                          }
                       }
              }
            else
              {
               if(m[j].open+sp>=g_open[k].stop && !justFilled)
                 {
                  CloseTrade(k,m[j].open+sp,tj);
                  closed=true;
                 }
               else
                  if(m[j].high+sp>=g_open[k].stop)
                    {
                     CloseTrade(k,g_open[k].stop,tj);
                     closed=true;
                    }
                  else
                     if(!justFilled)
                       {
                        if(g_open[k].hit1 && !g_open[k].be && m[j].high+sp>=g_open[k].entry)
                           g_open[k].be=true;
                        if(m[j].low+sp<=g_open[k].tp1 && !g_open[k].hit1)
                          {
                           g_open[k].hit1=true;
                           DeskEvent(k,"tp1",g_open[k].tp1,tj,0.0,0.0,false);
                          }
                        if(m[j].low+sp<=g_open[k].target)
                          {
                           CloseTrade(k,g_open[k].target,tj);
                           closed=true;
                          }
                       }
              }
            if(!closed)
              {
               g_open[k].tSeen=tj;
               g_openDirty=true;
              }
           }
        }
      if(closed)
         continue;
      //--- the price right now
      if(g_open[k].state==0)
        {
         if(g_open[k].dir==0 && tk.ask<=g_open[k].entry)
            FillPending(k,tk.ask,TimeCurrent());
         else
            if(g_open[k].dir==1 && tk.bid>=g_open[k].entry)
               FillPending(k,tk.bid,TimeCurrent());
         continue;
        }
      if(g_open[k].dir==0)
        {
         if(tk.bid<=g_open[k].stop)
            CloseTrade(k,tk.bid,TimeCurrent());
         else
           {
            if(g_open[k].hit1 && !g_open[k].be && tk.bid<=g_open[k].entry)
              {
               g_open[k].be=true;
               g_openDirty=true;
              }
            if(tk.bid>=g_open[k].tp1 && !g_open[k].hit1)
              {
               g_open[k].hit1=true;
               g_openDirty=true;
               DeskEvent(k,"tp1",g_open[k].tp1,TimeCurrent(),0.0,0.0,false);
              }
            if(tk.bid>=g_open[k].target)
               CloseTrade(k,g_open[k].target,TimeCurrent());
           }
        }
      else
        {
         if(tk.ask>=g_open[k].stop)
            CloseTrade(k,tk.ask,TimeCurrent());
         else
           {
            if(g_open[k].hit1 && !g_open[k].be && tk.ask>=g_open[k].entry)
              {
               g_open[k].be=true;
               g_openDirty=true;
              }
            if(tk.ask<=g_open[k].tp1 && !g_open[k].hit1)
              {
               g_open[k].hit1=true;
               g_openDirty=true;
               DeskEvent(k,"tp1",g_open[k].tp1,TimeCurrent(),0.0,0.0,false);
              }
            if(tk.ask<=g_open[k].target)
               CloseTrade(k,g_open[k].target,TimeCurrent());
           }
        }
     }
   if(g_openDirty)
      SaveOpen();
  }

//--- put a new order on the demo book. state 0 = pending at the zone edge, 1 = in at the market
void NewOrder(const int w,const int dir,const int state,const double entry,const double risk,const string zkey)
  {
   double unit=g_sm[g_watch[w].si]*risk;
   ArrayResize(g_open,g_nOpen+1,64);
   g_open[g_nOpen].w=w;
   g_open[g_nOpen].dir=dir;
   g_open[g_nOpen].state=state;
   g_open[g_nOpen].unit=unit;
   g_open[g_nOpen].entry=entry;
   g_open[g_nOpen].hit1=false;
   g_open[g_nOpen].be=false;
   g_open[g_nOpen].msg=0;
   g_open[g_nOpen].tk=0;
   g_open[g_nOpen].lots=0.0;
   if(dir==0)
     {
      g_open[g_nOpen].stop=entry-unit;
      g_open[g_nOpen].tp1=entry+unit;
      g_open[g_nOpen].target=entry+g_lev[g_watch[w].lv]*risk;
     }
   else
     {
      g_open[g_nOpen].stop=entry+unit;
      g_open[g_nOpen].tp1=entry-unit;
      g_open[g_nOpen].target=entry-g_lev[g_watch[w].lv]*risk;
     }
   g_open[g_nOpen].tIn=TimeCurrent();
   g_open[g_nOpen].tFill=(state==1) ? TimeCurrent() : 0;
   g_open[g_nOpen].tSeen=iTime(g_watch[w].sym,PERIOD_M1,0);
   g_open[g_nOpen].zkey=zkey;
   g_nOpen++;
   g_openDirty=true;
   TradeOpen(g_nOpen-1);
   DeskSignal(g_nOpen-1);
   if(state==1)
     {
      g_watch[w].nSig++;
      g_watch[w].nOpen++;
     }
   else
      g_watch[w].nPend++;
  }

//--- the message a member receives
string OrderText(const int k,const string headline,const string why)
  {
   int w=g_open[k].w;
   int dg=(int)SymbolInfoInteger(g_watch[w].sym,SYMBOL_DIGITS);
   double ratio=WatchRatio(w);
   string s=headline+"\nEntry   "+DoubleToString(g_open[k].entry,dg)+"\nStop    "+DoubleToString(g_open[k].stop,dg);
   if(ratio>1.0)
      s+="\nTP1     "+DoubleToString(g_open[k].tp1,dg)+"   (1:1 - a place to take part profit)\nTP2     "+DoubleToString(g_open[k].target,dg)+
         "   (full target, "+RRText(g_watch[w].si,g_watch[w].lv)+")";
   else
      s+="\nTarget  "+DoubleToString(g_open[k].target,dg)+"   ("+RRText(g_watch[w].si,g_watch[w].lv)+")";
   s+="\n\nWhy: "+why+"\n"+RecordText(w)+"\n\nRisk 1% of the account or less on any one trade. Losing runs are normal.\nDEMO TEST signal - not financial advice.";
   return s;
  }

//--- zones of every followed setup: pending orders ahead of price, entries when price arrives, cancels when a zone is gone
void CheckSignals()
  {
   for(int a=0;a<g_nWatch;a++)
     {
      //--- handle each asset x strategy once
      bool first=true;
      for(int b=0;b<a && first;b++)
         if(g_watch[b].sym==g_watch[a].sym && g_watch[b].strat==g_watch[a].strat)
            first=false;
      if(!first)
         continue;
      if(!SetCtx(g_watch[a].sym,InpChartTF,InpScoreBars))
         continue;
      SetStrategy(g_watch[a].strat);
      if(g_nAct==0)
         continue;
      MqlTick tk;
      if(!SymbolInfoTick(g_sym,tk) || tk.bid<=0.0 || tk.ask<=0.0)
         continue;
      double price=tk.bid;
      MqlRates lcb[];
      int ln=CopyRates(g_sym,g_per,0,MathMax(InpRangeBars,MathMax(InpTrendBars,200))+30,lcb);
      if(ln<40)
         continue;
      double latr=AtrAt(lcb,ln-1);
      if(latr<=0.0)
         continue;
      PrepLive(price);
      ZGap gaps[];
      int ng=0;
      GenLive(gaps,ng,price);
      ZBox zb[];
      int nzb=0;
      for(int kd=0;kd<g_kinds;kd++)
        {
         nzb=AppendZones(gaps,ng,0,kd,zb,nzb);
         nzb=AppendZones(gaps,ng,1,kd,zb,nzb);
        }
      string base=g_sym+"|"+IntegerToString(g_strat)+"|";

      //--- a pending order whose zone no longer exists is cancelled
      for(int k=g_nOpen-1;k>=0;k--)
        {
         if(g_open[k].state!=0 || StringFind(g_open[k].zkey,base)!=0)
            continue;
         bool alive=false;
         for(int z=0;z<nzb && !alive;z++)
            if(g_open[k].zkey==base+IntegerToString(zb[z].dir)+"|"+IntegerToString(zb[z].kind)+"|"+IntegerToString((long)zb[z].t))
               alive=true;
         if(alive)
            continue;
         CancelPending(k);
        }

      for(int z=0;z<nzb;z++)
        {
         bool inside=(price>=zb[z].lo && price<=zb[z].hi);
         bool ahead=((zb[z].dir==0 && price>zb[z].hi) || (zb[z].dir==1 && price<zb[z].lo));
         if(!inside && !ahead)
            continue;
         string zkey=base+IntegerToString(zb[z].dir)+"|"+IntegerToString(zb[z].kind)+"|"+IntegerToString((long)zb[z].t);
         string why=g_sName[g_strat]+" - "+ZoneName(zb[z].dir,zb[z].kind)+" on "+MaskNames(zb[z].mask);
         bool told=false;
         for(int w=a;w<g_nWatch;w++)
           {
            if(g_watch[w].sym!=g_sym || g_watch[w].strat!=g_strat)
               continue;
            if(!(g_watch[w].side==0 || (g_watch[w].side==1 && zb[z].dir==0) || (g_watch[w].side==2 && zb[z].dir==1)))
               continue;
            string wk=zkey+"|"+IntegerToString(w);
            //--- can this setup be judged before price arrives? only the plain views (and stack / sweep, which never change)
            bool pendable=(g_pendOK[g_strat] && (g_watch[w].view==0 || g_viewExcl) && g_watch[w].view!=2);
            double risk=MathMax(zb[z].hi-zb[z].lo,MathMax(g_rk[g_watch[w].scale],0.0)*latr);
            if(g_sm[g_watch[w].si]*risk<=0.0)
               continue;
            //--- what this setup learned in the backtest
            for(int q=0;q<26;q++)
               g_gl[q]=g_watch[w].gl[q];
            g_gOk=g_watch[w].gOk;
            for(int q=0;q<18;q++)
               S4_g_lift[q]=g_watch[w].lift[q];
            S4_g_modelOk=g_watch[w].mOk;
            string note="";
            double lvl=0.0;
            bool flag=LiveInfo(zb[z],price,note,lvl);
            bool vOk=false;
            if(g_watch[w].view==0)
               vOk=(!g_viewExcl || !flag);
            if(g_watch[w].view==1)
               vOk=flag;

            if(ahead)
              {
               if(pendable)
                 {
                  if(!vOk || WasAlerted(wk+"|p"))
                     continue;
                  WasAlerted(wk+"|in");
                  double e=(zb[z].dir==0) ? zb[z].hi : zb[z].lo;
                  NewOrder(w,zb[z].dir,0,e,risk,zkey);
                  Print("T2R Lab pending order: ",((zb[z].dir==0) ? "BUY LIMIT " : "SELL LIMIT "),WatchLabel(w));
                  if(!told && InpTgSignals)
                    {
                     TgSignal(g_nOpen-1,why,false);
                     told=true;
                    }
                 }
               else
                  if(InpTgSignals && InpTgHeadsUp && !told && MathAbs(price-((zb[z].dir==0) ? zb[z].hi : zb[z].lo))<=2.0*latr && !WasAlerted(zkey+"|h"))
                    {
                     TgHeads(w,zb[z].dir,(zb[z].dir==0) ? zb[z].hi : zb[z].lo,risk,why);
                     told=true;
                    }
               continue;
              }

            //--- price is in the zone now
            if(g_watch[w].view==2 && g_hasPick[g_strat] && g_gOk)
              {
               int gf[9];
               GenFeat(zb[z].dir,zb[z].lo,zb[z].hi,zb[z].mask,zb[z].t,flag,lcb,ln-1,latr,gf);
               vOk=(GenScore(gf)>=InpPickScore);
              }
            if(!vOk || WasAlerted(wk+"|in"))
               continue;
            NewOrder(w,zb[z].dir,1,(zb[z].dir==0) ? tk.ask : tk.bid,risk,zkey);
            Print("T2R Lab demo trade: ",((zb[z].dir==0) ? "BUY " : "SELL "),WatchLabel(w));
            if(!told && InpTgSignals)
              {
               TgSignal(g_nOpen-1,why,true);
               told=true;
              }
           }
        }
     }
   if(g_openDirty)
      SaveOpen();
  }

//--- everything the "full story" pop-up needs about one followed setup, backtest and live
string WatchData(const int w)
  {
   string s="";
   for(int sg=0;sg<3;sg++)
      s+=IntegerToString(g_watch[w].bn[sg])+","+IntegerToString(g_watch[w].bw[sg])+",";
   s+=DoubleToString(WatchRatio(w),2);
   for(int sg=0;sg<3;sg++)
      s+=","+IntegerToString(g_watch[w].b1[sg]);
   for(int q=0;q<4;q++)
      s+=","+DateS(g_watch[w].tt[q]);
   s+=","+DoubleToString((double)((long)g_watch[w].tt[3]-(long)g_watch[w].tt[0])/604800.0,1);
   for(int sg=0;sg<3;sg++)
      s+=","+DoubleToString(g_watch[w].bt[sg],3);
   s+=","+IntegerToString(g_watch[w].nWin)+","+IntegerToString(g_watch[w].nLoss)+","+DoubleToString(g_watch[w].sumR,2)+","+
      IntegerToString(g_watch[w].nTp1)+","+DoubleToString(g_watch[w].sumR2,2)+","+IntegerToString(g_watch[w].nPend)+","+
      IntegerToString(g_watch[w].nOpen)+","+IntegerToString(g_watch[w].nCancel);
   return s;
  }

//--- an open demo trade valued at the current price, in R (a pending order has no floating result)
double FloatR(const int k)
  {
   MqlTick tk;
   if(g_open[k].state!=1 || g_open[k].unit<=0.0 || !SymbolInfoTick(g_watch[g_open[k].w].sym,tk))
      return 0.0;
   if(g_open[k].dir==0)
      return (tk.bid-g_open[k].entry)/g_open[k].unit;
   return (g_open[k].entry-tk.ask)/g_open[k].unit;
  }

//--- the live scoreboard on the dashboard
void WriteLiveHtml(const int h)
  {
   if(g_nWatch<=0)
     {
      FileWriteString(h,"<div class='box'><h2>Live demo test</h2><p class='note'>Starts by itself when the scan finishes: every setup that held up in all "+
                      "three stages is followed, each signal becomes a demo trade, and each trade is tracked to its stop or target.</p></div>");
      return;
     }
   int sig=0;
   int win=0;
   int loss=0;
   int opn=0;
   int pend=0;
   int tp1=0;
   int mk=0;
   double tot=0.0;
   double tot2=0.0;
   for(int w=0;w<g_nWatch;w++)
     {
      sig+=g_watch[w].nSig;
      win+=g_watch[w].nWin;
      loss+=g_watch[w].nLoss;
      opn+=g_watch[w].nOpen;
      pend+=g_watch[w].nPend;
      tp1+=g_watch[w].nTp1;
      tot+=g_watch[w].sumR;
      tot2+=g_watch[w].sumR2;
      bool seen=false;
      for(int e=0;e<w && !seen;e++)
         if(g_watch[e].sym==g_watch[w].sym)
            seen=true;
      if(!seen)
         mk++;
     }
   int done=win+loss;
   double fl[];
   ArrayResize(fl,g_nWatch);
   ArrayInitialize(fl,0.0);
   double flt=0.0;
   for(int oi=0;oi<g_nOpen;oi++)
      if(g_open[oi].state==1)
        {
         double fr=FloatR(oi);
         fl[g_open[oi].w]+=fr;
         flt+=fr;
        }
   string s="<div class='box fb' id='b0'><h2>Live demo test</h2><p class='note'>The setups that held up in all three backtest stages, fixed as one list: <b>"+
            IntegerToString(g_nWatch)+" setups on "+IntegerToString(mk)+" markets</b> (at most "+IntegerToString(MathMax(InpWatchPerAsset,1))+
            " per market). Where the zone is known in advance a <b>pending order</b> is given ahead of time; setups that need a last check are entered "+
            "when price arrives. Every order is followed to its stop or target at real prices, so a stop that gets jumped costs more than 1R. No real "+
            "orders are placed. This is fresh data the backtest never saw: whatever stays green here is what deserves real money.</p>";
   s+="<div class='cards'><div class='c'><b>"+IntegerToString(pend)+"</b><span>Pending orders waiting</span></div>";
   s+="<div class='c'><b>"+IntegerToString(opn)+"</b><span>Trades open now</span></div>";
   s+="<div class='c'><b>"+IntegerToString(win)+" / "+IntegerToString(loss)+"</b><span>Wins / losses"+
      ((done>0) ? " ("+IntegerToString((int)MathRound(100.0*win/done))+"% won)" : "")+"</span></div>";
   s+="<div class='c'><b>"+((done>0) ? IntegerToString((int)MathRound(100.0*tp1/done))+"%" : "-")+"</b><span>Reached 1:1 first</span></div>";
   s+="<div class='c'><b class='"+RCls(tot)+"'>"+RTxt(tot)+"R</b><span>Holding to full target</span></div>";
   s+="<div class='c'><b class='"+RCls(tot2)+"'>"+RTxt(tot2)+"R</b><span>Half off at 1:1</span></div>";
   s+="<div class='c'><b class='"+RCls(flt)+"'>"+RTxt(flt)+"R</b><span>Floating now, "+IntegerToString(opn)+" open</span></div>";
   s+="<div class='c'><b class='mn "+RCls(flt)+"' data-r='"+DoubleToString(flt,2)+"'>-</b><span>Floating, with your risk</span></div></div>";
   s+="<div class='tools'><input class='q' type='text' placeholder='Filter: market, strategy, buys, wide ...'></div><div class='sc'><table><thead><tr>"+
      "<th class='l'>Market</th><th class='l'>Strategy</th><th class='l'>View</th><th class='l'>Side</th><th class='l'>Stop class</th>"+
      "<th>Risk : reward</th><th>Backtest win rate</th><th>Backtest avg R, stages 1 / 2 / 3</th><th>Per week</th><th>Pending</th><th>Open</th>"+
      "<th>Wins</th><th>Losses</th><th>Live win rate</th><th>Reached 1:1</th><th>Live avg R</th><th>Live total R</th><th>Half off at 1:1</th><th>Floating now</th>"+
      "</tr></thead><tbody>";
   FileWriteString(h,s);
   double k[][2];
   ArrayResize(k,g_nWatch);
   for(int w=0;w<g_nWatch;w++)
     {
      int act=g_watch[w].nSig+g_watch[w].nPend;
      k[w][0]=(act>0) ? -(1000000.0+g_watch[w].sumR+0.001*act) : (double)w;
      k[w][1]=w;
     }
   ArraySort(k);
   for(int q=0;q<g_nWatch;q++)
     {
      int w=(int)k[q][1];
      int dn=g_watch[w].nWin+g_watch[w].nLoss;
      double avg=(dn>0) ? g_watch[w].sumR/dn : 0.0;
      string line="<tr class='"+((dn>=20 && avg>=InpConfirmR) ? "p" : "")+"' data-k='"+g_watch[w].sym+"|"+g_sName[g_watch[w].strat]+"|"+
                  ViewName(g_watch[w].strat,g_watch[w].view)+"|"+g_sideName[g_watch[w].side]+"|"+g_scName[g_watch[w].scale]+"|"+g_smName[g_watch[w].si]+"|"+
                  g_levName[g_watch[w].lv]+"' data-d='"+WatchData(w)+"'><td class='l'>"+g_watch[w].sym+"</td><td class='l'>"+g_sName[g_watch[w].strat]+
                  "</td><td class='l'>"+ViewName(g_watch[w].strat,g_watch[w].view)+"</td><td class='l'>"+g_sideName[g_watch[w].side]+"</td><td class='l'>"+
                  g_scName[g_watch[w].scale]+(g_watch[w].house ? " *" : "")+"</td><td>"+RRText(g_watch[w].si,g_watch[w].lv)+"</td><td>"+
                  IntegerToString((int)MathRound(100.0*g_watch[w].wr))+"%</td><td>"+RTxt(g_watch[w].bt[0])+" / "+RTxt(g_watch[w].bt[1])+" / "+
                  RTxt(g_watch[w].bt[2])+" <small>("+IntegerToString(g_watch[w].btN)+")</small></td><td>"+DoubleToString(g_watch[w].perWeek,1)+"</td><td>"+
                  IntegerToString(g_watch[w].nPend)+"</td><td>"+IntegerToString(g_watch[w].nOpen)+"</td><td>"+IntegerToString(g_watch[w].nWin)+"</td><td>"+
                  IntegerToString(g_watch[w].nLoss)+"</td>";
      if(dn>0)
         line+="<td>"+IntegerToString((int)MathRound(100.0*g_watch[w].nWin/dn))+"%</td><td>"+IntegerToString((int)MathRound(100.0*g_watch[w].nTp1/dn))+
               "%</td><td class='"+RCls(avg)+"'>"+RTxt(avg)+"</td><td class='"+RCls(g_watch[w].sumR)+"'>"+RTxt(g_watch[w].sumR)+"</td><td class='"+
               RCls(g_watch[w].sumR2)+"'>"+RTxt(g_watch[w].sumR2)+"</td>";
      else
         line+="<td>-</td><td>-</td><td>-</td><td>-</td><td>-</td>";
      line+=(g_watch[w].nOpen>0) ? "<td class='"+RCls(fl[w])+"'>"+RTxt(fl[w])+"R</td></tr>" : "<td>-</td></tr>";
      FileWriteString(h,line);
     }
   FileWriteString(h,"</tbody></table></div><p class='note' style='margin-top:10px'>* followed because its whole market family passed. A row turns gold "+
                   "after 20 closed trades at "+RTxt(InpConfirmR)+"R a trade or better. Backtest win rate is from stages 2 and 3 only (history the "+
                   "strategy never saw). Every closed trade is in forward.csv.</p></div>");
//--- every activated trade, valued at the current price
   if(opn>0)
     {
      FileWriteString(h,"<div class='box fb' id='b8'><h2>Open trades right now</h2><p class='note'>Demo trades that have been activated and have not yet hit "+
                      "their stop or target, valued at the current price. Floating means not yet banked: it changes with every tick until the trade closes.</p>"+
                      "<div class='tools'><input class='q' type='text' placeholder='Filter: market, buy, sell ...'></div><div class='sc' style='max-height:420px'>"+
                      "<table><thead><tr><th class='l'>Opened</th><th class='l'>Market</th><th class='l'>Strategy</th><th class='l'>Order</th><th>Entry</th><th>Stop</th>"+
                      "<th>TP1 (1:1)</th><th>Target</th><th>Price now</th><th>Floating</th><th>With your risk</th><th>Reached 1:1</th></tr></thead><tbody>");
      for(int oi=0;oi<g_nOpen;oi++)
        {
         if(g_open[oi].state!=1)
            continue;
         int w=g_open[oi].w;
         int dg=(int)SymbolInfoInteger(g_watch[w].sym,SYMBOL_DIGITS);
         MqlTick tk;
         double now=0.0;
         if(SymbolInfoTick(g_watch[w].sym,tk))
            now=(g_open[oi].dir==0) ? tk.bid : tk.ask;
         double fr=FloatR(oi);
         FileWriteString(h,"<tr><td class='l'>"+TimeToString(g_open[oi].tFill,TIME_DATE|TIME_MINUTES)+"</td><td class='l'>"+g_watch[w].sym+"</td><td class='l'>"+
                         g_sName[g_watch[w].strat]+" <small>"+ViewName(g_watch[w].strat,g_watch[w].view)+", "+g_scName[g_watch[w].scale]+"</small></td><td class='l'>"+
                         ((g_open[oi].dir==0) ? "BUY" : "SELL")+"</td><td>"+DoubleToString(g_open[oi].entry,dg)+"</td><td>"+DoubleToString(g_open[oi].stop,dg)+
                         "</td><td>"+DoubleToString(g_open[oi].tp1,dg)+"</td><td>"+DoubleToString(g_open[oi].target,dg)+"</td><td>"+DoubleToString(now,dg)+
                         "</td><td class='"+RCls(fr)+"'>"+RTxt(fr)+"R</td><td class='mn "+RCls(fr)+"' data-r='"+DoubleToString(fr,2)+"'>-</td><td>"+
                         (g_open[oi].hit1 ? "yes" : "not yet")+"</td></tr>");
        }
      FileWriteString(h,"</tbody></table></div></div>");
     }
  }

//+------------------------------------------------------------------+
//| Replay: the signals the followed setups would have given over    |
//| the last few days, trade by trade, from the same test engine.    |
//+------------------------------------------------------------------+
struct RepTrade
  {
   int               w;
   datetime          tIn;
   datetime          tOut;
   int               dir;
   double            entry;
   double            stop;
   double            target;
   int               res;        // 1 won, 0 lost, 2 still open
   double            peak;       // the furthest level reached before the trade ended, in R (at least this far)
   double            t2r;        // result under the T2R rule: half off at +1R, stop to entry
   double            r;
  };

RepTrade g_rep[];
int      g_nRep       = 0;
bool     g_repActive  = false;
bool     g_repDone    = false;
int      g_repIdx     = 0;
datetime g_repFrom    = 0;
datetime g_repTo      = 0;

//--- called by the test engine for the asset / strategy it has just run
void ReplayCollect(ZTest &outs[],const int nouts)
  {
   for(int o=0;o<nouts;o++)
     {
      if(outs[o].tIn<g_repFrom)
         continue;
      for(int w=0;w<g_nWatch;w++)
        {
         if(g_watch[w].sym!=g_sym || g_watch[w].strat!=g_strat || g_watch[w].scale!=outs[o].scale)
            continue;
         if(!(g_watch[w].side==0 || (g_watch[w].side==1 && outs[o].dir==0) || (g_watch[w].side==2 && outs[o].dir==1)))
            continue;
         bool vOk=false;
         if(g_watch[w].view==0)
            vOk=(!g_viewExcl || !outs[o].flag);
         if(g_watch[w].view==1)
            vOk=outs[o].flag;
         if(g_watch[w].view==2)
            vOk=outs[o].pick;
         if(!vOk)
            continue;
         int si=g_watch[w].si;
         int lv=g_watch[w].lv;
         double ratio=g_lev[lv]/g_sm[si];
         double costR=outs[o].cost/g_sm[si];
         double unit=g_sm[si]*outs[o].risk;
         ArrayResize(g_rep,g_nRep+1,1024);
         g_rep[g_nRep].w=w;
         g_rep[g_nRep].tIn=outs[o].tIn;
         g_rep[g_nRep].dir=outs[o].dir;
         g_rep[g_nRep].entry=outs[o].entry;
         g_rep[g_nRep].stop=(outs[o].dir==0) ? outs[o].entry-unit : outs[o].entry+unit;
         g_rep[g_nRep].target=(outs[o].dir==0) ? outs[o].entry+g_lev[lv]*outs[o].risk : outs[o].entry-g_lev[lv]*outs[o].risk;
         if(outs[o].reached[si]>lv)
           {
            g_rep[g_nRep].res=1;
            g_rep[g_nRep].r=ratio-costR;
            g_rep[g_nRep].tOut=outs[o].tHit[si*4+lv];
           }
         else
            if(outs[o].done[si])
              {
               g_rep[g_nRep].res=0;
               g_rep[g_nRep].r=-1.0-costR;
               g_rep[g_nRep].tOut=outs[o].tEnd[si];
              }
            else
              {
               g_rep[g_nRep].res=2;
               g_rep[g_nRep].r=0.0;
               g_rep[g_nRep].tOut=0;
              }
         int rc=MathMin(outs[o].reached[si],4);
         g_rep[g_nRep].peak=(rc>0) ? g_lev[rc-1]/g_sm[si] : 0.0;
         g_rep[g_nRep].t2r=g_rep[g_nRep].r;
         if(ratio>1.0 && g_rep[g_nRep].peak>=1.0)
           {
            if(g_rep[g_nRep].res==1)
               g_rep[g_nRep].t2r=0.5+0.5*ratio-costR;
            if(g_rep[g_nRep].res==0)
               g_rep[g_nRep].t2r=0.5-costR;
           }
         g_nRep++;
        }
     }
  }

double RepFloat(const int i)
  {
   if(g_rep[i].res!=2)
      return 0.0;
   MqlTick tk;
   double unit=MathAbs(g_rep[i].entry-g_rep[i].stop);
   if(unit<=0.0 || !SymbolInfoTick(g_watch[g_rep[i].w].sym,tk))
      return 0.0;
   return (g_rep[i].dir==0) ? (tk.bid-g_rep[i].entry)/unit : (g_rep[i].entry-tk.ask)/unit;
  }

void ReplayStart()
  {
   g_nRep=0;
   ArrayResize(g_rep,0);
   g_repIdx=0;
   g_repDone=false;
   g_repTo=TimeCurrent();
   g_repFrom=(datetime)((long)g_repTo-(long)MathMax(InpReplayDays,0)*86400);
   g_repActive=(g_nWatch>0 && InpReplayDays>0);
  }

void WriteReplayCsv()
  {
   int h=FileOpen(DIR_OUT+"replay.csv",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE)
      return;
   FileWriteString(h,"time_in,time_out,asset,strategy,view,side,stop_class,direction,entry,stop,target,risk_to_reward,result,R,peak_R_at_least,reached_1R,R_t2r\r\n");
   for(int i=0;i<g_nRep;i++)
     {
      int w=g_rep[i].w;
      int dg=(int)SymbolInfoInteger(g_watch[w].sym,SYMBOL_DIGITS);
      FileWriteString(h,TimeToString(g_rep[i].tIn,TIME_DATE|TIME_MINUTES)+","+((g_rep[i].tOut>0) ? TimeToString(g_rep[i].tOut,TIME_DATE|TIME_MINUTES) : "")+","+
                      g_watch[w].sym+","+g_sName[g_watch[w].strat]+","+ViewName(g_watch[w].strat,g_watch[w].view)+","+g_sideName[g_watch[w].side]+","+
                      g_scName[g_watch[w].scale]+","+((g_rep[i].dir==0) ? "buy" : "sell")+","+DoubleToString(g_rep[i].entry,dg)+","+
                      DoubleToString(g_rep[i].stop,dg)+","+DoubleToString(g_rep[i].target,dg)+","+RRText(g_watch[w].si,g_watch[w].lv)+","+
                      ((g_rep[i].res==1) ? "won" : ((g_rep[i].res==0) ? "lost" : "open"))+","+DoubleToString(g_rep[i].r,3)+","+
                      DoubleToString(g_rep[i].peak,2)+","+((g_rep[i].peak>=1.0) ? "yes" : "no")+","+DoubleToString(g_rep[i].t2r,3)+"\r\n");
     }
   FileClose(h);
  }

//--- one asset x strategy per call, so the terminal stays responsive
void ReplayStep()
  {
   while(g_repIdx<g_nWatch)
     {
      int a=g_repIdx;
      g_repIdx++;
      bool first=true;
      for(int b=0;b<a && first;b++)
         if(g_watch[b].sym==g_watch[a].sym && g_watch[b].strat==g_watch[a].strat)
            first=false;
      if(!first)
         continue;
      if(!SetCtx(g_watch[a].sym,InpChartTF,InpScoreBars))
         continue;
      SetStrategy(g_watch[a].strat);
      if(g_nAct==0)
         continue;
      g_liveScale=0;
      g_repOn=true;
      RunScore();
      g_repOn=false;
      Comment("T2R Lab: replaying the last ",InpReplayDays," days... ",g_repIdx," / ",g_nWatch,"   signals found ",g_nRep);
      return;
     }
   g_repActive=false;
   g_repDone=true;
   WriteReplayCsv();
   WriteHtml();
   int win=0;
   int loss=0;
   int opn=0;
   double tot=0.0;
   double flt=0.0;
   for(int i=0;i<g_nRep;i++)
     {
      if(g_rep[i].res==1)
         win++;
      if(g_rep[i].res==0)
         loss++;
      if(g_rep[i].res==2)
        {
         opn++;
         flt+=RepFloat(i);
        }
      tot+=g_rep[i].r;
     }
   string msg="T2R Lab - the last "+IntegerToString(InpReplayDays)+" days replayed\n"+IntegerToString(g_nRep)+" signals from "+IntegerToString(g_nWatch)+
              " followed setups: "+IntegerToString(win)+" won, "+IntegerToString(loss)+" lost, "+IntegerToString(opn)+" still open ("+RTxt(flt)+"R floating now).\nClosed trades: "+RTxt(tot)+
              "R after costs.\nThis week was part of the history the setups were chosen on, so it shows what the signals look like, not proof they work.";
   Tg(msg);
   Print(msg);
   Comment("T2R Lab: replay done, ",g_nRep," signals, ",RTxt(tot),"R. Live demo test running. Dashboard: MQL5\\Files\\",DIR_OUT,"dashboard.html");
  }

void WriteReplayHtml(const int h)
  {
   if(InpReplayDays<=0 || g_nWatch<=0)
      return;
   if(!g_repDone)
     {
      FileWriteString(h,"<div class='box'><h2>The last "+IntegerToString(InpReplayDays)+" days, replayed</h2><p class='note'>"+
                      (g_repActive ? "Working it out now: "+IntegerToString(g_repIdx)+" of "+IntegerToString(g_nWatch)+" setups checked, "+
                       IntegerToString(g_nRep)+" signals found so far." : "Appears here once the scan has finished.")+"</p></div>");
      return;
     }
   int win=0;
   int loss=0;
   int opn=0;
   double tot=0.0;
   double flt=0.0;
   int wn[];
   int wl[];
   int wo[];
   double wr[];
   ArrayResize(wn,g_nWatch);
   ArrayResize(wl,g_nWatch);
   ArrayResize(wo,g_nWatch);
   ArrayResize(wr,g_nWatch);
   ArrayInitialize(wn,0);
   ArrayInitialize(wl,0);
   ArrayInitialize(wo,0);
   ArrayInitialize(wr,0.0);
   for(int i=0;i<g_nRep;i++)
     {
      int w=g_rep[i].w;
      if(g_rep[i].res==1)
        {
         win++;
         wn[w]++;
        }
      if(g_rep[i].res==0)
        {
         loss++;
         wl[w]++;
        }
      if(g_rep[i].res==2)
        {
         opn++;
         wo[w]++;
         flt+=RepFloat(i);
        }
      tot+=g_rep[i].r;
      wr[w]+=g_rep[i].r;
     }
   int act=0;
   int green=0;
   for(int w=0;w<g_nWatch;w++)
      if(wn[w]+wl[w]+wo[w]>0)
        {
         act++;
         if(wr[w]>0.0)
            green++;
        }
   int done=win+loss;
   string s="<div class='box fb' id='b6'><h2>The last "+IntegerToString(InpReplayDays)+" days, replayed</h2><p class='note'>Every signal the followed setups "+
            "would have given from <b>"+TimeToString(g_repFrom,TIME_DATE|TIME_MINUTES)+"</b> to <b>"+TimeToString(g_repTo,TIME_DATE|TIME_MINUTES)+
            "</b>, with its entry, stop, target and result, after trading costs. <b>Read this as an example of a week, not as proof:</b> these days were "+
            "part of the history the setups were chosen on, so the result is flattered by hindsight. Stops are assumed filled at the stop price; the "+
            "live demo test above uses real fills. A market with several followed setups can show the same move more than once.</p>";
   s+="<div class='cards'><div class='c'><b>"+Num(g_nRep)+"</b><span>Signals</span></div>";
   s+="<div class='c'><b>"+Num(win)+" / "+Num(loss)+"</b><span>Won / lost"+((done>0) ? " ("+IntegerToString((int)MathRound(100.0*win/done))+"% won)" : "")+"</span></div>";
   s+="<div class='c'><b>"+Num(opn)+"</b><span>Still open</span></div>";
   s+="<div class='c'><b class='"+RCls(flt)+"'>"+RTxt(flt)+"R</b><span>Open ones, floating now</span></div>";
   s+="<div class='c'><b class='"+RCls(tot)+"'>"+RTxt(tot)+"R</b><span>Total result</span></div>";
   s+="<div class='c'><b class='mn "+RCls(tot)+"' data-r='"+DoubleToString(tot,2)+"'>-</b><span>With your risk per trade</span></div>";
   s+="<div class='c'><b>"+IntegerToString(green)+" / "+IntegerToString(act)+"</b><span>Setups in profit / with signals</span></div></div>";
   s+="<h3>Setup by setup</h3><div class='tools'><input class='q' type='text' placeholder='Filter: market, strategy, sells ...'></div>"+
      "<div class='sc' style='max-height:420px'><table><thead><tr><th class='l'>Market</th><th class='l'>Strategy</th><th class='l'>View</th><th class='l'>Side</th>"+
      "<th class='l'>Stop class</th><th>Risk : reward</th><th>Signals</th><th>Won</th><th>Lost</th><th>Open</th><th>Win rate</th><th>Result</th>"+
      "<th>With your risk</th></tr></thead><tbody>";
   FileWriteString(h,s);
   double k[][2];
   ArrayResize(k,g_nWatch);
   for(int w=0;w<g_nWatch;w++)
     {
      k[w][0]=-wr[w];
      k[w][1]=w;
     }
   ArraySort(k);
   for(int q=0;q<g_nWatch;q++)
     {
      int w=(int)k[q][1];
      int n=wn[w]+wl[w]+wo[w];
      if(n<=0)
         continue;
      int dn=wn[w]+wl[w];
      FileWriteString(h,"<tr data-k='"+g_watch[w].sym+"|"+g_sName[g_watch[w].strat]+"|"+ViewName(g_watch[w].strat,g_watch[w].view)+"|"+
                      g_sideName[g_watch[w].side]+"|"+g_scName[g_watch[w].scale]+"|"+g_smName[g_watch[w].si]+"|"+g_levName[g_watch[w].lv]+"' data-d='"+
                      WatchData(w)+"'><td class='l'>"+g_watch[w].sym+"</td><td class='l'>"+g_sName[g_watch[w].strat]+"</td><td class='l'>"+
                      ViewName(g_watch[w].strat,g_watch[w].view)+"</td><td class='l'>"+g_sideName[g_watch[w].side]+"</td><td class='l'>"+
                      g_scName[g_watch[w].scale]+"</td><td>"+RRText(g_watch[w].si,g_watch[w].lv)+"</td><td>"+IntegerToString(n)+"</td><td>"+
                      IntegerToString(wn[w])+"</td><td>"+IntegerToString(wl[w])+"</td><td>"+IntegerToString(wo[w])+"</td><td>"+
                      ((dn>0) ? IntegerToString((int)MathRound(100.0*wn[w]/dn))+"%" : "-")+"</td><td class='"+RCls(wr[w])+"'>"+RTxt(wr[w])+
                      "R</td><td class='mn "+RCls(wr[w])+"' data-r='"+DoubleToString(wr[w],2)+"'>-</td></tr>");
     }
   FileWriteString(h,"</tbody></table></div></div>");

//--- every signal, newest first
   s="<div class='box fb' id='b7'><h2>Every signal in those "+IntegerToString(InpReplayDays)+" days</h2><p class='note'>Newest first"+
     ((g_nRep>1500) ? ", the latest 1500 of "+Num(g_nRep)+" shown; all of them are in replay.csv" : "")+
     ". This is what the Telegram feed would have looked like.</p><div class='tools'><input class='q' type='text' placeholder='Filter: market, strategy, won, lost, buy ...'></div>"+
     "<div class='sc' style='max-height:520px'><table><thead><tr><th class='l'>Signal time</th><th class='l'>Market</th><th class='l'>Strategy</th>"+
     "<th class='l'>Order</th><th>Entry</th><th>Stop</th><th>Target</th><th>Risk : reward</th><th class='l'>Result</th><th>R</th><th class='l'>Closed</th>"+
     "</tr></thead><tbody>";
   FileWriteString(h,s);
   if(g_nRep>0)
     {
      double tk[][2];
      ArrayResize(tk,g_nRep);
      for(int i=0;i<g_nRep;i++)
        {
         tk[i][0]=-(double)((long)g_rep[i].tIn);
         tk[i][1]=i;
        }
      ArraySort(tk);
      for(int q=0;q<g_nRep && q<1500;q++)
        {
         int i=(int)tk[q][1];
         int w=g_rep[i].w;
         int dg=(int)SymbolInfoInteger(g_watch[w].sym,SYMBOL_DIGITS);
         string res=(g_rep[i].res==1) ? "<span class='g'>won</span>" : ((g_rep[i].res==0) ? "<span class='r'>lost</span>" : "open, not closed yet");
         FileWriteString(h,"<tr><td class='l'>"+TimeToString(g_rep[i].tIn,TIME_DATE|TIME_MINUTES)+"</td><td class='l'>"+g_watch[w].sym+"</td><td class='l'>"+
                         g_sName[g_watch[w].strat]+" <small>"+ViewName(g_watch[w].strat,g_watch[w].view)+", "+g_scName[g_watch[w].scale]+"</small></td><td class='l'>"+
                         ((g_rep[i].dir==0) ? "BUY" : "SELL")+"</td><td>"+DoubleToString(g_rep[i].entry,dg)+"</td><td>"+DoubleToString(g_rep[i].stop,dg)+
                         "</td><td>"+DoubleToString(g_rep[i].target,dg)+"</td><td>"+RRText(g_watch[w].si,g_watch[w].lv)+"</td><td class='l'>"+res+
                         "</td><td class='"+RCls(g_rep[i].r)+"'>"+((g_rep[i].res==2) ? RTxt(RepFloat(i))+" floating" : RTxt(g_rep[i].r))+"</td><td class='l'>"+
                         ((g_rep[i].tOut>0) ? TimeToString(g_rep[i].tOut,TIME_DATE|TIME_MINUTES) : "-")+"</td></tr>");
        }
     }
   FileWriteString(h,"</tbody></table></div></div>");
  }

//+------------------------------------------------------------------+
//| Events                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_study=(InpStudyOnly!="");
   if(g_study)
     {
      DIR_OUT="T2R_Study\\";
      FolderCreate("T2R_Study");
      g_studyH=FileOpen(DIR_OUT+"study.csv",FILE_WRITE|FILE_TXT|FILE_ANSI);
      if(g_studyH==INVALID_HANDLE)
        {
         Print("T2R Lab STUDY: cannot write MQL5\\Files\\T2R_Study\\study.csv");
         return INIT_FAILED;
        }
      FileWriteString(g_studyH,"asset,strategy,in_view_all,in_view_second,picked,direction,stop_class,tf_mask,time_in,cost_R,"
                      "reached_s02,done_s02,reached_s05,done_s05,reached_s1,done_s1,reached_s2,done_s2\r\n");
      g_studyN=0;
      StartScan();
      EventSetTimer(1);
      return INIT_SUCCEEDED;
     }
   FolderCreate("T2R_Lab");
   LoadWatch();
   LoadLedger();
   LoadOpen();
   if(InpScanOnStart || g_nWatch==0)
      StartScan();
   else
     {
      g_scanning=false;
      g_scanEnd=TimeLocal();
      ReplayStart();
      WriteHtml();
      Comment("T2R Lab: live demo test, following ",g_nWatch," combos. Dashboard: MQL5\\Files\\",DIR_OUT,"dashboard.html");
     }
   if(InpTgToken!="" && InpTgChat!="")
      TgSend("<b>T2R Lab is live</b> "+U(0x1F7E2)+"\nSignals from the live demo arrive here as cards: entry, stop, TP1 and target, then updates under each one (activated, +1R, target, stop, cancel)."+
             ((InpTgMaxPerDay>0) ? "\nAt most "+IntegerToString(InpTgMaxPerDay)+" signals per market per day." : ""),0);
   DeskSyncAll();
   if(InpWebUrl!="" && InpWebKey!="")
      Print("T2R Lab: posting signals to the website desk at ",InpWebUrl);
   EventSetTimer(1);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(g_studyH!=INVALID_HANDLE)
      FileClose(g_studyH);
   Comment("");
  }

void OnTick()
  {
  }

void OnTimer()
  {
   DeskFlush();
   TradeGuard();
   if(g_scanning)
      ScanStep();
   if(g_study)
      return;
   else
      if(InpRescanHours>0 && TimeLocal()-g_scanEnd>=InpRescanHours*3600)
        {
         StartScan();
         return;
        }
   if(g_nWatch<=0)
      return;
   if(g_repActive && !g_scanning)
      ReplayStep();
   if(TimeLocal()-g_lastSig>=60)
     {
      g_lastSig=TimeLocal();
      UpdateTrades(true);
      CheckSignals();
      if(!g_scanning && GetTickCount()-g_lastHtml>60000)
         WriteHtml();
     }
   else
      if(!g_scanning)
         UpdateTrades(false);
  }
//+------------------------------------------------------------------+
