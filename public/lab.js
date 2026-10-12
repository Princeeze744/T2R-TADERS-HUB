(function(){fetch('/data/lab.json').then(function(r){return r.json();}).then(function(D){

var SM=[0.2,0.5,1,2],LV=[0.5,1,2,3],SMN=['0.2x','0.5x','1x','2x'],LVN=['0.5x','1x','2x','3x'];
var RISK=10;try{var r0=localStorage.getItem('t2r_risk');if(r0)RISK=parseFloat(r0)||10;}catch(e){}
var FAMS=['Synthetics','Boom and Crash','Volatility','Forex','Metals'];
var SYN={'Synthetics':1,'Boom and Crash':1,'Volatility':1};
var MK={};D.markets.forEach(function(m){MK[m[0]]={name:m[0],fam:m[1],bars:m[2],from:m[3],to:m[4],status:m[5]};});
function famOf(a){return MK[a]?MK[a].fam:'Synthetics';}
var STRATS=['Trap Zones','Trap + Gap','Untouched Ground','Rejection Stacks','Self-taught Zones','Self-taught 4H+1D','FVG Confluence','Flip Levels','Stretch Bands'];
var INFO={
'Trap Zones':{one:'A failed breakout. Traders who chased a strong breakout get trapped when the very next candle wipes the move out. Their entry area becomes a zone to trade against them.',
 find:'On the 1-hour, 4-hour, daily or weekly chart: a candle closes beyond the previous high (or low) with a strong body, then the next candle closes back past where it started.',
 entry:'A limit order at the edge of the zone, waiting for price to come back to it.',stop:'Beyond the far side of the zone. The zone height sets the size of 1R.',target:'A multiple of the zone height in the opposite direction to the breakout.'},
'Trap + Gap':{one:'A trap zone that also has a fair value gap inside it, so two separate reasons point to the same price.',
 find:'A trap zone as above, plus a three-candle price gap of the same direction that formed inside it.',
 entry:'A limit order at the edge of the trap zone.',stop:'Beyond the far side of the zone.',target:'A multiple of the zone height.'},
'Untouched Ground':{one:'A strip of price the market rushed through once and never revisited, sitting between two busy areas. When price finally comes back, it tends to react there.',
 find:'The last 150 candles are sliced into thin price bands and each band\'s visits are counted. A run of almost-empty bands between two heavily traded areas is the zone.',
 entry:'When price returns to the edge of the untouched strip.',stop:'Beyond the far side of the strip (or a minimum size).',target:'A multiple of the strip height.'},
'Rejection Stacks':{one:'A price where the market has been pushed back several separate times. Bounce trades the next push back. Sweep trades the turn just after price pokes past it to take out the stops resting there.',
 find:'Long wicks (at least a third of the candle) whose tips line up at almost the same price, at least two separate times, and not yet broken.',
 entry:'Bounce: a limit at the stack. Sweep: a limit just beyond it.',stop:'Beyond the zone.',target:'A multiple of the zone height.'},
'Self-taught Zones':{one:'Every recent swing high and low is a candidate. The computer studied stage 1 to learn which ones tended to work, and scores each new one.',
 find:'Swing highs and lows on the higher timeframes. Each is scored on where it sits in the range, the size of its wick, its age, how fast price approaches, time of day and trend.',
 entry:'At the level when price returns. Model picks only takes levels scoring 0.30 or more.',stop:'Beyond the level.',target:'A multiple of the zone height.'},
'Self-taught 4H+1D':{one:'The same self-taught model, using only swing highs and lows from the 4-hour and daily charts, the bigger levels.',
 find:'Swing highs and lows on the 4-hour and daily charts, scored by the model.',
 entry:'At the level when price returns.',stop:'Beyond the level.',target:'A multiple of the zone height.'},
'FVG Confluence':{one:'Fair value gaps: three candles where the market moved so fast it left a gap that was never traded both ways. When gaps on different timeframes overlap, they merge into one stronger zone.',
 find:'The third candle\'s low is above the first candle\'s high (a buy gap), or the mirror for a sell gap. Gaps from the 1-hour, 4-hour, daily and weekly charts are overlaid.',
 entry:'A limit order at the edge of the gap.',stop:'Beyond the far side of the gap.',target:'A multiple of the gap height.'},
'Flip Levels':{one:'Going with a break instead of fading it. A swing high that price closes above with a strong candle turns from ceiling into floor. The first return to it is a buy. The mirror gives sells.',
 find:'A swing high (or low) is broken by a candle closing beyond it with a strong body.',
 entry:'A limit order at the broken level, waiting for the first return.',stop:'Below the level (for buys).',target:'A multiple of the zone height, in the direction of the break.'},
'Stretch Bands':{one:'No chart pattern, only distance. When price is stretched far above its recent average it is a sell zone; far below is a buy zone.',
 find:'The average of the last 20 candles, and a band 2.5 normal candle ranges above and below it.',
 entry:'When price reaches the band.',stop:'Beyond the band.',target:'Back towards the average, as a multiple of the zone height.'}};
var VIEWTXT={'Learned picks':'only the setups the learning step liked after studying stage 1.','Model picks':'only the levels the model scored highly.','At a stack':'only traps that sit at a rejection stack.','With a gap':'only traps with a price gap inside.','2+ timeframes':'only gaps where two or more timeframes overlap.','Bounce':'the bounce version.','Sweep':'the sweep version.'};
function f2(x){return (x>=0?'+':'')+x.toFixed(2);}
function mny(r){var v=Math.round(r*RISK);return (v>=0?'+':'−')+'$'+Math.abs(v).toLocaleString('en-US');}
function pc(w,n){return n>0?Math.round(100*w/n)+'%':'–';}
function cl(x){return x>0.005?'g':(x<-0.005?'r':'n');}
function rrTxt(ratio){return '1:'+(Math.round(ratio*100)/100);}
function esc(s){return String(s).replace(/[&<>"']/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];});}
function cell(t){if(!t||!t[0])return '<td class="num">–</td>';return '<td class="num '+cl(t[2])+'">'+f2(t[2])+'R<small>'+pc(t[1],t[0])+' of '+t[0]+'</small></td>';}
function minU(st){return Math.min(st[1][2],st[2][2]);}
function nf(n){return Number(n).toLocaleString('en-US');}
/* ---------- diagrams ---------- */
function diagram(s){var P=PAT[s];if(!P)return '';var C=P.c,W=560,H=300,pl=10,pr=118,pt=14,pb=14;
 var lo=1e9,hi=-1e9;C.forEach(function(k){lo=Math.min(lo,k[2]);hi=Math.max(hi,k[1]);});(P.lines||[]).forEach(function(l){lo=Math.min(lo,l.y);hi=Math.max(hi,l.y);});(P.boxes||[]).forEach(function(b){lo=Math.min(lo,b.lo);hi=Math.max(hi,b.hi);});
 var pad=(hi-lo)*0.06;lo-=pad;hi+=pad;var n=C.length,cw=(W-pl-pr)/n;
 function X(i){return pl+cw*(i+0.5);}function Y(v){return pt+(H-pt-pb)*(1-(v-lo)/(hi-lo));}
 var o='<svg viewBox="0 0 '+W+' '+H+'" role="img" aria-label="'+esc(s)+' example">';
 (P.boxes||[]).forEach(function(b){o+='<rect x="'+(X(b.x0)-cw/2)+'" y="'+Y(b.hi)+'" width="'+(X(b.x1)-X(b.x0)+cw)+'" height="'+(Y(b.lo)-Y(b.hi))+'" class="bx '+(b.k||'')+'"/>';});
 if(P.ma)o+='<path d="'+P.ma.map(function(v,i){return (i?'L':'M')+X(i).toFixed(1)+' '+Y(v).toFixed(1);}).join(' ')+'" class="ma"/>';
 if(P.band)o+='<path d="'+P.band.map(function(v,i){return (i?'L':'M')+X(i).toFixed(1)+' '+Y(v).toFixed(1);}).join(' ')+'" class="band"/>';
 C.forEach(function(k,i){var up=k[3]>=k[0];o+='<line x1="'+X(i)+'" x2="'+X(i)+'" y1="'+Y(k[1])+'" y2="'+Y(k[2])+'" class="wk '+(up?'u':'d')+'"/><rect x="'+(X(i)-cw*0.32)+'" y="'+Y(Math.max(k[0],k[3]))+'" width="'+(cw*0.64)+'" height="'+Math.max(1.5,Math.abs(Y(k[0])-Y(k[3])))+'" class="cd '+(up?'u':'d')+'"/>';});
 (P.boxes||[]).forEach(function(b){if(b.t)o+='<text x="'+(X(b.x1)+cw/2-6)+'" y="'+(Y(b.hi)+13)+'" class="bt" text-anchor="end">'+b.t+'</text>';});
 (P.lines||[]).forEach(function(l){o+='<line x1="'+(X(l.x)-cw/2)+'" x2="'+(W-pr+4)+'" y1="'+Y(l.y)+'" y2="'+Y(l.y)+'" class="ln '+l.k+'"/><text x="'+(W-pr+8)+'" y="'+(Y(l.y)+4)+'" class="lt '+l.k+'">'+l.t+'</text>';});
 (P.marks||[]).forEach(function(m){o+='<circle cx="'+X(m.x)+'" cy="'+Y(m.y)+'" r="3.5" class="mk"/><text x="'+(X(m.x)+(m.left?-8:8))+'" y="'+(Y(m.y)+(m.dy||-8))+'" class="mt"'+(m.left?' text-anchor="end"':'')+'>'+m.t+'</text>';});
 return o+'</svg>';}
function L(x,y,t,k){return {x:x,y:y,t:t,k:k};}
var TRAPC=[[100,101.5,99.6,101],[101,102.2,100.7,101.8],[101.8,102.5,101.2,102.1],[102.1,102.6,101.5,101.9],[101.9,104.3,101.8,104.1],[104.1,104.3,101.0,101.4],[101.4,101.8,100.2,100.6],[100.6,101.0,99.8,100.2],[100.2,101.2,100.0,101.0],[101,102.0,100.8,101.8],[101.8,102.7,101.6,102.4],[102.4,102.7,101.5,101.7],[101.7,101.9,100.4,100.6],[100.6,100.9,99.4,99.6],[99.6,99.9,98.9,99.1]];
var PAT={
'Trap Zones':{c:TRAPC,boxes:[{x0:4,x1:14,lo:102.6,hi:104.1,t:'Sell trap zone',k:'z'}],marks:[{x:4,y:104.3,t:'strong breakout candle',left:true},{x:5,y:101.0,t:'wiped out next candle',dy:16},{x:10,y:102.7,t:'price returns: sell',dy:-10,left:true}],lines:[L(10,104.1,'Stop (1R)','s'),L(10,102.6,'Sell limit','e'),L(10,101.1,'TP1 1:1','t'),L(10,99.6,'Target 1:2','t')]},
'Trap + Gap':{c:TRAPC,boxes:[{x0:4,x1:14,lo:102.6,hi:104.1,t:'Sell trap zone',k:'z'},{x0:4,x1:14,lo:103.2,hi:103.7,t:'gap inside',k:'g2'}],marks:[{x:4,y:104.3,t:'breakout leaves a gap',left:true},{x:10,y:102.7,t:'price returns: sell',dy:-10,left:true}],lines:[L(10,104.1,'Stop (1R)','s'),L(10,102.6,'Sell limit','e'),L(10,101.1,'TP1 1:1','t'),L(10,99.6,'Target 1:2','t')]},
'Untouched Ground':{c:[[100,100.8,99.7,100.4],[100.4,100.9,99.9,100.2],[100.2,101,99.8,100.7],[100.7,101.1,100.1,100.5],[100.5,101.2,100.3,101.0],[101.0,103.5,100.9,103.3],[103.3,103.9,102.9,103.6],[103.6,104.0,103.0,103.2],[103.2,103.8,102.9,103.5],[103.5,104.1,103.1,103.8],[103.8,104.0,103.0,103.1],[103.1,103.2,102.6,102.8],[102.8,103.9,102.7,103.8],[103.8,104.8,103.6,104.6],[104.6,105.5,104.3,105.3],[105.3,106.2,105.1,106.0]],boxes:[{x0:0,x1:4,lo:99.7,hi:101.2,t:'busy',k:'busy'},{x0:6,x1:10,lo:102.9,hi:104.1,t:'busy',k:'busy'},{x0:5,x1:15,lo:101.2,hi:102.8,t:'untouched ground',k:'z'}],marks:[{x:5,y:103.5,t:'rushed through once',left:true},{x:11,y:102.6,t:'first return: buy',dy:16}],lines:[L(11,104.4,'TP1 1:1','t'),L(11,106.0,'Target 1:2','t'),L(11,102.8,'Buy limit','e'),L(11,101.2,'Stop (1R)','s')]},
'Rejection Stacks':{c:[[103,104.1,102.8,103.8],[103.8,105.0,103.6,104.1],[104.1,104.3,103.2,103.4],[103.4,103.9,102.9,103.7],[103.7,104.95,103.5,103.9],[103.9,104.2,103.0,103.2],[103.2,103.7,102.6,103.5],[103.5,104.3,103.3,104.0],[104.0,105.05,103.8,104.2],[104.2,104.4,103.1,103.3],[103.3,103.8,103.0,103.6],[103.6,104.5,103.4,104.4],[104.4,104.9,104.3,104.7],[104.7,104.9,103.6,103.8],[103.8,104.0,102.6,102.8],[102.8,103.0,102.1,102.3]],boxes:[{x0:1,x1:15,lo:104.75,hi:105.05,t:'stack: 3 rejections',k:'z'},{x0:1,x1:15,lo:105.25,hi:105.65,t:'sweep zone',k:'g2'}],marks:[{x:1,y:105.0,t:'1',dy:-6},{x:4,y:104.95,t:'2',dy:-6},{x:8,y:105.05,t:'3',dy:-6},{x:12,y:104.9,t:'bounce: sell',dy:16,left:true}],lines:[L(12,105.05,'Stop (1R)','s'),L(12,104.75,'Sell limit','e'),L(12,104.45,'TP1 1:1','t'),L(12,104.15,'Target 1:2','t')]},
'Self-taught Zones':{c:[[100,100.9,99.8,100.7],[100.7,101.6,100.5,101.4],[101.4,102.4,101.2,102.2],[102.2,104.0,102.0,102.6],[102.6,102.9,101.6,101.8],[101.8,102.1,100.9,101.1],[101.1,101.6,100.6,101.4],[101.4,102.3,101.2,102.1],[102.1,103.1,102.0,102.9],[102.9,103.8,102.7,103.6],[103.6,103.8,102.6,102.8],[102.8,103.0,101.7,101.9],[101.9,102.1,100.9,101.2],[101.2,101.4,100.5,100.7]],boxes:[{x0:3,x1:13,lo:103.6,hi:104.0,t:'swing high level',k:'z'}],marks:[{x:3,y:104.0,t:'swing high: long wick',left:true},{x:9,y:103.8,t:'model score +0.42: picked',dy:-10,left:true}],lines:[L(9,104.0,'Stop (1R)','s'),L(9,103.6,'Sell limit','e'),L(9,103.2,'TP1 1:1','t'),L(9,102.8,'Target 1:2','t')]},
'FVG Confluence':{c:[[100,100.6,99.6,100.3],[100.3,101.0,100.0,100.8],[100.8,103.4,100.7,103.2],[103.2,104.2,102.0,103.9],[103.9,104.6,103.5,104.4],[104.4,104.8,103.6,103.8],[103.8,104.0,102.9,103.1],[103.1,103.3,102.3,102.5],[102.5,102.6,101.9,102.2],[102.2,103.4,102.0,103.3],[103.3,104.4,103.1,104.2],[104.2,105.3,104.0,105.1],[105.1,106.2,104.9,106.0]],boxes:[{x0:2,x1:12,lo:101.0,hi:102.0,t:'1-hour gap',k:'z'},{x0:2,x1:12,lo:101.3,hi:102.4,t:'4-hour gap overlaps',k:'g2'}],marks:[{x:1,y:101.0,t:'candle 1 high',left:true,dy:-6},{x:3,y:102.0,t:'candle 3 low',dy:16},{x:8,y:101.9,t:'return to the gap: buy',dy:18}],lines:[L(8,104.0,'Target 1:2','t'),L(8,103.0,'TP1 1:1','t'),L(8,102.0,'Buy limit','e'),L(8,101.0,'Stop (1R)','s')]},
'Flip Levels':{c:[[100,101.0,99.8,100.8],[100.8,101.8,100.6,101.6],[101.6,103.0,101.4,102.6],[102.6,102.8,101.8,102.0],[102.0,102.3,101.3,101.6],[101.6,102.4,101.4,102.2],[102.2,104.4,102.1,104.2],[104.2,104.9,103.9,104.6],[104.6,104.8,103.8,104.0],[104.0,104.1,103.1,103.3],[103.3,103.5,102.85,103.2],[103.2,104.3,103.1,104.1],[104.1,105.0,103.9,104.8],[104.8,105.6,104.6,105.4]],boxes:[{x0:2,x1:13,lo:102.7,hi:103.0,t:'old ceiling becomes floor',k:'z'}],marks:[{x:2,y:103.0,t:'swing high',left:true},{x:6,y:104.4,t:'strong close above it',left:true},{x:10,y:102.85,t:'first return: buy',dy:18}],lines:[L(10,104.2,'Target 1:2','t'),L(10,103.6,'TP1 1:1','t'),L(10,103.0,'Buy limit','e'),L(10,102.4,'Stop (1R)','s')]},
'Stretch Bands':{c:[[100,100.5,99.6,100.3],[100.3,100.8,100.0,100.6],[100.6,101.0,100.2,100.4],[100.4,100.9,100.1,100.8],[100.8,101.3,100.5,101.1],[101.1,101.5,100.8,100.9],[100.9,101.6,100.7,101.5],[101.5,102.6,101.4,102.5],[102.5,103.7,102.3,103.5],[103.5,104.2,103.2,103.6],[103.6,103.8,102.7,102.9],[102.9,103.1,102.1,102.3],[102.3,102.5,101.6,101.8],[101.8,102.0,101.3,101.5]],ma:[100.2,100.3,100.4,100.5,100.6,100.7,100.8,101.0,101.2,101.4,101.5,101.6,101.6,101.6],band:[102.8,102.9,103.0,103.1,103.2,103.3,103.4,103.6,103.8,104.0,104.1,104.2,104.2,104.2],boxes:[{x0:8,x1:13,lo:103.9,hi:104.5,t:'stretch zone',k:'z'}],marks:[{x:3,y:100.5,t:'20-candle average',dy:20},{x:9,y:104.2,t:'price far above average: sell',left:true,dy:-8}],lines:[L(9,104.5,'Stop (1R)','s'),L(9,103.9,'Sell limit','e'),L(9,103.3,'TP1 1:1','t'),L(9,102.7,'Target 1:2','t')]}};
PAT['Self-taught 4H+1D']=JSON.parse(JSON.stringify(PAT['Self-taught Zones']));PAT['Self-taught 4H+1D'].boxes[0].t='4-hour / daily swing level';

/* ---------- rows ---------- */
var ROWS=D.rows.map(function(r,i){return {i:i,a:r[0],s:r[1],v:r[2],sd:r[3],c:r[4],st:r[5],best:r[6],pass:r[7],strong:r[8],fam:famOf(r[0])};});
var WATCH=D.watch.map(function(w){return {a:w[0],s:w[1],v:w[2],sd:w[3],c:w[4],si:w[5],lv:w[6],st:w[7],b1:w[8],pw:w[9],z:w[10],house:w[11],fam:famOf(w[0])};});
function wkey(a,s,v,sd,c){return a+'|'+s+'|'+v+'|'+sd+'|'+c;}
var WSET={};WATCH.forEach(function(w){WSET[wkey(w.a,w.s,w.v,w.sd,w.c)]=w;});
var REP=D.replay.map(function(x){return {tin:x[0],tout:x[1],a:x[2],s:x[3],v:x[4],sd:x[5],c:x[6],dir:x[7],e:x[8],sl:x[9],tp:x[10],rr:x[11],res:x[12],R:x[13],fam:famOf(x[2]),day:x[0].slice(0,10)};});
function repFor(a,s,v,sd,c){return REP.filter(function(t){return t.a==a&&t.s==s&&t.v==v&&t.sd==sd&&t.c==c;});}
function sumRep(list){var o={n:list.length,w:0,l:0,o:0,R:0};list.forEach(function(t){if(t.res=='won')o.w++;else if(t.res=='lost')o.l++;else o.o++;o.R+=t.R;});return o;}
/* ---------- hero ---------- */
(function(){var passed={},fam={};ROWS.forEach(function(r){if(r.pass)passed[r.a]=1;});
var rs=sumRep(REP);
document.getElementById('h_trades').textContent=nf(D.meta.trades);
document.getElementById('h_pass').textContent=Object.keys(passed).length;
document.getElementById('h_follow').textContent=Object.keys(WATCH.reduce(function(o,w){o[w.a]=1;return o;},{})).length;
document.getElementById('h_week').textContent=f2(rs.R)+'R';
document.getElementById('h_weekw').textContent=nf(rs.n)+' signals, '+rs.w+' won, '+rs.l+' lost';})();
/* ---------- top 10 ---------- */
function bestWatchPerMarket(filter){var by={};WATCH.forEach(function(w){if(!filter(w))return;var strong=Math.min(w.st[1][0],w.st[2][0])>=100&&Math.min(w.st[1][2],w.st[2][2])>=0.05;var k=(strong?1000:0)+w.z;if(!by[w.a]||k>by[w.a].k)by[w.a]={w:w,k:k};});
 return Object.keys(by).map(function(a){return by[a];}).sort(function(x,y){return y.k-x.k;}).map(function(x){return x.w;});}
function pickCard(w,rank){var ratio=LV[w.lv]/SM[w.si];var un=w.st[1][0]+w.st[2][0],uw=w.st[1][1]+w.st[2][1];var rp=sumRep(repFor(w.a,w.s,w.v,w.sd,w.c));
 var notes=[];if(/Boom|Crash|Jump|Range Break/.test(w.a))notes.push('spike market');if(w.fam=='Forex'&&w.sd!='Both')notes.push(w.sd.toLowerCase()+' only');if(ratio>=6)notes.push('long-shot payoff');
 return '<button class="pick" data-w="'+esc(wkey(w.a,w.s,w.v,w.sd,w.c))+'" type="button"><span class="rk">'+rank+'</span><span class="pm">'+esc(w.a)+'</span><span class="ps">'+esc(w.s)+' &middot; '+esc(w.sd)+' &middot; '+rrTxt(ratio)+'</span>'+
 '<span class="pk"><b>'+pc(uw,un)+'</b> won on unseen history <i>(needs '+Math.round(100/(1+ratio))+'%)</i></span>'+
 '<span class="pk"><b class="'+cl(w.st[1][2])+'">'+f2(w.st[1][2])+'</b> / <b class="'+cl(w.st[2][2])+'">'+f2(w.st[2][2])+'</b> R a trade, stages 2 and 3</span>'+
 '<span class="pk">Last week: '+(rp.n?'<b class="'+cl(rp.R)+'">'+f2(rp.R)+'R</b> from '+rp.n+' signals ('+rp.w+' won)':'no signal')+'</span>'+
 (notes.length?'<span class="pn">'+notes.join(' &middot; ')+'</span>':'')+'</button>';}
(function(){var syn=bestWatchPerMarket(function(w){return SYN[w.fam];}).slice(0,5);var fx=bestWatchPerMarket(function(w){return w.fam=='Forex';}).slice(0,5);
document.getElementById('top_syn').innerHTML=syn.map(function(w,i){return pickCard(w,i+1);}).join('');
document.getElementById('top_fx').innerHTML=fx.map(function(w,i){return pickCard(w,i+1);}).join('');})();
/* ---------- explorer ---------- */
var fFam=document.getElementById('f_fam'),fMk=document.getElementById('f_mk'),fSt=document.getElementById('f_st'),fSd=document.getElementById('f_sd'),fCl=document.getElementById('f_cl'),fPs=document.getElementById('f_ps');
FAMS.forEach(function(f){fFam.add(new Option(f,f));});
STRATS.forEach(function(s){fSt.add(new Option(s,s));});
function fillMarkets(){var cur=fMk.value;fMk.innerHTML='';fMk.add(new Option('All markets',''));
 Object.keys(MK).sort().forEach(function(a){if(!fFam.value||MK[a].fam==fFam.value)fMk.add(new Option(a,a));});
 if(cur&&MK[cur]&&(!fFam.value||MK[cur].fam==fFam.value))fMk.value=cur;}
fillMarkets();
var HEAD='<th class="l">Market</th><th class="l">Strategy</th><th class="l">View</th><th class="l">Side</th><th class="l">Stop class</th><th>Stage 1</th><th>Stage 2</th><th>Stage 3</th><th class="l">Verdict</th><th class="l">Best stop and target</th>';
function verdict(r){var w=WSET[wkey(r.a,r.s,r.v,r.sd,r.c)];var h='';if(r.pass)h+='<span class="pill pa">Pass</span>';else if(r.strong)h+='<span class="pill pb">Stronghold</span>';else h+='<span class="pill">No</span>';if(w)h+='<span class="pill pf">Followed live</span>';return h;}
function bestCell(r){if(!r.best)return '<td class="l dim">none passed</td>';var b=r.best,ratio=LV[b[1]]/SM[b[0]];var e3=b[2][2];return '<td class="l">'+rrTxt(ratio)+' <small>stop '+SMN[b[0]]+', target '+LVN[b[1]]+' &middot; exam <span class="'+cl(e3[2])+'">'+f2(e3[2])+'R</span> ('+pc(e3[1],e3[0])+' of '+e3[0]+')</small></td>';}
function rowHtml(r){return '<tr data-r="'+r.i+'"><td class="l b">'+esc(r.a)+'</td><td class="l">'+esc(r.s)+'</td><td class="l">'+esc(r.v)+'</td><td class="l">'+r.sd+'</td><td class="l">'+r.c+'</td>'+cell(r.st[0])+cell(r.st[1])+cell(r.st[2])+'<td class="l">'+verdict(r)+'</td>'+bestCell(r)+'</tr>';}
function score(r){return minU(r.st)+(r.pass?5:0)+(r.strong?1:0)-(Math.min(r.st[1][0],r.st[2][0])<40?3:0);}
function runExplorer(){var fam=fFam.value,mk=fMk.value,st=fSt.value,sd=fSd.value,c=fCl.value,po=fPs.checked;
 var list=ROWS.filter(function(r){return (!fam||r.fam==fam)&&(!mk||r.a==mk)&&(!st||r.s==st)&&(!sd||r.sd==sd)&&(!c||r.c==c)&&(!po||r.pass||r.strong);});
 var head=document.getElementById('ex_head');
 if(mk){var m=MK[mk];var nP=0,nW=0;ROWS.forEach(function(r){if(r.a==mk&&(r.pass||r.strong))nP++;});WATCH.forEach(function(w){if(w.a==mk)nW++;});
  var rp=sumRep(REP.filter(function(t){return t.a==mk;}));
  head.innerHTML='<div class="mh"><div><h3>'+esc(mk)+'</h3><p class="dim">'+esc(m.fam)+' &middot; '+nf(m.bars)+' fifteen-minute candles tested, '+m.from+' to '+m.to+(m.status=='short'?' (all the history the broker has)':'')+'</p></div>'+
  '<div class="mstats"><span><b>'+nP+'</b> setups passed</span><span><b>'+nW+'</b> followed live</span><span><b class="'+cl(rp.R)+'">'+(rp.n?f2(rp.R)+'R':'–')+'</b> last week, '+rp.n+' signals</span></div></div>';}
 else if(st){var mks={};list.forEach(function(r){if(r.pass||r.strong)mks[r.a]=1;});var rp2=sumRep(REP.filter(function(t){return t.s==st;}));
  head.innerHTML='<div class="mh"><div><h3>'+esc(st)+'</h3><p class="dim">'+esc(INFO[st].one)+'</p></div><div class="mstats"><span><b>'+Object.keys(mks).length+'</b> markets where it passed</span><span><b class="'+cl(rp2.R)+'">'+f2(rp2.R)+'R</b> last week, '+rp2.n+' signals</span></div></div>';}
 else head.innerHTML='';
 list.sort(function(x,y){return score(y)-score(x);});
 var shown=list.slice(0,400);
 document.getElementById('ex_count').textContent=nf(list.length)+' results'+(list.length>400?', best 400 shown':'');
 document.getElementById('ex_body').innerHTML=shown.map(rowHtml).join('')||'<tr><td class="l dim" colspan="10">Nothing matches these filters.</td></tr>';}
[fFam,fMk,fSt,fSd,fCl,fPs].forEach(function(el){el.addEventListener('change',function(){if(el===fFam)fillMarkets();runExplorer();});});
runExplorer();
/* ---------- story ---------- */
var MOD=document.getElementById('mo');
function stageDates(a){var m=MK[a];if(!m)return ['','','',''];var t0=new Date(m.from.replace(/\./g,'-')).getTime(),t3=new Date(m.to.replace(/\./g,'-')).getTime();function d(t){return new Date(t).toISOString().slice(0,10);}return [d(t0),d(t0+(t3-t0)/3),d(t0+2*(t3-t0)/3),d(t3)];}
function story(a,s,v,sd,c,st,ratio,mixTxt,t1){
 var n=[st[0][0],st[1][0],st[2][0]],w=[st[0][1],st[1][1],st[2][1]],e=[st[0][2],st[1][2],st[2][2]];
 var N=n[0]+n[1]+n[2],W=w[0]+w[1]+w[2],un=n[1]+n[2],uw=w[1]+w[2],R=[e[0]*n[0],e[1]*n[1],e[2]*n[2]],RT=R[0]+R[1]+R[2];
 var dt=stageDates(a),nm=['Stage 1 (learning)','Stage 2 (first unseen test)','Stage 3 (final exam)'];
 var good=e[1]>0&&e[2]>0,strong=good&&Math.min(n[1],n[2])>=100;var rt=Math.round(ratio*100)/100;
 var h='<p class="eyebrow">'+esc(famOf(a))+'</p><h2>'+esc(a)+'</h2><p class="dim">'+esc(s)+' &middot; '+esc(v)+' &middot; '+sd+' &middot; '+c+' stop class &middot; '+mixTxt+'</p>';
 h+='<p class="vd"><b>Bottom line:</b> '+(strong?'made money in both unseen periods on a solid number of trades. A serious candidate.':(good?'made money in both unseen periods, on a smaller number of trades. Promising, not proven.':'did not make money in both unseen periods. Not one to trade as it stands.'))+'</p>';
 h+='<h4>What the strategy does</h4><p>'+esc(INFO[s].one)+(VIEWTXT[v]?' This row takes '+VIEWTXT[v]:'')+'</p>';
 h+='<h4>The trade</h4><ul><li><b>Risk to reward 1:'+rt+'.</b> A loss costs 1R (the amount risked); a win pays '+rt+'R.</li><li><b>Break-even win rate '+Math.round(100/(1+ratio))+'%.</b> Win more often than that and it makes money.</li><li><b>Win rate on history it never saw: '+pc(uw,un)+'</b> ('+uw+' wins in '+un+' trades).</li></ul>';
 h+='<h4>What happened in the test</h4><div class="sc"><table class="st"><thead><tr><th class="l">Period</th><th class="l">Dates (approx.)</th><th>Trades</th><th>Won</th><th>Lost</th><th>Win rate</th><th>Average</th><th>Total</th><th>At $'+RISK+' a trade</th></tr></thead><tbody>';
 for(var i=0;i<3;i++)h+='<tr><td class="l">'+nm[i]+'</td><td class="l">'+dt[i]+' to '+dt[i+1]+'</td><td class="num">'+n[i]+'</td><td class="num">'+w[i]+'</td><td class="num">'+(n[i]-w[i])+'</td><td class="num">'+pc(w[i],n[i])+'</td><td class="num '+cl(e[i])+'">'+f2(e[i])+'R</td><td class="num '+cl(R[i])+'">'+f2(R[i])+'R</td><td class="num '+cl(R[i])+'">'+mny(R[i])+'</td></tr>';
 h+='<tr class="tot"><td class="l">Whole test</td><td class="l">'+dt[0]+' to '+dt[3]+'</td><td class="num">'+N+'</td><td class="num">'+W+'</td><td class="num">'+(N-W)+'</td><td class="num">'+pc(W,N)+'</td><td class="num '+cl(RT)+'">'+(N?f2(RT/N):'–')+'R</td><td class="num '+cl(RT)+'">'+f2(RT)+'R</td><td class="num '+cl(RT)+'">'+mny(RT)+'</td></tr></tbody></table></div>';
 h+='<p class="note">Averages and totals are after trading costs. Stage 1 is where the setup learned or was chosen, so stages 2 and 3 are the fair test.</p>';
 var wr=N?W/N:0,streak=(wr>0&&wr<1&&N>1)?Math.round(Math.log(N)/Math.log(1/(1-wr))):0,weeks=(new Date(dt[3])-new Date(dt[0]))/6048e5,pw=weeks>0?N/weeks:0;
 h+='<h4>What to expect</h4><ul><li>About <b>'+(pw>=1?pw.toFixed(1)+' signals a week':(pw*4.3).toFixed(1)+' signals a month')+'</b>.</li><li>It loses about '+Math.round(100*(1-wr))+' trades in 100. A run of about <b>'+streak+' losses in a row</b> is normal for a record like this.</li><li>Risking 1% of the account per trade keeps that run to about '+streak+'% of the account.</li>';
 if(t1&&t1[1]>=0&&ratio>1){h+='<li><b>Taking profit early:</b> '+pc(t1[1]+t1[2],un)+' of unseen trades reached 1:1 before the stop.</li>';}
 h+='</ul>';
 var rp=repFor(a,s,v,sd,c);
 if(rp.length){var o=sumRep(rp);h+='<h4>Last week (5 to 12 October), replayed</h4><p>'+o.n+' signals: '+o.w+' won, '+o.l+' lost'+(o.o?', '+o.o+' still open':'')+'. Result <b class="'+cl(o.R)+'">'+f2(o.R)+'R</b> ('+mny(o.R)+').</p><div class="sc"><table class="st"><thead><tr><th class="l">Signal</th><th class="l">Order</th><th>Entry</th><th>Stop</th><th>Target</th><th class="l">Result</th><th>R</th></tr></thead><tbody>'+
  rp.slice(0,40).map(function(t){return '<tr><td class="l">'+t.tin+'</td><td class="l">'+t.dir.toUpperCase()+'</td><td class="num">'+t.e+'</td><td class="num">'+t.sl+'</td><td class="num">'+t.tp+'</td><td class="l '+(t.res=='won'?'g':(t.res=='lost'?'r':''))+'">'+t.res+'</td><td class="num '+cl(t.R)+'">'+(t.res=='open'?'–':f2(t.R))+'</td></tr>';}).join('')+'</tbody></table></div>';}
 var notes=[];if(Math.min(n[1],n[2])<60)notes.push('Small sample: an unseen stage has fewer than 60 trades.');if(ratio>=6)notes.push('Long-shot payoff: rare, big wins, so results swing.');if(/Boom|Crash|Jump|Range Break/.test(a))notes.push('Spike market: a stop can be jumped, making a real loss bigger than planned.');if(famOf(a)=='Forex'&&sd!='Both')notes.push('One direction only on a pair that has trended: part of the record may be the trend itself.');if(v=='Learned picks'||v=='Model picks')notes.push('Stage 1 flatters this row, because the model learned from it.');notes.push('Thousands of combinations were tested, so some look good by luck. Live demo results decide what reaches real money.');
 h+='<h4>Honest notes</h4><ul>'+notes.map(function(x){return '<li>'+x+'</li>';}).join('')+'</ul>';
 h+='<h4>How '+esc(s)+' places the trade</h4><div class="chart">'+diagram(s)+'</div>';
 document.getElementById('mb').innerHTML=h;MOD.hidden=false;document.body.style.overflow='hidden';document.getElementById('mx').focus();}
function closeStory(){MOD.hidden=true;document.body.style.overflow='';}
document.getElementById('mx').addEventListener('click',closeStory);
MOD.addEventListener('click',function(e){if(e.target===MOD)closeStory();});
document.addEventListener('keydown',function(e){if(e.key=='Escape'&&!MOD.hidden)closeStory();});
document.getElementById('ex_body').addEventListener('click',function(e){var tr=e.target.closest('tr[data-r]');if(!tr)return;var r=ROWS[+tr.getAttribute('data-r')];
 if(r.best&&!r.pass){var b=r.best;story(r.a,r.s,r.v,r.sd,r.c,b[2],LV[b[1]]/SM[b[0]],'stop '+SMN[b[0]]+', target '+LVN[b[1]],null);}
 else story(r.a,r.s,r.v,r.sd,r.c,r.st,2,'stop 1x, target 2x (the standard setup)',null);});
document.addEventListener('click',function(e){var b=e.target.closest('.pick');if(!b)return;var w=WSET[b.getAttribute('data-w')];if(!w)return;story(w.a,w.s,w.v,w.sd,w.c,w.st,LV[w.lv]/SM[w.si],'stop '+SMN[w.si]+', target '+LVN[w.lv],w.b1);});
/* ---------- strategies ---------- */
(function(){var h='';STRATS.forEach(function(s){var I=INFO[s];var mks={};ROWS.forEach(function(r){if(r.s==s&&(r.pass||r.strong))mks[r.a]=1;});var nw=WATCH.filter(function(w){return w.s==s;}).length;var rp=sumRep(REP.filter(function(t){return t.s==s;}));
 h+='<article class="strat"><div class="sx"><h3>'+esc(s)+'</h3><p>'+esc(I.one)+'</p><dl><dt>Finds the zone</dt><dd>'+esc(I.find)+'</dd><dt>Entry</dt><dd>'+esc(I.entry)+'</dd><dt>Stop</dt><dd>'+esc(I.stop)+'</dd><dt>Target</dt><dd>'+esc(I.target)+'</dd></dl>'+
 '<div class="sstats"><span><b>'+Object.keys(mks).length+'</b> markets passed</span><span><b>'+nw+'</b> setups followed</span><span><b class="'+cl(rp.R)+'">'+f2(rp.R)+'R</b> last week ('+rp.w+' won, '+rp.l+' lost)</span></div>'+
 '<button class="lnk" type="button" data-st="'+esc(s)+'">See every market for '+esc(s)+'</button></div><div class="chart">'+diagram(s)+'</div></article>';});
 document.getElementById('strats').innerHTML=h;
 document.getElementById('strats').addEventListener('click',function(e){var b=e.target.closest('[data-st]');if(!b)return;fFam.value='';fillMarkets();fMk.value='';fSt.value=b.getAttribute('data-st');fPs.checked=true;runExplorer();document.getElementById('explorer').scrollIntoView({behavior:'smooth'});});})();
/* ---------- last week ---------- */
var wDay=document.getElementById('w_day'),wFam=document.getElementById('w_fam'),wQ=document.getElementById('w_q');
var DAYS=[];REP.forEach(function(t){if(DAYS.indexOf(t.day)<0)DAYS.push(t.day);});DAYS.sort();
var DN=['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
function dayLabel(d){var x=new Date(d.replace(/\./g,'-')+'T12:00:00Z');return DN[x.getUTCDay()]+' '+x.getUTCDate();}
wDay.innerHTML='<button type="button" class="chip" aria-pressed="true" data-d="">Whole week</button>'+DAYS.map(function(d){return '<button type="button" class="chip" aria-pressed="false" data-d="'+d+'">'+dayLabel(d)+'</button>';}).join('');
FAMS.forEach(function(f){wFam.add(new Option(f,f));});
var curDay='';
wDay.addEventListener('click',function(e){var b=e.target.closest('.chip');if(!b)return;curDay=b.getAttribute('data-d');wDay.querySelectorAll('.chip').forEach(function(c){c.setAttribute('aria-pressed',c===b?'true':'false');});runWeek();});
wFam.addEventListener('change',runWeek);wQ.addEventListener('input',runWeek);
function runWeek(){var q=wQ.value.toLowerCase();var L=REP.filter(function(t){return (!curDay||t.day==curDay)&&(!wFam.value||t.fam==wFam.value)&&(!q||(t.a+' '+t.s).toLowerCase().indexOf(q)>=0);});
 var o=sumRep(L);document.getElementById('w_cards').innerHTML='<div class="kpi"><b>'+nf(o.n)+'</b><span>Signals</span></div><div class="kpi"><b>'+o.w+' / '+o.l+'</b><span>Won / lost ('+pc(o.w,o.w+o.l)+')</span></div><div class="kpi"><b class="'+cl(o.R)+'">'+f2(o.R)+'R</b><span>Closed result</span></div><div class="kpi"><b class="'+cl(o.R)+'">'+mny(o.R)+'</b><span>At $'+RISK+' a trade</span></div>';
 drawCurve(L);
 var by={};L.forEach(function(t){var k=t.a;if(!by[k])by[k]=[];by[k].push(t);});
 var ms=Object.keys(by).map(function(a){var x=sumRep(by[a]);x.a=a;return x;}).sort(function(x,y){return y.R-x.R;});
 document.getElementById('w_mk').innerHTML=ms.map(function(x){return '<tr><td class="l b">'+esc(x.a)+'</td><td class="num">'+x.n+'</td><td class="num">'+x.w+'</td><td class="num">'+x.l+'</td><td class="num">'+pc(x.w,x.w+x.l)+'</td><td class="num '+cl(x.R)+'">'+f2(x.R)+'R</td><td class="num '+cl(x.R)+'">'+mny(x.R)+'</td></tr>';}).join('');
 var perf=ms.filter(function(x){return x.w>=5&&x.l==0;});
 document.getElementById('w_perf').innerHTML=perf.length?perf.map(function(x){return '<span class="perf"><b>'+esc(x.a)+'</b> '+x.w+' out of '+x.w+'</span>';}).join(''):'<span class="dim">None with five or more wins and no loss in this selection.</span>';
 var T=L.slice().sort(function(x,y){return x.tin<y.tin?1:-1;}).slice(0,400);
 document.getElementById('w_tr').innerHTML=T.map(function(t){return '<tr><td class="l">'+t.tin+'</td><td class="l b">'+esc(t.a)+'</td><td class="l">'+esc(t.s)+' <small>'+esc(t.v)+', '+t.c+'</small></td><td class="l">'+t.dir.toUpperCase()+'</td><td class="num">'+t.e+'</td><td class="num">'+t.sl+'</td><td class="num">'+t.tp+'</td><td class="num">'+t.rr+'</td><td class="l '+(t.res=='won'?'g':(t.res=='lost'?'r':''))+'">'+t.res+'</td><td class="num '+cl(t.R)+'">'+(t.res=='open'?'–':f2(t.R))+'</td><td class="l">'+(t.tout||'–')+'</td></tr>';}).join('');
 document.getElementById('w_trn').textContent=L.length>400?'Latest 400 of '+nf(L.length)+' shown.':'';}
function drawCurve(L){var el=document.getElementById('w_curve');var c=L.filter(function(t){return t.res!='open';}).sort(function(x,y){return (x.tout||x.tin)<(y.tout||y.tin)?-1:1;});
 if(c.length<2){el.innerHTML='<p class="dim">Not enough closed trades to draw.</p>';return;}
 var pts=[0],s=0;c.forEach(function(t){s+=t.R;pts.push(s);});
 var W=760,H=220,pl=46,pr=64,pt=14,pb=26,mn=Math.min(0,Math.min.apply(null,pts)),mx=Math.max(0,Math.max.apply(null,pts));if(mx-mn<1)mx=mn+1;
 function X(i){return pl+(W-pl-pr)*i/(pts.length-1);}function Y(v){return pt+(H-pt-pb)*(1-(v-mn)/(mx-mn));}
 var step=Math.pow(10,Math.floor(Math.log10((mx-mn)/3)));var ticks=[];for(var v=Math.ceil(mn/step)*step;v<=mx;v+=step)ticks.push(v);if(ticks.length>6)ticks=ticks.filter(function(_,i){return i%2==0;});
 var g=ticks.map(function(v){return '<line x1="'+pl+'" x2="'+(W-pr)+'" y1="'+Y(v)+'" y2="'+Y(v)+'" class="grid"/><text x="'+(pl-6)+'" y="'+(Y(v)+4)+'" class="ax" text-anchor="end">'+Math.round(v)+'R</text>';}).join('');
 var d=pts.map(function(v,i){return (i?'L':'M')+X(i).toFixed(1)+' '+Y(v).toFixed(1);}).join(' ');
 var area=d+' L'+X(pts.length-1).toFixed(1)+' '+Y(0)+' L'+X(0)+' '+Y(0)+' Z';var end=pts[pts.length-1];
 el.innerHTML='<svg viewBox="0 0 '+W+' '+H+'" role="img" aria-label="Running total of closed trades in R"><g>'+g+'</g><line x1="'+pl+'" x2="'+(W-pr)+'" y1="'+Y(0)+'" y2="'+Y(0)+'" class="zero"/><path d="'+area+'" class="area"/><path d="'+d+'" class="line"/><circle cx="'+X(pts.length-1)+'" cy="'+Y(end)+'" r="4" class="dot"/><text x="'+(X(pts.length-1)+8)+'" y="'+(Y(end)+4)+'" class="endl">'+f2(end)+'R</text><text x="'+pl+'" y="'+(H-6)+'" class="ax">first closed trade</text><text x="'+(W-pr)+'" y="'+(H-6)+'" class="ax" text-anchor="end">last ('+c.length+' closed)</text></svg>';}
runWeek();
/* ---------- risk ---------- */
var ri=document.getElementById('risk');ri.value=RISK;ri.addEventListener('input',function(){var v=parseFloat(ri.value);if(v>0){RISK=v;try{localStorage.setItem('t2r_risk',v);}catch(e){}runWeek();}});

var ld=document.getElementById('loading');if(ld)ld.remove();
}).catch(function(e){var ld=document.getElementById('loading');if(ld)ld.innerHTML='<b>T2R <span>Lab</span></b><span>The results could not load. Refresh the page.</span>';console.error(e);});})();
