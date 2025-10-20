import { NextResponse } from 'next/server'
export async function GET() {
  // kan senere hentes fra ekstern PIM – holdes lokalt nå
  return NextResponse.json({
    channels: [
      { code: 'ecommerce', label: 'E-commerce', locales: ['en_US','nb_NO'] },
      { code: 'admin',     label: 'Admin',     locales: ['en_US'] }
    ],
    default: { channel: 'ecommerce', locale: 'nb_NO' }
  })
}
