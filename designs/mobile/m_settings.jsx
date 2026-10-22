/* ============================================================
   Settings tab — 设置
   结构对齐 lib/mobile/pages/settings_page.dart：分组列表，点行下钻到
   对应 section（语言 / 主题 / 编辑器 / 提供商 …）。
   ============================================================ */

/* ---------- 设置主页（分组列表） ---------- */
function SettingsScreen({onOpen}){
  const [ref, scrolled] = useScrolled();
  const [dream, setDream] = useState(true);

  const Group = ({title, children}) => (
    <div style={{marginBottom:22}}>
      <div style={{fontSize:11.5, fontWeight:700, color:'var(--text-subtle)', letterSpacing:.6, padding:'0 4px 8px'}}>{title}</div>
      <div className="slist">{children}</div>
    </div>
  );
  const Row = ({icon, iconBg, iconColor, label, value, right, onClick}) => {
    const Cmp = typeof icon==='string'?I[icon]:icon;
    return (
      <div className="srow" onClick={onClick}>
        <div className="sicon" style={{background:iconBg, color:iconColor}}><Cmp s={18}/></div>
        <div className="col" style={{flex:1, gap:2}}>
          <span style={{fontSize:14.5, fontWeight:500, color:'var(--text-primary)'}}>{label}</span>
        </div>
        {value && <span style={{fontSize:13, color:'var(--text-muted)'}}>{value}</span>}
        {right!==undefined ? right : <I.chevR s={18} c="var(--text-subtle)"/>}
      </div>
    );
  };

  return (
    <div className="screen" data-screen-label="settings">
      <PageHead title="设置" big scrolled={scrolled}/>
      <div className="viewport" ref={ref} style={{padding:'8px 18px 28px'}}>
        <Group title="偏好">
          <Row icon="globe"  iconBg="rgba(107,118,137,.12)" iconColor="#6B7689"        label="语言"   value="中文简体" onClick={()=>onOpen('language')}/>
          <Row icon="palette" iconBg="rgba(59,81,130,.14)" iconColor="var(--accent-warm)" label="主题"   value="墨蓝纸本 · 浅色" onClick={()=>onOpen('appearance')}/>
          <Row icon="text"   iconBg="rgba(103,117,108,.14)" iconColor="#67756C"        label="编辑器" value="思源宋体 · 17px" onClick={()=>onOpen('editorSettings')}/>
        </Group>

        <Group title="AI">
          <Row icon="brain" iconBg="rgba(76,110,145,.12)" iconColor="var(--info)" label="AI 提供商" value="5 个 · 4 已连接" onClick={()=>onOpen('providers')}/>
          <Row icon="model" iconBg="rgba(136,57,239,.12)" iconColor="#8839EF" label="默认模型" value="mimo-v2.5"/>
          <Row icon="robot" iconBg="rgba(59,81,130,.14)" iconColor="var(--accent-warm)" label="智能体" value={SUBAGENTS.length+' 个'}/>
          <div className="srow">
            <div className="sicon" style={{background:'rgba(36,59,90,.12)', color:'#243B5A'}}><I.moon s={18}/></div>
            <div className="col" style={{flex:1}}>
              <span style={{fontSize:14.5, fontWeight:500}}>做梦</span>
              <span style={{fontSize:11, color:'var(--text-subtle)'}}>空闲时让 AI 自动整理伏笔与设定</span>
            </div>
            <Switch on={dream} onToggle={()=>setDream(v=>!v)}/>
          </div>
        </Group>

        <Group title="数据">
          <Row icon="chart" iconBg="rgba(74,124,89,.13)" iconColor="var(--success)" label="用量统计" value="本月 34.3 万词元" onClick={()=>onOpen('usage')}/>
          <Row icon="archive" iconBg="rgba(107,118,137,.12)" iconColor="#6B7689" label="存储与备份" value="248 MB"/>
        </Group>

        <Group title="系统">
          <Row icon="info" iconBg="var(--surface-dim)" iconColor="var(--text-muted)" label="关于 Reveric" value="v0.4.2"/>
        </Group>

        <div style={{textAlign:'center', fontSize:11, color:'var(--text-subtle)', padding:'8px 0 4px', fontFamily:'var(--serif)'}}>
          Reveric · 为创作者打造的写作空间
        </div>
      </div>
    </div>
  );
}

/* ---------- 通用小组件 ---------- */
function SectHead({title, desc}){
  return (
    <div className="col" style={{gap:3, marginBottom:14, padding:'0 2px'}}>
      <span style={{fontSize:14, fontWeight:700, color:'var(--text-primary)'}}>{title}</span>
      {desc && <span style={{fontSize:12, color:'var(--text-muted)', lineHeight:1.5}}>{desc}</span>}
    </div>
  );
}
function ToggleChip({label, on, onTap, disabled}){
  return <span className={"tchip"+(on?' on':'')} onClick={disabled?undefined:onTap}
    style={{opacity:disabled?.5:1}}>{label}</span>;
}
function SettingSlider({value, min, max, step, fmt, onChange}){
  return (
    <div className="row gap12">
      <input type="range" className="mslider" min={min} max={max} step={step||1} value={value}
        onChange={e=>onChange(parseFloat(e.target.value))} style={{flex:1}}/>
      <span style={{minWidth:46, textAlign:'center', padding:'4px 8px', borderRadius:'var(--r-sm)',
        border:'1px solid var(--border)', background:'var(--surface)', fontSize:12.5, fontWeight:700, color:'var(--accent)'}}>
        {fmt?fmt(value):value}</span>
    </div>
  );
}
function ColorSwatches({colors, sel, onSel}){
  return (
    <div className="row gap8" style={{flexWrap:'wrap'}}>
      {colors.map(c=>(
        <span key={c} className="press" onClick={()=>onSel(c)} style={{width:24,height:24,borderRadius:'50%',background:c,
          border:(sel===c?'2.5px solid var(--accent)':'1px solid var(--border-subtle)'), cursor:'pointer'}}></span>
      ))}
    </div>
  );
}

/* ---------- 语言 ---------- */
function LanguageDetail({onBack}){
  const [sel, setSel] = useState('zh');
  const [ref, scrolled] = useScrolled();
  return (
    <div className="screen fade-in" data-screen-label="settings-language">
      <PageHead title="语言" onBack={onBack} scrolled={scrolled} center/>
      <div className="viewport" ref={ref} style={{padding:'14px 20px 28px'}}>
        <SectHead title="语言" desc="选择应用界面语言。"/>
        <div className="col gap10">
          {LANGUAGES.map(l=>{
            const on = sel===l.k;
            return (
              <div key={l.k} className="press" onClick={()=>setSel(l.k)} style={{display:'flex', alignItems:'center', gap:12,
                padding:'14px 16px', borderRadius:'var(--r-lg)', background:on?'var(--selected)':'var(--surface)',
                border:'1px solid '+(on?'var(--accent)':'var(--border-input)')}}>
                <div className="col" style={{flex:1, gap:2}}>
                  <span style={{fontSize:14.5, fontWeight:600, color:'var(--text-primary)'}}>{l.label}</span>
                  <span style={{fontSize:11.5, color:'var(--text-muted)'}}>{l.sub}</span>
                </div>
                {on && <I.checkCircle s={20} c="var(--accent)"/>}
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}

/* ---------- 主题 / 外观 ---------- */
function ThemePreview({t}){
  return (
    <div style={{width:64, height:48, borderRadius:'var(--r-md)', overflow:'hidden', flex:'0 0 auto',
      background:t.canvas, border:'1px solid var(--border-subtle)'}}>
      <div style={{height:16, background:t.accent}}></div>
      <div className="row gap4" style={{padding:4}}>
        <div style={{width:12, height:12, borderRadius:2, background:t.surface, border:'1px solid '+tint(t.text==='#000000'?'#000000':t.text,.12)}}></div>
        <div style={{flex:1, height:4, borderRadius:1, background:tint(t.text==='#000000'?'#000000':t.text,.3)}}></div>
      </div>
    </div>
  );
}
function AppearanceDetail({onBack}){
  const [ref, scrolled] = useScrolled();
  const [mode, setMode] = useState('light');
  const [theme, setTheme] = useState('reveric');
  const [bgColor, setBgColor] = useState('none');
  const [bgImg, setBgImg] = useState(null);

  const setAccent = (t)=>{
    setTheme(t.k);
    document.documentElement.style.setProperty('--accent', t.accent);
    document.documentElement.style.setProperty('--accent-warm', t.accent);
  };

  return (
    <div className="screen fade-in" data-screen-label="settings-appearance">
      <PageHead title="主题" onBack={onBack} scrolled={scrolled} center/>
      <div className="viewport" ref={ref} style={{padding:'16px 20px 28px'}}>
        <SectHead title="主题模式" desc="选择浅色、深色或跟随系统。"/>
        <div className="col gap8" style={{marginBottom:24}}>
          {THEME_MODES.map(m=>{
            const Cmp = I[m.icon]; const on = mode===m.k;
            return (
              <div key={m.k} className="press" onClick={()=>setMode(m.k)} style={{display:'flex', alignItems:'center', gap:12,
                padding:'13px 14px', borderRadius:'var(--r-lg)', background:on?'var(--selected)':'var(--canvas)',
                border:'1px solid '+(on?'var(--accent)':'var(--border-input)')}}>
                <Cmp s={22} c={on?'var(--accent)':'var(--text-secondary)'}/>
                <span style={{flex:1, fontSize:14, fontWeight:600, color:'var(--text-primary)'}}>{m.label}</span>
                {on && <I.checkCircle s={20} c="var(--accent)"/>}
              </div>
            );
          })}
        </div>

        <SectHead title="主题" desc="选择应用主题风格。"/>
        <div className="col gap8" style={{marginBottom:24}}>
          {THEMES.map(t=>{
            const on = theme===t.k;
            return (
              <div key={t.k} className="press" onClick={()=>setAccent(t)} style={{display:'flex', alignItems:'center', gap:12,
                padding:'12px 14px', borderRadius:'var(--r-lg)', background:on?'var(--selected)':'var(--canvas)',
                border:'1px solid '+(on?'var(--accent)':'var(--border-input)')}}>
                <ThemePreview t={t}/>
                <div className="col" style={{flex:1, gap:2, minWidth:0}}>
                  <span style={{fontSize:14, fontWeight:700, color:'var(--text-primary)'}}>{t.name}</span>
                  <span style={{fontSize:11.5, color:'var(--text-muted)', lineHeight:1.45}}>{t.desc}</span>
                </div>
                {on && <I.checkCircle s={20} c="var(--accent)" style={{flex:'0 0 auto'}}/>}
              </div>
            );
          })}
        </div>

        <SectHead title="应用背景" desc="为整个应用设置统一的背景颜色或图片。"/>
        <div className="card" style={{padding:'14px 14px'}}>
          <div style={{fontSize:12.5, fontWeight:600, color:'var(--text-primary)', marginBottom:9}}>背景颜色</div>
          <div className="row gap8" style={{flexWrap:'wrap', marginBottom:16}}>
            <span className="tchip" onClick={()=>{setBgColor('none'); setBgImg(null);}}
              style={bgColor==='none'&&!bgImg?{borderColor:'var(--accent)',background:'var(--selected)',color:'var(--text-primary)',fontWeight:600}:{}}>
              <span style={{width:14,height:14,borderRadius:3,background:'var(--surface-dim)',border:'1px solid var(--border)'}}></span>无</span>
            {THEMES.slice(0,7).map(t=>{
              const on = bgColor===t.k && !bgImg;
              return (
                <span key={t.k} className="tchip" onClick={()=>{setBgColor(t.k); setBgImg(null);}}
                  style={on?{borderColor:'var(--accent)',background:'var(--selected)',color:'var(--text-primary)',fontWeight:600}:{}}>
                  <span style={{width:14,height:14,borderRadius:3,background:t.accent}}></span>{t.name}</span>
              );
            })}
          </div>
          <div style={{height:1, background:'var(--border-subtle)', margin:'2px 0 14px'}}></div>
          <div style={{fontSize:12.5, fontWeight:600, color:'var(--text-primary)', marginBottom:9}}>内置图片</div>
          <div style={{display:'grid', gridTemplateColumns:'repeat(3,1fr)', gap:10}}>
            {BACKGROUNDS.map(b=>{
              const on = bgImg===b.k;
              return (
                <div key={b.k} className="press" onClick={()=>setBgImg(b.k)} style={{display:'flex', flexDirection:'column', gap:5}}>
                  <div style={{width:'100%', aspectRatio:'16/9', borderRadius:8, background:b.tint,
                    border:'2px solid '+(on?'var(--accent)':'transparent'), boxShadow:on?'0 2px 8px rgba(40,60,95,.3)':'inset 0 0 0 1px var(--border-subtle)'}}></div>
                  <span style={{fontSize:10.5, textAlign:'center', color:on?'var(--text-primary)':'var(--text-muted)', fontWeight:on?700:500}}>{b.name}</span>
                </div>
              );
            })}
          </div>
          <button className="btn-ghost press" style={{width:'100%', height:40, marginTop:14, borderStyle:'dashed', color:'var(--accent-warm)', fontWeight:600}}>
            <I.image s={16}/>选择自定义图片</button>
        </div>
      </div>
    </div>
  );
}

/* ---------- 编辑器 ---------- */
function EditorDetail({onBack}){
  const [ref, scrolled] = useScrolled();
  const [size, setSize] = useState(17);
  const [spacing, setSpacing] = useState(0.0);
  const [lineH, setLineH] = useState(1.9);
  const [entity, setEntity] = useState({italic:true, bold:false, underline:false, highlight:true});
  const [hl, setHl] = useState('#33FFD54F');
  const [indent, setIndent] = useState(2);
  const [paraSp, setParaSp] = useState('one');
  const [keepSp, setKeepSp] = useState(true);
  const [lineOn, setLineOn] = useState(true);
  const [lineStyle, setLineStyle] = useState('solid');
  const [lineColor, setLineColor] = useState('#FFFF0000');
  const tg = (k)=> setEntity(e=>({...e,[k]:!e[k]}));

  const hlPresets = ['#33FFD54F','#33FF8A65','#334FC3F7','#3381C784','#33BA68C8','#33F06292','#33A1887F','#335C6BC0'];
  const linePresets = ['#FFFF0000','#FF0000FF','#FF00AA00','#FFFF8800','#FF8800FF','#FF00CCCC','#FF444444','#FF000000'];
  const toCss = (h)=>{ // #AARRGGBB -> rgba
    if(h.length===9){const a=parseInt(h.slice(1,3),16)/255,r=parseInt(h.slice(3,5),16),g=parseInt(h.slice(5,7),16),b=parseInt(h.slice(7,9),16);return `rgba(${r},${g},${b},${a.toFixed(2)})`;}
    return h;
  };

  const Card = ({children}) => <div className="card" style={{padding:'4px 14px'}}>{children}</div>;
  const RowItem = ({label, desc, children, last}) => (
    <div style={{padding:'13px 0', borderBottom:last?'none':'1px solid var(--border-subtle)'}}>
      <div className="col" style={{gap:2, marginBottom:children?9:0}}>
        <span style={{fontSize:13.5, fontWeight:600, color:'var(--text-primary)'}}>{label}</span>
        {desc && <span style={{fontSize:11.5, color:'var(--text-muted)', lineHeight:1.5}}>{desc}</span>}
      </div>
      {children}
    </div>
  );

  return (
    <div className="screen fade-in" data-screen-label="settings-editor">
      <PageHead title="编辑器" onBack={onBack} scrolled={scrolled} center/>
      <div className="viewport" ref={ref} style={{padding:'16px 20px 28px'}}>
        {/* 字体 */}
        <SectHead title="编辑器" desc="配置编辑器的字体、间距和排版。"/>
        <Card>
          {/* preview */}
          <div style={{padding:'13px 0'}}>
            <div style={{border:'1px solid var(--border-subtle)', borderRadius:'var(--r-md)', padding:'14px 16px', background:'var(--surface-high)'}}>
              <div className="serif" style={{fontSize:size, lineHeight:lineH, letterSpacing:spacing, color:'var(--text-primary)'}}>The quick brown fox jumps over the lazy dog.</div>
              <div className="serif" style={{fontSize:size, lineHeight:lineH, letterSpacing:spacing, color:'var(--text-primary)', marginTop:6}}>秋风萧瑟天气凉，草木摇落露为霜。</div>
            </div>
          </div>
          <RowItem label="编辑器字体" desc="从系统字体中选择，或输入自定义字体名称。">
            <div className="row press" style={{height:42, padding:'0 13px', border:'1px solid var(--border-input)', borderRadius:'var(--r-lg)', background:'var(--surface-high)'}}>
              <span style={{flex:1, fontSize:14, color:'var(--text-primary)', fontFamily:'var(--serif)'}}>思源宋体 Source Han Serif</span>
              <I.caretD s={15} c="var(--text-subtle)"/>
            </div>
          </RowItem>
          <RowItem label="编辑器字号" desc="设置编辑器内容区域的文字大小。">
            <SettingSlider value={size} min={10} max={32} onChange={setSize}/>
          </RowItem>
          <RowItem label="字间距" desc="设置编辑器内容的字间距。">
            <SettingSlider value={spacing} min={0} max={4} step={0.1} fmt={v=>v.toFixed(1)} onChange={setSpacing}/>
          </RowItem>
          <RowItem label="行间距" desc="设置编辑器内容的行高。" last>
            <SettingSlider value={lineH} min={1.2} max={2.4} step={0.05} fmt={v=>v.toFixed(2)} onChange={setLineH}/>
          </RowItem>
        </Card>

        {/* 实体标记 */}
        <div style={{height:24}}></div>
        <SectHead title="实体标记" desc="配置正文中识别到角色、物品等实体时使用的行内样式。"/>
        <Card>
          <div style={{padding:'14px 0', borderBottom:entity.highlight?'1px solid var(--border-subtle)':'none'}}>
            <div className="row gap8" style={{flexWrap:'wrap'}}>
              <ToggleChip label="斜体" on={entity.italic} onTap={()=>tg('italic')}/>
              <ToggleChip label="粗体" on={entity.bold} onTap={()=>tg('bold')}/>
              <ToggleChip label="划线" on={entity.underline} onTap={()=>tg('underline')}/>
              <ToggleChip label="高亮" on={entity.highlight} onTap={()=>tg('highlight')}/>
            </div>
            {/* sample */}
            <div style={{marginTop:12, fontSize:14, color:'var(--text-secondary)'}}>例：
              <span style={{fontStyle:entity.italic?'italic':'normal', fontWeight:entity.bold?700:400,
                textDecoration:entity.underline?'underline':'none',
                background:entity.highlight?toCss(hl):'transparent', borderRadius:3, padding:'0 2px'}}>周清远</span>
              推开酒馆的门。</div>
          </div>
          {entity.highlight && (
            <RowItem label="高亮颜色" last>
              <ColorSwatches colors={hlPresets} sel={hl} onSel={setHl}/>
            </RowItem>
          )}
        </Card>

        {/* 自动排版 */}
        <div style={{height:24}}></div>
        <SectHead title="自动排版" desc="配置章节正文的自动排版行为。"/>
        <Card>
          <RowItem label="段首缩进" desc="每段开头的全角空格数量（0–8）。">
            <SettingSlider value={indent} min={0} max={8} onChange={setIndent}/>
          </RowItem>
          <RowItem label="段落间距" desc="段落之间是否插入一个空行。">
            <div className="row gap8">
              <ToggleChip label="不空行" on={paraSp==='none'} onTap={()=>setParaSp('none')}/>
              <ToggleChip label="空一行" on={paraSp==='one'} onTap={()=>setParaSp('one')}/>
            </div>
          </RowItem>
          <RowItem label="保留空格" desc="关闭后将移除所有空格；开启后规范中英文间距。" last>
            <Switch on={keepSp} onToggle={()=>setKeepSp(v=>!v)}/>
          </RowItem>
        </Card>

        {/* 线条标注 */}
        <div style={{height:24}}></div>
        <div className="row" style={{justifyContent:'space-between', alignItems:'flex-start', marginBottom:14, padding:'0 2px'}}>
          <div className="col" style={{gap:3, flex:1}}>
            <span style={{fontSize:14, fontWeight:700, color:'var(--text-primary)'}}>线条标注</span>
            <span style={{fontSize:12, color:'var(--text-muted)', lineHeight:1.5}}>配置编辑器线条标注的显示、风格和颜色。</span>
          </div>
          <Switch on={lineOn} onToggle={()=>setLineOn(v=>!v)}/>
        </div>
        <Card>
          <RowItem label="线条风格">
            <div className="row gap8" style={{flexWrap:'wrap'}}>
              {[['solid','实线'],['sparse','稀疏虚线'],['dense','密集虚线']].map(([k,l])=>(
                <ToggleChip key={k} label={l} on={lineStyle===k} onTap={()=>setLineStyle(k)} disabled={!lineOn}/>
              ))}
            </div>
          </RowItem>
          <RowItem label="线条颜色" last>
            <div style={{opacity:lineOn?1:.5, pointerEvents:lineOn?'auto':'none'}}>
              <ColorSwatches colors={linePresets} sel={lineColor} onSel={setLineColor}/>
            </div>
          </RowItem>
        </Card>
      </div>
    </div>
  );
}

/* ---------- AI 提供商 ---------- */
function ProvidersScreen({onBack}){
  const [ref, scrolled] = useScrolled();
  const tone = (k)=> k==='ok'?{c:'var(--success)',bg:'rgba(74,124,89,.12)'}:{c:'var(--warning)',bg:'rgba(217,119,6,.12)'};
  return (
    <div className="screen fade-in" data-screen-label="providers">
      <PageHead title="AI 提供商" onBack={onBack} scrolled={scrolled} center right={<IconBtn icon="plus"/>}/>
      <div className="viewport" ref={ref} style={{padding:'12px 18px 28px'}}>
        <p style={{margin:'0 0 14px', fontSize:12.5, color:'var(--text-muted)', lineHeight:1.65, padding:'0 4px'}}>
          主笔智能体会从已连接的提供商中，按你设定的优先级选择模型。</p>
        <div className="col gap10">
          {PROVIDERS.map(p=>{
            const tn = tone(p.kind);
            return (
              <div key={p.name} className="card" style={{padding:'13px 14px', display:'flex', gap:12, alignItems:'center'}}>
                <div style={{width:40,height:40,borderRadius:10,flex:'0 0 auto',background:'rgba(76,110,145,.12)',color:'var(--info)',display:'flex',alignItems:'center',justifyContent:'center'}}><I.brain s={20}/></div>
                <div className="col" style={{flex:1, gap:2, minWidth:0}}>
                  <span style={{fontSize:14.5, fontWeight:700}}>{p.name}</span>
                  <span style={{fontSize:11.5, color:'var(--text-muted)'}}>{p.model}</span>
                </div>
                <div className="col" style={{alignItems:'flex-end', gap:6}}>
                  <span className="chip" style={{height:20,fontSize:10.5,padding:'0 8px',color:tn.c,background:tn.bg,fontWeight:600}}>{p.state}</span>
                  <button className="btn-ghost press" style={{height:28, padding:'0 12px', fontSize:12}}>配置</button>
                </div>
              </div>
            );
          })}
        </div>
        <button className="btn-ghost press"
          style={{width:'100%', height:44, marginTop:14, borderStyle:'dashed', color:'var(--accent-warm)', fontWeight:600}}>
          <I.plus s={16}/>添加自定义提供商
        </button>
      </div>
    </div>
  );
}

/* ---------- 用量统计（对齐桌面端 usage.jsx） ---------- */
const USAGE_BD = {input:'var(--accent)', cacheRead:'var(--success)', cacheWrite:'var(--accent-warm)', output:'var(--text-muted)'};
function UsageScreen({onBack}){
  const [ref, scrolled] = useScrolled();
  const t = USAGE.today, m = USAGE.month;
  const H = 100;
  return (
    <div className="screen fade-in" data-screen-label="settings-usage">
      <PageHead title="用量" onBack={onBack} scrolled={scrolled} center/>
      <div className="viewport" ref={ref} style={{padding:'14px 20px 28px'}}>
        <div className="row gap10" style={{marginBottom:18}}>
          {[['本日',t.total,t.requests],['本月',m.total,null]].map(([label,total,req],i)=>(
            <div key={i} className="card" style={{flex:1, padding:14}}>
              <span style={{fontSize:12, color:'var(--text-muted)', fontWeight:600}}>{label}</span>
              <div className="row gap4" style={{alignItems:'baseline', margin:'6px 0 4px'}}>
                <span className="serif" style={{fontSize:20, fontWeight:700}}>{fmt(total)}</span>
                <span style={{fontSize:11, color:'var(--text-subtle)'}}>词元</span>
              </div>
              {req!==null && <span style={{fontSize:11, color:'var(--text-subtle)'}}>{req} 次请求</span>}
              {req===null && <span style={{fontSize:11, color:m.trendUp?'var(--warning)':'var(--success)'}}>{m.trendUp?'↑':'↓'} 较上月 {m.trend}</span>}
            </div>
          ))}
        </div>
        <div className="card" style={{padding:14, marginBottom:18}}>
          <div style={{fontSize:13, fontWeight:700, marginBottom:4}}>每日词元用量</div>
          <div style={{fontSize:11, color:'var(--text-muted)', marginBottom:12}}>过去 30 天</div>
          <div className="row gap8" style={{marginBottom:10, flexWrap:'wrap'}}>
            {[['输入',USAGE_BD.input],['缓存读取',USAGE_BD.cacheRead],['缓存写入',USAGE_BD.cacheWrite],['输出',USAGE_BD.output]].map(([l,c])=>(
              <div key={l} className="row gap4" style={{alignItems:'center'}}><span style={{width:8,height:8,borderRadius:2,background:c}}/><span style={{fontSize:10, color:'var(--text-muted)'}}>{l}</span></div>
            ))}
          </div>
          <div style={{display:'flex', gap:2, alignItems:'flex-end', height:H}}>
            {[0.3,0.5,0.7,0.4,0.6,0.8,0.35,0.55,0.65,0.45,0.75,0.9,0.5,0.6,0.4,0.7,0.55,0.85,0.45,0.65,0.5,0.7,0.4,0.6,0.8,0.35,0.55,0.7,0.45,0.6].map((v,i)=>(
              <div key={i} style={{flex:1, display:'flex', flexDirection:'column', gap:0}}>
                <div style={{height:v*H*0.4, background:USAGE_BD.input, borderRadius:'2px 2px 0 0'}}/>
                <div style={{height:v*H*0.2, background:USAGE_BD.cacheRead}}/>
                <div style={{height:v*H*0.1, background:USAGE_BD.cacheWrite}}/>
                <div style={{height:v*H*0.3, background:USAGE_BD.output, borderRadius:'0 0 2px 2px'}}/>
              </div>
            ))}
          </div>
        </div>
        <SectHead title="用量明细" desc="每次请求的词元消耗"/>
        <div className="col gap8">
          {USAGE.records.map((r,i)=>(
            <div key={i} className="card" style={{padding:'10px 12px', display:'flex', gap:10, alignItems:'center'}}>
              <div className="col" style={{flex:1, gap:2, minWidth:0}}>
                <span style={{fontSize:13, fontWeight:600}}>{r.model}</span>
                <span style={{fontSize:11, color:'var(--text-muted)'}}>{r.time}</span>
              </div>
              <div className="row gap8" style={{flex:'0 0 auto'}}>
                <span style={{fontSize:12, color:'var(--text-muted)'}}>入 {fmt(r.input)}</span>
                <span style={{fontSize:12, color:'var(--text-muted)'}}>出 {fmt(r.output)}</span>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { SettingsScreen, LanguageDetail, AppearanceDetail, EditorDetail, ProvidersScreen, UsageScreen });
