import React from "react";
import Link from "next/link";
import { CartProvider } from "@/context/cart";

export const metadata = { title: "Litebrygg – Nettbutikk", description: "Frontend (store)" };

export default function StoreLayout({ children }: { children: React.ReactNode }) {
  return (
    <CartProvider>
      <div className="min-h-dvh flex flex-col">
        <header className="sticky top-0 z-20 bg-white/80 dark:bg-black/40 backdrop-blur border-b">
          <nav className="mx-auto max-w-6xl px-4 h-14 flex items-center gap-4">
            <Link href="/" className="font-semibold">Litebrygg</Link>
            <Link href="/cart" className="ml-auto">Kurv</Link>
            <Link href="/account">Min side</Link>
          </nav>
        </header>
        <main className="mx-auto max-w-6xl w-full px-4 py-6">{children}</main>
        <footer className="border-t py-6 text-center text-sm opacity-70">© Litebrygg</footer>
      </div>
    </CartProvider>
  );
}
