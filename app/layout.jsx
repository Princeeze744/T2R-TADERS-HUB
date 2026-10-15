import '@fontsource/instrument-serif/400.css';
import '@fontsource/instrument-serif/400-italic.css';
import { GeistSans } from 'geist/font/sans';
import { GeistMono } from 'geist/font/mono';
import './globals.css';
import DataProvider from '@/components/DataProvider';
import Nav from '@/components/Nav';
import CommandPalette from '@/components/CommandPalette';

const SITE = 'https://t2r-traders-hub.vercel.app';
const DESC = 'Every signal, every trade, every result. Nine tested strategies on Deriv synthetics, led by Boom & Crash, with a full public record. By Trade2Retire Academy.';
export const metadata = {
  metadataBase: new URL(SITE),
  title: 'T2R Lab · Trade2Retire Academy',
  description: DESC,
  applicationName: 'T2R Lab',
  openGraph: {
    type: 'website', url: SITE, siteName: 'T2R Lab · Trade2Retire Academy',
    title: 'T2R Lab · Every signal, every trade, every result',
    description: DESC,
    images: [{ url: '/og.jpg', width: 1200, height: 630, alt: 'T2R Lab by Trade2Retire Academy' }],
  },
  twitter: { card: 'summary_large_image', title: 'T2R Lab · Every signal, every trade, every result', description: DESC, images: ['/og.jpg'] },
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
