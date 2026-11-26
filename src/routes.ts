export type Page = 'chats' | 'contacts' | 'search' | 'profile' | 'settings' | 'admin' | 'community' | 'stats' | 'market' | 'gifts' | 'marketAdmin' | 'studio' | 'saved' | 'music' | 'stickers' | 'year' | 'updates'
export type MeloRoute = {kind:'page';page:Page}|{kind:'chat';id:string}|{kind:'channel';username:string}|{kind:'username';username:string}|{kind:'invite';token:string}|{kind:'auth'}|{kind:'unknown'}
const pages:Record<Page,string>={chats:'chats',contacts:'contacts',search:'search',profile:'profile',settings:'settings',admin:'admin',community:'community',stats:'admin/stats',market:'market',gifts:'gifts',marketAdmin:'admin/market',studio:'tools',saved:'saved',music:'music',stickers:'tools/stickers',year:'year',updates:'updates'}
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const handle=/^[a-z][a-z0-9_]{3,31}$/
export const pageHash=(page:Page)=>'#/'+pages[page]
export const chatHash=(id:string)=>'#/chat/'+id
export const channelHash=(username:string)=>'#/channel/'+username
export const usernameHash=(username:string)=>'#/username/'+username
export const inviteHash=(token:string)=>'#/invite/'+token
export function parseRoute(hash:string):MeloRoute{
 if(!hash||hash==='#'||hash==='#/')return {kind:'page',page:'chats'}
 if(/(?:^#|[&])(?:access_token|refresh_token|error|type|token_hash)=/.test(hash))return {kind:'auth'}
 const legacy=hash.match(/^#(username|invite)=([^&]+)$/)
 const route=legacy?legacy[1]+'/'+legacy[2]:hash.startsWith('#/')?hash.slice(2).replace(/\/$/,''):''
 const oldTools:Record<string,Page>={studio:'studio',bots:'studio',apps:'studio','tools/studio':'studio','tools/bots':'studio','tools/apps':'studio'}
 if(Object.prototype.hasOwnProperty.call(oldTools,route))return {kind:'page',page:oldTools[route]}
 const page=(Object.keys(pages) as Page[]).find(p=>pages[p]===route)
 if(page)return {kind:'page',page}
 const [kind,value,...rest]=route.split('/')
 if(rest.length||!value)return {kind:'unknown'}
 if(kind==='chat'&&uuid.test(value))return {kind:'chat',id:value}
 if(kind==='channel'&&handle.test(value))return {kind:'channel',username:value}
 if(kind==='username'&&handle.test(value)&&value.length<=24)return {kind:'username',username:value}
 if(kind==='invite'&&uuid.test(value))return {kind:'invite',token:value}
 return {kind:'unknown'}
}
export function writeHash(hash:string,replace=false){if(location.hash===hash)return;history[replace?'replaceState':'pushState'](null,'',location.pathname+location.search+hash)}
