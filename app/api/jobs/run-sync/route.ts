export const runtime = 'nodejs';
import { NextResponse } from 'next/server';
import path from 'node:path';
import fs from 'node:fs/promises';

export const dynamic = 'force-dynamic';

// enkel fil-lock for å hindre parallelle kjøringer
async function withLock<T>(name: string, fn: () => Promise<T>): Promise<T> {
  const LOCKS_DIR = path.join(process.cwd(), 'var', 'locks');
  await fs.mkdir(LOCKS_DIR, { recursive: true });
  const lockFile = path.join(LOCKS_DIR, `${name}.lock`);

  try {
    await fs.writeFile(lockFile, String(Date.now()), { flag: 'wx' });
  } catch {
    // låst
    // @ts-ignore
    return NextResponse.json({ error: 'busy' }, { status: 429 }) as any;
  }
  try {
    const started = new Date();
    // … her ville man kalt ekte synk; vi simulerer tall og litt venting
    const counts = { products: 8, customers: 1, orders: 6 };
    // lite delay for å etterligne arbeid
    await new Promise(r => setTimeout(r, 250));

    const job = {
      id: `JOB-${Date.now()}`,
      ts: new Date().toISOString(),
      type: 'sync-all' as const,
      started: started.toString(),
      finished: new Date().toString(),
      counts,
    };

    const JOBS_DIR = path.join(process.cwd(), 'var', 'jobs');
    await fs.mkdir(JOBS_DIR, { recursive: true });
    await fs.writeFile(path.join(JOBS_DIR, `${job.id}.json`), JSON.stringify(job, null, 2), 'utf8');
    await fs.writeFile(path.join(JOBS_DIR, 'latest.json'), JSON.stringify({ item: job }, null, 2), 'utf8');

    return NextResponse.json({ id: job.id, counts: counts });
  } finally {
    try { await fs.unlink(lockFile); } catch {}
  }
}

export async function POST() {
  return withLock('run-sync', async () => null);
}
