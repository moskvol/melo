import { describe,it,expect } from 'vitest'
import { parseRoute,pageHash,chatHash,channelHash,usernameHash,inviteHash } from './routes'
const id='490f2d56-691a-4326-9370-2787975140e0'
describe('Melo hash routing',()=>{
 it('round trips every page',()=>{for(const p of ['chats','contacts','search','profile','settings','admin','community','stats','market','gifts','marketAdmin','studio'] as const)expect(parseRoute(pageHash(p))).toEqual({kind:'page',page:p})})
 it('redirects retired tools routes to Studio',()=>{expect(pageHash('studio')).toBe('#/tools');for(const h of ['#/studio','#/bots','#/apps','#/tools/studio','#/tools/bots','#/tools/apps'])expect(parseRoute(h)).toEqual({kind:'page',page:'studio'})})
 it('opens direct conversation and public channel',()=>{expect(parseRoute(chatHash(id))).toEqual({kind:'chat',id});expect(parseRoute(channelHash('melo_news'))).toEqual({kind:'channel',username:'melo_news'})})
 it('supports new and old collectible and group invitation links',()=>{for(const h of [usernameHash('legend'),'#username=legend'])expect(parseRoute(h)).toEqual({kind:'username',username:'legend'});for(const h of [inviteHash(id),'#invite='+id])expect(parseRoute(h)).toEqual({kind:'invite',token:id})})
 it('leaves auth callbacks alone',()=>{expect(parseRoute('#access_token=example&type=recovery')).toEqual({kind:'auth'})})
 it('handles invalid and root routes',()=>{expect(parseRoute('')).toEqual({kind:'page',page:'chats'});expect(parseRoute('#/chat/invalid')).toEqual({kind:'unknown'});expect(parseRoute('#/admin/unknown')).toEqual({kind:'unknown'})})
})
