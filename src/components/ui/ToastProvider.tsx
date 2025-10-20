'use client';
import * as React from 'react'
export default function ToastProvider({ children }:{children:React.ReactNode}){
  // Eksponér en enkel toast-hook globalt om ønskelig senere
  return <>{children}</>
}
