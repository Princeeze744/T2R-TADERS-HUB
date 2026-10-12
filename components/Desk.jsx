'use client';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { useData } from './DataProvider';
import TradeDrawer from './TradeDrawer';
import { Reveal, Seg, Toggle, ease } from './ui';
import { IcLeft, IcRight } from './Icons';
import { FAMS } from '@/lib/constants';
import { sb, rowToTrade } from '@/lib/supabase-client';
import { f1, f2, cl, pc, nf, money, fmtPrice, hhmm, dayKey, keyToTs, addDays, dayLabel, ratioOf } from '@/lib/util';

const ST = {
  pending: { l: 'WAITING', c: 'soft' },
  active: { l: 'ACTIVE', c: 'open' },
  won: { l: 'TARGET HIT', c: 'won' },
  lost: { l: 'STOPPED', c: 'lost' },
  cancelled: { l: 'CANCELLED', c: 'soft' },
};

// ---------- preview: a replay day played back fast, used only until the live feed has data ----------
function buildPreview(trades, speed) {
  const days = new Map();
  trades.filter((t) => t.src === 'r').forEach((t) => days.set(t.day, (days.get(t.day) || 0) + 1));
  const day = [...days.entries()].sort((a, b) => b[1] - a[1])[0]?.[0];
  if (!day) return null;
  const list = trades.filter((t) => t.src === 'r' && t.day === day).slice(0, 400);
  return { day, list, t0: keyToTs(day), speed };
}
function previewRows(P, clock) {
  return P.list.filter((t) => t.tin <= clock).map((t) => {
    const done = t.tout && t.tout <= clock;
    const unit = Math.abs(t.e - t.sl);
    return {
      id: 'p' + t.id, market: t.a, family: t.fam, strategy: t.s, view: t.v, side: t.sd, stop_class: t.c, dir: t.dir, order_type: 'limit',
      entry: t.e, stop: t.sl, tp1: t.dir === 'buy' ? t.e + unit : t.e - unit, target: t.tp, rr: t.rr,
      status: done ? (t.res === 'won' ? 'won' : 'lost') : 'active', hit_tp1: t.res === 'won' && done,
      t_signal: t.tin, t_fill: t.tin, t_close: done ? t.tout : null, r_full: done ? t.R : null, r_t2r: null, exit_price: null,
    };
  });
}

function chime() {
  try {
    const A = new (window.AudioContext || window.webkitAudioContext)();
    [880, 1320].forEach((f, i) => {
      const o = A.createOscillator(), g = A.createGain();
      o.type = 'sine'; o.frequency.value = f; o.connect(g); g.connect(A.destination);
      const t = A.currentTime + i * 0.12;
      g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(0.15, t + 0.02); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.35);
      o.start(t); o.stop(t + 0.4);
    });
  } catch (e) { /* no audio */ }
}

export default function Desk() {
  const { data, risk } = useData();
  const live = !!sb();
  const todayKey = dayKey(Date.now() / 1000);
  const [day, setDay] = useState(todayKey);
  const [rows, setRows] = useState(new Map());
  const [running, setRunning] = useState([]); // pending + active from any day
  const [conn, setConn] = useState(live ? 'connecting' : 'off');
  const [fam, setFam] = useState('All');
  const [q, setQ] = useState('');
  const [ping, setPing] = useState(false);
  const [fresh, setFresh] = useState({});
  const [open, setOpen] = useState(null);
  const pingRef = useRef(ping);
  pingRef.current = ping;

  // preview mode (until live data exists)
  const [preview, setPreview] = useState(false);
  const P = useMemo(() => buildPreview(data.TRADES, 600), [data]);
  const [clock, setClock] = useState(0);

  const markFresh = (id) => { setFresh((f) => ({ ...f, [id]: Date.now() })); };

  // ---------- live: load the chosen day + everything still running, then listen ----------
  const loadDay = useCallback(async () => {
    const c = sb();
    if (!c) return;
    const a = keyToTs(day), b = a + 86400;
    const [d1, d2] = await Promise.all([
      c.from('signals').select('*').gte('t_signal', a).lt('t_signal', b).order('t_signal', { ascending: false }).limit(1000),
      c.from('signals').select('*').in('status', ['pending', 'active']).order('t_signal', { ascending: false }).limit(1000),
    ]);
    if (d1.error || d2.error) { setConn('error'); return; }
    setRows(new Map(d1.data.map((r) => [r.id, r])));
    setRunning(d2.data);
    setConn('live');
  }, [day]);

  useEffect(() => { loadDay(); }, [loadDay]);
  useEffect(() => {
    const c = sb();
    if (!c) return;
    const ch = c.channel('desk')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'signals' }, (msg) => {
        const r = msg.new;
        if (!r || !r.id) return;
        const inDay = r.t_signal >= keyToTs(day) && r.t_signal < keyToTs(day) + 86400;
        if (inDay) setRows((m) => { const n = new Map(m); n.set(r.id, r); return n; });
        setRunning((L) => {
          const rest = L.filter((x) => x.id !== r.id);
          return r.status === 'pending' || r.status === 'active' ? [r, ...rest] : rest;
        });
        markFresh(r.id);
        if (msg.eventType === 'INSERT' && pingRef.current) chime();
      })
      .subscribe((s) => { if (s === 'SUBSCRIBED') setConn('live'); if (s === 'CHANNEL_ERROR' || s === 'TIMED_OUT') setConn('error'); });
    const poll = setInterval(loadDay, 60000); // safety net if the live push drops
    return () => { clearInterval(poll); c.removeChannel(ch); };
  }, [day, loadDay]);

  // ---------- preview clock ----------
  useEffect(() => {
    if (!preview || !P) return;
    setClock(P.t0);
    const id = setInterval(() => setClock((c) => {
      const n = c + P.speed / 4; // ticks 4x a second
      return n > P.t0 + 86400 ? P.t0 : n;
    }), 250);
    return () => clearInterval(id);
  }, [preview, P]);
  const prevIds = useRef(new Set());
  const pRows = useMemo(() => (preview && P ? previewRows(P, clock) : []), [preview, P, clock]);
  useEffect(() => {
    if (!preview) { prevIds.current = new Set(); return; }
    pRows.forEach((r) => { const k = r.id + r.status; if (!prevIds.current.has(k)) { prevIds.current.add(k); markFresh(r.id); } });
  }, [pRows, preview]);

  const all = useMemo(() => {
    if (preview) return pRows;
    const m = new Map(rows);
    if (day === todayKey) running.forEach((r) => { if (!m.has(r.id)) m.set(r.id, r); });
    return [...m.values()];
  }, [preview, pRows, rows, running, day, todayKey]);
  const goTo = (id) => { const el = document.getElementById('sig-' + id); if (el) { el.scrollIntoView({ behavior: 'smooth', block: 'center' }); markFresh(id); } };
  const runAll = preview ? pRows.filter((r) => r.status === 'active') : running;
  const match = (r) => (fam === 'All' || (r.family || data.famOf(r.market)) === fam) && (!q || (r.market + ' ' + r.strategy).toLowerCase().includes(q.toLowerCase()));
  const feed = all.filter(match).sort((a, b) => (b.t_signal || b.t_fill || 0) - (a.t_signal || a.t_fill || 0));
  const act = runAll.filter((r) => r.status === 'active' && match(r));
  const wait = runAll.filter((r) => r.status === 'pending' && match(r));
  const S = useMemo(() => {
    const o = { n: 0, act: 0, wait: 0, w: 0, l: 0, c: 0, R: 0, T: 0, tN: 0 };
    feed.forEach((r) => {
      o.n++;
      if (r.status === 'active') o.act++; else if (r.status === 'pending') o.wait++; else if (r.status === 'won') o.w++; else if (r.status === 'lost') o.l++; else o.c++;
      if (r.r_full != null && (r.status === 'won' || r.status === 'lost')) o.R += r.r_full;
      if (r.r_t2r != null) { o.T += r.r_t2r; o.tN++; }
    });
    return o;
  }, [feed]);

  const toTrade = (r) => rowToTrade(r, data.famOf, dayKey, ratioOf);
  const list = feed.filter((r) => r.status !== 'cancelled' && r.status !== 'pending').map(toTrade);
  const openT = open ? list.find((t) => t.id === open) || null : null;
  const showLive = live && !preview;
  const empty = !preview && (!live || (conn === 'live' && rows.size === 0 && running.length === 0));

  return (
    <div className="wrap">
      <div className="page-head">
        <Reveal>
          <span className="eyebrow" style={{ gap: 10 }}>
            Signal Desk
            {showLive && conn === 'live' && <span className="badge live" style={{ marginLeft: 6 }}><span className="live-dot" />LIVE</span>}
            {preview && <span className="badge gold" style={{ marginLeft: 6 }}>PREVIEW</span>}
          </span>
        </Reveal>
        <Reveal delay={0.05}><h1 className="h-sec">Signals, <em>as they happen.</em></h1></Reveal>
        <Reveal delay={0.1}><p className="lead">Every signal the lab sends appears here the moment it fires, then updates itself: waiting, activated, +1R, target or stop. Nothing is hidden and nothing is deleted. Free for everyone.</p></Reveal>
      </div>

      {preview && P && (
        <div className="callout" style={{ marginBottom: 16 }}>
          <b>Preview.</b> This is {dayLabel(P.day, true)} from the replay, played back 600 times faster ({hhmm(Math.floor(clock))} GMT now). The live desk takes over the moment the VPS starts sending signals.
          <button type="button" className="chip" style={{ marginLeft: 10 }} onClick={() => setPreview(false)}>Stop preview</button>
        </div>
      )}

      {empty && (
        <div className="card pad" style={{ marginBottom: 16, display: 'flex', gap: 16, alignItems: 'center', flexWrap: 'wrap', justifyContent: 'space-between' }}>
          <div>
            <b className="serif" style={{ fontSize: 26, fontWeight: 400 }}>{live ? 'No signals yet today.' : 'The live feed starts when the VPS connects.'}</b>
            <p className="dim" style={{ margin: '4px 0 0' }}>{live ? 'New signals will drop in here by themselves. Keep this page open.' : 'Until then, watch a replayed day play out exactly the way the desk will look live.'}</p>
          </div>
          {P && <button type="button" className="btn primary sm" onClick={() => setPreview(true)}>Watch the preview</button>}
        </div>
      )}

      <div className="sticky-bar">
        <div className="toolbar">
          {!preview && (
            <div className="row" style={{ gap: 6 }}>
              <button type="button" className="iconbtn" onClick={() => setDay(addDays(day, -1))} aria-label="Previous day"><IcLeft s={16} /></button>
              <span className="field-btn set" style={{ minWidth: 150, justifyContent: 'center' }}>{day === todayKey ? 'Today · ' : ''}{dayLabel(day)}</span>
              <button type="button" className="iconbtn" disabled={day >= todayKey} onClick={() => setDay(addDays(day, 1))} aria-label="Next day"><IcRight s={16} /></button>
            </div>
          )}
          <Seg id="dfam" value={fam} onChange={setFam} options={['All', ...FAMS].map((f) => ({ value: f, label: f === 'Boom and Crash' ? 'Boom/Crash' : f }))} />
          <input className="field-btn" style={{ width: 180, outline: 0 }} placeholder="Search a market" value={q} onChange={(e) => setQ(e.target.value)} />
          <Toggle checked={ping} onChange={(v) => { setPing(v); if (v) chime(); }}>Sound on new signal</Toggle>
        </div>
      </div>

      <div className="kpis" style={{ marginTop: 6 }}>
        <Kpi l={day === todayKey || preview ? 'On the desk today' : 'Signals'} v={nf(S.n)} s={`${S.c} cancelled`} />
        <Kpi l="Running now" v={act.length} s="in the trade" c="o" />
        <Kpi l="Waiting for entry" v={wait.length} s="pending orders" />
        <Kpi l="Won · lost" v={`${S.w} · ${S.l}`} s={pc(S.w, S.w + S.l) + ' win rate'} />
        <Kpi l="Result (full target)" v={f1(S.R) + 'R'} c={cl(S.R)} s={money(S.R, risk) + ' at $' + risk} />
        <Kpi l="Result (T2R rule)" v={S.tN ? f1(S.T) + 'R' : '–'} c={cl(S.T)} s="half off at 1:1, stop to entry" />
      </div>

      <div className="desk">
        <section>
          <div className="between" style={{ margin: '24px 0 12px' }}>
            <h2 className="serif" style={{ fontSize: 30 }}>The feed</h2>
            <span className="note">{nf(feed.length)} signals · newest first · times GMT</span>
          </div>
          <div className="feed">
            <AnimatePresence initial={false}>
              {feed.slice(0, 300).map((r) => (
                <SignalCard key={r.id} r={r} today={day === todayKey} fam={r.family || data.famOf(r.market)} fresh={fresh[r.id] && Date.now() - fresh[r.id] < 25000} risk={risk}
                  onOpen={r.status === 'active' || r.status === 'won' || r.status === 'lost' ? () => setOpen('s' + r.id) : null} />
              ))}
            </AnimatePresence>
            {!feed.length && <div className="card empty"><b>Nothing here yet</b>{preview ? 'The first signals of the day are about to drop.' : 'Signals for this day will appear here.'}</div>}
          </div>
        </section>
        <aside className="desk-side">
          <div className="card pad">
            <div className="between"><div className="eyebrow">Running now</div><span className="badge open">{act.length}</span></div>
            <div style={{ marginTop: 10 }}>
              {act.slice(0, 60).map((r) => <Mini key={r.id} r={r} onOpen={() => goTo(r.id)} />)}
              {!act.length && <p className="dim" style={{ fontSize: 13.5, margin: '8px 0 0' }}>No trade running right now.</p>}
            </div>
          </div>
          <div className="card pad" style={{ marginTop: 14 }}>
            <div className="between"><div className="eyebrow">Waiting for entry</div><span className="badge soft">{wait.length}</span></div>
            <div style={{ marginTop: 10 }}>
              {wait.slice(0, 60).map((r) => <Mini key={r.id} r={r} onOpen={() => goTo(r.id)} />)}
              {!wait.length && <p className="dim" style={{ fontSize: 13.5, margin: '8px 0 0' }}>No pending orders.</p>}
            </div>
          </div>
          <p className="note" style={{ marginTop: 12 }}>{showLive ? (conn === 'live' ? 'Connected. Updates arrive by themselves.' : conn === 'error' ? 'Connection dropped. Retrying every minute.' : 'Connecting…') : ''}</p>
        </aside>
      </div>

      <TradeDrawer trade={openT} list={list} onClose={() => setOpen(null)} onNav={(id) => setOpen(id)} />
    </div>
  );
}

function Kpi({ l, v, s, c = '' }) {
  return <div className="card kpi"><div className="l"><span>{l}</span></div><div className={'v ' + c}>{v}</div><div className="s">{s}</div></div>;
}

function orderLabel(r) {
  const d = r.dir === 'buy' ? 'BUY' : 'SELL';
  if (r.order_type === 'market') return d + ' NOW';
  return d + ' LIMIT';
}

function Steps({ r }) {
  const reached = [true, r.status !== 'pending' && r.status !== 'cancelled', !!r.hit_tp1, r.status === 'won' || r.status === 'lost'];
  const end = r.status === 'lost' ? 'Stop' : 'Target';
  const lab = ['Signal', 'Active', '+1R', end];
  return (
    <div className="steps-line">
      {lab.map((x, i) => (
        <span key={x} className={'st' + (reached[i] ? ' on' : '') + (i === 3 && r.status === 'lost' ? ' bad' : '') + (i === 3 && r.status === 'won' ? ' good' : '')}>
          <i />{x}
        </span>
      ))}
    </div>
  );
}

function SignalCard({ r, fam, fresh, onOpen, risk, today }) {
  const s = ST[r.status] || ST.pending;
  const closed = r.status === 'won' || r.status === 'lost';
  const ref = r.entry;
  return (
    <motion.div layout initial={{ opacity: 0, y: -16, scale: 0.98 }} animate={{ opacity: 1, y: 0, scale: 1 }} exit={{ opacity: 0 }} transition={{ duration: 0.45, ease }}
      id={'sig-' + r.id} className={'card sig' + (fresh ? ' fresh' : '') + (onOpen ? ' click' : '') + ' st-' + r.status} onClick={onOpen || undefined} role={onOpen ? 'button' : undefined} tabIndex={onOpen ? 0 : undefined}>
      <div className="sig-top">
        <span className="mono dim" style={{ fontSize: 12.5 }}>{r.t_signal ? (today && dayKey(r.t_signal) !== dayKey(Date.now() / 1000) ? dayLabel(dayKey(r.t_signal)) + ' ' : '') + hhmm(r.t_signal) : 'carried over'}</span>
        <span className="sig-mk">{r.market}<small>{fam}</small></span>
        <span className={'badge ' + (r.dir === 'buy' ? 'buy' : 'sell')}>{orderLabel(r)}</span>
        <span className={'badge ' + s.c} style={{ marginLeft: 'auto' }}>{fresh && !closed ? <><span className="dot" />{s.l}</> : s.l}</span>
      </div>
      <div className="sig-lv">
        <div><span>Entry</span><b style={{ color: 'var(--gold2)' }}>{fmtPrice(r.entry, ref)}</b></div>
        <div><span>Stop</span><b className="r">{fmtPrice(r.stop, ref)}</b></div>
        <div><span>TP1 1:1</span><b className="g" style={{ opacity: 0.8 }}>{fmtPrice(r.tp1, ref)}</b></div>
        <div><span>Target {r.rr}</span><b className="g">{fmtPrice(r.target, ref)}</b></div>
      </div>
      <div className="sig-foot">
        <Steps r={r} />
        <span className="sig-res">
          {closed && <b className={'mono ' + cl(r.r_full)}>{f2(r.r_full)}R <small>{money(r.r_full, risk)}</small></b>}
          {r.status === 'active' && r.r_float != null && <b className={'mono ' + cl(r.r_float)}>{f2(r.r_float)}R <small>floating</small></b>}
          {r.r_t2r != null && closed && <small className="dim"> · T2R rule {f2(r.r_t2r)}R</small>}
        </span>
      </div>
      <div className="note" style={{ marginTop: 8 }}>{r.strategy}{r.view ? ' · ' + r.view : ''}{r.stop_class ? ' · ' + r.stop_class : ''}</div>
    </motion.div>
  );
}

function Mini({ r, onOpen }) {
  return (
    <button type="button" className="opt" style={{ padding: '9px 6px', borderBottom: '1px solid var(--line)', borderRadius: 0 }} onClick={onOpen}>
      <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
        <span className={'badge ' + (r.dir === 'buy' ? 'buy' : 'sell')} style={{ marginRight: 8 }}>{r.dir.toUpperCase()}</span>{r.market}
      </span>
      <small className="mono">{r.r_float != null ? f2(r.r_float) + 'R' : fmtPrice(r.entry, r.entry)}</small>
    </button>
  );
}
