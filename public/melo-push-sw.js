/* Web Push: generic notifications, no private message content. */
self.addEventListener('push',event=>{
 let payload={};try{payload=event.data?event.data.json():{}}catch{}
 event.waitUntil(self.registration.showNotification('Melo',{body:'Новое сообщение. Откройте Melo.',icon:new URL('icon-192.png',self.registration.scope).href,badge:new URL('icon-192.png',self.registration.scope).href,tag:'melo-new-message',renotify:false,data:{url:self.registration.scope+'#/chats'}}))
});
self.addEventListener('notificationclick',event=>{
 event.notification.close();
 event.waitUntil((async()=>{
 const scope=self.registration.scope;const windows=await self.clients.matchAll({type:'window',includeUncontrolled:true});
 const existing=windows.find(c=>c.url.startsWith(scope));
 if(existing)return existing.focus();
 return self.clients.openWindow(scope+'#/chats');
 })());
});