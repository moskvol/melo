import { createClient } from 'npm:@supabase/supabase-js@2.81.1'
import webpush from 'npm:web-push@3.6.7'

const url=Deno.env.get('SUPABASE_URL')!
const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}})
const cors={'Access-Control-Allow-Origin':'https://moskvol.github.io','Access-Control-Allow-Headers':'authorization, apikey, x-client-info, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Vary':'Origin'}
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store'}})
function allowed(endpoint:string){
 try{
 const u=new URL(endpoint),h=u.hostname.toLowerCase();
 return u.protocol==='https:'&&!u.username&&!u.password&&!u.port&&(h==='fcm.googleapis.com'||h.endsWith('.push.services.mozilla.com')||h==='web.push.apple.com'||h.endsWith('.web.push.apple.com')||h==='notify.windows.com'||h.endsWith('.notify.windows.com'));
 }catch{return false}
}
function same(a:string,b:string){if(a.length!==b.length)return false;let d=0;for(let i=0;i<a.length;i++)d|=a.charCodeAt(i)^b.charCodeAt(i);return d===0}
type Job={job_id:string;endpoint:string;p256dh:string;auth_key:string}
Deno.serve(async(req)=>{
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
 if(req.method!=='POST')return json({error:'Method not allowed'},405);
 let body:{action?:string};try{body=await req.json()}catch{return json({error:'Invalid request'},400)}
 try{
 if(body.action==='key'){
 const token=req.headers.get('authorization')?.replace(/^Bearer\s+/i,'');
 if(!token)return json({error:'Unauthorized'},401);
 const {data:user,error:authError}=await admin.auth.getUser(token);
 if(authError||!user.user)return json({error:'Unauthorized'},401);
 let {data:config,error}=await admin.rpc('melo_push_worker_config');
 if(error)throw error;
 if(!config?.public||!config?.private){
 const pair=webpush.generateVAPIDKeys();
 const r=await admin.rpc('melo_push_worker_config',{p_public:pair.publicKey,p_private:pair.privateKey});if(r.error)throw r.error;config=r.data;
 }
 return json({publicKey:config.public});
 }
 if(body.action!=='dispatch')return json({error:'Invalid action'},400);
 const provided=req.headers.get('x-melo-worker-key')||'';
 if(provided.length!==64)return json({error:'Unauthorized'},401);
 const {data:config,error}=await admin.rpc('melo_push_worker_config');if(error)throw error;
 if(typeof config?.worker!=='string'||!same(provided,config.worker))return json({error:'Unauthorized'},401);
 if(!config.public||!config.private)return json({processed:0});
 const {data,error:claimError}=await admin.rpc('melo_push_claim');if(claimError)throw claimError;
 const jobs=(data||[]) as Job[];
 const send=async(job:Job)=>{
 let outcome='retry';
 if(!allowed(job.endpoint))outcome='invalid';
 else try{
 await webpush.sendNotification({endpoint:job.endpoint,keys:{p256dh:job.p256dh,auth:job.auth_key}},JSON.stringify({title:'Melo',body:'Новое сообщение. Откройте Melo.'}),{TTL:120,urgency:'normal',timeout:8000,vapidDetails:{subject:'https://moskvol.github.io/melo/',publicKey:config.public,privateKey:config.private}});
 outcome='sent';
 }catch(e){const status=(e as {statusCode?:number})?.statusCode;if(status===404||status===410)outcome='expired';else if(status===400||status===413)outcome='invalid'}
 const result=await admin.rpc('melo_push_finish',{job:job.job_id,outcome});if(result.error)console.error('Push completion failed');
 };
 for(let i=0;i<jobs.length;i+=6)await Promise.all(jobs.slice(i,i+6).map(send));
 return json({processed:jobs.length});
 }catch{console.error('Melo push request failed');return json({error:'Push service temporarily unavailable'},500)}
})
