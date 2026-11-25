import { describe, expect, it } from 'vitest'
import { assembleChats } from './lib'
import type { Conversation, Member, Message, Profile } from './lib'

const chat: Conversation = { id: 'c', kind: 'direct', name: null, description: null, avatar_path: null, invite_token: 't', owner_id: 'a', only_admins_can_post: false, updated_at: '2026-11-25T10:00:00Z' }
const me: Member = { conversation_id: 'c', user_id: 'a', role: 'member', last_read_at: '2026-11-25T10:00:00Z' }
const other: Member = { conversation_id: 'c', user_id: 'b', role: 'member', last_read_at: '2026-11-25T10:00:00Z' }
const person: Profile = { id: 'b', username: 'bravo', first_name: 'Борис', last_name: '', bio: '', avatar_path: null, show_online: true, show_last_seen: true, last_seen_at: null }
const message = (id: string, sender: string, created_at: string): Message => ({ id, conversation_id: 'c', sender_id: sender, body: id, kind: 'text', attachment_path: null, attachment_name: null, attachment_mime: null, reply_to_id: null, forwarded_from_id: null, pinned: false, edited_at: null, deleted_at: null, created_at })

describe('chat summaries', () => {
  it('counts only incoming messages newer than the read marker', () => {
    const rows = [message('old', 'b', '2026-11-25T09:00:00Z'), message('mine', 'a', '2026-11-25T10:30:00Z'), message('new', 'b', '2026-11-25T11:00:00Z')]
    const [summary] = assembleChats([chat], [me, other], rows, [person], 'a')
    expect(summary.unread).toBe(1)
    expect(summary.last?.id).toBe('new')
    expect(summary.peer?.username).toBe('bravo')
  })
  it('keeps summaries isolated by conversation', () => {
    const second = { ...chat, id: 'd', kind: 'group' as const, name: 'Команда' }
    const [first, group] = assembleChats([chat, second], [me, other, { ...me, conversation_id: 'd' }], [message('one', 'b', '2026-11-25T11:00:00Z')], [person], 'a')
    expect(first.unread).toBe(1)
    expect(group.unread).toBe(0)
    expect(group.last).toBeUndefined()
  })
})
