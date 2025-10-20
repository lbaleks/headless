"use client";
import * as React from 'react'
import {usePathname} from 'next/navigation'
/* eslint-disable jsx-a11y/no-static-element-interactions, jsx-a11y/click-events-have-key-events */

type Item = { label:string; href?:string; children?:Item[] }
const NAV: Item[] = [
  { label:'Dashboard', href:'/admin/dashboard' },
  { label:'Products', children:[
      { label:'All products', href:'/admin/products' },
      { label:'Pricing', href:'/admin/pricing' },
      { label:'Categories', href:'/admin/categories' },
      { label:'Parametrics', href:'/admin/parametrics' },
    ]
  },
  { label:'Shopping', children:[
      { label:'Orders', href:'/admin/orders' },
      { label:'Returns (RMA)', href:'/admin/returns' }
    ]
  },
  { label:'Promotions', href:'/admin/promotions' },
  { label:'Customers', children:[
      { label:'All customers', href:'/admin/customers' },
      { label:'Segments', href:'/admin/segments' },
    ]
  },
  { label:'Suppliers', children:[
      { label:'Directory', href:'/admin/suppliers' }
    ]
  },
  { label:'Integrations', children:[
      { label:'Magento', href:'/admin/integrations/magento' },
      { label:'Channels', href:'/admin/channels' }
    ]
  },
  { label:'Settings', href:'/admin/settings' },
]

function Caret({open}:{open:boolean}){ return <span className={"inline-block transition-transform "+(open?'rotate-90':'rotate-0')}>›</span> }

export default function AdminNav(){
  const pathname = usePathname() || ''
  const [open,setOpen]=useState<Record<string,boolean>>({})
  useEffect(()=>{
    // auto-åpne gruppa som matcher aktiv rute
    NAV.forEach(g=>{
      if(g.children?.some(c=>pathname.startsWith(c.href||''))){
        setOpen(o=>({...o,[g.label]:true}))
      }
    })
  },[pathname])

  const Link = ({href,children}:{href?:string;children:React.ReactNode}) =>
    href ? <a href={href} className="block no-underline">{children}</a> : <>{children}</>

  const isActive=(href?:string)=> href && pathname.startsWith(href)

  return (
    <aside className="lb-side fixed left-0 top-0 bottom-0">
      <div className="lb-side-inner">
        <div className="lb-brand">norce-style</div>
        <nav className="lb-menu">
          {NAV.map((g,i)=>{
            const hasChildren=!!g.children?.length
            const groupActive = isActive(g.href) || g.children?.some(c=>isActive(c.href))
            return (
              <div key={i} className="lb-group">
                <div className={"lb-group-head "+(groupActive?'active':'')}
                  onClick={()=> hasChildren && setOpen(o=>({...o,[g.label]:!o[g.label]}))}>
                  {hasChildren && <Caret open={!!open[g.label]} />} <span>{g.label}</span>
                </div>
                {!hasChildren && g.href && (
                  <Link href={g.href}><div className={"lb-leaf "+(isActive(g.href)?'active':'')}>{g.label}</div></Link>
                )}
                {hasChildren && open[g.label] && (
                  <div className="lb-children">
                    {g.children!.map((c,idx)=>(
                      <Link key={idx} href={c.href}>
                        <div className={"lb-leaf "+(isActive(c.href)?'active':'')}>{c.label}</div>
                      </Link>
                    ))}
                  </div>
                )}
              </div>
            )
          })}
        </nav>
      </div>
    </aside>
  )
}
