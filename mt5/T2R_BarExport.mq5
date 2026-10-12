//+------------------------------------------------------------------+
//| T2R_BarExport.mq5                                                |
//| Trade2Retire Academy - T2R Lab                                   |
//| Saves the candles of every market in Market Watch so the website |
//| can draw each trade on the SAME price feed the EA tested on.     |
//| Output: MQL5\Files\T2R_Lab\bars\<market>.csv + _index.csv        |
//+------------------------------------------------------------------+
#property copyright   "Trade2Retire Academy"
#property version     "1.00"
#property description "T2R Lab: export candles for the website trade charts"
#property script_show_inputs

input int             InpDays            = 45;          // Days of candles to save (45 covers a 6-week replay)
input ENUM_TIMEFRAMES InpTF              = PERIOD_M15;  // Candle size (keep 15 minutes, same as the lab)
input bool            InpOnlyMarketWatch = true;        // Only markets shown in Market Watch

//--- make a market name safe for a file name
string CleanName(const string s)
  {
   string o=s;
   StringReplace(o," ","_");
   StringReplace(o,"/","_");
   StringReplace(o,"\\","_");
   StringReplace(o,":","_");
   StringReplace(o,"(","");
   StringReplace(o,")","");
   StringReplace(o,"*","");
   StringReplace(o,"?","");
   StringReplace(o,"\"","");
   StringReplace(o,"<","");
   StringReplace(o,">","");
   StringReplace(o,"|","");
   return o;
  }

void OnStart()
  {
   int total=SymbolsTotal(InpOnlyMarketWatch);
   datetime toT=TimeCurrent();
   datetime fromT=toT-(datetime)(InpDays*86400);
   int ok=0,bad=0;
   string badList="";

   int hi=FileOpen("T2R_Lab\\bars\\_index.csv",FILE_WRITE|FILE_ANSI|FILE_TXT);
   if(hi==INVALID_HANDLE)
     {
      Alert("T2R bar export: cannot write to MQL5\\Files\\T2R_Lab\\bars (error ",GetLastError(),")");
      return;
     }
   FileWriteString(hi,"symbol;file;digits;bars;first;last\n");

   for(int i=0;i<total && !IsStopped();i++)
     {
      string s=SymbolName(i,InpOnlyMarketWatch);
      if(s=="")
         continue;
      SymbolSelect(s,true);
      Comment("T2R bar export: ",i+1," of ",total,"  ",s);

      MqlRates r[];
      ArraySetAsSeries(r,false);
      int n=-1,last=-2;
      //--- ask several times: MT5 downloads history in the background
      for(int k=0;k<20 && !IsStopped();k++)
        {
         n=CopyRates(s,InpTF,fromT,toT,r);
         if(n>0 && n==last)
            break;
         last=n;
         Sleep(300);
        }
      if(n<=0)
        {
         bad++;
         badList+=s+", ";
         continue;
        }

      int dg=(int)SymbolInfoInteger(s,SYMBOL_DIGITS);
      string fn=CleanName(s)+".csv";
      int h=FileOpen("T2R_Lab\\bars\\"+fn,FILE_WRITE|FILE_ANSI|FILE_TXT);
      if(h==INVALID_HANDLE)
        {
         bad++;
         badList+=s+", ";
         continue;
        }
      FileWriteString(h,"time;open;high;low;close\n");
      for(int j=0;j<n;j++)
        {
         FileWriteString(h,IntegerToString((long)r[j].time)+";"+
                         DoubleToString(r[j].open,dg)+";"+
                         DoubleToString(r[j].high,dg)+";"+
                         DoubleToString(r[j].low,dg)+";"+
                         DoubleToString(r[j].close,dg)+"\n");
        }
      FileClose(h);
      FileWriteString(hi,s+";"+fn+";"+IntegerToString(dg)+";"+IntegerToString(n)+";"+
                      IntegerToString((long)r[0].time)+";"+IntegerToString((long)r[n-1].time)+"\n");
      ok++;
     }
   FileClose(hi);
   Comment("");

   string msg="T2R bar export finished: "+IntegerToString(ok)+" markets saved, "+IntegerToString(bad)+" skipped.";
   if(bad>0)
      msg+=" Skipped: "+badList;
   Print(msg);
   Alert(msg);
  }
//+------------------------------------------------------------------+
