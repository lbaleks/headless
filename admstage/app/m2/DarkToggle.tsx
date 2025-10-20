"use client";
/* eslint-disable @typescript-eslint/no-unused-expressions */
// app/m2/DarkToggle.tsximport { useEffect, useState } from "react";

export default function DarkToggle() {
  const [on, setOn] = useState(false);
  useEffect(() => {
    const el = document.documentElement;
    on ? el.classList.add("dark") : el.classList.remove("dark");
  }, [on]);
  return (
    <button
      onClick={() => setOn(v => !v)}
      className="px-3 py-2 rounded-lg border hover:bg-black/5"
    >
      {on ? "☀️ Light" : "🌙 Dark"}
    </button>
  );
}
