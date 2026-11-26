import { useState,useEffect,useCallback } from 'react'
import { db } from './lib'
function err(e:unknown){return e&&typeof e==='object'&&'message' in e?String(e.message):String(e)}
function vapidKey(value:string){const s=value.replace(/-/g,'+').replace(/_/g,'/');return Uint8Array.from(atob(s+'='.repeat((4-s.length%4)%4)),c=>c.charCodeAt(0))}
async function registration(){const reg=await navigator.serviceWorker.getRegistration();if(reg?.active)return reg;return Promise.race([navigator.serviceWorker.ready,new Promise<never>((_,reject)=>setTimeout(()=>reject(new Error('Service worker ещё не активен. Обновите страницу.')),8000))])}
export async function disableDevicePush(){if(!db||!('serviceWorker' in navigator)||!('PushManager' in window))return;const reg=await navigator.serviceWorker.getRegistration();const sub=await reg?.pushManager.getSubscription();if(sub){await db.rpc('melo_push_unregister',{p_endpoint:sub.endpoint});await sub.unsubscribe()}}
export function PushSettings(){const supported='serviceWorker' in navigator&&'PushManager' in window&&'Notification' in window&&window.isSecureContext;
 const [enabled,setEnabled]=useState(false),[busy,setBusy]=useState(false),[status,setStatus]=useState('');
 const check=useCallback(async()=>{if(!supported||!db)return;try{const reg=await navigator.serviceWorker.getRegistration();const sub=await reg?.pushManager.getSubscription();if(!sub){setEnabled(false);return}const {data,error}=await db.rpc('melo_push_registered',{p_endpoint:sub.endpoint});if(error)throw error;setEnabled(Boolean(data))}catch(e){setStatus(err(e))}},[supported]);
 useEffect(()=>{check()},[check]);
 async function enable(){if(!db||busy||!supported)return;setBusy(true);setStatus('');try{
 const permission=await Notification.requestPermission();if(permission!=='granted')throw Error('Разрешите уведомления в браузере');
 const reg=await registration();const {data,error}=await db.functions.invoke('melo-push',{body:{action:'key'}});if(error)throw error;if(typeof data?.publicKey!=='string')throw Error('Push-ключ недоступен');
 let sub=await reg.pushManager.getSubscription();
 if(!sub)sub=await reg.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:vapidKey(data.publicKey)});
 const info=sub.toJSON();if(!info.keys?.p256dh||!info.keys?.auth)throw Error('Браузер не вернул ключи подписки');
 const result=await db.rpc('melo_push_register',{p_endpoint:sub.endpoint,p_key:info.keys.p256dh,p_auth:info.keys.auth});if(result.error)throw result.error;
 setEnabled(true);setStatus('Push-уведомления включены на этом устройстве');
 }catch(e){setStatus(err(e))}finally{setBusy(false)}}
 async function disable(){if(busy)return;setBusy(true);setStatus('');try{await disableDevicePush();setEnabled(false);setStatus('Push-уведомления отключены')}catch(e){setStatus(err(e))}finally{setBusy(false)}}
 return <section className="melo-tool-card"><h3>Push-уведомления</h3><p>Новые сообщения при закрытой вкладке. Уведомления не содержат текст переписки.</p>{supported?<><button className="melo-tool-button" disabled={busy} onClick={enabled?disable:enable}>{busy?'Подключение…':enabled?'Отключить на этом устройстве':'Включить на этом устройстве'}</button><small>{enabled?'Включены':'Выключены'} · доставка зависит от браузера и сети</small></>:<small>Этот браузер не поддерживает Web Push. На iPhone установите Melo на экран «Домой» и откройте его оттуда.</small>}{status&&<p role="status">{status}</p>}</section>}
