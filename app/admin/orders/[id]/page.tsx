import React from 'react'
import { AdminPage } from '@/components/AdminPage'
import OrderDetail from './OrderDetail.client'

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  return (
    <AdminPage title={`Order #${id}`}>
      <OrderDetail id={id} />
    </AdminPage>
  )
}
