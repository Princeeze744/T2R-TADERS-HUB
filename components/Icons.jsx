const P = { fill: 'none', stroke: 'currentColor', strokeWidth: 1.7, strokeLinecap: 'round', strokeLinejoin: 'round' };
const I = ({ d, s = 18, children }) => (
  <svg width={s} height={s} viewBox="0 0 24 24" aria-hidden="true" {...P}>{d ? <path d={d} /> : children}</svg>
);
export const IcHome = (p) => <I {...p} d="M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6h-6v6H4a1 1 0 0 1-1-1z" />;
export const IcJournal = (p) => <I {...p}><rect x="3" y="4" width="18" height="17" rx="3" /><path d="M3 9h18M8 2v4M16 2v4M7 13h4M7 17h7" /></I>;
export const IcExplore = (p) => <I {...p}><path d="M4 20V10M10 20V4M16 20v-7M22 20H2" /></I>;
export const IcStrat = (p) => <I {...p}><path d="M4 6h10M4 12h16M4 18h7" /><circle cx="18" cy="6" r="2" /><circle cx="15" cy="18" r="2" /></I>;
export const IcStar = (p) => <I {...p} d="m12 3 2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1L3.2 9.5l6.1-.9z" />;
export const IcBook = (p) => <I {...p}><path d="M4 5a2 2 0 0 1 2-2h13v16H6a2 2 0 0 0-2 2z" /><path d="M4 21V5M8 7h7" /></I>;
export const IcSearch = (p) => <I {...p}><circle cx="11" cy="11" r="7" /><path d="m20 20-3.5-3.5" /></I>;
export const IcChevron = (p) => <I {...p} d="m6 9 6 6 6-6" />;
export const IcLeft = (p) => <I {...p} d="m15 6-6 6 6 6" />;
export const IcRight = (p) => <I {...p} d="m9 6 6 6-6 6" />;
export const IcX = (p) => <I {...p} d="M6 6l12 12M18 6 6 18" />;
export const IcCal = (p) => <I {...p}><rect x="3" y="5" width="18" height="16" rx="3" /><path d="M3 10h18M8 3v4M16 3v4" /></I>;
export const IcArrow = (p) => <I {...p} d="M5 12h14m-6-6 6 6-6 6" />;
export const IcCopy = (p) => <I {...p}><rect x="9" y="9" width="12" height="12" rx="2.5" /><path d="M5 15V5a2 2 0 0 1 2-2h8" /></I>;
export const IcCheck = (p) => <I {...p} d="m5 12.5 4.5 4.5L19 7.5" />;
export const IcPlay = (p) => <I {...p} d="M7 4.5v15l12-7.5z" />;
export const IcLink = (p) => <I {...p}><path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1" /><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1" /></I>;
export const IcFlask = (p) => <I {...p}><path d="M9 3h6M10 3v6L4.5 18.5A2 2 0 0 0 6.2 21h11.6a2 2 0 0 0 1.7-2.5L14 9V3" /><path d="M7 15h10" /></I>;
export const IcShield = (p) => <I {...p} d="M12 3 4 6v6c0 4.5 3.4 8.3 8 9 4.6-.7 8-4.5 8-9V6z" />;
export const IcRadio = (p) => <I {...p}><circle cx="12" cy="12" r="2" /><path d="M16.2 7.8a6 6 0 0 1 0 8.4M7.8 16.2a6 6 0 0 1 0-8.4M19 5a10 10 0 0 1 0 14M5 19A10 10 0 0 1 5 5" /></I>;
export const IcSend = (p) => <I {...p} d="M21 3 10 14M21 3l-7 18-4-7-7-4z" />;
