// app/lib/rbac.ts
export type Role = "admin" | "ops" | "support" | "viewer";

export async function getRole(): Promise<Role> {
  try {
    const r = await fetch("/api/auth/role", { cache: "no-store" });
    const j = await r.json();
    return (j?.role as Role) || "viewer";
  } catch {
    return "viewer";
  }
}

export async function setRole(role: Role) {
  await fetch("/api/auth/role", {
    method: "POST",
    headers: { "Content-Type":"application/json" },
    body: JSON.stringify({ role })
  });
}
