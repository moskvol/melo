import { useCallback, useEffect, useId, useRef, useState } from 'react'
import type { FormEvent, ChangeEvent, ReactNode, CSSProperties } from 'react'
import { createPortal } from 'react-dom'
import type { User } from '@supabase/supabase-js'
import { AnimatePresence, motion } from 'motion/react'
import { avatarUrl, configured, date, db, displayName, errorText, initials, loadChats, loadMessages, loadReactions, searchProfiles, time, uploadAvatar, uploadChatFile } from './lib'
import type { Chat, Message, Profile, Reaction } from './lib'

type Page = 'chats' | 'contacts' | 'search' | 'profile' | 'settings' | 'admin' | 'community'
type AuthMode = 'login' | 'register' | 'reset' | 'update' | 'otp' | 'otp_verify' | 'signup_verify'
type Dialog = 'new' | 'group' | 'manage' | 'forward' | 'deleteAccount' | 'organize' | null
const accents = ['#6558b8', '#276d84', '#9b466d', '#437549', '#a45f22']

function Icon({ name, size = 24, filled = false }: { name: string; size?: number; filled?: boolean }) {
  return <span className="material-symbols-rounded" style={{ fontSize: size, fontVariationSettings: `'FILL' ${filled ? 1 : 0}` }} aria-hidden="true">{name}</span>
}
type SocialProfile = Profile & {plus?:boolean;rare_badge?:string;banner_path?:string|null;frame?:string}
const rareBadgeInfo: Record<string,{name:string;description:string;icon:string;color:string}> = {
  founder:{name:'Основатель',description:'Почётный значок за вклад в создание Melo.',icon:'workspace_premium',color:'#d89b37'},
  developer:{name:'Разработчик',description:'Значок участника команды разработки Melo.',icon:'code',color:'#55a69a'},
  tester:{name:'Тестировщик',description:'За помощь в тестировании и улучшении Melo.',icon:'science',color:'#9b83e9'},
  legend:{name:'Легенда',description:'Редкая награда за особый вклад в сообщество Melo.',icon:'star',color:'#d89b37'}
}
function BadgeHint({name,description,children,style}:{name:string;description:string;children:ReactNode;style?:CSSProperties}) {
  const ref=useRef<HTMLSpanElement>(null)
  const id=useId()
  const [position,setPosition]=useState<{left:number;top:number;above:boolean;width:number}|null>(null)
  const [pinned,setPinned]=useState(false)
  const show=()=>{const rect=ref.current?.getBoundingClientRect();if(!rect)return;const width=Math.min(260,window.innerWidth-24);const above=rect.bottom+140>window.innerHeight&&rect.top>140;setPosition({left:Math.max(12,Math.min(rect.left+rect.width/2-width/2,window.innerWidth-width-12)),top:above?rect.top-9:rect.bottom+9,above,width})}
  const hide=()=>{setPosition(null);setPinned(false)}
  useEffect(()=>{if(!position)return;const outside=(e:PointerEvent)=>{if(!ref.current?.contains(e.target as Node))hide()};const key=(e:KeyboardEvent)=>{if(e.key==='Escape')hide()};document.addEventListener('pointerdown',outside);document.addEventListener('keydown',key);window.addEventListener('resize',hide);window.addEventListener('scroll',hide,true);return()=>{document.removeEventListener('pointerdown',outside);document.removeEventListener('keydown',key);window.removeEventListener('resize',hide);window.removeEventListener('scroll',hide,true)}},[position])
  return <><span ref={ref} tabIndex={0} role="button" aria-label={name+': '+description} aria-describedby={position?id:undefined} onPointerEnter={e=>{if(e.pointerType==='mouse')show()}} onPointerLeave={e=>{if(e.pointerType==='mouse'&&!pinned)hide()}} onFocus={show} onBlur={hide} onClick={e=>{e.preventDefault();e.stopPropagation();if(pinned)hide();else{show();setPinned(true)}}} onKeyDown={e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();e.stopPropagation();if(pinned)hide();else{show();setPinned(true)}}}} style={{display:'inline-flex',flex:'none',alignItems:'center',verticalAlign:'middle',marginInlineStart:4,cursor:'help',...style}}>{children}</span>{position&&createPortal(<div style={{position:'fixed',left:position.left,top:position.top,width:position.width,transform:position.above?'translateY(-100%)':undefined,zIndex:1000,pointerEvents:'none'}}><motion.div id={id} role="tooltip" initial={{opacity:0,scale:.94}} animate={{opacity:1,scale:1}} transition={{type:'spring',stiffness:400,damping:28}} style={{background:'var(--surface-high)',color:'var(--on-surface)',border:'1px solid var(--outline)',borderRadius:20,padding:'12px 15px',boxShadow:'0 8px 26px #0003',textAlign:'left',whiteSpace:'normal',overflowWrap:'anywhere'}}><div style={{fontWeight:750,fontSize:15,marginBottom:5}}>{name}</div><div style={{fontSize:13,lineHeight:1.45,fontWeight:400,color:'var(--on-surface)'}}>{description}</div></motion.div></div>,document.body)}</>
}
function Awards({profile}:{profile?:Profile|null}) {
  const p=profile as SocialProfile|undefined|null
  const rare=p?.rare_badge?rareBadgeInfo[p.rare_badge]:undefined
  return <>{p?.plus&&<BadgeHint name="Melo Plus" description="Особый статус, выданный администрацией Melo." style={{color:'#a47cfa'}}><Icon name="diamond" filled size={19}/></BadgeHint>}{rare&&<BadgeHint name={rare.name} description={rare.description} style={{color:rare.color}}><Icon name={rare.icon} filled size={19}/></BadgeHint>}</>
}
function Verified({profile}:{profile?:Profile|null}) {
  const p=profile as (Profile & {verified?:boolean;is_melo_admin?:boolean})|null|undefined
  return <>{p?.verified&&<BadgeHint name="Подтверждённый аккаунт" description="Этот аккаунт получил синюю галочку от администрации Melo." style={{color:'#2196f3'}}><Icon name="verified" filled size={19}/></BadgeHint>}{p?.is_melo_admin&&<BadgeHint name="Администратор Melo" description="Участник администрации Melo с правами управления пользователями и наградами." style={{marginInlineStart:6,backgroundColor:'#C62828',color:'#FFFFFF',borderRadius:7,padding:'3px 7px',fontSize:11,fontWeight:700,lineHeight:'14px',whiteSpace:'nowrap'}}>Админ</BadgeHint>}</>
}
function Avatar({ name, path, size = 48, group = false }: { name: string; path?: string | null; size?: number; group?: boolean }) {
  const src = avatarUrl(path)
  return <div className={`avatar ${group ? 'avatar-group' : ''}`} style={{ width: size, height: size, fontSize: size * .32 }}>
    {src ? <img src={src} alt="" /> : group ? <Icon name="groups" size={size * .5} /> : initials(name)}
  </div>
}
function Button({ icon, children, onClick, title, className = '', disabled = false, type = 'button' }: { icon?: string; children?: React.ReactNode; onClick?: () => void; title?: string; className?: string; disabled?: boolean; type?: 'button' | 'submit' }) {
  return <button type={type} disabled={disabled} title={title} className={`button ${className}`} onClick={onClick}>{icon && <Icon name={icon} />}{children}</button>
}
function Loader() { return <div className="loader" aria-label="Загрузка"><i/><i/><i/><i/></div> }

function Auth({ onNotice, recovery = false, onRecoveryDone }: { onNotice: (s: string) => void; recovery?: boolean; onRecoveryDone?: () => void }) {
  const [mode, setMode] = useState<AuthMode>(recovery ? 'update' : 'login')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [name, setName] = useState('')
  const [otpCode, setOtpCode] = useState('')
  const [busy, setBusy] = useState(false)
  const [resendCooldown, setResendCooldown] = useState(0)
  useEffect(() => { if (resendCooldown <= 0) return; const timer = setTimeout(() => setResendCooldown(value => Math.max(0, value - 1)), 1000); return () => clearTimeout(timer) }, [resendCooldown])
  const [error, setError] = useState('')
  async function submit(e: FormEvent) {
    e.preventDefault(); if (!db) return
    setBusy(true); setError('')
    try {
      if (mode === 'register') {
        const { data, error } = await db.auth.signUp({ email, password, options: { data: { first_name: name }, emailRedirectTo: window.location.href.split('#')[0] } })
        if (error) throw error
        if (!data.session) { setOtpCode(''); setPassword(''); setMode('signup_verify'); setResendCooldown(30); onNotice('Код подтверждения отправлен на почту') }
      } else if (mode === 'login') {
        const { error } = await db.auth.signInWithPassword({ email, password }); if (error) throw error
      } else if (mode === 'otp') {
        const { error } = await db.auth.signInWithOtp({ email: email.trim(), options: { shouldCreateUser: false } })
        if (error) throw error
        setOtpCode(''); setMode('otp_verify'); setResendCooldown(30); onNotice('Код отправлен на почту')
      } else if (mode === 'otp_verify' || mode === 'signup_verify') {
        const { error } = await db.auth.verifyOtp({ email: email.trim(), token: otpCode, type: mode === 'signup_verify' ? 'signup' : 'email' })
        if (error) throw error
      } else if (mode === 'reset') {
        const { error } = await db.auth.resetPasswordForEmail(email, { redirectTo: window.location.href.split('#')[0] })
        if (error) throw error
        onNotice('Ссылка для восстановления отправлена на почту'); setMode('login')
      } else {
        const { error } = await db.auth.updateUser({ password }); if (error) throw error
        onNotice('Пароль обновлён'); setMode('login'); onRecoveryDone?.()
      }
    } catch (x) { setError(errorText(x)) } finally { setBusy(false) }
  }
  const verifying = mode === 'otp_verify' || mode === 'signup_verify'
  async function resendCode() {
    if (!db || busy || !verifying || resendCooldown > 0) return
    setBusy(true); setError('')
    try {
      const result = mode === 'signup_verify' ? await db.auth.resend({ type: 'signup', email: email.trim() }) : await db.auth.signInWithOtp({ email: email.trim(), options: { shouldCreateUser: false } })
      if (result.error) throw result.error
      setOtpCode(''); setResendCooldown(30); onNotice('Новый код отправлен на почту')
    } catch (x) { setError(errorText(x)) } finally { setBusy(false) }
  }
  return <div className="auth-page"><div className="auth-art"><div className="brand-mark"><Icon name="chat_bubble" size={32} filled /></div><h1>Ближе,<br/>чем кажется.</h1><p>Добро пожаловать в Melo. Место для разговоров, которые важны.</p><div className="art-bubbles"><span>Привет! 👋</span><span>Как твой день?</span><span>Лучше, когда мы на связи 💜</span></div></div>
    <motion.div className="auth-card" initial={{ opacity: 0, y: 24 }} animate={{ opacity: 1, y: 0 }} transition={{ type: 'spring', stiffness: 210, damping: 22 }}>
      <div className="mobile-logo"><div className="brand-mark"><Icon name="chat_bubble" size={28} filled /></div><b>Melo</b></div>
      <h2>{mode === 'register' ? 'Создать аккаунт' : mode === 'reset' ? 'Восстановить пароль' : mode === 'update' ? 'Новый пароль' : mode === 'otp' ? 'Вход по коду' : verifying ? 'Введите код' : 'С возвращением'}</h2>
      <p className="muted">{mode === 'register' ? 'Начните общение за пару минут' : mode === 'reset' ? 'Отправим ссылку на вашу почту' : mode === 'update' ? 'Придумайте новый надёжный пароль' : mode === 'otp' ? 'Пришлём одноразовый код на вашу почту' : verifying ? `Введите код из письма, отправленного на ${email}` : 'Продолжим с того места, где остановились'}</p>
      <form onSubmit={submit} className="auth-form">
        {mode === 'register' && <label>Имя<input required maxLength={50} value={name} onChange={e => setName(e.target.value)} placeholder="Как к вам обращаться" /></label>}
        {mode !== 'update' && !verifying && <label>Электронная почта<input required type="email" autoComplete="email" value={email} onChange={e => setEmail(e.target.value)} placeholder="you@example.com" /></label>}
        {verifying && <label>Код из письма<input required type="text" inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6,8}" maxLength={8} value={otpCode} onChange={e => setOtpCode(e.target.value.replace(/\D/g, ''))} placeholder="000000" /></label>}
        {['login', 'register', 'update'].includes(mode) && <label>Пароль<input required type="password" minLength={6} autoComplete={mode === 'login' ? 'current-password' : 'new-password'} value={password} onChange={e => setPassword(e.target.value)} placeholder="Не менее 6 символов" /></label>}
        {error && <div className="error" role="alert">{error}</div>}
        <Button type="submit" className="primary full" disabled={busy}>{busy ? 'Подождите…' : mode === 'register' ? 'Создать аккаунт' : mode === 'reset' ? 'Отправить ссылку' : mode === 'update' ? 'Сохранить пароль' : mode === 'otp' ? 'Отправить код' : verifying ? 'Подтвердить код' : 'Войти'}<Icon name="arrow_forward" /></Button>
      </form>
      <div className="auth-links">{verifying && <button disabled={busy || resendCooldown > 0} onClick={resendCode}>{resendCooldown > 0 ? `Отправить код повторно через ${resendCooldown} сек.` : 'Отправить код повторно'}</button>}{mode === 'login' ? <><button onClick={() => setMode('otp')}>Войти по коду из письма</button><button onClick={() => setMode('reset')}>Забыли пароль?</button><span>Нет аккаунта? <button onClick={() => setMode('register')}>Регистрация</button></span></> : <button onClick={() => { setError(''); setMode('login') }}>Вернуться ко входу</button>}</div>
    </motion.div>
  </div>
}

function App() {
  const [user, setUser] = useState<User | null>(null)
  const [recovery, setRecovery] = useState(window.location.hash.includes('type=recovery'))
  const [booting, setBooting] = useState(true)
  const [profile, setProfile] = useState<Profile | null>(null)
  const [chats, setChats] = useState<Chat[]>([])
  const [selected, setSelected] = useState<string | null>(null)
  const [messages, setMessages] = useState<Message[]>([])
  const [reactions, setReactions] = useState<Reaction[]>([])
  const [people, setPeople] = useState<Record<string, Profile>>({})
  const [fileUrls, setFileUrls] = useState<Record<string, string>>({})
  const [siteAdmin, setSiteAdmin] = useState(false)
  useEffect(() => { let active = true; setSiteAdmin(false); if (user && db) db.from('melo_admins').select('user_id').eq('user_id', user.id).maybeSingle().then(({data}) => { if(active) setSiteAdmin(Boolean(data)) }); return () => { active = false } }, [user?.id])
  const [page, setPage] = useState<Page>('chats')
  const [dialog, setDialog] = useState<Dialog>(null)
  const [notice, setNotice] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [query, setQuery] = useState('')
  const [results, setResults] = useState<Profile[]>([])
  const [chatSearch, setChatSearch] = useState('')
  const [folderFilter,setFolderFilter]=useState('')
  const [messageMenu,setMessageMenu]=useState<string|null>(null)
  const [recording,setRecording]=useState(false)
  const [recordSeconds,setRecordSeconds]=useState(0)
  useEffect(()=>{if(!recording)return;const id=setInterval(()=>setRecordSeconds(v=>v+1),1000);return()=>clearInterval(id)},[recording])
  const [draft, setDraft] = useState('')
  const [reply, setReply] = useState<Message | null>(null)
  const [forward, setForward] = useState<Message | null>(null)
  const [typing, setTyping] = useState(false)
  const [theme, setTheme] = useState(localStorage.getItem('melo-theme') || 'system')
  const [accent, setAccent] = useState(localStorage.getItem('melo-accent') || accents[0])
  const [fontSize, setFontSize] = useState(Number(localStorage.getItem('melo-font') || 16))
  const [notifications, setNotifications] = useState(localStorage.getItem('melo-notifications') === 'true' && 'Notification' in window && Notification.permission === 'granted')
  const [sounds, setSounds] = useState(localStorage.getItem('melo-sounds') !== 'false')
  const [online, setOnline] = useState(navigator.onLine)
  const [mobileOpen, setMobileOpen] = useState(false)
  const endRef = useRef<HTMLDivElement>(null)
  const typingChannel = useRef<ReturnType<NonNullable<typeof db>['channel']> | null>(null)
  const recordRef = useRef<MediaRecorder | null>(null)
  const discardRecording=useRef(false)
  const requestingMic=useRef(false)
  const typingTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const inviteHandled = useRef(false)
  const dialogFocus = useRef<HTMLElement | null>(null)

  const unreadTotal=chats.reduce((n,c)=>n+c.unread,0)
  const folderNames=[...new Set(chats.map(c=>(c.members.find(m=>m.user_id===user?.id) as {folder?:string}|undefined)?.folder).filter((f):f is string=>Boolean(f)))]
  const visibleChats=chats.filter(x=>{const own=x.members.find(m=>m.user_id===user?.id) as {archived?:boolean;folder?:string}|undefined;return (folderFilter==='__archive'?own?.archived:!own?.archived&&(!folderFilter||own?.folder===folderFilter))&&(!query||(x.kind==='group'?x.name:displayName(x.peer))?.toLowerCase().includes(query.toLowerCase())||x.peer?.username.includes(query.toLowerCase().replace(/^@/,'')))})
  const chat = chats.find(x => x.id === selected)
  const chatName = chat?.kind === 'group' ? chat.name || 'Группа' : displayName(chat?.peer)
  const myMember = chat?.members.find(x => x.user_id === user?.id)
  const isAdmin = myMember?.role === 'admin' || myMember?.role === 'owner'
  const canPost = !chat?.only_admins_can_post || isAdmin

  const refreshChats = useCallback(async () => {
    if (!user) return
    try { setChats(await loadChats(user.id)) } catch (x) { setError(errorText(x)) }
  }, [user])
  const refreshMessages = useCallback(async (id: string) => {
    try { const rows = await loadMessages(id); setMessages(rows); setReactions(await loadReactions(rows.map(x => x.id))) } catch (x) { setError(errorText(x)) }
  }, [])

  useEffect(() => {
    if (!db) { setBooting(false); return }
    db.auth.getSession().then(({ data }) => { setUser(data.session?.user || null); setBooting(false) })
    const { data: { subscription } } = db.auth.onAuthStateChange((event, session) => {
      setUser(session?.user || null)
      if (event === 'PASSWORD_RECOVERY') setRecovery(true)
    })
    return () => subscription.unsubscribe()
  }, [])
  useEffect(() => {
    const onOnline = () => setOnline(true), onOffline = () => setOnline(false)
    window.addEventListener('online', onOnline); window.addEventListener('offline', onOffline)
    return () => { window.removeEventListener('online', onOnline); window.removeEventListener('offline', onOffline) }
  }, [])
  useEffect(() => {
    document.documentElement.dataset.theme = theme
    document.documentElement.style.setProperty('--accent', accent)
    document.documentElement.style.setProperty('--message-size', `${fontSize}px`)
    localStorage.setItem('melo-theme', theme); localStorage.setItem('melo-accent', accent); localStorage.setItem('melo-font', String(fontSize))
  }, [theme, accent, fontSize])
  useEffect(() => {
    if (!user || !db) { setProfile(null); setChats([]); return }
    db.from('profiles').select('*').eq('id', user.id).single().then(({ data, error }) => { if (error) setError(error.message); else setProfile(data as Profile) })
    refreshChats()
    const listInterval = setInterval(refreshChats, 60000)
    const handleMessage = (payload: { new: Record<string, unknown>; old: Record<string, unknown>; eventType: string }) => {
        refreshChats()
        const incoming = payload.new as unknown as Message
        const id = incoming.conversation_id || (payload.old as { conversation_id?: string }).conversation_id
        if (id && id === selected) {
          refreshMessages(id)
          if (payload.eventType === 'INSERT' && incoming.sender_id !== user.id) db?.from('conversation_members').update({ last_read_at: new Date().toISOString() }).eq('conversation_id', id).eq('user_id', user.id).then(() => refreshChats())
        }
        if (payload.eventType === 'INSERT' && incoming.sender_id !== user.id && id !== selected && notifications && 'Notification' in window && Notification.permission === 'granted') new Notification('Новое сообщение в Melo', { body: 'Откройте Melo, чтобы прочитать сообщение', icon: `${import.meta.env.BASE_URL}icon-192.png` })
        if (payload.eventType === 'INSERT' && incoming.sender_id !== user.id && sounds) { try { const audio = new AudioContext(); const oscillator = audio.createOscillator(); const gain = audio.createGain(); oscillator.connect(gain); gain.connect(audio.destination); oscillator.frequency.value = 660; gain.gain.value = .035; oscillator.start(); oscillator.stop(audio.currentTime + .07); oscillator.onended = () => audio.close() } catch { /* Browser may block audio until interaction. */ } }
    }
    const channel = db.channel(`changes-${user.id}`, { config: { private: true } })
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'messages' }, handleMessage)
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'messages' }, handleMessage)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'conversation_members' }, () => refreshChats())
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'conversation_members' }, () => refreshChats())
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'conversations' }, () => refreshChats())
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'conversations' }, () => { refreshChats(); if (selected) refreshMessages(selected) })
      .subscribe()
    return () => { clearInterval(listInterval); db?.removeChannel(channel) }
  }, [user?.id, selected, refreshChats, refreshMessages, notifications, sounds])
  useEffect(() => {
    if (!user || !db) return
    const update = () => { if (document.visibilityState === 'visible') db?.from('profiles').update({ last_seen_at: new Date().toISOString() }).eq('id', user.id).then(() => {}) }
    update(); const interval = setInterval(update, 60000)
    document.addEventListener('visibilitychange', update)
    return () => { clearInterval(interval); document.removeEventListener('visibilitychange', update) }
  }, [user?.id])
  useEffect(() => {
    if (!user || !db || inviteHandled.current || !window.location.hash.startsWith('#invite=')) return
    inviteHandled.current = true
    const invite = window.location.hash.slice(8)
    db.rpc('join_group', { invite }).then(async ({ data, error }) => { if (error) setError(error.message); else { await refreshChats(); openChat(data as string); setNotice('Вы присоединились к группе') } history.replaceState(null, '', window.location.pathname + window.location.search) })
  }, [user?.id, refreshChats])
  useEffect(() => {
    if (!selected || !db || !user) { setMessages([]); return }
    refreshMessages(selected)
    const messageInterval = setInterval(() => refreshMessages(selected), 60000)
    setDraft(sessionStorage.getItem(`melo-draft-${selected}`) || '')
    setReply(null); setChatSearch('')
    db.from('conversation_members').update({ last_read_at: new Date().toISOString() }).eq('conversation_id', selected).eq('user_id', user.id).then(() => refreshChats())
    const ch = db.channel(`typing-${selected}`, { config: { private: true, broadcast: { self: false } } })
      .on('broadcast', { event: 'typing' }, () => { setTyping(true); if (typingTimer.current) clearTimeout(typingTimer.current); typingTimer.current = setTimeout(() => setTyping(false), 2500) }).subscribe()
    typingChannel.current = ch
    return () => { clearInterval(messageInterval); db?.removeChannel(ch); typingChannel.current = null }
  }, [selected, user?.id, refreshMessages])
  useEffect(() => { endRef.current?.scrollIntoView({ behavior: 'smooth' }) }, [messages.length, selected])
  useEffect(() => {
    if (!chat || !db) return
    const ids = chat.members.map(x => x.user_id)
    db.from('profiles').select('*').in('id', ids).then(({ data }) => { if (data) setPeople(Object.fromEntries(data.map(p => [p.id, p as Profile]))) })
  }, [chat?.id, chat?.members.length])
  useEffect(() => {
    if (!db) return
    const paths = messages.filter(x => x.attachment_path).map(x => x.attachment_path!)
    Promise.all(paths.map(async path => { const { data } = await db!.storage.from('chat-files').createSignedUrl(path, 3600); return [path, data?.signedUrl || ''] as const }))
      .then(entries => setFileUrls(Object.fromEntries(entries)))
  }, [messages])
  useEffect(() => {
    if (!query.trim()) { setResults([]); return }
    const timer = setTimeout(() => { searchProfiles(query).then(setResults).catch(x => setError(errorText(x))) }, 250)
    return () => clearTimeout(timer)
  }, [query])
  useEffect(() => { if (notice) { const t = setTimeout(() => setNotice(''), 4500); return () => clearTimeout(t) } }, [notice])
  useEffect(() => {
    if (!dialog) return
    dialogFocus.current = document.activeElement as HTMLElement
    const frame = requestAnimationFrame(() => document.querySelector<HTMLElement>('.dialog input:not([type=file]), .dialog button:not(.dialog-close)')?.focus())
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setDialog(null)
      if (event.key !== 'Tab') return
      const items = [...document.querySelectorAll<HTMLElement>('.dialog button:not([disabled]), .dialog input:not([disabled]):not([type=file]), .dialog textarea:not([disabled])')].filter(x => x.offsetParent !== null)
      if (!items.length) return
      const first = items[0], last = items[items.length - 1]
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus() }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus() }
    }
    document.addEventListener('keydown', onKey)
    return () => { cancelAnimationFrame(frame); document.removeEventListener('keydown', onKey); dialogFocus.current?.focus() }
  }, [dialog])

  async function run(action: () => Promise<unknown>, success?: string) {
    setBusy(true); setError('')
    try { await action(); if (success) setNotice(success) } catch (x) { setError(errorText(x)) } finally { setBusy(false) }
  }
  function cancelRecording(){discardRecording.current=true;if(recordRef.current?.state==='recording')recordRef.current.stop();setRecording(false)}
  function openChat(id: string) { if(id!==selected)cancelRecording();setSelected(id); setPage('chats'); setDialog(null); setMobileOpen(true); setMessageMenu(null); setChatSearch('') }
  function navigate(id:Page){cancelRecording();setPage(id);setMobileOpen(false);setQuery('');setMessageMenu(null)}
  async function startDirect(p: Profile) {
    if (!db) return
    await run(async () => { const { data, error } = await db!.rpc('create_direct_chat', { other_user: p.id }); if (error) throw error; await refreshChats(); openChat(data as string) })
  }
  async function sendMessage(e?: FormEvent) {
    e?.preventDefault(); if (!db || !user || !selected || !canPost || !draft.trim() || busy) return
    const body = draft.trim()
    await run(async () => {
      const { error } = await db!.from('messages').insert({ conversation_id: selected, sender_id: user.id, body, reply_to_id: reply?.id || null })
      if (error) throw error
      setDraft(''); sessionStorage.removeItem(`melo-draft-${selected}`); setReply(null)
      await refreshMessages(selected); await refreshChats()
    })
  }
  async function sendFile(file: File, forcedKind?: Message['kind']) {
    if (!db || !user || !selected || !canPost) return
    await run(async () => {
      const path = await uploadChatFile(selected, user.id, file)
      const kind = forcedKind || (file.type.startsWith('image/') ? 'image' : file.type.startsWith('video/') ? 'video' : 'file')
      const { error } = await db!.from('messages').insert({ conversation_id: selected, sender_id: user.id, body: file.name, kind, attachment_path: path, attachment_name: file.name, attachment_mime: file.type, reply_to_id: reply?.id || null })
      if (error) { await db!.storage.from('chat-files').remove([path]); throw error }
      setReply(null); await refreshMessages(selected); await refreshChats()
    }, 'Файл отправлен')
  }
  async function recordVoice() {
    if (recordRef.current?.state === 'recording') { recordRef.current.stop(); return }
    if(requestingMic.current||recordRef.current)return
    requestingMic.current=true;discardRecording.current=false
    let stream:MediaStream|undefined
    try {
      stream = await navigator.mediaDevices.getUserMedia({ audio: true })
      if(discardRecording.current){stream.getTracks().forEach(t=>t.stop());return}
      const media=stream
      const chunks: BlobPart[] = []
      const recorder = new MediaRecorder(media)
      recorder.ondataavailable = e => chunks.push(e.data)
      recorder.onstop = () => { media.getTracks().forEach(t => t.stop()); const discarded=discardRecording.current; recordRef.current=null;setRecording(false);if(discarded)return;const mime=recorder.mimeType||'audio/webm';const ext=mime.includes('mp4')?'m4a':mime.includes('ogg')?'ogg':'webm';const file = new File(chunks, `voice-${Date.now()}.${ext}`, { type:mime }); if(file.size)sendFile(file, 'voice') }
      recordRef.current = recorder; recorder.start(); setRecordSeconds(0); setRecording(true)
    } catch (x) { stream?.getTracks().forEach(t=>t.stop());recordRef.current=null;setRecording(false);setError(errorText(x)) } finally {requestingMic.current=false}
  }
  async function messageAction(m: Message, action: 'edit' | 'delete' | 'pin' | 'react' | 'forward', emoji?: string) {
    if (!db || !user) return
    if (action === 'forward') { setForward(m); setDialog('forward'); return }
    if (action === 'edit') {
      const body = window.prompt('Изменить сообщение', m.body)
      if (body === null || !body.trim() || body === m.body) return
      await run(async () => { const { error } = await db!.from('messages').update({ body: body.trim() }).eq('id', m.id); if (error) throw error; await refreshMessages(m.conversation_id) })
    } else if (action === 'delete') {
      if (!window.confirm('Удалить сообщение для всех?')) return
      await run(async () => { const { error } = await db!.from('messages').update({ deleted_at: new Date().toISOString() }).eq('id', m.id); if (error) throw error; await refreshMessages(m.conversation_id) })
    } else if (action === 'pin') {
      await run(async () => { const { error } = await db!.from('messages').update({ pinned: !m.pinned }).eq('id', m.id); if (error) throw error; await refreshMessages(m.conversation_id) })
    } else if (action === 'react' && emoji) {
      await run(async () => {
        const existing = reactions.some(x => x.message_id === m.id && x.user_id === user.id && x.emoji === emoji)
        const result = existing ? await db!.from('reactions').delete().eq('message_id', m.id).eq('user_id', user.id).eq('emoji', emoji) : await db!.from('reactions').insert({ message_id: m.id, user_id: user.id, emoji })
        if (result.error) throw result.error; setReactions(await loadReactions(messages.map(x => x.id)))
      })
    }
  }
  async function forwardTo(target: Chat) {
    if (!db || !user || !forward) return
    await run(async () => {
      const original = forward!
      let path: string | null = null
      if (original.attachment_path) {
        const { data: blob, error: downloadError } = await db!.storage.from('chat-files').download(original.attachment_path)
        if (downloadError || !blob) throw downloadError || new Error('Не удалось прочитать вложение')
        path = await uploadChatFile(target.id, user.id, new File([blob], original.attachment_name || 'attachment', { type: original.attachment_mime || blob.type }))
      }
      const { error } = await db!.from('messages').insert({ conversation_id: target.id, sender_id: user.id, body: original.body || original.attachment_name || 'Пересланное сообщение', kind: original.kind, attachment_path: path, attachment_name: original.attachment_name, attachment_mime: original.attachment_mime, forwarded_from_id: original.id })
      if (error) { if (path) await db!.storage.from('chat-files').remove([path]); throw error }
      setDialog(null); setForward(null); openChat(target.id)
    }, 'Сообщение переслано')
  }

  if (!configured) return <div className="setup"><div className="brand-mark"><Icon name="chat_bubble" filled /></div><h1>Melo готов к подключению</h1><p>Создайте проект Supabase, выполните SQL-миграцию и заполните <code>.env</code> по образцу <code>.env.example</code>. Подробные шаги есть в README.md.</p></div>
  if (booting) return <div className="splash"><div className="brand-mark"><Icon name="chat_bubble" filled /></div><Loader/></div>
  if (!online && !user) return <div className="setup offline-screen"><Icon name="wifi_off" size={50}/><h1>Нет подключения</h1><p>Проверьте сеть и откройте Melo снова. Интерфейс доступен офлайн, переписка загрузится после подключения.</p><Button icon="refresh" className="primary" onClick={() => window.location.reload()}>Повторить</Button></div>
  if (!user || recovery) return <><Auth onNotice={setNotice} recovery={recovery} onRecoveryDone={() => { setRecovery(false); history.replaceState(null, '', window.location.pathname + window.location.search) }}/>{notice && <div className="toast" role="status">{notice}</div>}</>

  return <div className="app-shell">
    <aside className="rail"><div className="rail-logo" title="Melo"><Icon name="chat_bubble" size={27} filled /></div>
      <nav aria-label="Навигация">
        {([['chats','forum','Чаты'],['contacts','group','Контакты'],['search','search','Поиск'],['profile','person','Профиль']] as const).map(([id, icon, label]) =>
          <button key={id} className={`rail-item ${page === id ? 'active' : ''}`} onClick={() => { navigate(id) }} title={label}><span><Icon name={icon} filled={page === id} /></span><small>{label}</small></button>)}
      </nav><button className={`rail-item rail-settings ${page === 'settings' ? 'active' : ''}`} onClick={() => { navigate('settings') }} title="Настройки"><span><Icon name="settings" filled={page === 'settings'} /></span><small>Настройки</small></button>
    </aside>

    <section className={`sidebar ${mobileOpen ? 'mobile-hidden' : ''}`}>
      {page === 'chats' ? <><header className="sidebar-head"><div className="melo-heading-row"><div><div className="eyebrow">Melo · Сообщения</div><h1>Чаты<span className="title-dot">.</span></h1></div><button className="melo-profile-shortcut" title="Мой профиль" onClick={()=>navigate('profile')}><Avatar name={displayName(profile||undefined)} path={profile?.avatar_path} size={44}/></button></div><p className="muted">{unreadTotal ? `Непрочитанных: ${unreadTotal}` : 'Все разговоры в одном месте'}</p></header>
        <div className="searchbox"><Icon name="search" size={22}/><input aria-label="Поиск чатов" placeholder="Поиск чатов" value={query} onChange={e => setQuery(e.target.value)}/>{query && <button onClick={() => setQuery('')} title="Очистить"><Icon name="close" size={18}/></button>}</div>
        <div className="melo-community-link"><button onClick={()=>navigate('community')}><span className="melo-community-icon"><Icon name="auto_awesome" filled/></span><span><b>Сообщество</b><small>Каналы и истории</small></span><Icon name="chevron_right"/></button></div><div className="melo-folder-tabs" aria-label="Папки чатов">{[['','Все'],['__archive','Архив'],...folderNames.map(f=>[f,f])].map(([value,label])=><button key={value} aria-pressed={folderFilter===value} className={folderFilter===value?'selected':''} onClick={()=>setFolderFilter(value)}>{value==='__archive'&&<Icon name="archive" size={17}/>} {label}</button>)}</div><div className="list-title"><b>{folderFilter==='__archive'?'Архив':folderFilter||'Все чаты'}</b><span>{visibleChats.length}</span></div>
        <div className="chat-list">{visibleChats.map(x => {
          const name = x.kind === 'group' ? x.name || 'Группа' : displayName(x.peer)
          return <button key={x.id} className={`chat-row ${selected === x.id ? 'selected' : ''}`} onClick={() => openChat(x.id)}><Avatar name={name} path={x.kind === 'group' ? x.avatar_path : x.peer?.avatar_path} group={x.kind === 'group'} size={52}/><span className="chat-row-main"><span className="chat-row-top"><b><span className="melo-name">{name}</span>{x.kind === 'direct' && <><Verified profile={x.peer}/><Awards profile={x.peer}/></>}</b><time>{x.last ? time(x.last.created_at) : ''}</time></span><span className="chat-row-bottom"><span>{x.last ? x.last.deleted_at ? 'Сообщение удалено' : x.last.kind === 'voice' ? 'Голосовое сообщение' : x.last.kind !== 'text' ? `Вложение: ${x.last.attachment_name || ''}` : x.last.body : x.kind === 'group' ? 'Группа создана' : `@${x.peer?.username || ''}`}</span>{x.unread > 0 && <em>{x.unread}</em>}</span></span></button>
        })}{visibleChats.length === 0 && <div className="empty-list"><div className="empty-orb"><Icon name={query?'search_off':folderFilter==='__archive'?'archive':'mark_chat_unread'} size={36}/></div><b>{query?'Ничего не найдено':folderFilter?'Здесь пока пусто':'Пока тихо'}</b><p>{query?'Попробуйте другое имя или username':folderFilter?'Чаты появятся после добавления в папку':'Найдите человека и начните разговор'}</p>{!query&&!folderFilter&&<Button icon="add" className="tonal" onClick={()=>setDialog('new')}>Начать общение</Button>}</div>}</div>
        <motion.button layout className="fab" onClick={() => setDialog('new')} whileTap={{ scale: .94 }}><Icon name="edit_square" /><span>Новый чат</span></motion.button>
      </> : page === 'contacts' || page === 'search' ? <><header className="sidebar-head"><div className="eyebrow">Melo</div><h1>{page === 'contacts' ? 'Контакты' : 'Поиск'}<span className="title-dot">.</span></h1><p className="muted">Найдите людей по имени или @username</p></header><div className="searchbox"><Icon name="search"/><input autoFocus aria-label="Поиск людей" placeholder="Имя или @username" value={query} onChange={e => setQuery(e.target.value)}/></div><div className="people-list">{(query ? results : page === 'contacts' ? chats.filter(c => c.kind === 'direct' && c.peer).map(c => c.peer!) : []).filter(p => p.id !== user.id).map(p => <button key={p.id} className="person-row" onClick={() => startDirect(p)}><Avatar name={displayName(p)} path={p.avatar_path}/><span><b>{displayName(p)}<Verified profile={p}/><Awards profile={p}/></b><small>@{p.username}</small></span><Icon name="chat" size={20}/></button>)}{!query && page === 'search' && <div className="empty-list"><Icon name="person_search" size={36}/><p>Введите имя или username</p></div>}{!query && page === 'contacts' && !chats.some(c => c.kind === 'direct') && <div className="empty-list"><Icon name="group" size={36}/><p>Люди, с которыми вы общаетесь, появятся здесь</p></div>}</div></>
      : page === 'profile' ? <div className="profile-section"><button className="profile-settings icon-button" onClick={() => setPage('settings')} title="Настройки"><Icon name="settings"/></button><ProfilePanel user={user} profile={profile} onProfile={setProfile} onError={setError} onNotice={setNotice}/>{siteAdmin && <div className="melo-admin-entry"><Button icon="admin_panel_settings" className="tonal full" onClick={() => navigate('admin')}>Админ-панель</Button></div>}</div>
      : page === 'community' ? <CommunityPanel me={user.id} onBack={()=>setPage('chats')}/>
      : page === 'admin' ? (siteAdmin ? <AdminPanel onBack={() => setPage('profile')} onChange={() => { refreshChats(); if(user && db) db.from('profiles').select('*').eq('id',user.id).single().then(({data}) => { if(data) setProfile(data as Profile) }) }}/> : <div className="panel-scroll">Нет доступа</div>)
      : <SettingsPanel profile={profile} theme={theme} setTheme={setTheme} accent={accent} setAccent={setAccent} fontSize={fontSize} setFontSize={setFontSize} notifications={notifications} setNotifications={setNotifications} sounds={sounds} setSounds={setSounds} onLogout={() => db?.auth.signOut()} onDelete={() => setDialog('deleteAccount')} onError={setError}/>}
    </section>

    <main className={`conversation ${mobileOpen ? 'mobile-open' : ''}`}>
      {page === 'chats' && chat ? <><header className="conversation-head"><button className="mobile-back icon-button" onClick={() => {cancelRecording();setMobileOpen(false)}} title="Назад"><Icon name="arrow_back" /></button><Avatar name={chatName} path={chat.kind === 'group' ? chat.avatar_path : chat.peer?.avatar_path} group={chat.kind === 'group'} size={44}/><div className="conversation-title"><b><span className="melo-name">{chatName}</span>{chat.kind === 'direct' && <><Verified profile={chat.peer}/><Awards profile={chat.peer}/></>}</b><small>{typing ? 'печатает…' : chat.kind === 'group' ? `${chat.members.length} участников` : chat.peer?.show_online && chat.peer?.last_seen_at && Date.now() - new Date(chat.peer.last_seen_at).getTime() < 120000 ? 'в сети' : chat.peer?.show_last_seen && chat.peer?.last_seen_at ? `был(а) ${date(chat.peer.last_seen_at)} в ${time(chat.peer.last_seen_at)}` : `@${chat.peer?.username || ''}`}</small></div><button className="icon-button" onClick={() => setChatSearch(chatSearch === '__open__' ? '' : '__open__')} title="Поиск по чату"><Icon name="search" /></button><button className="icon-button" title="Папка или архив" onClick={()=>setDialog('organize')}><Icon name="folder"/></button><button className="icon-button" onClick={() => setDialog('manage')} title="Информация о чате"><Icon name="more_vert" /></button></header>
          {chatSearch === '__open__' || (chatSearch && chatSearch !== '__open__') ? <div className="chat-search"><Icon name="search"/><input autoFocus placeholder="Поиск в переписке" value={chatSearch === '__open__' ? '' : chatSearch} onChange={e => setChatSearch(e.target.value || '__open__')}/><button onClick={() => setChatSearch('')} title="Закрыть"><Icon name="close"/></button></div> : null}
          {messages.some(x => x.pinned && !x.deleted_at) && <button className="pinned" onClick={() => { const el = document.getElementById(`msg-${messages.find(x => x.pinned && !x.deleted_at)?.id}`); el?.scrollIntoView({ behavior: 'smooth', block: 'center' }) }}><Icon name="push_pin" size={19}/><span>{messages.find(x => x.pinned && !x.deleted_at)?.body || 'Закреплённое сообщение'}</span></button>}
          <div className="messages" role="log" aria-live="polite">{messages.filter(x => !chatSearch || chatSearch === '__open__' || x.body.toLowerCase().includes(chatSearch.toLowerCase())).map((m, i) => {
            const mine = m.sender_id === user.id
            const sender = people[m.sender_id]
            const replyMessage = messages.find(x => x.id === m.reply_to_id)
            const rs = reactions.filter(x => x.message_id === m.id)
            const reactionGroups = [...new Set(rs.map(x => x.emoji))]
            return <div key={m.id} id={`msg-${m.id}`} className={`message-line ${mine ? 'mine' : ''} ${messageMenu===m.id?'menu-open':''}`}>
              {i === 0 || date(m.created_at) !== date(messages[i - 1].created_at) ? <div className="date-chip">{date(m.created_at)}</div> : null}
              <div className="message-wrap">{!mine && chat.kind === 'group' && <Avatar name={displayName(sender)} path={sender?.avatar_path} size={28}/>}<div className={`bubble ${mine ? 'bubble-mine' : ''} ${m.deleted_at ? 'deleted' : ''}`}>
                {!mine && chat.kind === 'group' && <b className="sender">{displayName(sender)}<Verified profile={sender}/><Awards profile={sender}/></b>}
                {m.forwarded_from_id && <div className="forwarded"><Icon name="forward" size={15}/> Переслано</div>}
                {replyMessage && <div className="reply-preview"><b>{replyMessage.sender_id === user.id ? 'Вы' : displayName(people[replyMessage.sender_id])}</b><span>{replyMessage.deleted_at ? 'Сообщение удалено' : replyMessage.body}</span></div>}
                {m.deleted_at ? <span className="muted">Сообщение удалено</span> : <>{m.kind === 'image' && m.attachment_path && <a href={fileUrls[m.attachment_path]} target="_blank" rel="noreferrer"><img className="chat-image" src={fileUrls[m.attachment_path]} alt={m.attachment_name || 'Фото'}/></a>}
                  {m.kind === 'video' && m.attachment_path && <video controls src={fileUrls[m.attachment_path]} className="chat-video"/>}
                  {m.kind === 'voice' && m.attachment_path && <audio controls src={fileUrls[m.attachment_path]} />}
                  {m.kind === 'file' && m.attachment_path && <a className="file-link" href={fileUrls[m.attachment_path]} target="_blank" rel="noreferrer"><Icon name="draft"/>{m.attachment_name || 'Скачать файл'}</a>}
                  {m.kind === 'text' && <div className="message-text">{m.body}</div>}
                  {m.kind !== 'text' && m.body !== m.attachment_name && <div className="message-text">{m.body}</div>}</>}
                <div className="message-meta">{m.pinned && <Icon name="push_pin" size={13}/ >}{m.edited_at && !m.deleted_at && 'изменено · '}{time(m.created_at)}{mine && <Icon name={chat.members.some(x => x.user_id !== user.id && x.last_read_at > m.created_at) ? 'done_all' : 'done'} size={16}/>}</div>
                {!m.deleted_at && <button className="melo-message-more" aria-label="Действия с сообщением" aria-expanded={messageMenu===m.id} onClick={()=>setMessageMenu(v=>v===m.id?null:m.id)}><Icon name="more_horiz" size={18}/></button>}{!m.deleted_at && <div className="message-actions"><button onClick={() => setReply(m)} title="Ответить"><Icon name="reply" size={18}/></button><button onClick={() => messageAction(m,'forward')} title="Переслать"><Icon name="forward" size={18}/></button>{isAdmin && <button onClick={() => messageAction(m,'pin')} title={m.pinned ? 'Открепить' : 'Закрепить'}><Icon name="push_pin" size={18}/></button>}{mine && <><button onClick={() => messageAction(m,'edit')} title="Изменить"><Icon name="edit" size={18}/></button><button onClick={() => messageAction(m,'delete')} title="Удалить"><Icon name="delete" size={18}/></button></>}</div>}
              </div></div>{!m.deleted_at && <div className="reactions">{reactionGroups.map(emoji => <button key={emoji} className={rs.some(x => x.emoji === emoji && x.user_id === user.id) ? 'chosen' : ''} onClick={() => messageAction(m,'react',emoji)}>{emoji} {rs.filter(x => x.emoji === emoji).length}</button>)}<span className="emoji-menu">{['❤️','👍','😂','🔥'].map(emoji => <button key={emoji} onClick={() => messageAction(m,'react',emoji)} title={`Реакция ${emoji}`}>{emoji}</button>)}</span></div>}</div>
          })}{messages.length === 0 && <div className="empty-conversation"><div className="empty-orb"><Icon name="waving_hand" size={38}/></div><h2>Скажите привет!</h2><p>Начните разговор. Здесь появятся ваши сообщения.</p></div>}<div ref={endRef}/></div>
          <div className="composer-area">{reply && <div className="replying"><Icon name="reply" size={20}/><span><b>Ответ</b><small>{reply.body}</small></span><button onClick={() => setReply(null)} title="Отменить ответ"><Icon name="close" size={19}/></button></div>}
            <form className="composer" onSubmit={sendMessage}><button type="button" className="attach" disabled={!canPost||recording} title="Прикрепить файл" onClick={() => document.getElementById('attachment-picker')?.click()}><Icon name="attach_file"/></button><input id="attachment-picker" type="file" hidden disabled={!canPost} onChange={(e: ChangeEvent<HTMLInputElement>) => { const f = e.target.files?.[0]; if (f) sendFile(f); e.target.value = '' }}/><button type="button" disabled={!canPost || recording} title="GIF или видео" onClick={()=>document.getElementById('melo-media')?.click()}><Icon name="gif_box"/></button><input id="melo-media" type="file" accept="image/gif,video/*" hidden onChange={e=>{const f=e.target.files?.[0];if(f)sendFile(f);e.target.value=''}}/>{recording?<div className="melo-recording"><button type="button" title="Отменить запись" aria-label="Отменить запись" onClick={cancelRecording}><Icon name="close" size={20}/></button><Loader/><span role="status">{Math.floor(recordSeconds/60)}:{String(recordSeconds%60).padStart(2,'0')}</span></div>:<textarea aria-label="Сообщение" rows={1} disabled={!canPost} placeholder={canPost ? 'Написать сообщение…' : 'Пишут только администраторы'} value={draft} onChange={e => { setDraft(e.target.value); sessionStorage.setItem(`melo-draft-${selected}`, e.target.value); typingChannel.current?.send({ type: 'broadcast', event: 'typing', payload: { user: user.id } }) }} onKeyDown={e => { if (e.key === 'Enter' && !e.shiftKey && !e.nativeEvent.isComposing && !window.matchMedia('(pointer:coarse)').matches) { e.preventDefault(); sendMessage() } }}/>}<motion.button layout type={draft.trim()&&!recording?'submit':'button'} className={`send ${recording?'recording':''}`} disabled={!canPost || busy} aria-label={recording?'Завершить запись':draft.trim()?'Отправить':'Голосовое сообщение'} title={recording?'Завершить запись':draft.trim()?'Отправить':'Голосовое сообщение'} onClick={recording||!draft.trim()?recordVoice:undefined} whileTap={{scale:.88}}><AnimatePresence mode="wait" initial={false}><motion.span key={recording?'stop':draft.trim()?'send':'mic'} initial={{opacity:0,scale:.7,rotate:-20}} animate={{opacity:1,scale:1,rotate:0}} exit={{opacity:0,scale:.7,rotate:20}} transition={{duration:.12}}><Icon name={recording?'stop':draft.trim()?'arrow_upward':'mic'}/></motion.span></AnimatePresence></motion.button></form><small className="composer-hint">{canPost ? 'Enter — отправить · Shift+Enter — новая строка' : 'Отправка сообщений доступна администраторам'}</small></div>
        </> : <div className="welcome"><div className="welcome-art"><div className="welcome-logo"><Icon name="chat_bubble" size={58} filled /></div><span className="float-dot dot-a"/><span className="float-dot dot-b"/><span className="float-dot dot-c"/></div><h2>Ваше пространство для общения</h2><p>Выберите чат слева или найдите человека, чтобы начать разговор.</p><Button icon="edit_square" className="primary" onClick={() => setDialog('new')}>Новое сообщение</Button></div>}
    </main>

    <nav className="bottom-nav" aria-label="Навигация"><button className={page === 'chats' || page === 'community' ? 'active' : ''} onClick={() => { navigate('chats') }}><Icon name="forum" filled={page === 'chats' || page === 'community'}/><span>Чаты</span></button><button className={page === 'contacts' ? 'active' : ''} onClick={() => { navigate('contacts') }}><Icon name="group" filled={page === 'contacts'}/><span>Контакты</span></button><button className={page === 'search' ? 'active' : ''} onClick={() => { navigate('search') }}><Icon name="search" filled={page === 'search'}/><span>Поиск</span></button><button className={page === 'profile' || page === 'settings' || page === 'admin' ? 'active' : ''} onClick={() => { navigate('profile') }}><Icon name="person" filled={page === 'profile' || page === 'settings' || page === 'admin'}/><span>Профиль</span></button></nav>
    {!online && <div className="offline"><Icon name="wifi_off" size={18}/> Нет подключения. Сообщения появятся после восстановления сети.</div>}
    {(notice || error) && <div className={`toast ${error ? 'toast-error' : ''}`} role="status">{error || notice}<button onClick={() => { setError(''); setNotice('') }} title="Закрыть"><Icon name="close" size={18}/></button></div>}
    <AnimatePresence>{dialog && <motion.div className="dialog-backdrop" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} onMouseDown={e => { if (e.target === e.currentTarget) setDialog(null) }}><motion.div className="dialog" role="dialog" aria-modal="true" initial={{ y: 25, scale: .96 }} animate={{ y: 0, scale: 1 }} exit={{ y: 25, scale: .96 }} transition={{ type: 'spring', stiffness: 270, damping: 26 }}><button className="dialog-close icon-button" onClick={() => setDialog(null)} title="Закрыть"><Icon name="close"/></button>
      {dialog === 'new' && <><h2>Новый разговор</h2><p className="muted">Найдите человека или создайте группу</p><div className="searchbox"><Icon name="search"/><input autoFocus placeholder="Имя или @username" value={query} onChange={e => setQuery(e.target.value)}/></div><button className="option-row" onClick={() => setDialog('group')}><span className="option-icon"><Icon name="group_add"/></span><b>Создать группу</b><Icon name="chevron_right"/></button><div className="dialog-results">{results.filter(p => p.id !== user.id).map(p => <button key={p.id} className="person-row" onClick={() => startDirect(p)}><Avatar name={displayName(p)} path={p.avatar_path}/><span><b>{displayName(p)}<Verified profile={p}/><Awards profile={p}/></b><small>@{p.username}</small></span></button>)}</div></>}
      {dialog === 'group' && <GroupCreate onCreate={async (name, description) => { if (!db) return; await run(async () => { const { data, error } = await db!.rpc('create_group_chat', { group_name: name, group_description: description }); if (error) throw error; await refreshChats(); openChat(data as string) }, 'Группа создана') }} busy={busy}/>}
      {dialog === 'forward' && <><h2>Переслать сообщение</h2><p className="muted">Выберите чат</p><div className="forward-list">{chats.map(x => <button key={x.id} className="person-row" onClick={() => forwardTo(x)}><Avatar name={x.kind === 'group' ? x.name || 'Группа' : displayName(x.peer)} path={x.kind === 'group' ? x.avatar_path : x.peer?.avatar_path} group={x.kind === 'group'}/><b>{x.kind === 'group' ? x.name : displayName(x.peer)}</b></button>)}</div></>}
      {dialog === 'organize' && chat && <OrganizeChat chat={chat} me={user.id} onSave={()=>{refreshChats();setDialog(null)}} onError={setError}/>}{dialog === 'manage' && chat && <ManageChat chat={chat} people={people} me={user.id} isAdmin={isAdmin} onRefresh={refreshChats} onClose={() => setDialog(null)} onLeave={() => { setSelected(null); setMobileOpen(false) }} onError={setError} onNotice={setNotice}/>}
      {dialog === 'deleteAccount' && <><h2>Удалить аккаунт?</h2><p className="muted">Профиль и ваши сообщения будут удалены без возможности восстановления. Для подтверждения введите «УДАЛИТЬ».</p><DeleteConfirm onConfirm={() => run(async () => { const { error } = await db!.rpc('delete_my_account'); if (error) throw error; await db!.auth.signOut(); setDialog(null) })} busy={busy}/></>}
    </motion.div></motion.div>}</AnimatePresence>
  </div>
}

function OrganizeChat({chat,me,onSave,onError}:{chat:Chat;me:string;onSave:()=>void;onError:(s:string)=>void}){const own=chat.members.find(m=>m.user_id===me) as {folder?:string;archived?:boolean}|undefined;const [folder,setFolder]=useState(own?.folder||'');const [archived,setArchived]=useState(Boolean(own?.archived));const [saving,setSaving]=useState(false);async function save(e:FormEvent){e.preventDefault();if(!db)return;setSaving(true);const {error}=await db.from('conversation_members').update({folder:folder.trim(),archived}).eq('conversation_id',chat.id).eq('user_id',me);setSaving(false);if(error)onError(error.message);else onSave()}return <form className="dialog-form" onSubmit={save}><h2>Организация чата</h2><p className="muted">Настройте отображение чата в своём списке.</p><label>Папка<input maxLength={40} value={folder} onChange={e=>setFolder(e.target.value)} placeholder="Например, Друзья"/></label><div className="toggle-row"><span><b>В архиве</b><small>Скрыть из основного списка</small></span><input aria-label="В архиве" type="checkbox" checked={archived} onChange={e=>setArchived(e.target.checked)}/></div><Button type="submit" icon="check" className="primary full" disabled={saving}>Сохранить</Button></form>}
function GroupCreate({ onCreate, busy }: { onCreate: (name: string, description: string) => void; busy: boolean }) {
  const [name, setName] = useState(''), [description, setDescription] = useState('')
  return <form className="dialog-form" onSubmit={e => { e.preventDefault(); onCreate(name.trim(), description.trim()) }}><h2>Новая группа</h2><p className="muted">Соберите всех в одном месте</p><label>Название<input required maxLength={80} value={name} onChange={e => setName(e.target.value)} placeholder="Например, Команда Melo"/></label><label>Описание<textarea maxLength={500} value={description} onChange={e => setDescription(e.target.value)} placeholder="О чём ваша группа?"/></label><Button type="submit" icon="group_add" className="primary full" disabled={busy || !name.trim()}>Создать группу</Button></form>
}
function DeleteConfirm({ onConfirm, busy }: { onConfirm: () => void; busy: boolean }) {
  const [value, setValue] = useState('')
  return <div className="dialog-form"><input aria-label="Подтверждение удаления" value={value} onChange={e => setValue(e.target.value)} placeholder="УДАЛИТЬ"/><Button className="danger full" disabled={busy || value !== 'УДАЛИТЬ'} onClick={onConfirm}>Удалить навсегда</Button></div>
}

function CommunityPanel({me,onBack}:{me:string;onBack:()=>void}){
 type Channel={id:string;name:string;description:string;owner_id:string};type Story={id:string;user_id:string;body:string;expires_at:string;profiles?:{username:string}};type Post={id:string;body:string;created_at:string};
 const [channels,setChannels]=useState<Channel[]>([]),[stories,setStories]=useState<Story[]>([]),[posts,setPosts]=useState<Post[]>([]),[active,setActive]=useState<Channel|null>(null),[name,setName]=useState(''),[body,setBody]=useState(''),[status,setStatus]=useState('');
 const load=useCallback(async()=>{if(!db)return;const [c,t]=await Promise.all([db.from('melo_channels').select('*').order('created_at',{ascending:false}).limit(100),db.from('melo_stories').select('*,profiles(username)').gt('expires_at',new Date().toISOString()).order('created_at',{ascending:false}).limit(100)]);if(c.error||t.error)setStatus((c.error||t.error)?.message||'Ошибка');setChannels((c.data||[]) as Channel[]);setStories((t.data||[]) as unknown as Story[])},[]);
 useEffect(()=>{load();const timer=setInterval(load,30000);return()=>clearInterval(timer)},[load]);
 useEffect(()=>{if(!db||!active){setPosts([]);return}const id=active.id;let live=true;const fetchPosts=async()=>{const {data,error}=await db!.from('melo_channel_posts').select('*').eq('channel_id',id).order('created_at',{ascending:false}).limit(100);if(live){if(error)setStatus(error.message);else setPosts((data||[]) as Post[])}};fetchPosts();const ch=db.channel('melo-posts-'+id).on('postgres_changes',{event:'*',schema:'public',table:'melo_channel_posts',filter:'channel_id=eq.'+id},fetchPosts).subscribe();return()=>{live=false;db?.removeChannel(ch)}},[active?.id]);
 async function publish(kind:'channel'|'story'|'post'){if(!db)return;setStatus('');const result=kind==='channel'?await db.from('melo_channels').insert({owner_id:me,name:name.trim()}):kind==='story'?await db.from('melo_stories').insert({user_id:me,body:body.trim()}):await db.from('melo_channel_posts').insert({channel_id:active?.id,body:body.trim()});if(result.error){setStatus(result.error.message);return}setBody('');setName('');setStatus('Опубликовано');load();if(active){const {data}=await db.from('melo_channel_posts').select('*').eq('channel_id',active.id).order('created_at',{ascending:false}).limit(100);setPosts((data||[]) as Post[])}}
 return <div className="panel-scroll melo-panel melo-community"><Button icon="arrow_back" onClick={onBack}>Чаты</Button><header className="sidebar-head"><h1>Сообщество<span className="title-dot">.</span></h1><p>Истории и публичные каналы</p></header><h3>Истории · 24 часа</h3><div className="melo-stories">{stories.map(t=><motion.div layout key={t.id} className="melo-social-card"><b>@{t.profiles?.username||'user'}</b><p>{t.body}</p>{t.user_id===me&&<button onClick={async()=>{const r=await db!.from('melo_stories').delete().eq('id',t.id);if(r.error)setStatus(r.error.message);else load()}}>Удалить</button>}</motion.div>)}</div><textarea maxLength={500} placeholder="Новая история" value={active?'':body} disabled={!!active} onChange={e=>setBody(e.target.value)}/><Button disabled={!!active||!body.trim()} onClick={()=>publish('story')}>Опубликовать историю</Button><h3>Публичные каналы</h3><input maxLength={80} placeholder="Название канала" value={name} onChange={e=>setName(e.target.value)}/><Button disabled={!name.trim()} icon="add" onClick={()=>publish('channel')}>Создать канал</Button>{channels.map(c=><button className="person-row" key={c.id} onClick={()=>{setActive(c);setBody('')}}><Icon name="campaign"/><span><b>{c.name}</b><small>{c.description||'Публичный канал'}</small></span></button>)}{active&&<motion.div layout className="melo-social-card"><Button onClick={()=>{setActive(null);setBody('')}}>Закрыть канал</Button><h2>{active.name}</h2>{active.owner_id===me&&<><textarea maxLength={4096} value={body} onChange={e=>setBody(e.target.value)} placeholder="Публикация"/><Button disabled={!body.trim()} onClick={()=>publish('post')}>Опубликовать</Button></>}{posts.map(p=><article key={p.id}><p>{p.body}</p><small>{date(p.created_at)} {time(p.created_at)}</small></article>)}</motion.div>}{status&&<p role="status">{status}</p>}</div>
}
function AdminPanel({onBack,onChange}: {onBack:()=>void;onChange:()=>void}) {
  const [term,setTerm]=useState(''); const [target,setTarget]=useState<Profile|null>(null); const [busy,setBusy]=useState(false); const [status,setStatus]=useState('');
  async function find(e:FormEvent) { e.preventDefault(); if(!db)return; setBusy(true);setTarget(null);setStatus('');try { const {data,error}=await db.from('profiles').select('*').eq('username',term.trim().replace(/^@/,'').toLowerCase()).maybeSingle();if(error)throw error;setTarget(data as Profile|null);if(!data)setStatus('Пользователь не найден') }catch(e){setStatus(errorText(e))}finally{setBusy(false)} }
  async function verify(value:boolean) { if(!db||!target)return;setBusy(true);setStatus('');try{const {error}=await db.rpc('set_melo_verified',{target_username:target.username,make_verified:value});if(error)throw error;setTarget({...target,verified:value} as Profile);setStatus(value?'Галочка выдана':'Галочка снята');onChange()}catch(e){setStatus(errorText(e))}finally{setBusy(false)} }
  async function award(plus:boolean,badge:string){if(!db||!target)return;setBusy(true);try{const {error}=await db.rpc('set_melo_awards',{target_username:target.username,make_plus:plus,badge});if(error)throw error;setTarget({...target,plus,rare_badge:badge} as SocialProfile);setStatus('Награды сохранены');onChange()}catch(e){setStatus(errorText(e))}finally{setBusy(false)}}
  const checked=(target as (Profile & {verified?:boolean})|null)?.verified;
  return <div className="panel-scroll melo-panel melo-admin"><Button icon="arrow_back" onClick={onBack}>Профиль</Button><header className="sidebar-head"><div className="eyebrow">Управление Melo</div><h1>Админ-панель<span className="title-dot">.</span></h1><p className="muted">Верификация пользователей</p></header><form className="profile-form" onSubmit={find}><label>Username<input required value={term} onChange={e=>{setTerm(e.target.value);setTarget(null);setStatus('')}} placeholder="@username"/></label><Button type="submit" icon="search" className="primary full" disabled={busy}>Найти пользователя</Button></form>{target && <><div className="person-row"><Avatar name={displayName(target)} path={target.avatar_path}/><span><b>{displayName(target)}<Verified profile={target}/><Awards profile={target}/></b><small>@{target.username}</small></span></div><p>{checked?'Аккаунт подтверждён':'Аккаунт не подтверждён'}</p><Button icon={checked?'remove_circle':'verified'} className="primary full" disabled={busy} onClick={()=>verify(!checked)}>{checked?'Снять галочку':'Выдать галочку'}</Button><Button disabled={busy} icon="diamond" onClick={()=>award(!(target as SocialProfile).plus,(target as SocialProfile).rare_badge||'')}>{(target as SocialProfile).plus?'Снять Melo Plus':'Выдать Melo Plus'}</Button><label>Редкий значок<select disabled={busy} value={(target as SocialProfile).rare_badge||''} onChange={e=>award(Boolean((target as SocialProfile).plus),e.target.value)}><option value="">Нет</option><option value="founder">Основатель</option><option value="developer">Разработчик</option><option value="tester">Тестировщик</option><option value="legend">Легенда</option></select></label></>}{status&&<p role="status">{status}</p>}</div>
}
function ProfilePanel({ user, profile, onProfile, onError, onNotice }: { user: User; profile: Profile | null; onProfile: (p: Profile) => void; onError: (s: string) => void; onNotice: (s: string) => void }) {
  const [form, setForm] = useState<Profile | null>(null)
  const [available, setAvailable] = useState<string>('')
  const [busy, setBusy] = useState(false)
  useEffect(() => { setForm(profile) }, [profile])
  useEffect(() => {
    if (!db || !form || form.username === profile?.username) { setAvailable(''); return }
    if (!/^[a-z][a-z0-9_]{3,23}$/.test(form.username)) { setAvailable('Используйте 4–24 латинских символа, цифры или _'); return }
    const timer = setTimeout(() => { db!.from('profiles').select('id').eq('username', form.username).maybeSingle().then(({ data }) => setAvailable(data ? 'Имя занято' : 'Имя свободно')) }, 300)
    return () => clearTimeout(timer)
  }, [form?.username, profile?.username])
  async function save(e: FormEvent) {
    e.preventDefault(); if (!db || !form) return
    setBusy(true)
    const { data, error } = await db.from('profiles').update({ first_name: form.first_name.trim(), last_name: form.last_name.trim(), username: form.username, bio: form.bio.trim(), show_online: form.show_online, show_last_seen: form.show_last_seen }).eq('id', user.id).select().single()
    if (error) onError(error.message); else { onProfile(data as Profile); onNotice('Профиль сохранён') }
    setBusy(false)
  }
  async function changeAvatar(file: File) {
    if (!db) return
    setBusy(true)
    try { const path = await uploadAvatar(user.id, file); const { data, error } = await db.from('profiles').update({ avatar_path: path }).eq('id', user.id).select().single(); if (error) throw error; onProfile(data as Profile); onNotice('Аватар обновлён') } catch (x) { onError(errorText(x)) } finally { setBusy(false) }
  }
  async function cosmetic(values:{banner_path?:string|null;frame?:string}){if(!db)return;const {data,error}=await db.from('profiles').update(values).eq('id',user.id).select().single();if(error)onError(error.message);else onProfile(data as Profile)}
  if (!form) return <Loader/>
  return <div className="panel-scroll"><header className="sidebar-head"><div className="eyebrow">Ваше пространство</div><h1>Профиль<span className="title-dot">.</span></h1><p className="muted">Расскажите о себе</p></header><motion.div layout className="melo-banner" style={{backgroundImage:(form as SocialProfile).banner_path?'url('+avatarUrl((form as SocialProfile).banner_path)+')':undefined}}><label>Изменить баннер<input hidden type="file" accept="image/png,image/jpeg,image/webp,image/gif" onChange={async e=>{const f=e.target.files?.[0];if(f)try{await cosmetic({banner_path:await uploadAvatar(user.id,f)})}catch(x){onError(errorText(x))}}}/></label></motion.div><label className="melo-frame-select">Рамка аватарки<select value={(form as SocialProfile).frame||'none'} onChange={e=>cosmetic({frame:e.target.value})}><option value="none">Без рамки</option><option value="violet">Аметист</option><option value="mint">Мята</option><option value="gold">Золото</option></select></label><div className={'profile-photo melo-frame-'+((form as SocialProfile).frame||'none')}><Avatar name={displayName(form)} path={form.avatar_path} size={92}/><label className="avatar-edit" title="Загрузить аватар"><Icon name="photo_camera" size={20}/><input hidden type="file" accept="image/png,image/jpeg,image/webp,image/gif" onChange={e => { const f = e.target.files?.[0]; if (f) changeAvatar(f) }}/></label></div><div className="melo-profile-name">{displayName(form)}</div><div className="profile-handle">@{form.username}<Verified profile={profile}/><Awards profile={profile}/></div><form className="profile-form" onSubmit={save}><label>Имя<input maxLength={50} value={form.first_name} onChange={e => setForm({ ...form, first_name: e.target.value })}/></label><label>Фамилия<input maxLength={50} value={form.last_name} onChange={e => setForm({ ...form, last_name: e.target.value })}/></label><label>Username<div className="input-prefix"><span>@</span><input value={form.username} onChange={e => setForm({ ...form, username: e.target.value.toLowerCase().replace(/[^a-z0-9_]/g,'') })}/></div>{available && <small className={available === 'Имя свободно' ? 'success-text' : 'error-text'}>{available}</small>}</label><label>О себе<textarea maxLength={240} rows={3} value={form.bio} onChange={e => setForm({ ...form, bio: e.target.value })} placeholder="Пара слов о вас"/></label><div className="toggle-row"><span><b>Показывать активность</b><small>Другие видят, когда вы в сети</small></span><input type="checkbox" checked={form.show_online} onChange={e => setForm({ ...form, show_online: e.target.checked })}/></div><div className="toggle-row"><span><b>Показывать время посещения</b></span><input type="checkbox" checked={form.show_last_seen} onChange={e => setForm({ ...form, show_last_seen: e.target.checked })}/></div><Button type="submit" icon="check" className="primary full" disabled={busy || (available !== '' && available !== 'Имя свободно')}>Сохранить изменения</Button></form></div>
}

function SettingsPanel({ profile, theme, setTheme, accent, setAccent, fontSize, setFontSize, notifications, setNotifications, sounds, setSounds, onLogout, onDelete, onError }: { profile: Profile | null; theme: string; setTheme: (x: string) => void; accent: string; setAccent: (x: string) => void; fontSize: number; setFontSize: (x: number) => void; notifications: boolean; setNotifications: (x: boolean) => void; sounds: boolean; setSounds: (x: boolean) => void; onLogout: () => void; onDelete: () => void; onError: (x: string) => void }) {
  const [blocked, setBlocked] = useState<Profile[]>([])
  useEffect(() => { if (!db || !profile) return; db.from('blocks').select('blocked_id').eq('blocker_id', profile.id).then(async ({ data }) => { const ids = (data || []).map(x => x.blocked_id); if (ids.length) { const r = await db!.from('profiles').select('*').in('id', ids); setBlocked((r.data || []) as Profile[]) } else setBlocked([]) }) }, [profile?.id])
  async function unblock(id: string) { const { error } = await db!.from('blocks').delete().eq('blocker_id', profile!.id).eq('blocked_id', id); if (error) onError(error.message); else setBlocked(blocked.filter(x => x.id !== id)) }
  async function enableNotifications() { if (!('Notification' in window)) { onError('Уведомления не поддерживаются браузером'); return } const permission = await Notification.requestPermission(); if (permission !== 'granted') { onError('Разрешите уведомления в браузере'); return } setNotifications(true); localStorage.setItem('melo-notifications','true') }
  return <div className="panel-scroll settings"><header className="sidebar-head"><div className="eyebrow">Под себя</div><h1>Настройки<span className="title-dot">.</span></h1></header><h3>Внешний вид</h3><div className="segmented">{[['system','Система'],['light','Светлая'],['dark','Тёмная']].map(([v,label]) => <button key={v} className={theme === v ? 'active' : ''} onClick={() => setTheme(v)}>{label}</button>)}</div><label className="settings-label">Акцентный цвет</label><div className="swatches">{accents.map(x => <button key={x} aria-label={`Цвет ${x}`} aria-pressed={accent === x} style={{ background: x }} onClick={() => setAccent(x)}>{accent === x && <Icon name="check" size={19}/>}</button>)}</div><label className="settings-label">Размер текста сообщений</label><input type="range" min="14" max="22" value={fontSize} onChange={e => setFontSize(Number(e.target.value))}/><div className="range-caption">{fontSize} px</div><h3>Уведомления</h3><div className="toggle-row"><span><b>Уведомления</b><small>Когда Melo открыт в браузере</small></span><input type="checkbox" checked={notifications} onChange={e => { if (e.target.checked) enableNotifications(); else { setNotifications(false); localStorage.setItem('melo-notifications','false') } }}/></div><div className="toggle-row"><span><b>Звуки сообщений</b></span><input type="checkbox" checked={sounds} onChange={e => { setSounds(e.target.checked); localStorage.setItem('melo-sounds',String(e.target.checked)) }}/></div><h3>Конфиденциальность</h3><p className="muted">Активность и видимость времени посещения настраиваются в профиле.</p><div className="settings-label">Заблокированные пользователи</div>{blocked.length ? blocked.map(p => <div className="blocked-row" key={p.id}><span>{displayName(p)}</span><button onClick={() => unblock(p.id)}>Разблокировать</button></div>) : <p className="muted small">Список пуст</p>}<h3>О Melo</h3><p className="muted small">Melo 2.0 · Создан для простого общения. Сообщения хранятся в Supabase. Сквозное шифрование не реализовано.</p><Button icon="logout" className="tonal full" onClick={onLogout}>Выйти</Button><Button icon="delete_forever" className="text-danger full" onClick={onDelete}>Удалить аккаунт</Button></div>
}

function ManageChat({ chat, people, me, isAdmin, onRefresh, onClose, onLeave, onError, onNotice }: { chat: Chat; people: Record<string, Profile>; me: string; isAdmin: boolean; onRefresh: () => Promise<void>; onClose: () => void; onLeave: () => void; onError: (x: string) => void; onNotice: (x: string) => void }) {
  const [name, setName] = useState(chat.name || ''), [description, setDescription] = useState(chat.description || ''), [term, setTerm] = useState(''), [results, setResults] = useState<Profile[]>([])
  useEffect(() => { if (!term) { setResults([]); return }; const t = setTimeout(() => searchProfiles(term).then(setResults).catch(x => onError(errorText(x))), 250); return () => clearTimeout(t) }, [term])
  async function mutate(fn: () => PromiseLike<{ error: { message: string } | null }>, success: string) { try { const { error } = await fn(); if (error) throw new Error(error.message); await onRefresh(); onNotice(success); return true } catch (x) { onError(errorText(x)); return false } }
  const invite = `${window.location.origin}${import.meta.env.BASE_URL}#invite=${chat.invite_token}`
  return <div className="manage"><h2>{chat.kind === 'group' ? 'О группе' : 'О чате'}</h2><div className="manage-hero"><Avatar name={chat.kind === 'group' ? chat.name || 'Группа' : displayName(chat.peer)} path={chat.kind === 'group' ? chat.avatar_path : chat.peer?.avatar_path} group={chat.kind === 'group'} size={76}/><b>{chat.kind === 'group' ? chat.name : displayName(chat.peer)}{chat.kind==='direct'&&<><Verified profile={chat.peer}/><Awards profile={chat.peer}/></>}</b><small>{chat.kind === 'group' ? `${chat.members.length} участников` : `@${chat.peer?.username}`}</small></div>
    {chat.kind === 'direct' && chat.peer ? <Button icon="block" className="tonal full" onClick={() => mutate(() => db!.from('blocks').insert({ blocker_id: me, blocked_id: chat.peer!.id }), 'Пользователь заблокирован')}>Заблокировать</Button> : <>
      {isAdmin && <><label>Название группы<input value={name} maxLength={80} onChange={e => setName(e.target.value)}/></label><label>Описание<textarea value={description} maxLength={500} onChange={e => setDescription(e.target.value)}/></label><Button className="tonal full" icon="save" onClick={() => mutate(() => db!.from('conversations').update({ name, description }).eq('id', chat.id), 'Группа обновлена')}>Сохранить</Button><label className="avatar-upload">Изменить аватар группы<input type="file" accept="image/*" onChange={async e => { const f = e.target.files?.[0]; if (!f) return; try { const path = await uploadAvatar(me, f); const { error } = await db!.from('conversations').update({ avatar_path: path }).eq('id', chat.id); if (error) throw error; await onRefresh(); onNotice('Аватар группы обновлён') } catch (x) { onError(errorText(x)) } }}/></label><div className="toggle-row"><span><b>Пишут только администраторы</b></span><input type="checkbox" checked={chat.only_admins_can_post} onChange={e => mutate(() => db!.from('conversations').update({ only_admins_can_post: e.target.checked }).eq('id', chat.id), 'Разрешения обновлены')}/></div></>}
      <div className="settings-label">Ссылка приглашения</div><div className="invite-link"><input readOnly value={invite} aria-label="Ссылка приглашения"/><button onClick={() => { navigator.clipboard.writeText(invite); onNotice('Ссылка скопирована') }} title="Скопировать"><Icon name="content_copy" size={20}/></button></div>
      <div className="settings-label">Участники</div>{chat.members.map(member => <div className="member-row" key={member.user_id}><Avatar name={member.user_id === me ? 'Вы' : displayName(people[member.user_id])} path={people[member.user_id]?.avatar_path} size={34}/><span><b>{member.user_id === me ? 'Вы' : displayName(people[member.user_id])}<Verified profile={people[member.user_id]}/><Awards profile={people[member.user_id]}/></b><small>{member.role === 'owner' ? 'Владелец' : member.role === 'admin' ? 'Администратор' : 'Участник'}</small></span>{chat.owner_id === me && member.user_id !== me && <button title={member.role === 'admin' ? 'Снять администратора' : 'Сделать администратором'} onClick={() => mutate(() => db!.rpc('set_group_admin', { chat_id: chat.id, member_id: member.user_id, make_admin: member.role !== 'admin' }), 'Роль обновлена')}><Icon name="admin_panel_settings" size={19}/></button>}{isAdmin && member.user_id !== me && <button title="Удалить из группы" onClick={() => mutate(() => db!.rpc('remove_group_member', { chat_id: chat.id, member_id: member.user_id }), 'Участник удалён')}><Icon name="person_remove" size={19}/></button>}</div>)}
      {isAdmin && <><div className="settings-label">Добавить участника</div><input placeholder="Имя или @username" value={term} onChange={e => setTerm(e.target.value)}/>{results.filter(p => !chat.members.some(m => m.user_id === p.id)).map(p => <button className="person-row" key={p.id} onClick={() => mutate(() => db!.from('conversation_members').insert({ conversation_id: chat.id, user_id: p.id, role: 'member' }), 'Участник добавлен')}><Avatar name={displayName(p)} path={p.avatar_path} size={35}/><span><b>{displayName(p)}<Verified profile={p}/><Awards profile={p}/></b><small>@{p.username}</small></span><Icon name="add" size={20}/></button>)}</>}
      <Button icon="logout" className="text-danger full" onClick={() => { if (!window.confirm('Выйти из группы?')) return; mutate(() => db!.rpc('leave_group', { chat_id: chat.id }), 'Вы вышли из группы').then(ok => { if (ok) { onLeave(); onClose() } }) }}>Выйти из группы</Button>
    </>}
  </div>
}

export default App
