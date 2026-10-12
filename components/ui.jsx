'use client';
import { useEffect, useRef, useState, useId } from 'react';
import { motion, useInView, animate, AnimatePresence } from 'framer-motion';
import { IcChevron, IcCheck } from './Icons';

export const ease = [0.2, 0.8, 0.2, 1];

export function Reveal({ children, delay = 0, y = 18, className, as = 'div' }) {
  const M = motion[as] || motion.div;
  return (
    <M className={className} initial={{ opacity: 0, y }} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true, margin: '-60px' }} transition={{ duration: 0.7, delay, ease }}>
      {children}
    </M>
  );
}

export function Counter({ value, format = (v) => Math.round(v).toLocaleString('en-US'), duration = 1.4 }) {
  const ref = useRef(null);
  const inView = useInView(ref, { once: true });
  const [v, setV] = useState(0);
  useEffect(() => {
    if (!inView) return;
    const c = animate(0, value, { duration, ease, onUpdate: setV });
    return () => c.stop();
  }, [inView, value, duration]);
  return <span ref={ref}>{format(v)}</span>;
}

export function Ring({ value, size = 38, color = 'var(--win)' }) {
  const r = (size - 6) / 2, c = 2 * Math.PI * r;
  return (
    <svg className="ring" width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden="true">
      <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="rgba(255,255,255,.08)" strokeWidth="4" />
      <motion.circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke={color} strokeWidth="4" strokeLinecap="round"
        transform={`rotate(-90 ${size / 2} ${size / 2})`} strokeDasharray={c}
        initial={{ strokeDashoffset: c }} animate={{ strokeDashoffset: c * (1 - Math.max(0, Math.min(1, value))) }} transition={{ duration: 1.1, ease }} />
    </svg>
  );
}

// close a popover when clicking outside or pressing Escape
export function useDismiss(open, setOpen) {
  const ref = useRef(null);
  useEffect(() => {
    if (!open) return;
    const onDown = (e) => { if (ref.current && !ref.current.contains(e.target)) setOpen(false); };
    const onKey = (e) => { if (e.key === 'Escape') setOpen(false); };
    document.addEventListener('mousedown', onDown);
    document.addEventListener('touchstart', onDown);
    document.addEventListener('keydown', onKey);
    return () => { document.removeEventListener('mousedown', onDown); document.removeEventListener('touchstart', onDown); document.removeEventListener('keydown', onKey); };
  }, [open, setOpen]);
  return ref;
}

export const popAnim = { initial: { opacity: 0, y: -6, scale: 0.98 }, animate: { opacity: 1, y: 0, scale: 1 }, exit: { opacity: 0, y: -6, scale: 0.98 }, transition: { duration: 0.18, ease } };

// Searchable dropdown. options: [{value,label,group?,hint?}]
export function Select({ label, value, onChange, options, allLabel = 'All', searchable, right }) {
  const [open, setOpen] = useState(false);
  const [q, setQ] = useState('');
  const [act, setAct] = useState(0);
  const ref = useDismiss(open, setOpen);
  const cur = options.find((o) => o.value === value);
  const list = [{ value: '', label: allLabel }, ...options].filter((o) => !q || o.label.toLowerCase().includes(q.toLowerCase()));
  useEffect(() => { if (!open) { setQ(''); setAct(0); } }, [open]);
  const pick = (v) => { onChange(v); setOpen(false); };
  const onKey = (e) => {
    if (e.key === 'ArrowDown') { e.preventDefault(); setAct((a) => Math.min(list.length - 1, a + 1)); }
    if (e.key === 'ArrowUp') { e.preventDefault(); setAct((a) => Math.max(0, a - 1)); }
    if (e.key === 'Enter' && list[act]) { e.preventDefault(); pick(list[act].value); }
  };
  let lastGroup = null;
  return (
    <div className="field" ref={ref}>
      <button type="button" className={'field-btn' + (value ? ' set' : '')} onClick={() => setOpen((o) => !o)} aria-haspopup="listbox" aria-expanded={open}>
        <span className="k">{label}</span><span className="v">{cur ? cur.label : allLabel}</span><IcChevron s={15} />
      </button>
      <AnimatePresence>
        {open && (
          <motion.div className={'pop' + (right ? ' right' : '')} {...popAnim} role="listbox">
            {searchable && <input className="q" autoFocus placeholder={'Search ' + label.toLowerCase()} value={q} onChange={(e) => { setQ(e.target.value); setAct(0); }} onKeyDown={onKey} />}
            <div className="list" onKeyDown={onKey}>
              {list.map((o, i) => {
                const g = o.group && o.group !== lastGroup ? o.group : null;
                lastGroup = o.group || lastGroup;
                return (
                  <div key={o.value + '_' + i}>
                    {g && <div className="opt-group">{g}</div>}
                    <button type="button" className={'opt' + (o.value === value ? ' sel' : '') + (i === act ? ' act' : '')} onMouseEnter={() => setAct(i)} onClick={() => pick(o.value)}>
                      <span>{o.label}</span>{o.hint ? <small>{o.hint}</small> : o.value === value ? <IcCheck s={15} /> : null}
                    </button>
                  </div>
                );
              })}
              {!list.length && <div className="opt dim">Nothing matches</div>}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

export function Seg({ value, onChange, options, id }) {
  const uid = useId();
  return (
    <div className="seg" role="tablist">
      {options.map((o) => {
        const v = typeof o === 'string' ? o : o.value, l = typeof o === 'string' ? o : o.label;
        const on = v === value;
        return (
          <button key={v} type="button" role="tab" aria-selected={on} className={on ? 'on' : ''} onClick={() => onChange(v)}>
            {on && <motion.span layoutId={'seg' + (id || uid)} className="pill" transition={{ type: 'spring', bounce: 0.18, duration: 0.45 }} />}
            {l}
          </button>
        );
      })}
    </div>
  );
}

export function Toggle({ checked, onChange, children }) {
  return (
    <button type="button" role="switch" aria-checked={checked} className="toggle" onClick={() => onChange(!checked)}>
      <span className="sw" />{children}
    </button>
  );
}
