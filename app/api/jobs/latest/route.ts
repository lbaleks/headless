import { NextResponse } from 'next/server';
import path from 'node:path';
import fs from 'node:fs/promises';

export const dynamic = 'force-dynamic';

export async function GET() {
  const latest = path.join(process.cwd(), 'var', 'jobs', 'latest.json');
  try {
    const json = JSON.parse(await fs.readFile(latest, 'utf8'));
    return NextResponse.json(json);
  } catch {
    return NextResponse.json({ item: null });
  }
}
