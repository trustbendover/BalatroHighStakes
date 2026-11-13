// TCP <-> Lua P2P-server-core bridge: lets the normal server tests run against
// mod/networking/p2p_server.lua. Usage: PORT=xxxx node test/luaBridge.mjs
import net from 'node:net'
import { spawn } from 'node:child_process'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
const here = path.dirname(fileURLToPath(import.meta.url))
const core = process.env.LUA_CORE || path.resolve(here, '../../mod/networking/p2p_server.lua')
const lua = spawn(process.env.LUAJIT || 'luajit', [path.join(here, 'lua_harness.lua'), here, core], { stdio: ['pipe', 'pipe', 'inherit'] })
const socks = new Map(); let nextId = 1; let buf = ''
lua.stdout.on('data', (d) => {
  buf += d; let i
  while ((i = buf.indexOf('\n')) >= 0) {
    const line = buf.slice(0, i); buf = buf.slice(i + 1); if (!line) continue
    const f = JSON.parse(line); const s = socks.get(f.id); if (!s) continue
    if (f.close) { s.destroy(); continue }
    s.write(JSON.stringify(f.m) + '\n')
  }
})
// Stamp every command with millisecond time. The Lua host used to read os.time(),
// so a 1s grace could expire on the next whole second (before this reconnect finished).
const send = (o) => { o.now = Date.now() / 1000; lua.stdin.write(JSON.stringify(o) + '\n') }
// the game calls Server:tick() about once per frame/second; do the same here
setInterval(() => send({ t: 'tick' }), 250).unref()
net.createServer((s) => {
  const id = nextId++; socks.set(id, s); send({ t: 'open', id }); let b = ''
  s.on('data', (d) => { b += d; let i; while ((i = b.indexOf('\n')) >= 0) { const l = b.slice(0, i); b = b.slice(i + 1); if (l.trim()) { try { send({ t: 'msg', id, m: JSON.parse(l) }) } catch {} } } })
  const gone = () => { if (socks.has(id)) { socks.delete(id); send({ t: 'close', id }) } }
  s.on('close', gone); s.on('error', gone)
}).listen(Number(process.env.PORT), '127.0.0.1', () => console.log('lua bridge listening'))
process.on('SIGTERM', () => { lua.kill(); process.exit(0) })
