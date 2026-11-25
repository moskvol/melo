import { createClient } from '@supabase/supabase-js'

export const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
export const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string | undefined
export const configured = Boolean(url && key && !url.includes('YOUR_PROJECT'))
export const db = configured ? createClient(url!, key!, { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true } }) : null

export type Profile = {
  id: string; username: string; first_name: string; last_name: string; bio: string; avatar_path: string | null;
  show_online: boolean; show_last_seen: boolean; last_seen_at: string | null
}
export type Conversation = {
  id: string; kind: 'direct' | 'group'; name: string | null; description: string | null;
  avatar_path: string | null; invite_token: string; owner_id: string | null;
  only_admins_can_post: boolean; updated_at: string
}
export type Member = { conversation_id: string; user_id: string; role: 'owner' | 'admin' | 'member'; last_read_at: string }
export type Message = {
  id: string; conversation_id: string; sender_id: string; body: string; kind: 'text' | 'image' | 'video' | 'file' | 'voice';
  attachment_path: string | null; attachment_name: string | null; attachment_mime: string | null;
  reply_to_id: string | null; forwarded_from_id: string | null; pinned: boolean;
  edited_at: string | null; deleted_at: string | null; created_at: string
}
export type Reaction = { message_id: string; user_id: string; emoji: string }
export type Chat = Conversation & { members: Member[]; peer?: Profile; last?: Message; unread: number }

export const displayName = (p?: Profile) => p ? ([p.first_name, p.last_name].filter(Boolean).join(' ') || `@${p.username}`) : 'Пользователь'
export const avatarUrl = (path?: string | null) => path && db ? db.storage.from('avatars').getPublicUrl(path).data.publicUrl : undefined
export const initials = (name: string) => name.trim().slice(0, 2).toUpperCase() || 'M'
export const time = (iso: string) => new Intl.DateTimeFormat('ru', { hour: '2-digit', minute: '2-digit' }).format(new Date(iso))
export const date = (iso: string) => new Intl.DateTimeFormat('ru', { day: 'numeric', month: 'long' }).format(new Date(iso))
export const errorText = (error: unknown) => error instanceof Error ? error.message : 'Не удалось выполнить действие'
export const cleanFileName = (name: string) => name.replace(/[^a-zA-Z0-9._-]/g, '_').slice(0, 100)

export async function loadChats(me: string): Promise<Chat[]> {
  if (!db) return []
  const { data: mine, error: e1 } = await db.from('conversation_members').select('*').eq('user_id', me)
  if (e1) throw e1
  const ids = (mine || []).map(x => x.conversation_id as string)
  if (!ids.length) return []
  const [c, m, msg] = await Promise.all([
    db.from('conversations').select('*').in('id', ids).order('updated_at', { ascending: false }),
    db.from('conversation_members').select('*').in('conversation_id', ids),
    db.from('messages').select('*').in('conversation_id', ids).order('created_at', { ascending: false }).limit(1000)
  ])
  for (const x of [c,m,msg]) if (x.error) throw x.error
  const allMembers = (m.data || []) as Member[]
  const peers = [...new Set(allMembers.map(x => x.user_id))]
  const { data: people, error: pe } = await db.from('profiles').select('*').in('id', peers)
  if (pe) throw pe
  return assembleChats((c.data || []) as Conversation[], allMembers, (msg.data || []) as Message[], (people || []) as Profile[], me)
}

export function assembleChats(conversations: Conversation[], members: Member[], messages: Message[], profiles: Profile[], me: string): Chat[] {
  const profileMap = new Map(profiles.map(p => [p.id, p]))
  return conversations.map(chat => {
    const chatMembers = members.filter(x => x.conversation_id === chat.id)
    const own = chatMembers.find(x => x.user_id === me)
    const chatMessages = messages.filter(x => x.conversation_id === chat.id).sort((a,b) => b.created_at.localeCompare(a.created_at))
    return { ...chat, members: chatMembers, peer: profileMap.get(chatMembers.find(x => x.user_id !== me)?.user_id || ''), last: chatMessages[0],
      unread: chatMessages.filter(x => x.sender_id !== me && (!own?.last_read_at || x.created_at > own.last_read_at)).length }
  })
}

export async function loadMessages(chatId: string): Promise<Message[]> {
  if (!db) return []
  const { data, error } = await db.from('messages').select('*').eq('conversation_id', chatId).order('created_at', { ascending: false }).limit(200)
  if (error) throw error
  return ((data || []) as Message[]).reverse()
}

export async function loadReactions(ids: string[]): Promise<Reaction[]> {
  if (!db || !ids.length) return []
  const { data, error } = await db.from('reactions').select('message_id,user_id,emoji').in('message_id', ids)
  if (error) throw error
  return (data || []) as Reaction[]
}

export async function searchProfiles(term: string): Promise<Profile[]> {
  if (!db || !term.trim()) return []
  const q = term.replace(/^@/, '').trim().replace(/[%_\\]/g, '')
  if (!q) return []
  const [a,b,c] = await Promise.all([
    db.from('profiles').select('*').ilike('username', `%${q}%`).limit(20),
    db.from('profiles').select('*').ilike('first_name', `%${q}%`).limit(20),
    db.from('profiles').select('*').ilike('last_name', `%${q}%`).limit(20)
  ])
  for (const x of [a,b,c]) if (x.error) throw x.error
  return [...new Map([...a.data!, ...b.data!, ...c.data!].map(p => [p.id as string, p as Profile])).values()]
}

export async function uploadAvatar(userId: string, file: File) {
  if (!db) throw new Error('Нет подключения')
  if (!['image/jpeg','image/png','image/webp','image/gif'].includes(file.type) || file.size > 5 * 1024 * 1024) throw new Error('Выберите изображение JPG, PNG, WebP или GIF до 5 МБ')
  const path = `${userId}/${crypto.randomUUID()}.${file.type.split('/')[1]}`
  const { error } = await db.storage.from('avatars').upload(path, file, { contentType: file.type })
  if (error) throw error
  return path
}

export async function uploadChatFile(chatId: string, userId: string, file: File) {
  if (!db) throw new Error('Нет подключения')
  if (file.size > 25 * 1024 * 1024) throw new Error('Файл должен быть меньше 25 МБ')
  const path = `${chatId}/${userId}/${crypto.randomUUID()}-${cleanFileName(file.name)}`
  const { error } = await db.storage.from('chat-files').upload(path, file, { contentType: file.type || 'application/octet-stream' })
  if (error) throw error
  return path
}
