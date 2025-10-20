"use client";
import React from 'react'
// Hydration-safe AdminPage med tabs

export type TabDef = { key: string; label: string }

type Props = {
  title: string
  actions?: React.ReactNode
  tabs?: TabDef[]
  activeTab?: string
  onTabChange?: (key: string) => void
  children: React.ReactNode
}

function TabBar({
  tabs = [],
  active,
  onChange,
}: { tabs?: TabDef[]; active?: string; onChange?: (k: string) => void }) {
  if (!tabs || tabs.length === 0) return null
  return (
    <div className="mt-4 border-b">
      <nav className="flex gap-2">
        {tabs.map(t => {
          const isActive = t.key === active
          const base = 'px-3 py-2 text-sm rounded-t'
          const cls = isActive
            ? base + ' bg-neutral-900 text-white'
            : base + ' text-neutral-700 hover:bg-neutral-200'
          return (
            <button
              key={t.key}
              type="button"
              className={cls}
              onClick={() => onChange?.(t.key)}
            >
              {t.label}
            </button>
          )
        })}
      </nav>
    </div>
  )
}

export function AdminPage({
  title,
  actions,
  tabs,
  activeTab,
  onTabChange,
  children,
}: Props) {
  return (
    <div className="p-4">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold">{title}</h1>
        {actions && <div className="flex items-center gap-2">{actions}</div>}
      </div>

      <TabBar tabs={tabs} active={activeTab} onChange={onTabChange} />

      <div className="mt-4">{children}</div>
    </div>
  )
}

// Gi både named og default export for å tåle begge import-varianter
export default AdminPage
