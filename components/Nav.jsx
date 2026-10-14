'use client';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { motion } from 'framer-motion';
import { useData } from './DataProvider';
import { IcHome, IcJournal, IcExplore, IcStrat, IcStar, IcBook, IcSearch, IcRadio, IcFlask } from './Icons';

export const PAGES = [
  { href: '/', label: 'Overview', Ic: IcHome },
  { href: '/desk', label: 'Signal Desk', short: 'Desk', Ic: IcRadio, live: true },
  { href: '/spikes', label: 'Spike Study', short: 'Spikes', Ic: IcFlask },
  { href: '/journal', label: 'Journal', short: 'Trades', Ic: IcJournal },
  { href: '/watchlist', label: 'Watchlist', short: 'Watch', Ic: IcStar, noTab: true },
  { href: '/strategies', label: 'Strategies', short: 'Strategy', Ic: IcStrat },
  { href: '/explorer', label: 'Backtest', short: 'Backtest', Ic: IcExplore },
  { href: '/method', label: 'Method', short: 'Method', Ic: IcBook, noTab: true },
];

const isOn = (path, href) => (href === '/' ? path === '/' : path.startsWith(href));

export default function Nav() {
  const path = usePathname() || '/';
  const ctx = useData();
  const openSearch = () => window.dispatchEvent(new Event('t2r-search'));
  return (
    <>
      <header className="nav">
        <div className="wrap">
          <Link href="/" className="brand" aria-label="T2R Lab home">
            <span className="mark">T</span>
            <span>T2R Lab<small>Trade2Retire Academy</small></span>
          </Link>
          <nav className="links" aria-label="Main">
            {PAGES.map((p) => (
              <Link key={p.href} href={p.href} className={isOn(path, p.href) ? 'on' : ''}>
                {isOn(path, p.href) && <motion.span layoutId="navpill" className="pill" transition={{ type: 'spring', bounce: 0.2, duration: 0.5 }} />}
                {p.live && <span className="live-dot" style={{ display: 'inline-block', marginRight: 7, verticalAlign: 1 }} />}{p.label}
              </Link>
            ))}
          </nav>
          <div className="navr">
            <button type="button" className="search-btn" onClick={openSearch} aria-label="Search markets and strategies">
              <IcSearch s={16} /><span className="lbl">Search markets</span><span className="kbd">⌘K</span>
            </button>
            {ctx && (
              <label className="risk" title="Dollar amount risked per trade. Every money figure follows it.">
                <span className="lbl">Risk</span>$
                <input type="number" min="1" step="1" value={ctx.risk} onChange={(e) => { const v = parseFloat(e.target.value); if (v > 0) ctx.setRisk(v); }} aria-label="Dollars risked per trade" />
              </label>
            )}
          </div>
        </div>
      </header>
      <nav className="tabbar" aria-label="Main">
        {PAGES.filter((p) => !p.noTab).map((p) => (
          <Link key={p.href} href={p.href} className={isOn(path, p.href) ? 'on' : ''}>
            {isOn(path, p.href) && <motion.span layoutId="tabpill" className="pill" transition={{ type: 'spring', bounce: 0.2, duration: 0.5 }} />}
            <p.Ic s={20} />{p.short || p.label}
          </Link>
        ))}
      </nav>
    </>
  );
}
