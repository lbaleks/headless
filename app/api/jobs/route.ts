import { NextResponse } from 'next/server';
import path from 'node:path';
import fs from 'node:fs/promises';

export const dynamic = 'force-dynamic';

export async function GET() {
  const dir = path.join(process.cwd(), 'var', 'jobs');
  try {
    const entries = await fs.readdir(dir);
    const items = [];
    for (const f of entries) {
      if (f.endsWith('.json') && f !== 'latest.json') {
        const j = JSON.parse(await fs.readFile(path.join(dir, f), 'utf8'));
        items.push(j);
      }
    }
    items.sort((a,b)=> (a.id> b.id ? -1 : 1));
    return NextResponse.json({ total: items.length, items });
  } catch {
    return NextResponse.json({ total: 0, items: [] });
  }
}
