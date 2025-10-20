#!/usr/bin/env bash
set -euo pipefail
FILE="lib/env.ts"
tmp="$(mktemp)"
awk '
  BEGIN{patched=0}
  {
    print $0
  }
  END{
    if(!patched){ }
  }
' "$FILE" > "$tmp"

# Replace getAdminToken body to strip JSON quotes
perl -0777 -pe '
  s/export async function getAdminToken\([^\)]*\)\s*:\s*Promise<string>\s*\{[\s\S]*?\}/export async function getAdminToken(baseUrl: string, user: string, pass: string): Promise<string> {\n  const res = await fetch(`${v1(baseUrl)}/integration\/admin\/token`, {\n    method: "POST",\n    headers: { "Content-Type": "application\/json" },\n    body: JSON.stringify({ username: user, password: pass }),\n    cache: "no-store",\n  });\n  if (!res.ok) throw new Error(`Admin token ${res.status}`);\n  const t = (await res.text()).trim();\n  // Magento returns a JSON string: \"eyJ...\" → strip safely\n  try { const j = JSON.parse(t); if (typeof j === "string") return j.trim(); } catch {}\n  return t.replace(/^\"|\"$/g, \"\").trim();\n}/s
' -i "$FILE"

echo "✓ fixed getAdminToken in $FILE"
