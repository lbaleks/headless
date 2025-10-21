export const runtime = 'nodejs';
import { NextResponse } from 'next/server'
import { health } from '@/integrations/magento/client'
export async function GET(){ return NextResponse.json(await health()) }
