# T2R Traders Hub · T2R Lab website

Next.js 14 site for Trade2Retire Academy's T2R Lab: backtest results, the 300-setup watchlist,
the nine strategies explained, and a trade journal where every trade can be opened on a candle chart.

## Run it
    npm install
    npm run dev        # http://localhost:3000
    npm run build      # production build (Vercel runs this)

## Refresh the data (after MT5 has produced new files)
1. In MT5, run the EA as usual. It writes to `MQL5\Files\T2R_Lab`.
2. In MT5, drag the script `T2R_BarExport` (from `mt5/`) onto any chart. It saves 15-minute candles for every market.
3. `npm run sync`   (finds the MT5 folder by itself; or `npm run sync -- "C:\...\MQL5\Files\T2R_Lab"`)
4. `git add . ; git commit -m "data update" ; git push`  → Vercel publishes in about a minute.

## Where things are
- `app/` pages · `components/` UI · `lib/` constants and maths
- `public/data/lab.json` backtest scan (changes only when the scan is rerun)
- `public/data/trades.json` replay and live demo trades (written by `npm run sync`)
- `public/data/bars/` candles per market (written by `npm run sync`)
- `mt5/T2R_BarExport.mq5` candle export script for MT5
- `app/api/health` placeholder; the Telegram bot webhook and database link come here next
