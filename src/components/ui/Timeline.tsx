'use client';

import * as React from 'react';

type TimelineItem = {
  id?: string | number;
  ts: string | number | Date;         // tidsstempel
  text: string;                       // beskrivelse
  tone?: 'info' | 'success' | 'warn' | 'danger' | 'neutral';
};

export default function Timeline({ items }: { items?: TimelineItem[] }) {
  const toneCls: Record<NonNullable<TimelineItem['tone']>, string> = {
    info: 'bg-blue-600',
    success: 'bg-green-600',
    warn: 'bg-amber-500',
    danger: 'bg-red-600',
    neutral: 'bg-neutral-300',
  };

  const safeItems = items ?? [];

  return (
    <div className="space-y-3">
      {safeItems.map((i, idx) => {
        // stabil og unik key:
        const key =
          i.id != null
            ? String(i.id)
            : (i.ts != null ? `${new Date(i.ts as any).getTime()}-${i.text}` : `idx-${idx}`);

        const dot = toneCls[i.tone ?? 'neutral'];

        return (
          <div key={key} className="relative pl-4">
            <div className={`absolute left-0 top-1.5 h-2 w-2 rounded-full ${dot}`} />
            <div className="text-sm text-neutral-900">{i.text}</div>
            <div className="text-xs text-neutral-500">
              {new Date(i.ts as any).toLocaleString()}
            </div>
          </div>
        );
      })}
    </div>
  );
}