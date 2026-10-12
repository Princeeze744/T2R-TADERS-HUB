import '@fontsource/instrument-serif/400.css';
import '@fontsource/instrument-serif/400-italic.css';
import { GeistSans } from 'geist/font/sans';
import { GeistMono } from 'geist/font/mono';
import './globals.css';
import DataProvider from '@/components/DataProvider';
import Nav from '@/components/Nav';
import CommandPalette from '@/components/CommandPalette';

export const metadata = {
  title: 'T2R Lab · Trade2Retire Academy',
  description: 'Nine zone strategies tested on 150 markets, every trade counted, then followed live. Trade2Retire Academy research.',
};
export const viewport = { themeColor: '#06080c', width: 'device-width', initialScale: 1 };

export default function RootLayout({ children }) {
  return (
    <html lang="en" className={`${GeistSans.variable} ${GeistMono.variable}`}>
      <body>
        <DataProvider>
          <div className="app">
            <Nav />
            <CommandPalette />
            <main>{children}</main>
            <footer className="foot">
              <div className="wrap">
                <span>T2R Lab · Trade2Retire Academy research · all times are MT5 server time (GMT)</span>
                <span>Historical tests and demo results, not a promise of future returns and not financial advice.</span>
              </div>
            </footer>
          </div>
        </DataProvider>
      </body>
    </html>
  );
}
