'use client';
import { useEffect,useState } from 'react'
import AdminPage from '@/components/AdminPage'

type User={id:string;name:string;email:string;role:string;active:boolean}
export default function UsersPage(){
  const [users,setUsers]=useState<User[]>([])
  const [page,setPage]=useState(1)
  const [total,setTotal]=useState(0)
  const [query,setQuery]=useState('')
  const [busy,setBusy]=useState(false)
  const size=10
  const fetchUsers=async()=>{
    const r=await fetch('/api/users?q='+encodeURIComponent(query)+'&page='+page+'&size='+size)
    const j=await r.json(); setUsers(j.users); setTotal(j.total)
  }
  useEffect(()=>{fetchUsers()},[page,query])

  const toggle=async(u:User)=>{
    setBusy(true)
    await fetch('/api/users',{method:'PUT',headers:{'content-type':'application/json'},body:JSON.stringify({...u,active:!u.active})})
    await fetchUsers(); setBusy(false)
  }

  const del=async(u:User)=>{
    if(!confirm('Delete '+u.name+'?'))return
    setBusy(true); await fetch('/api/users?id='+u.id,{method:'DELETE'}); await fetchUsers(); setBusy(false)
  }

  const pages=Math.ceil(total/size)
  return (
    <AdminPage title="Users">
      <div className="flex items-center justify-between mb-4">
        <input placeholder="Search..." className="border p-2 rounded w-60" value={query} onChange={e=>{setQuery(e.target.value);setPage(1)}} />
        <div className="text-sm text-gray-500">Page {page}/{pages||1}</div>
      </div>
      <table className="min-w-full border text-sm">
        <thead className="bg-gray-50"><tr><th className="p-2 border">Name</th><th className="p-2 border">Email</th><th className="p-2 border">Role</th><th className="p-2 border">Active</th><th className="p-2 border">Actions</th></tr></thead>
        <tbody>
          {users.map(u=>(
            <tr key={u.id} className="odd:bg-white even:bg-gray-50">
              <td className="p-2 border">{u.name}</td>
              <td className="p-2 border">{u.email}</td>
              <td className="p-2 border">{u.role}</td>
              <td className="p-2 border text-center">{u.active?'✅':'❌'}</td>
              <td className="p-2 border text-right space-x-2">
                <button disabled={busy} onClick={()=>toggle(u)} className="px-2 py-1 border rounded">{u.active?'Deactivate':'Activate'}</button>
                <button disabled={busy} onClick={()=>del(u)} className="px-2 py-1 border rounded text-red-600">Delete</button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      <div className="flex justify-between mt-3">
        <button onClick={()=>setPage(p=>Math.max(1,p-1))} disabled={page<=1} className="px-3 py-1 border rounded">Prev</button>
        <button onClick={()=>setPage(p=>p+1)} disabled={page>=pages} className="px-3 py-1 border rounded">Next</button>
      </div>
    </AdminPage>
  )
}
