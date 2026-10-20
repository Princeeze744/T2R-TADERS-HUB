//+------------------------------------------------------------------+
//| T2R_Clock.mq5                                                    |
//| Trade2Retire Academy - T2R Clock (Rollover Bounce)               |
//| From the T2R Market DNA study: on most forex pairs the hour      |
//| after the New York 17:00 rollover closes up far more often than  |
//| chance. This EA buys each listed pair at New York 18:00          |
//| (Mon-Thu) once the spread has settled and closes at 19:00.       |
//| v1.30: posts every signal and result to Telegram (your DM) and   |
//| to the website Signal Desk, same address and key as T2R Lab.     |
//| It keeps a CSV journal of every real fill and spread so we can   |
//| see if the edge survives real execution.                         |
//| Times are New York time, worked out from GMT, so it runs the     |
//| same on any broker (the server's clock does not matter).         |
//| One chart runs every pair. Attach it to any chart.               |
//+------------------------------------------------------------------+
#property copyright   "Trade2Retire Academy"
#property version     "1.31"
#property description "T2R Clock: after-rollover bounce, all pairs from one chart, Telegram + website signals"
#include <Trade/Trade.mqh>

input group "Pairs"
input string InpPairs      = "GBPCHF,EURCAD,EURAUD,USDCHF,EURCHF,CHFJPY"; // Pairs to trade (the 6 core pairs; missing ones are skipped)
input string InpBreakEven  = "CHFJPY:10.9,GBPCHF:7.2,GBPSGD:12.9,EURSGD:11.1,AUDSGD:6.3,EURAUD:6.1,AUDCAD:4.7,USDCHF:4.3,EURJPY:4.5,EURCAD:4.5,NZDCAD:4.6,NZDJPY:4.0,AUDNZD:4.3,GBPJPY:5.3,GBPCAD:4.7,NZDCHF:4.0,AUDJPY:3.9,CADCHF:3.6,EURCHF:3.3,GBPUSD:2.9,EURGBP:2.2"; // Average move NY 18:00-19:00 in pips, 3 years of data (the yardstick)
input string InpSuffix     = "";        // Broker suffix (e.g. ".r" or "m"), blank if none
input group "Timing (New York time)"
input int    InpEntryHour  = 18;        // Buy at this New York hour
input int    InpEntryWindow= 20;        // ...within this many minutes, once the spread is normal
input int    InpExitHour   = 19;        // Close at this New York hour
input bool   InpMonThu     = true;      // Only Monday-Thursday evenings (skip the weekly close)
input bool   InpSummerOnly = true;      // Only while the US is on summer time (2nd Sun March - 1st Sun Nov): winter was flat in tests
input group "Costs (works for any prop firm)"
input double InpCommission = 5.0;       // Your commission, USD per round lot (Deriv 0, Equity Edge 3, The5ers 4)
input double InpSafety     = 0.5;       // Trade a pair only if spread+commission <= this x its average move
input group "Risk (prop-firm safe)"
input double InpRiskPct    = 0.10;      // Risk per trade, % of equity (all pairs move together: keep it small)
input double InpStopDays   = 0.5;       // Stop = this x a normal day's range (DNA: beats 9 in 10 stop hunts)
input double InpDailyStop  = 2.0;       // Stop trading for the day if equity falls this % from the day's start
input int    InpMaxOpen    = 12;        // Most trades open at once
input double InpSpreadMult = 0;         // Extra guard: only enter when spread <= this x the pair's normal spread (0 = off; the cost check above already protects)
input int    InpMinWait    = 3;         // Wait this many minutes after the entry hour starts (the rollover spread spike is in the first 1-3 minutes)
input bool   InpTrade      = true;      // false = signals only (Telegram, website, journal), place no orders
input long   InpMagic      = 18190;     // Magic number
input group "Telegram (leave empty to switch off)"
input string InpTgToken    = "";        // Bot token from @BotFather (same as T2R Lab)
input string InpTgChat     = "";        // Chat id: your own DM id for the forward test
input bool   InpTgHeadsUp  = true;      // Send a 5-minute heads-up before the entry
input group "Website Signal Desk (leave empty to switch off)"
input string InpWebUrl     = "";        // e.g. https://t2r-traders-hub.vercel.app/api/ingest (same as T2R Lab)
input string InpWebKey     = "";        // The T2R_INGEST_KEY password set in Vercel (same as T2R Lab)
input group "Strategy Tester only"
input int    InpTesterGMT  = 0;         // Server clock minus GMT, in hours (Deriv = 0). Only used in the Strategy Tester

#define STRAT_NAME "T2R Clock"

CTrade  trade;
string  g_sym[];          // broker symbol (with suffix)
string  g_name[];         // clean pair name (no suffix)
double  g_normSpr[];      // each pair's normal spread (points), learned outside the rollover hours
double  g_be[];           // each pair's average NY 18-19 move in pips (0 = unknown)
datetime g_doneDay[];      // New York day already handled per pair
// today's trade per pair (real fill, or paper when InpTrade=false)
int     g_st[];           // 0 none, 1 open, 2 closed (time), 3 stopped, 9 skipped
ulong   g_tk[];
double  g_ent[], g_sl[], g_exit[], g_lots[];
datetime g_tin[], g_tout[];
string  g_why[];          // skip reason / status text
string  g_id[];
double  g_dayStartEq = 0;
int     g_dayKey = -1;
bool    g_halt = false;
int     g_fileOk = 1;
int     g_lastJm[];       // minute of the last WAIT line in the journal, per pair
datetime g_tgHead = 0, g_tgSig = 0, g_tgRes = 0;   // New York day the heads-up / signal / result message went out
string  g_dq[];
int     g_nDq = 0;
uint    g_dqLast = 0;
bool    g_dqWarned = false, g_tgWarned = false;

//--- New York offset from GMT: -4 in US daylight time (2nd Sun Mar .. 1st Sun Nov), else -5
int NYOffset(datetime gmt)
  {
   MqlDateTime t; TimeToStruct(gmt, t);
   int y = t.year;
   datetime mar = StringToTime(IntegerToString(y) + ".03.08 07:00");   // 2am NY = 07:00 GMT
   MqlDateTime a; TimeToStruct(mar, a);
   mar += (datetime)(((7 - a.day_of_week) % 7) * 86400);
   datetime nov = StringToTime(IntegerToString(y) + ".11.01 06:00");   // 2am NY (EDT) = 06:00 GMT
   MqlDateTime b; TimeToStruct(nov, b);
   nov += (datetime)(((7 - b.day_of_week) % 7) * 86400);
   return (gmt >= mar && gmt < nov) ? -4 : -5;
  }

//--- in the Strategy Tester TimeGMT() equals the server clock, so remove the server's offset by hand
datetime GMTNow() { return MQLInfoInteger(MQL_TESTER) ? TimeCurrent() - InpTesterGMT * 3600 : TimeGMT(); }
datetime NYNow() { datetime g = GMTNow(); return g + NYOffset(g) * 3600; }
string   Lagos(datetime gmt) { return TimeToString(gmt + 3600, TIME_MINUTES); }   // Lagos = GMT+1 all year

double DayRange(const string s)
  {
   double h[], l[];
   if(CopyHigh(s, PERIOD_D1, 1, 20, h) < 10 || CopyLow(s, PERIOD_D1, 1, 20, l) < 10) return 0;
   double r[]; int n = ArraySize(h); ArrayResize(r, n);
   for(int i = 0; i < n; i++) r[i] = h[i] - l[i];
   ArraySort(r);
   return r[n / 2];
  }

double RiskPerLot(const string s, double stopDist)
  {
   double tv = SymbolInfoDouble(s, SYMBOL_TRADE_TICK_VALUE), ts = SymbolInfoDouble(s, SYMBOL_TRADE_TICK_SIZE);
   if(tv <= 0 || ts <= 0 || stopDist <= 0) return 0;
   return stopDist / ts * tv;
  }

double LotsFor(const string s, double stopDist)
  {
   double risk = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPct / 100.0;
   double rpl = RiskPerLot(s, stopDist);
   if(rpl <= 0) return 0;
   double lots = risk / rpl;
   double step = SymbolInfoDouble(s, SYMBOL_VOLUME_STEP), mn = SymbolInfoDouble(s, SYMBOL_VOLUME_MIN), mx = SymbolInfoDouble(s, SYMBOL_VOLUME_MAX);
   lots = MathFloor(lots / step) * step;
   if(lots < mn) return 0;                      // never take more risk than asked
   return MathMin(lots, mx);
  }

void Journal(const string what, const string s, double bid, double ask, double sprPts, double normPts, double lots, double sl, double pnl)
  {
   int h = FileOpen("T2R_Clock_journal.csv", FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ, ',');
   if(h == INVALID_HANDLE) { g_fileOk = 0; return; }
   if(FileSize(h) == 0) FileWrite(h, "time_gmt", "ny_time", "event", "symbol", "bid", "ask", "spread_pts", "normal_spread_pts", "lots", "stop", "profit");
   FileSeek(h, 0, SEEK_END);
   int dg = (int)SymbolInfoInteger(s, SYMBOL_DIGITS);
   FileWrite(h, TimeToString(GMTNow(), TIME_DATE | TIME_SECONDS), TimeToString(NYNow(), TIME_DATE | TIME_MINUTES), what, s,
             DoubleToString(bid, dg), DoubleToString(ask, dg), DoubleToString(sprPts, 0), DoubleToString(normPts, 1), DoubleToString(lots, 2),
             DoubleToString(sl, dg), DoubleToString(pnl, 2));
   FileClose(h);
  }

double BreakEven(string name)
  {
   StringTrimLeft(name); StringTrimRight(name);
   string it[]; int n = StringSplit(InpBreakEven, ',', it);
   for(int i = 0; i < n; i++)
     {
      string kv[];
      if(StringSplit(it[i], ':', kv) == 2) { string a = kv[0]; StringTrimLeft(a); StringTrimRight(a); if(a == name) return StringToDouble(kv[1]); }
     }
   return 0;
  }

double PipSize(const string s)
  {
   int dg = (int)SymbolInfoInteger(s, SYMBOL_DIGITS); double pt = SymbolInfoDouble(s, SYMBOL_POINT);
   return (dg == 3 || dg == 5) ? pt * 10 : pt;
  }

//--- all-in cost of one trade right now, in pips: spread + commission
double CostPips(const string s, double sprPts)
  {
   double pip = PipSize(s), pt = SymbolInfoDouble(s, SYMBOL_POINT);
   double tv = SymbolInfoDouble(s, SYMBOL_TRADE_TICK_VALUE), ts = SymbolInfoDouble(s, SYMBOL_TRADE_TICK_SIZE);
   double pipValueLot = (ts > 0) ? tv * pip / ts : 0;
   double comm = (pipValueLot > 0) ? InpCommission / pipValueLot : 0;
   return sprPts * pt / pip + comm;
  }

int OpenCount()
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetTicket(i) > 0 && PositionGetInteger(POSITION_MAGIC) == InpMagic) n++;
   return n;
  }

//+------------------------------------------------------------------+
//| Telegram                                                         |
//+------------------------------------------------------------------+
string U(const int cp)
  {
   if(cp < 0x10000) return ShortToString((ushort)cp);
   int v = cp - 0x10000;
   return ShortToString((ushort)(0xD800 + (v >> 10))) + ShortToString((ushort)(0xDC00 + (v & 0x3FF)));
  }

string UrlEnc(const string txt)
  {
   uchar b[];
   int n = StringToCharArray(txt, b, 0, WHOLE_ARRAY, CP_UTF8) - 1;
   string out = "";
   for(int i = 0; i < n; i++)
     {
      uchar c = b[i];
      if((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.') out += CharToString(c);
      else out += StringFormat("%%%02X", c);
     }
   return out;
  }

bool TgSend(const string html)
  {
   if(MQLInfoInteger(MQL_TESTER) || InpTgToken == "" || InpTgChat == "") return false;
   string url = "https://api.telegram.org/bot" + InpTgToken + "/sendMessage";
   string body = "chat_id=" + UrlEnc(InpTgChat) + "&parse_mode=HTML&disable_web_page_preview=true&text=" + UrlEnc(html);
   uchar post[], res[]; string hdr = "";
   int len = StringToCharArray(body, post, 0, WHOLE_ARRAY, CP_UTF8) - 1;
   if(len <= 0) return false;
   ArrayResize(post, len);
   ResetLastError();
   int code = WebRequest("POST", url, "Content-Type: application/x-www-form-urlencoded\r\n", 5000, post, res, hdr);
   if(code != 200 && !g_tgWarned)
     {
      g_tgWarned = true;
      Print("T2R Clock: Telegram not sent (code ", code, ", error ", GetLastError(), ") ", StringSubstr(CharArrayToString(res, 0, WHOLE_ARRAY, CP_UTF8), 0, 200),
            " In MT5: Tools > Options > Expert Advisors > allow WebRequest for https://api.telegram.org");
     }
   return code == 200;
  }

string Pips(double v) { return (v >= 0 ? "+" : "") + DoubleToString(v, 1); }
string Rs(double v)   { return (v >= 0 ? "+" : "") + DoubleToString(v, 2) + "R"; }

//+------------------------------------------------------------------+
//| Website Signal Desk (same /api/ingest as T2R Lab)                |
//+------------------------------------------------------------------+
string JStr(const string v)
  {
   string o = v;
   StringReplace(o, "\\", "\\\\");
   StringReplace(o, "\"", "\\\"");
   return "\"" + o + "\"";
  }
string JKey(const string k) { return "\"" + k + "\":"; }

void Desk(const int k, const string kind, const double price, const datetime at, const bool hasR, const double r)
  {
   if(MQLInfoInteger(MQL_TESTER) || InpWebUrl == "" || InpWebKey == "") return;
   string s = g_sym[k];
   int dg = (int)SymbolInfoInteger(s, SYMBOL_DIGITS);
   string j = "{" + JKey("id") + JStr(g_id[k]) + "," + JKey("kind") + JStr(kind) + "," + JKey("at") + IntegerToString((long)at) + "," +
              JKey("market") + JStr(g_name[k]) + "," + JKey("family") + JStr("Forex") + "," + JKey("strategy") + JStr(STRAT_NAME) + "," +
              JKey("view") + JStr("Rollover bounce, 18:00-19:00 New York") + "," + JKey("side") + JStr("Buy only") + "," +
              JKey("stop_class") + JStr("Half a day's range") + "," + JKey("dir") + JStr("buy") + "," + JKey("order_type") + JStr("market") + "," +
              JKey("entry") + DoubleToString(g_ent[k], dg) + "," + JKey("stop") + DoubleToString(g_sl[k], dg) + "," +
              JKey("rr") + JStr("time exit, 1 hour") + "," + JKey("t_signal") + IntegerToString((long)g_tin[k]) + "," + JKey("t_fill") + IntegerToString((long)g_tin[k]) + "," +
              JKey("risk_per_lot") + DoubleToString(RiskPerLot(s, g_ent[k] - g_sl[k]), 4) + "," +
              JKey("vol_min") + DoubleToString(SymbolInfoDouble(s, SYMBOL_VOLUME_MIN), 4) + "," + JKey("vol_step") + DoubleToString(SymbolInfoDouble(s, SYMBOL_VOLUME_STEP), 4) + "," +
              JKey("ccy") + JStr(AccountInfoString(ACCOUNT_CURRENCY)) + "," + JKey("lots") + DoubleToString(g_lots[k], 2) + "," + JKey("tg") + "true";
   if(price > 0) j += "," + JKey("price") + DoubleToString(price, dg);
   if(hasR) j += "," + JKey("r") + DoubleToString(r, 3) + "," + JKey("r_t2r") + DoubleToString(r, 3);
   if(kind == "update") j += "," + JKey("r_float") + DoubleToString(r, 3);
   j += "}";
   ArrayResize(g_dq, g_nDq + 1, 64); g_dq[g_nDq] = j; g_nDq++;
   if(g_nDq > 500) { ArrayRemove(g_dq, 0, g_nDq - 500); g_nDq = 500; }
  }

void DeskFlush()
  {
   if(g_nDq == 0 || InpWebUrl == "" || InpWebKey == "" || GetTickCount() - g_dqLast < 5000) return;
   g_dqLast = GetTickCount();
   int n = MathMin(g_nDq, 40);
   string body = "{" + JKey("events") + "[";
   for(int i = 0; i < n; i++) body += (i > 0 ? "," : "") + g_dq[i];
   body += "]}";
   uchar post[], res[]; string hdr = "";
   int len = StringToCharArray(body, post, 0, WHOLE_ARRAY, CP_UTF8) - 1;
   if(len <= 0) return;
   ArrayResize(post, len);
   ResetLastError();
   int code = WebRequest("POST", InpWebUrl, "Content-Type: application/json\r\nx-t2r-key: " + InpWebKey + "\r\n", 8000, post, res, hdr);
   if(code == 200) { ArrayRemove(g_dq, 0, n); g_nDq -= n; g_dqWarned = false; return; }
   if(!g_dqWarned)
     {
      g_dqWarned = true;
      Print("T2R Clock: website desk not reached (code ", code, ", error ", GetLastError(), ", answer ", CharArrayToString(res, 0, WHOLE_ARRAY, CP_UTF8),
            "). In MT5: Tools > Options > Expert Advisors > allow WebRequest for your website address. Will retry.");
     }
   if(code == 401 || code == 400) { ArrayRemove(g_dq, 0, n); g_nDq -= n; }
  }

//+------------------------------------------------------------------+
//| Trade book                                                       |
//+------------------------------------------------------------------+
double RofExit(const int k, double px) { double risk = g_ent[k] - g_sl[k]; return risk > 0 ? (px - g_ent[k]) / risk : 0; }

//--- the position for this pair (ours), or 0
ulong FindPos(const string s)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk > 0 && PositionGetInteger(POSITION_MAGIC) == InpMagic && PositionGetString(POSITION_SYMBOL) == s) return tk;
     }
   return 0;
  }

//--- the exit price of a closed position, from history
double ClosedPrice(const ulong pos)
  {
   if(!HistorySelectByPosition(pos)) return 0;
   double px = 0;
   for(int i = 0; i < HistoryDealsTotal(); i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_OUT) px = HistoryDealGetDouble(d, DEAL_PRICE);
     }
   return px;
  }

void Finish(const int k, const int how, const double px, const datetime at)
  {
   g_st[k] = how; g_exit[k] = px; g_tout[k] = at;
   double r = RofExit(k, px);
   Desk(k, how == 3 ? "stop" : "closed", px, at, true, r);
   if(how == 3)
      TgSend(U(0x1F6D1) + " <b>T2R CLOCK · STOPPED</b>\n" + g_name[k] + " hit its stop at <code>" + DoubleToString(px, (int)SymbolInfoInteger(g_sym[k], SYMBOL_DIGITS)) +
             "</code>: " + Pips((px - g_ent[k]) / PipSize(g_sym[k])) + " pips (" + Rs(r) + ").\nLosses are part of the plan.");
  }

void ResetDay()
  {
   for(int k = 0; k < ArraySize(g_sym); k++)
     { g_st[k] = 0; g_tk[k] = 0; g_ent[k] = 0; g_sl[k] = 0; g_exit[k] = 0; g_lots[k] = 0; g_tin[k] = 0; g_tout[k] = 0; g_why[k] = ""; }
  }

int OnInit()
  {
   string p[]; int n = StringSplit(InpPairs, ',', p);
   ArrayResize(g_sym, 0);
   for(int i = 0; i < n; i++)
     {
      string nm = p[i]; StringTrimLeft(nm); StringTrimRight(nm);
      if(nm == "") continue;
      string s = nm + InpSuffix;
      if(!SymbolSelect(s, true)) { Print("T2R Clock: symbol not found on this broker: ", s); continue; }
      int k = ArraySize(g_sym);
      int z = k + 1;
      ArrayResize(g_sym, z); ArrayResize(g_name, z); ArrayResize(g_normSpr, z); ArrayResize(g_doneDay, z); ArrayResize(g_be, z);
      ArrayResize(g_st, z); ArrayResize(g_tk, z); ArrayResize(g_ent, z); ArrayResize(g_sl, z); ArrayResize(g_exit, z); ArrayResize(g_lots, z);
      ArrayResize(g_tin, z); ArrayResize(g_tout, z); ArrayResize(g_why, z); ArrayResize(g_id, z); ArrayResize(g_lastJm, z); g_lastJm[k] = -1;
      g_be[k] = BreakEven(nm);
      g_sym[k] = s; g_name[k] = nm; g_normSpr[k] = (double)SymbolInfoInteger(s, SYMBOL_SPREAD); g_doneDay[k] = 0; g_id[k] = "";
     }
   if(ArraySize(g_sym) == 0) { Alert("T2R Clock: none of the pairs exist on this broker. Check the suffix."); return INIT_FAILED; }
   ResetDay();
   // restarted during the trade hour: pick our open positions back up
   datetime ny = NYNow(), nyDay = ny - (ny % 86400);
   for(int k = 0; k < ArraySize(g_sym); k++)
     {
      ulong tk = FindPos(g_sym[k]);
      if(tk == 0 || !PositionSelectByTicket(tk)) continue;
      g_st[k] = 1; g_tk[k] = tk; g_ent[k] = PositionGetDouble(POSITION_PRICE_OPEN); g_sl[k] = PositionGetDouble(POSITION_SL);
      g_lots[k] = PositionGetDouble(POSITION_VOLUME); g_tin[k] = GMTNow(); g_doneDay[k] = nyDay;
      g_id[k] = "CLK_" + g_name[k] + "_" + TimeToString(nyDay, TIME_DATE);
     }
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(30);
   EventSetTimer(5);
   Print("T2R Clock started on ", ArraySize(g_sym), " pairs. New York time now ", TimeToString(NYNow(), TIME_MINUTES),
         (InpTgToken != "" && InpTgChat != "" ? " · Telegram ON" : " · Telegram off"), (InpWebUrl != "" && InpWebKey != "" ? " · website ON" : " · website off"),
         (InpTrade ? "" : " · SIGNALS ONLY (no orders)"));
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int r) { EventKillTimer(); DeskFlush(); Comment(""); }

void OnTimer()
  {
   datetime gmt = GMTNow();
   datetime ny = NYNow();
   MqlDateTime t; TimeToStruct(ny, t);
   datetime nyDay = ny - (ny % 86400);
   // daily loss guard
   int key = t.year * 1000 + t.day_of_year;
   if(key != g_dayKey) { g_dayKey = key; g_dayStartEq = AccountInfoDouble(ACCOUNT_EQUITY); g_halt = false; }
   if(!g_halt && AccountInfoDouble(ACCOUNT_EQUITY) < g_dayStartEq * (1 - InpDailyStop / 100.0))
     {
      g_halt = true; Print("T2R Clock: daily loss guard hit, closing and pausing until tomorrow");
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        { ulong tk = PositionGetTicket(i); if(tk > 0 && PositionGetInteger(POSITION_MAGIC) == InpMagic) trade.PositionClose(tk); }
     }
   bool dayOk = (!InpMonThu || (t.day_of_week >= 1 && t.day_of_week <= 4)) && (!InpSummerOnly || NYOffset(gmt) == -4);
   bool rollZone = (t.hour == 16 && t.min >= 45) || t.hour == 17;
   bool inWindow = t.hour == InpEntryHour && t.min < InpEntryWindow;
   // a new trading evening: clear yesterday's book (keeps anything still open)
   if(t.hour == InpEntryHour && t.min == 0 && g_tgSig != nyDay)
      for(int k = 0; k < ArraySize(g_sym); k++) if(g_st[k] != 1 && g_doneDay[k] != nyDay) { g_st[k] = 0; g_why[k] = ""; }
   // heads-up 5 minutes before
   if(InpTgHeadsUp && dayOk && !g_halt && g_tgHead != nyDay && t.hour == InpEntryHour - 1 && t.min >= 55)
     {
      g_tgHead = nyDay;
      string pl = ""; for(int k = 0; k < ArraySize(g_sym); k++) pl += (k > 0 ? " · " : "") + g_name[k];
      TgSend(U(0x23F0) + " <b>T2R CLOCK in 5 minutes</b>\nEntry " + Lagos(gmt + 300) + " Lagos (" + IntegerToString(InpEntryHour) + ":00 New York), exit " +
             Lagos(gmt + 300 + 3600) + " Lagos.\nWatching: " + pl + "\nPairs whose spread is too wide will be skipped.");
     }
   int nOpen = OpenCount();
   string lines = "";
   bool allFinal = true, anyToday = false;
   for(int k = 0; k < ArraySize(g_sym); k++)
     {
      string s = g_sym[k];
      double bid = SymbolInfoDouble(s, SYMBOL_BID), ask = SymbolInfoDouble(s, SYMBOL_ASK), pt = SymbolInfoDouble(s, SYMBOL_POINT);
      if(bid <= 0 || ask <= 0 || pt <= 0) { allFinal = false; continue; }
      double spr = (ask - bid) / pt;
      if(!rollZone && t.hour != InpEntryHour) g_normSpr[k] = 0.98 * g_normSpr[k] + 0.02 * spr;
      // ---- an open trade: stop check, time exit
      if(g_st[k] == 1)
        {
         if(InpTrade)
           {
            if(g_tk[k] > 0 && !PositionSelectByTicket(g_tk[k]))
              {   // gone without us closing it: the broker's stop
               double px = ClosedPrice(g_tk[k]); if(px <= 0) px = g_sl[k];
               Journal("STOP", s, bid, ask, spr, g_normSpr[k], g_lots[k], g_sl[k], 0);
               Finish(k, 3, px, gmt);
              }
           }
         else if(bid <= g_sl[k]) { Journal("STOP", s, bid, ask, spr, g_normSpr[k], g_lots[k], g_sl[k], 0); Finish(k, 3, g_sl[k], gmt); }
         if(g_st[k] == 1 && (t.hour >= InpExitHour || t.hour < InpEntryHour))
           {
            if(InpTrade)
              {
               if(PositionSelectByTicket(g_tk[k]))
                 {
                  double pr = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
                  if(trade.PositionClose(g_tk[k])) { Journal("EXIT", s, bid, ask, spr, g_normSpr[k], g_lots[k], 0, pr); Finish(k, 2, trade.ResultPrice() > 0 ? trade.ResultPrice() : bid, gmt); }
                 }
              }
            else { Journal("EXIT", s, bid, ask, spr, g_normSpr[k], g_lots[k], 0, 0); Finish(k, 2, bid, gmt); }
           }
        }
      // ---- older positions of ours that are not on today's book (restart): close at exit time too
      if(InpTrade && g_st[k] != 1 && (t.hour >= InpExitHour || t.hour < InpEntryHour))
        { ulong tk = FindPos(s); if(tk > 0) trade.PositionClose(tk); }
      // ---- entry
      string st = g_why[k] != "" ? g_why[k] : "waiting";
      if(g_doneDay[k] == nyDay) { anyToday = true; }
      else if(dayOk && inWindow && !g_halt)
        {
         double cost = CostPips(s, spr);
         if(g_be[k] <= 0) { st = g_why[k] = "no yardstick for this pair"; g_doneDay[k] = nyDay; g_st[k] = 9; }
         else if(t.min < InpMinWait) st = "waiting for the rollover spike to pass";
         else if(cost > InpSafety * g_be[k]) st = StringFormat("too costly: %.1f pips vs %.1f allowed", cost, InpSafety * g_be[k]);
         else if(InpSpreadMult > 0 && spr > InpSpreadMult * MathMax(g_normSpr[k], 1)) st = "spread wide, waiting";
         else if(nOpen >= InpMaxOpen) st = "max trades open";
         else
           {
            double dr = DayRange(s);
            double sl = ask - InpStopDays * dr;
            double lots = LotsFor(s, ask - sl);
            int dg = (int)SymbolInfoInteger(s, SYMBOL_DIGITS);
            g_doneDay[k] = nyDay; anyToday = true;
            g_id[k] = "CLK_" + g_name[k] + "_" + TimeToString(nyDay, TIME_DATE);
            if(dr <= 0) { st = g_why[k] = "skipped (no day range)"; g_st[k] = 9; Journal("SKIP", s, bid, ask, spr, g_normSpr[k], 0, sl, 0); }
            else if(!InpTrade)
              {
               g_st[k] = 1; g_ent[k] = ask; g_sl[k] = NormalizeDouble(sl, dg); g_lots[k] = lots; g_tin[k] = gmt; st = g_why[k] = "BOUGHT (signal only)";
               Journal("SIGNAL", s, bid, ask, spr, g_normSpr[k], lots, sl, 0); Desk(k, "signal", ask, gmt, false, 0);
              }
            else if(lots <= 0) { st = g_why[k] = "skipped (lot too big for the risk)"; g_st[k] = 9; Journal("SKIP", s, bid, ask, spr, g_normSpr[k], 0, sl, 0); }
            else if(trade.Buy(lots, s, 0, NormalizeDouble(sl, dg), 0, "T2R Clock"))
              {
               nOpen++;
               g_st[k] = 1; g_ent[k] = trade.ResultPrice() > 0 ? trade.ResultPrice() : ask; g_sl[k] = NormalizeDouble(sl, dg); g_lots[k] = lots; g_tin[k] = gmt;
               g_tk[k] = FindPos(s); st = g_why[k] = "BOUGHT";
               Journal("BUY", s, bid, g_ent[k], spr, g_normSpr[k], lots, sl, 0); Desk(k, "signal", g_ent[k], gmt, false, 0);
              }
            else { st = g_why[k] = "order failed " + IntegerToString(trade.ResultRetcode()); g_st[k] = 9; Journal("FAIL", s, bid, ask, spr, g_normSpr[k], lots, sl, 0); }
           }
         if(g_st[k] == 0)
           {   // not decided yet: keep trying inside the window; log the spread once a minute so we learn the real cost
            allFinal = false;
            if(g_lastJm[k] != t.min) { g_lastJm[k] = t.min; Journal("WAIT", s, bid, ask, spr, g_normSpr[k], 0, 0, cost); }
            lines += StringFormat("%-9s cost %4.1f pips / avg move %4.1f  %s\n", s, cost, g_be[k], st);
            continue;
           }
        }
      // remember why a pair was left out once the window closes
      if(dayOk && g_doneDay[k] != nyDay && t.hour == InpEntryHour && t.min >= InpEntryWindow && g_st[k] == 0)
        {
         double cost = CostPips(s, spr);
         g_why[k] = cost > InpSafety * g_be[k] ? StringFormat("skipped: cost %.1f pips, too high for a %.1f pip move", cost, g_be[k]) : StringFormat("skipped: spread %.1f pips never settled", CostPips(s, spr));
         g_st[k] = 9; g_doneDay[k] = nyDay;
        }
      if(g_st[k] == 1)
        {
         double fl = RofExit(k, bid);
         st = StringFormat("OPEN  %s pips  %s", Pips((bid - g_ent[k]) / PipSize(s)), Rs(fl));
        }
      if(g_st[k] == 2 || g_st[k] == 3) st = StringFormat("%s  %s pips  %s", g_st[k] == 3 ? "STOPPED" : "CLOSED", Pips((g_exit[k] - g_ent[k]) / PipSize(s)), Rs(RofExit(k, g_exit[k])));
      lines += StringFormat("%-9s cost %4.1f pips / avg move %4.1f  %s\n", s, CostPips(s, spr), g_be[k], st);
     }
   // ---- the signal message: once every pair is decided (or the window has closed)
   if(dayOk && anyToday && g_tgSig != nyDay && (allFinal || (t.hour == InpEntryHour && t.min >= InpEntryWindow)) && t.hour == InpEntryHour)
     {
      g_tgSig = nyDay;
      string buy = "", skip = ""; int nb = 0;
      for(int k = 0; k < ArraySize(g_sym); k++)
        {
         int dg = (int)SymbolInfoInteger(g_sym[k], SYMBOL_DIGITS);
         if(g_st[k] == 1)
           { nb++; buy += U(0x1F7E2) + " <b>" + g_name[k] + "</b>  entry <code>" + DoubleToString(g_ent[k], dg) + "</code>  stop <code>" + DoubleToString(g_sl[k], dg) + "</code> (" +
                         DoubleToString((g_ent[k] - g_sl[k]) / PipSize(g_sym[k]), 0) + " pips)\n"; }
         else if(g_why[k] != "") skip += U(0x26D4) + " " + g_name[k] + ": " + g_why[k] + "\n";
        }
      if(nb > 0 || skip != "")
         TgSend(U(0x1F550) + " <b>T2R CLOCK · " + TimeToString(nyDay, TIME_DATE) + "</b>\nBUY now, close at " + Lagos(gmt - (t.min * 60) + 3600) + " Lagos (" +
                IntegerToString(InpExitHour) + ":00 New York). No take profit: the exit is the clock.\n\n" + buy + (skip != "" ? "\n" + skip : "") +
                "\nRisk " + DoubleToString(InpRiskPct, 2) + "% per pair. Missed 23:00-23:20? Skip tonight, never chase.\n<i>Forward test: not yet proven on real fills.</i>");
     }
   // ---- the result message: after the exit hour, once nothing is open
   bool anyOpen = false, anyDone = false;
   for(int k = 0; k < ArraySize(g_sym); k++) { if(g_st[k] == 1) anyOpen = true; if((g_st[k] == 2 || g_st[k] == 3) && g_doneDay[k] == nyDay) anyDone = true; }
   if(anyDone && !anyOpen && g_tgRes != nyDay && t.hour >= InpExitHour)
     {
      g_tgRes = nyDay;
      string L = ""; double sp = 0, sr = 0; int w = 0, nn = 0;
      for(int k = 0; k < ArraySize(g_sym); k++)
        {
         if(!((g_st[k] == 2 || g_st[k] == 3) && g_doneDay[k] == nyDay)) continue;
         double pp = (g_exit[k] - g_ent[k]) / PipSize(g_sym[k]), rr = RofExit(k, g_exit[k]);
         sp += pp; sr += rr; nn++; if(pp > 0) w++;
         L += (pp > 0 ? U(0x2705) : U(0x274C)) + " " + g_name[k] + "  " + Pips(pp) + " pips  " + Rs(rr) + (g_st[k] == 3 ? "  (stop)" : "") + "\n";
        }
      TgSend(U(0x1F4CA) + " <b>T2R CLOCK · RESULT " + TimeToString(nyDay, TIME_DATE) + "</b>\n\n" + L + "\n<b>Night: " + Pips(sp) + " pips · " + Rs(sr) + " · " +
             IntegerToString(w) + "/" + IntegerToString(nn) + " won</b>\nAt " + DoubleToString(InpRiskPct, 2) + "% per pair that is " +
             (sr * InpRiskPct >= 0 ? "+" : "") + DoubleToString(sr * InpRiskPct, 2) + "% on the account (before commission).");
     }
   // floating results to the website every 5 minutes
   static datetime lastUpd = 0;
   if(gmt - lastUpd >= 300)
     {
      lastUpd = gmt;
      for(int k = 0; k < ArraySize(g_sym); k++)
         if(g_st[k] == 1) Desk(k, "update", 0, gmt, false, RofExit(k, SymbolInfoDouble(g_sym[k], SYMBOL_BID)));
     }
   DeskFlush();
   Comment("T2R CLOCK v1.31  ·  after-rollover bounce", (InpSummerOnly && NYOffset(gmt) != -4 ? "  ·  WINTER: RESTING UNTIL MARCH" : ""), "\n",
           "New York ", TimeToString(ny, TIME_MINUTES), "  ·  Lagos ", Lagos(gmt), "  ·  buy ", InpEntryHour, ":00 NY, close ", InpExitHour, ":00 NY (Mon-Thu)\n",
           "Risk ", DoubleToString(InpRiskPct, 2), "% a trade  ·  daily guard ", DoubleToString(InpDailyStop, 1), "%", (g_halt ? "  ·  PAUSED TODAY" : ""),
           (InpTrade ? "" : "  ·  SIGNALS ONLY"), (InpTgToken != "" && InpTgChat != "" ? "  ·  Telegram ON" : ""), (InpWebUrl != "" ? "  ·  website ON" : ""), "\n\n", lines,
           "\nJournal: MQL5\\Files\\T2R_Clock_journal.csv", (g_fileOk ? "" : " (cannot write!)"));
  }
//+------------------------------------------------------------------+
