#!/usr/bin/env bash
set -euo pipefail

FILE="app/admin/products/[id]/ProductDetail.client.tsx"

if ! test -f "$FILE"; then
  echo "Finner ikke $FILE" >&2
  exit 1
fi

python3 - "$FILE" <<'PY'
import sys, re, pathlib
p = pathlib.Path(sys.argv[1])
src = p.read_text()

added = False

# 1) Sørg for at adapter-funksjonen finnes
adapter = """
// Adapter sikrer at BulkVariantEdit alltid får props: variants og onVariantsChange
function BulkVariantEditAdapter({ product, onChange, ...rest }: any) {
  const variants = Array.isArray(product?.variants) ? product.variants : []
  const onVariantsChange = (next: any[]) => onChange({ ...product, variants: next })

  return (
    BulkVariantEdit ? (
      <BulkVariantEdit
        product={product}
        variants={variants}
        value={variants}
        list={variants}
        onChange={onChange}
        onVariantsChange={onVariantsChange}
        setVariants={onVariantsChange}
        {...rest}
      />
    ) : null
  )
}
""".lstrip()

if 'function BulkVariantEditAdapter' not in src:
    # Prøv å sette rett etter try/catch-blokken som initialiserer BulkVariantEdit
    pat = re.compile(r"(let\s+BulkVariantEdit[\s\S]+?catch\s*\{\s*\}\s*)", re.MULTILINE)
    m = pat.search(src)
    if m:
        src = src[:m.end()] + "\n" + adapter + "\n" + src[m.end():]
    else:
        # Hvis vi ikke finner blokken, legg den inn før første export default/return
        insert_at = src.find("export default")
        if insert_at == -1:
            insert_at = len(src)
        src = src[:insert_at] + "\n" + adapter + "\n" + src[insert_at:]
    added = True

# 2) Bytt alle <BulkVariantEdit .../> til <BulkVariantEditAdapter .../>
src_new = re.sub(r"<\s*BulkVariantEdit(\s[^/>]*)?/>", r"<BulkVariantEditAdapter\1/>", src)
if src_new != src:
    added = True
    src = src_new

# 3) For sikkerhets skyld: hvis komponenten BRUKES med åpne/lukkede tags, bytt også disse
src_new = re.sub(r"<\s*BulkVariantEdit(\s[^>]*)>", r"<BulkVariantEditAdapter\1>", src)
if src_new != src:
    added = True
    src = src_new
src_new = re.sub(r"</\s*BulkVariantEdit\s*>", r"</BulkVariantEditAdapter>", src)
if src_new != src:
    added = True
    src = src_new

p.write_text(src)
print("✓ Adapter er på plass og alle referanser er oppdatert." if added else "i Ingen endringer nødvendig (allerede ok).")
PY

echo "→ Rydder .next cache…"
rm -rf .next
echo "✓ Ferdig. Start dev-server på nytt."
