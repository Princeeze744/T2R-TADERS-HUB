//+------------------------------------------------------------------+
//| T2R_MarketExport.mq5                                             |
//| Trade2Retire Academy - T2R Markets Lab                           |
//| Saves the candles of forex, metals, indices, crypto, stocks and  |
//| commodities so the new strategies can be tested off the terminal.|
//| Output: MQL5\Files\T2R_Markets\<group>\<market>.csv + _index.csv |
//| A script: drag it onto any chart, it runs once and stops.        |
//+------------------------------------------------------------------+
#property copyright   "Trade2Retire Academy"
#property version     "1.01"
#property description "T2R Markets Lab: export candles for the forex-family strategy tests"
#property script_show_inputs

input datetime        InpFrom     = D'2024.07.01 00:00';  // Save candles from this date
input ENUM_TIMEFRAMES InpTF       = PERIOD_M15;           // Candle size (keep 15 minutes)
input bool            InpForex    = true;                 // Forex pairs
input bool            InpMetals   = true;                 // Metals (gold, silver ...)
input bool            InpIndices  = true;                 // Stock indices
input bool            InpCommod   = true;                 // Oil, gas and other commodities
input bool            InpCrypto   = true;                 // Crypto
input bool            InpStocks   = false;                // Single shares (many files - leave off first)
input string          InpOnly     = "";                   // ONLY markets whose name contains any of these, comma separated (overrides the ticks above)

string CleanName(const string s)
  {
   string o=s;
   string bad[]={" ","/","\\",":","(",")","*","?","\"","<",">","|","."};
   for(int i=0;i<ArraySize(bad);i++)
      StringReplace(o,bad[i],"_");
   return o;
  }

//--- which shelf a market belongs to, from the broker's own folder path
string GroupOf(const string sym)
  {
   string p=SymbolInfoString(sym,SYMBOL_PATH);
   string up=p+"\\"+sym;
   StringToUpper(up);
   if(StringFind(up,"DERIVED")>=0 || StringFind(up,"SYNTHETIC")>=0 || StringFind(up,"VOLATILITY")>=0 ||
      StringFind(up,"BOOM")>=0 || StringFind(up,"CRASH")>=0 || StringFind(up,"STEP")>=0 || StringFind(up,"JUMP")>=0 || StringFind(up,"BASKET")>=0)
      return "";
   if(StringFind(up,"CRYPTO")>=0)
      return "crypto";
   if(StringFind(up,"METAL")>=0 || StringFind(up,"XAU")>=0 || StringFind(up,"XAG")>=0 || StringFind(up,"XPT")>=0 || StringFind(up,"XPD")>=0)
      return "metals";
   if(StringFind(up,"FOREX")>=0 || StringFind(up,"CURRENC")>=0)
      return "forex";
   if(StringFind(up,"INDIC")>=0 || StringFind(up,"INDEX")>=0)
      return "indices";
   if(StringFind(up,"STOCK")>=0 || StringFind(up,"SHARE")>=0 || StringFind(up,"ETF")>=0)
      return "stocks";
   if(StringFind(up,"COMMOD")>=0 || StringFind(up,"ENERG")>=0 || StringFind(up,"OIL")>=0 || StringFind(up,"GAS")>=0)
      return "commod";
   //--- no folder hint: a plain six-letter currency pair
   if(StringLen(sym)==6 && SymbolInfoInteger(sym,SYMBOL_TRADE_CALC_MODE)==SYMBOL_CALC_MODE_FOREX)
      return "forex";
   return "";
  }

bool OnlyMatch(const string sym)
  {
   string toks[];
   int n=StringSplit(InpOnly,',',toks);
   string up=sym;
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

bool Wanted(const string g)
  {
   if(g=="forex")   return InpForex;
   if(g=="metals")  return InpMetals;
   if(g=="indices") return InpIndices;
   if(g=="commod")  return InpCommod;
   if(g=="crypto")  return InpCrypto;
   if(g=="stocks")  return InpStocks;
   return false;
  }

void OnStart()
  {
   int total=SymbolsTotal(false);
   datetime toT=TimeCurrent();
   int ok=0,bad=0;
   long rows=0;
   string badList="";

   FolderCreate("T2R_Markets");
   string gs[]={"forex","metals","indices","commod","crypto","stocks","spikes"};
   for(int q=0;q<ArraySize(gs);q++)
      FolderCreate("T2R_Markets\\"+gs[q]);
   int hi=FileOpen("T2R_Markets\\_index.csv",FILE_WRITE|FILE_ANSI|FILE_TXT);
   if(hi==INVALID_HANDLE)
     {
      Alert("T2R market export: cannot write to MQL5\\Files\\T2R_Markets (error ",GetLastError(),")");
      return;
     }
   FileWriteString(hi,"symbol,group,file,digits,point,contract,bars,first,last,path,description\n");

   for(int i=0;i<total && !IsStopped();i++)
     {
      string s=SymbolName(i,false);
      if(s=="")
         continue;
      string g="";
      if(InpOnly!="")
        {
         if(!OnlyMatch(s))
            continue;
         g="spikes";
        }
      else
        {
         g=GroupOf(s);
         if(g=="" || !Wanted(g))
            continue;
        }
      SymbolSelect(s,true);
      Comment("T2R market export: ",i+1," of ",total,"   ",g,"  ",s,"   saved ",ok);

      MqlRates r[];
      ArraySetAsSeries(r,false);
      int n=-1,last=-2;
      //--- ask several times: MT5 downloads history in the background
      for(int k=0;k<30 && !IsStopped();k++)
        {
         n=CopyRates(s,InpTF,InpFrom,toT,r);
         if(n>0 && n==last)
            break;
         last=n;
         Sleep(400);
        }
      if(n<200)
        {
         bad++;
         badList+=s+", ";
         continue;
        }
      int dg=(int)SymbolInfoInteger(s,SYMBOL_DIGITS);
      string fn=g+"\\"+CleanName(s)+".csv";
      int h=FileOpen("T2R_Markets\\"+fn,FILE_WRITE|FILE_ANSI|FILE_TXT);
      if(h==INVALID_HANDLE)
        {
         bad++;
         badList+=s+", ";
         continue;
        }
      FileWriteString(h,"time,open,high,low,close,spread\n");
      string buf="";
      for(int j=0;j<n;j++)
        {
         buf+=IntegerToString((long)r[j].time)+","+DoubleToString(r[j].open,dg)+","+DoubleToString(r[j].high,dg)+","+
              DoubleToString(r[j].low,dg)+","+DoubleToString(r[j].close,dg)+","+IntegerToString(r[j].spread)+"\n";
         if(StringLen(buf)>60000)
           {
            FileWriteString(h,buf);
            buf="";
           }
        }
      if(buf!="")
         FileWriteString(h,buf);
      FileClose(h);
      string desc=SymbolInfoString(s,SYMBOL_DESCRIPTION);
      StringReplace(desc,",",";");
      string path=SymbolInfoString(s,SYMBOL_PATH);
      StringReplace(path,",",";");
      FileWriteString(hi,s+","+g+","+fn+","+IntegerToString(dg)+","+DoubleToString(SymbolInfoDouble(s,SYMBOL_POINT),10)+","+
                      DoubleToString(SymbolInfoDouble(s,SYMBOL_TRADE_CONTRACT_SIZE),2)+","+IntegerToString(n)+","+
                      IntegerToString((long)r[0].time)+","+IntegerToString((long)r[n-1].time)+","+path+","+desc+"\n");
      ok++;
      rows+=n;
     }
   FileClose(hi);
   Comment("");
   string msg="T2R market export finished: "+IntegerToString(ok)+" markets, "+IntegerToString((int)rows)+" candles saved, "+IntegerToString(bad)+" skipped.";
   if(bad>0)
      msg+=" Skipped: "+StringSubstr(badList,0,400);
   Print(msg);
   Alert(msg);
  }
//+------------------------------------------------------------------+
