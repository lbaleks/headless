import React from 'react'
import OrderCreate from './OrderCreate.client'

export const metadata = {
  title: 'Opprett ordre'
}

export default async function Page() {
  // Server-komponent som rendrer klient-komponenten (ingen params)
  return <OrderCreate />
}
