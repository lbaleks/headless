import fs from 'fs'
import path from 'path'
export default async function openapi(app) {
  app.get('/v2/openapi.json', async (req, reply) => {
    const p = path.resolve(process.cwd(), 'src/docs/openapi.json')
    const buf = fs.readFileSync(p)
    reply.header('content-type','application/json; charset=utf-8')
    return reply.send(buf)
  })
  app.get('/v2/docs', async (req, reply) => {
    const html = `<!doctype html>
<html><head><meta charset="utf-8"/><title>Litebrygg Admin API Docs</title>
<script src="https://cdn.redoc.ly/redoc/latest/bundles/redoc.standalone.js"></script>
<style>body{margin:0} .hdr{padding:10px 14px;background:#0f172a;color:#fff;font-family:ui-sans-serif} .hdr code{background:#111827;padding:2px 6px;border-radius:6px}</style>
</head><body>
<div class="hdr">Litebrygg Admin API – <code>/v2/openapi.json</code></div>
<redoc spec-url="/v2/openapi.json"></redoc>
</body></html>`
    reply.type('text/html').send(html)
  })
}
