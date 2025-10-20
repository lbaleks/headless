import assert from 'node:assert/strict'
const base = process.env.BASE_URL || 'http://localhost:3000'
const j = r => r.json()
const ok = r => { if(!r.ok) throw new Error(r.status+': '+r.statusText); return r }
const health = await fetch(base+'/api/health').then(ok).then(j); console.assert(health.ok===true)
const rules  = await fetch(base+'/api/pricing/rules').then(ok).then(j); console.assert(Array.isArray(rules.rules))
const id='autotest-rule'
await fetch(base+'/api/pricing/rules',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({id,name:'Auto Test',type:'margin',value:0.2,enabled:true})}).then(r=>r.ok||r.status===409?r:Promise.reject(new Error(r.status)))
const updated = await fetch(base+'/api/pricing/rules',{method:'PUT',headers:{'content-type':'application/json'},body:JSON.stringify({id,name:'Auto Test',type:'margin',value:0.25,enabled:true})}).then(ok).then(j); console.assert(updated.value===0.25)
await fetch(base+`/api/pricing/rules?id=${id}`,{method:'DELETE'}).then(r=>r.ok||Promise.reject(new Error(r.status)))
console.log('Sanity OK')
