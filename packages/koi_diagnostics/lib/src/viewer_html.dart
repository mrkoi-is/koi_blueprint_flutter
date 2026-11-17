import 'dart:convert';

import 'package:koi_diagnostics/src/diagnostic_strings.dart';

String viewerHtml(String language) {
  final s = DiagnosticStrings(language);
  final vocabulary = jsonEncode({
    'logs': s.logs,
    'network': s.network,
    'search': s.search,
    'export': s.export,
    'credential': s.credential,
    'more': s.loadMore,
    'source': s.source,
    'connect': s.connect,
    'connected': s.connected,
    'disconnected': s.disconnected,
    'denied': s.denied,
    'levels': s.allLevels,
  });
  return '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Diagnostics</title><style>
body{font:14px system-ui;margin:20px;color:#242424;background:#fcfcfc}header{display:flex;gap:8px;flex-wrap:wrap;align-items:center}button,input,select{font:inherit;padding:8px}main{display:grid;grid-template-columns:minmax(240px,1fr) minmax(0,2fr);gap:16px;margin-top:16px}#list button{display:block;width:100%;min-width:0;overflow-wrap:anywhere;text-align:left;border:0;border-bottom:1px solid #ddd;background:transparent}pre{white-space:pre-wrap;overflow-wrap:anywhere;max-width:100%}#status{margin:10px 0}@media(max-width:650px){main{display:block}}@media(prefers-color-scheme:dark){body{color:#eee;background:#202020}button,input,select{color:inherit;background:#303030}}
</style><header><input id="token" type="password" autocomplete="off"><button id="connect">Connect</button><select id="kind"></select><input id="search"><input id="source"><select id="level"><option value="">All levels</option><option>debug</option><option>info</option><option>warning</option><option>error</option></select><button id="export"></button><button id="more"></button></header><p id="status"></p><main><section id="list"></section><pre id="detail"></pre></main>
<script>
const words=$vocabulary;
document.getElementById('connect').textContent=words.connect;document.getElementById('level').firstElementChild.textContent=words.levels;
for(const [id,key] of [['search','search'],['source','source'],['token','credential']])document.getElementById(id).placeholder=words[key];
for(const [id,key] of [['export','export'],['more','more']])document.getElementById(id).textContent=words[key];
for(const [value,label] of [['log',words.logs],['network',words.network]]){let o=document.createElement('option');o.value=value;o.textContent=label;kind.append(o)}
let records=new Map(),cursor=null,events=null,revision=-1,request=0;
const status=document.getElementById('status'),detail=document.getElementById('detail');
function params(){let p=new URLSearchParams({kind:kind.value,text:search.value});if(source.value)p.set('source',source.value);if(level.value)p.set('level',level.value);return p;}
async function load(append=false){const seq=++request;try{let p=params();if(append&&cursor)p.set('cursor',cursor);let r=await fetch('/records?'+p);if(!r.ok)throw Error(r.status===401?words.denied:'HTTP '+r.status);let data=await r.json();if(seq!==request)return;if(!append)records.clear();cursor=data.nextCursor;revision=data.revision;
for(const e of data.items){let key=e.network?e.network.id:e.id;if(!records.has(key)||records.get(key).id<e.id)records.set(key,e)}
let list=document.getElementById('list');list.replaceChildren();for(const e of records.values()){let b=document.createElement('button');b.textContent=e.time+' '+e.level+' '+e.message+(e.network?' ['+e.network.state+']':'');b.onclick=()=>detail.textContent=JSON.stringify(e,null,2);list.append(b)}status.textContent=words.connected+' · '+revision;more.disabled=!cursor;
}catch(e){status.textContent=String(e)}}
connect.onclick=async()=>{document.cookie='koi_diagnostic='+encodeURIComponent(token.value)+'; SameSite=Strict; Path=/';token.value='';await load();if(events)events.close();events=new EventSource('/events');events.onmessage=e=>{if(Number(e.data)!==revision)load()};events.onerror=()=>status.textContent=words.disconnected;};
for(const id of ['kind','search','source','level'])document.getElementById(id).oninput=()=>load();
more.onclick=()=>load(true);document.getElementById('export').onclick=async()=>{let r=await fetch('/export?'+params());if(!r.ok){status.textContent='Export failed: '+r.status;return}let url=URL.createObjectURL(await r.blob());let a=document.createElement('a');a.href=url;a.download='diagnostics.ndjson';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)};
</script></html>''';
}
