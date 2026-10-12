'use client';
import { motion } from 'framer-motion';
import { PAT } from '@/lib/constants';

// step: 1 zone forms, 2 entry, 3 stop, 4 targets + what happened. step 4 (default) shows everything.
export default function Diagram({ s, step = 4 }) {
  const P = PAT[s];
  if (!P) return null;
  const C = P.c, W = 560, H = 300, pl = 10, pr = 118, pt = 14, pb = 14;
  let lo = 1e9, hi = -1e9;
  C.forEach((k) => { lo = Math.min(lo, k[2]); hi = Math.max(hi, k[1]); });
  (P.lines || []).forEach((l) => { lo = Math.min(lo, l.y); hi = Math.max(hi, l.y); });
  (P.boxes || []).forEach((b) => { lo = Math.min(lo, b.lo); hi = Math.max(hi, b.hi); });
  const pad = (hi - lo) * 0.06; lo -= pad; hi += pad;
  const n = C.length, cw = (W - pl - pr) / n;
  const X = (i) => pl + cw * (i + 0.5);
  const Y = (v) => pt + (H - pt - pb) * (1 - (v - lo) / (hi - lo));
  const ex = P.lines[0].x; // the candle where the entry happens
  const lastC = step >= 4 ? n - 1 : step >= 2 ? ex : ex - 1;
  const lineStep = { e: 2, s: 3, t: 4 };
  const fade = { initial: { opacity: 0 }, animate: { opacity: 1 }, transition: { duration: 0.45 } };
  const path = (arr) => arr.map((v, i) => (i ? 'L' : 'M') + X(i).toFixed(1) + ' ' + Y(v).toFixed(1)).slice(0, lastC + 1).join(' ');
  return (
    <svg className="dg" viewBox={`0 0 ${W} ${H}`} role="img" aria-label={s + ' example'}>
      {(P.boxes || []).map((b, i) => (
        <rect key={'b' + i} x={X(b.x0) - cw / 2} y={Y(b.hi)} width={X(Math.min(b.x1, Math.max(lastC, b.x0))) - X(b.x0) + cw} height={Y(b.lo) - Y(b.hi)} className={'bx ' + (b.k || '')} />
      ))}
      {P.ma && <path d={path(P.ma)} className="ma" />}
      {P.band && <path d={path(P.band)} className="band" />}
      {C.map((k, i) => {
        if (i > lastC) return null;
        const up = k[3] >= k[0];
        return (
          <motion.g key={'c' + i} initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.3, delay: step === 4 && i > ex ? (i - ex) * 0.06 : 0 }}>
            <line x1={X(i)} x2={X(i)} y1={Y(k[1])} y2={Y(k[2])} className={'wk ' + (up ? 'u' : 'd')} />
            <rect x={X(i) - cw * 0.32} y={Y(Math.max(k[0], k[3]))} width={cw * 0.64} height={Math.max(1.5, Math.abs(Y(k[0]) - Y(k[3])))} className={'cd ' + (up ? 'u' : 'd')} rx="1" />
          </motion.g>
        );
      })}
      {(P.boxes || []).map((b, i) => b.t ? <text key={'bt' + i} x={X(b.x1) + cw / 2 - 6} y={Y(b.hi) + 13} className="bt" textAnchor="end">{b.t}</text> : null)}
      {(P.lines || []).map((l, i) => lineStep[l.k] <= step ? (
        <motion.g key={'l' + i} {...fade}>
          <line x1={X(l.x) - cw / 2} x2={W - pr + 4} y1={Y(l.y)} y2={Y(l.y)} className={'ln ' + l.k} />
          <text x={W - pr + 8} y={Y(l.y) + 4} className={'lt ' + l.k}>{l.t}</text>
        </motion.g>
      ) : null)}
      {(P.marks || []).map((m, i) => ((m.x >= ex ? 2 : 1) <= step ? (
        <motion.g key={'m' + i} {...fade}>
          <circle cx={X(m.x)} cy={Y(m.y)} r="3.5" className="mk" />
          <text x={X(m.x) + (m.left ? -8 : 8)} y={Y(m.y) + (m.dy || -8)} className="mt" textAnchor={m.left ? 'end' : 'start'}>{m.t}</text>
        </motion.g>
      ) : null))}
    </svg>
  );
}
