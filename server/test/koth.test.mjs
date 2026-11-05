// King of the Hill: rule vectors (TS) + a full 3-player KotH game over TCP.
// Runs against the TS server (dist/main.js) or the Lua core (SERVER_ENTRY=test/luaBridge.mjs).
import { spawn } from 'node:child_process'
import net from 'node:net'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import assert from 'node:assert/strict'

const here = path.dirname(fileURLToPath(import.meta.url))
const ENTRY = process.env.SERVER_ENTRY || 'dist/main.js'

// ---- 1. shared rule vectors (TS implementation; the Lua one is checked by mod/tests/test_koth.lua)
if (!process.env.SERVER_ENTRY) {
  const { resolveKoth, kothConfig } = await import(path.resolve(here, '../dist/koth.js'))
  const V = JSON.parse(fs.readFileSync(path.resolve(here, '../../mod/tests/koth_vectors.json'), 'utf8'))
  for (const c of V.cases) {
    const entries = Object.keys(c.scores).sort().map((id) => ({ id, name: 'n' + id, score: c.scores[id] }))
    const min = Math.min(...entries.map((e) => e.score))
    const lows = entries.filter((e) => e.score === min)
    const loser = lows.length === 1 ? lows[0].id : null
    const st = { kingId: c.state.kingId, streak: c.state.streak }
    const ev = resolveKoth(st, entries, loser, (a, b) => a > b, (a, b) => a === b, kothConfig(c.options))
    const finalLoser = loser !== ev.shieldedId ? loser : null
    for (const [k, want] of Object.entries(c.expect)) {
      const got = k === 'loser' ? finalLoser : ev[k]
      if (k === 'crowned' && !want) continue
      assert.equal(got ?? null, want ?? null, `${c.name}: ${k}`)
    }
    console.log('ok: vector ' + c.name)
  }
}

// ---- 2. full game
const PORT = 19788 + Math.floor(Math.random() * 1000)
const srv = spawn('node', [ENTRY], { env: { ...process.env, PORT: String(PORT) }, stdio: ['ignore', 'pipe', 'pipe'] })
let srvLog = ''
srv.stdout.on('data', (d) => { srvLog += d }); srv.stderr.on('data', (d) => { srvLog += d })
const fail = (e) => { console.error('FAIL', e); console.error(srvLog.slice(-2000)); srv.kill(); process.exit(1) }
setTimeout(() => fail('timeout'), 30000).unref()
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

class Fake {
  constructor(name) { this.name = name; this.msgs = []; this.waiters = [] }
  connect() {
    return new Promise((res, rej) => {
      this.sock = net.connect(PORT, '127.0.0.1', res); this.sock.on('error', rej)
      let buf = ''
      this.sock.on('data', (d) => {
        buf += d; let i
        while ((i = buf.indexOf('\n')) >= 0) {
          const line = buf.slice(0, i); buf = buf.slice(i + 1)
          if (!line.trim()) continue
          const m = JSON.parse(line)
          if (m.action === 'keepAlive') { this.send({ action: 'keepAliveAck' }); continue }
          this.msgs.push(m); this.waiters = this.waiters.filter((w) => !w(m))
        }
      })
    })
  }
  send(o) { this.sock.write(JSON.stringify(o) + '\n') }
  wait(pred, label = '') {
    const i = this.msgs.findIndex(pred)
    if (i >= 0) return Promise.resolve(this.msgs.splice(i, 1)[0])
    return new Promise((res, rej) => {
      const t = setTimeout(() => rej(new Error(`${this.name} waiting for ${label}`)), 5000)
      this.waiters.push((m) => { if (pred(m)) { clearTimeout(t); this.msgs.splice(this.msgs.indexOf(m), 1); res(m); return true } return false })
    })
  }
  waitAction(a) { return this.wait((m) => m.action === a, a) }
  has(a) { return this.msgs.some((m) => m.action === a) }
}

async function main() {
  for (let i = 0; i < 50; i++) { try { await new Promise((r, j) => { const s = net.connect(PORT, '127.0.0.1', () => { s.destroy(); r() }); s.on('error', j) }); break } catch { await sleep(100) } }
  const [A, B, C] = ['Alice', 'Bob', 'Carol'].map((n) => new Fake(n))
  for (const c of [A, B, C]) { await c.connect(); await c.waitAction('connected'); c.send({ action: 'username', username: c.name, modHash: 'test' }); c.send({ action: 'version', version: '0.6.9' }) }
  A.send({ action: 'createLobby', gameMode: 'koth' })
  const jl = await A.waitAction('joinedLobby'); assert.equal(jl.type, 'koth')
  B.send({ action: 'joinLobby', code: jl.code }); await B.waitAction('joinedLobby')
  C.send({ action: 'joinLobby', code: jl.code }); await C.waitAction('joinedLobby')
  await sleep(150)
  const info = A.msgs.filter((m) => m.action === 'lobbyInfo').pop()
  const ids = Object.fromEntries(info.players.map((p) => [p.username, p.id]))
  const all = [A, B, C]
  for (const c of all) c.msgs = []
  for (const c of all.slice(1)) c.send({ action: 'readyLobby' }); await new Promise((r) => setTimeout(r, 100))
  A.send({ action: 'startGame' })
  for (const c of all) {
    await c.waitAction('startGame')
    assert.equal((await c.waitAction('playerInfo')).lives, 3, 'koth starts with 3 lives')
    const k = await c.waitAction('kothUpdate'); assert.equal(k.kingId ?? null, null); assert.equal(k.you, ids[c.name]); assert.equal(k.holdTarget, 4)
  }
  console.log('ok: koth game starts with 3 lives and no King')

  const lives = { Alice: 3, Bob: 3, Carol: 3 }
  async function round(sc) {
    for (const c of all) { c.msgs = []; c.send({ action: 'newRound' }); c.send({ action: 'readyBlind' }) }
    for (const c of all) await c.waitAction('startBlind')
    for (const c of all) c.send({ action: 'playHand', score: String(sc[c.name]), handsLeft: 0 })
    const ups = {}
    for (const c of all) ups[c.name] = await c.waitAction('kothUpdate')
    await sleep(150)
    for (const c of all) { const pi = c.msgs.filter((m) => m.action === 'playerInfo').pop(); if (pi) lives[c.name] = pi.lives }
    return ups
  }
  // R1: Bob tops -> crowned; Carol lowest loses a life
  let u = await round({ Alice: 200, Bob: 300, Carol: 100 })
  assert.equal(u.Alice.kingId, ids.Bob); assert.equal(u.Alice.kingName, 'Bob'); assert.equal(u.Bob.crowned, true); assert.equal(u.Bob.you, ids.Bob)
  assert.deepEqual(lives, { Alice: 3, Bob: 3, Carol: 2 })
  console.log('ok: R1 Bob is crowned, Carol loses a life')
  // R2: Bob tops again -> streak 2
  u = await round({ Alice: 200, Bob: 300, Carol: 100 })
  assert.equal(u.Carol.streak, 2); assert.equal(u.Carol.bounty, 2); assert.equal(lives.Carol, 1)
  console.log('ok: R2 Bob keeps the crown, bounty 2')
  // R3: Bob scores lowest -> crown shield (no life lost), Alice claims bounty 2 = $8
  u = await round({ Alice: 500, Bob: 50, Carol: 100 })
  assert.equal(u.Alice.claimedBy, ids.Alice); assert.equal(u.Alice.reward, 8); assert.equal(u.Alice.shieldedId, ids.Bob); assert.equal(u.Alice.kingId, ids.Alice)
  assert.deepEqual(lives, { Alice: 3, Bob: 3, Carol: 1 })
  const endB = B.msgs.find((m) => m.action === 'endPvP'); assert.equal(endB.lost, false, 'shielded King did not lose')
  console.log('ok: R3 crown shield saves Bob, Alice claims a $8 bounty and the crown')
  // R4-R6: Alice holds the hill 3 more times -> streak 4 -> Alice wins
  u = await round({ Alice: 500, Bob: 200, Carol: 300 }) // Bob -1
  u = await round({ Alice: 500, Bob: 300, Carol: 200 }) // Carol eliminated? Carol had 1 -> 0
  // Carol is out now; continue with Alice & Bob
  assert.equal(lives.Carol, 0)
  const alive = [A, B]
  for (const c of alive) { c.msgs = []; c.send({ action: 'newRound' }); c.send({ action: 'readyBlind' }) }
  for (const c of alive) await c.waitAction('startBlind')
  for (const c of alive) c.send({ action: 'playHand', score: String(c === A ? 900 : 100), handsLeft: 0 })
  const last = await A.waitAction('kothUpdate'); assert.equal(last.winnerId, ids.Alice); assert.equal(last.streak, 4)
  await A.waitAction('winGame'); await B.waitAction('loseGame')
  console.log('ok: Alice holds the hill 4 PvPs in a row and wins')
  console.log('PASS: king of the hill tests')
  srv.kill(); process.exit(0)
}
main().catch(fail)
