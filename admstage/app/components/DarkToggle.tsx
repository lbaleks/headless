"use client";
import { useEffect, useState } from "react";

export default function DarkToggle() {
  const [ready, setReady] = useState(false);
  const [dark, setDark] = useState(false);

  useEffect(() => {
    setReady(true);
    const root = document.documentElement;
    const stored = localStorage.getItem("theme");
    const isDark = stored ? stored === "dark" : root.classList.contains("dark");
    setDark(isDark);
    root.classList.toggle("dark", isDark);
  }, []);

  if (!ready) return null;

  const toggle = () => {
    const next = !dark;
    setDark(next);
    document.documentElement.classList.toggle("dark", next);
    localStorage.setItem("theme", next ? "dark" : "light");
  };

  return (
    <button
      onClick={toggle}
      style={{ position: "fixed", right: 16, bottom: 16, zIndex: 9999 }}
      className="px-3 py-2 rounded-lg border bg-white/80 backdrop-blur dark:bg-neutral-800 dark:text-neutral-100"
      aria-label={dark ? "Switch to light mode" : "Switch to dark mode"}
    >
      {dark ? "☀️ Light" : "🌙 Dark"}
    </button>
  );
}
