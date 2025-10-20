import type { NextRequest } from 'next/server';
import { NextResponse } from 'next/server';

export function middleware(_req: NextRequest) {
  // Legg inn auth / rewrites her ved behov
  return NextResponse.next();
}

export const config = {
  // Tillat statiske assets; alt annet matcher.
  matcher: ['/((?!_next/static|_next/image|favicon.ico|.*\\..*).*)'],
};
