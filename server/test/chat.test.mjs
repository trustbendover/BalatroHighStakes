// Host-ordered lobby chat. Works against the TS server and the Lua host bridge.
import { spawn } from 'node:child_process'
import net from 'node:net'
import assert from 'node:assert/strict'

const ENTRY = process.env.SERVER_ENTRY || 'dist/main.js'
const PORT = 21770 + Math.floor(Math.random() * 1000)
const srv = spawn('node', [ENTRY], { env: { ...process.env, PORT: String(PORT) }, stdio: ['ignore', 'pipe', 'pipe'] })
let srvLog = ''
srv.stdout.on('data', (d) => { srvLog += d })
srv.stderr.on('data', (d) => { srvLog += d })
const fail = (e) => { console.error('FAIL', e); console.error(srvLog.slice(-2000)); srv.kill(); process.exit(1) }
setTimeout(() => fail('timeout'), 30000).unref()
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

class Fake {
  constructor(name) { this.name = name; this.msgs = []; this.waiters = [] }
  connect() {
    return new Promise((res, rej) => {
      this.sock = net.connect(PORT, '127.0.0.1', res)
      this.sock.on('error', rej)
      let buf = ''
      this.sock.on('data', (d) => {
        buf += d
        let i
        while ((i = buf.indexOf('\n')) >= 0) {
          const line = buf.slice(0, i); buf = buf.slice(i + 1)
          if (!line.trim()) continue
          const m = JSON.parse(line)
          if (m.action === 'keepAlive') { this.send({ action: 'keepAliveAck' }); continue }
          this.msgs.push(m)
          this.waiters = this.waiters.filter((w) => !w(m))
        }
      })
    })
  }
  send(o) { this.sock.write(JSON.stringify(o) + '\n') }
  wait(pred, label = '') {
    const i = this.msgs.findIndex(pred)
    if (i >= 0) return Promise.resolve(this.msgs.splice(i, 1)[0])
    return new Promise((res, rej) => {
      const t = setTimeout(() => rej(new Error(`${this.name} waiting for ${label}`)), 6000)
      this.waiters.push((m) => { if (pred(m)) { clearTimeout(t); this.msgs.splice(this.msgs.indexOf(m), 1); res(m); return true } return false })
    })
  }
  waitAction(a) { return this.wait((m) => m.action === a, a) }
  last(a) { for (let i = this.msgs.length - 1; i >= 0; i--) if (this.msgs[i].action === a) return this.msgs[i] }
}

async function person(name) {
  const c = new Fake(name)
  await c.connect()
  await c.waitAction('connected')
  c.send({ action: 'username', username: name, modHash: 'test' })
  c.send({ action: 'version', version: '0.6.9.1' })
  return c
}

async function main() {
  for (let i = 0; i < 50; i++) {
    try {
      await new Promise((res, rej) => { const s = net.connect(PORT, '127.0.0.1', () => { s.destroy(); res() }); s.on('error', rej) })
      break
    } catch { await sleep(100) }
  }
  const ann = await person('Ann~1')
  const bob = await person('Bob~2')
  ann.send({ action: 'createLobby', gameMode: 'attrition' })
  const joined = await ann.waitAction('joinedLobby')
  bob.send({ action: 'joinLobby', code: joined.code })
  await bob.waitAction('joinedLobby')
  await sleep(80)
  const lives = bob.last('playerInfo')?.lives
  ann.send({ action: 'chat', text: 'hello from the host' })
  bob.send({ action: 'chat', text: 'hello from the guest' })
  const a = await ann.wait((m) => m.action === 'chat' && m.text === 'hello from the guest', 'guest line')
  const b = await bob.wait((m) => m.action === 'chat' && m.text === 'hello from the host', 'host line')
  assert.equal(b.col, 1)
  assert.equal(a.col, 2)
  assert.equal(b.name, 'Ann')
  assert.equal(a.name, 'Bob')
  assert.notEqual(a.col, b.col)
  bob.send({ action: 'chat', text: 'y'.repeat(550) })
  const kept = await bob.wait((m) => m.action === 'chat' && m.text && m.text.length === 550, '550')
  assert.equal(kept.text.length, 550)
  bob.send({ action: 'chat', text: '   ' })
  bob.send({ action: 'chat', text: 'x'.repeat(551) })
  const empty = await bob.wait((m) => m.action === 'chatReject', 'reject')
  const long = await bob.wait((m) => m.action === 'chatReject' && m.reason === 'long', 'long')
  assert.equal(empty.reason === 'empty' || long.reason === 'long', true)
  assert.equal(bob.last('playerInfo')?.lives, lives)
  bob.send({ action: 'readyLobby' })
  await sleep(50)
  ann.send({ action: 'startGame' })
  const reset = await ann.waitAction('chatState')
  assert.equal(reset.view, 'match')
  assert.equal(reset.clear, true)
  ann.send({ action: 'chat', text: 'during the match' })
  const during = await bob.wait((m) => m.action === 'chat' && m.text === 'during the match', 'match line')
  assert.equal(during.scope, 'match')
  assert.equal(during.col, 1)
  console.log('ok: chat host and guest, distinct name colors, empty and too-long rejected, new match log')
  for (const c of [ann, bob]) c.sock.destroy()
  srv.kill()
  process.exit(0)
}
main().catch(fail)
