// Enkel SKU-forslag: strip, normaliser, norske tegn, A–Z/0–9, dash
export function suggestSku(input: string): string {
  const s = String(input || '')
    .normalize('NFKD')
    .replace(/[æÆ]/g, 'AE')
    .replace(/[øØ]/g, 'OE')
    .replace(/[åÅ]/g, 'AA')
    .replace(/[\u0300-\u036f]/g, '')        // diakritika
    .replace(/[^A-Za-z0-9]+/g, '-')         // alt annet → bindestrek
    .replace(/^-+|-+$/g, '')                // trim bindestreker
    .toUpperCase();
  return s || 'SKU';
}
export default suggestSku;
