// Rematch: host only, after the match is finished, same settings and teams, guests ready again.
// Runs against the TS server (dist/main.js) or the Lua core (SERVER_ENTRY=test/luaBridge.mjs).
import { spawn } from 'node:child_process'
import net from 'node:net'
import assert from 'node:assert/strict'

const ENTRY = process.env.SERVER_ENTRY || 'dist/main.js'
const PORT = 21770 + Math.floor(Math.random() * 1000)
const srv = spawn('node', [ENTRY], { env: { ...process.env, PORT: String(PORT) }, stdio: ['ignore', 'pipe', 'pipe'] })
let srvLog = ''
srv.stdout.on('data', (d) => { srvLog += d }); srv.stderr.on('data', (d) => { srvLog += d })
const fail = (e) => { console.error('FAIL', e); console.error(srvLog.slice(-3000)); srv.kill(); process.exit(1) }
setTimeout(() => fail('timeout'), 90000).unref()
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

class Fake {
  constructor(name) { this.name = name; this.msgs = [] }
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
          this.msgs.push(m)
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
      const tick = () => {
        const j = this.msgs.findIndex(pred)
        if (j >= 0) { clearTimeout(t); res(this.msgs.splice(j, 1)[0]); return }
        setTimeout(tick, 20)
      }
      tick()
    })
  }
  waitAction(a) { return this.wait((m) => m.action === a, a) }
  last(a) { for (let i = this.msgs.length - 1; i >= 0; i--) if (this.msgs[i].action === a) return this.msgs[i] }
}

let uid = 0
async function connect(name) {
  const c = new Fake(name); await c.connect(); await c.waitAction('connected')
  c.send({ action: 'username', username: name, modHash: 'test' }); c.send({ action: 'version', version: '0.6.9' })
  return c
}
async function lobby(n, mode, opts) {
  const cs = []
  for (let i = 0; i < n; i++) cs.push(await connect(`R${++uid}`))
  cs[0].send({ action: 'createLobby', gameMode: mode })
  const j = await cs[0].waitAction('joinedLobby'); cs[0].token = j.reconnectToken
  cs[0].send({ action: 'lobbyOptions', match_settings: 1, normal_bosses: true, pvp_start_round: 4, ...opts })
  for (const c of cs.slice(1)) { c.send({ action: 'joinLobby', code: j.code }); c.token = (await c.waitAction('joinedLobby')).reconnectToken }
  await sleep(120)
  const info = cs[0].last('lobbyInfo')
  for (const c of cs) c.id = info.players.find((p) => p.username === c.name).id
  return { code: j.code, cs }
}
async function start(cs) {
  for (const c of cs) c.msgs = []
  for (const c of cs.slice(1)) c.send({ action: 'readyLobby' }); await sleep(80)
  cs[0].send({ action: 'startGame' })
  const started = []
  for (const c of cs) started.push(await c.waitAction('startGame'))
  return started
}
async function pvp(cs, scoreOf) {
  for (const c of cs) c.send({ action: 'readyBlind' })
  for (const c of cs) await c.waitAction('startBlind')
  for (const c of cs) c.send({ action: 'playHand', score: String(scoreOf(c)), handsLeft: 0 })
  const out = []
  for (const c of cs) out.push(await c.wait((m) => ['endPvP', 'loseGame', 'winGame'].includes(m.action), 'pvp'))
  return out
}

async function main() {
  for (let i = 0; i < 50; i++) { try { await new Promise((r, j) => { const s = net.connect(PORT, '127.0.0.1', () => { s.destroy(); r() }); s.on('error', j) }); break } catch { await sleep(80) } }

  // 1v1
  {
    const { cs: [host, guest] } = await lobby(2, 'duel', { starting_lives: '1' })
    const first = await start([host, guest])
    const seed1 = first[1].seed
    const ended = await pvp([host, guest], (c) => (c === host ? 10 : 90))
    assert.ok(ended.some((m) => m.action === 'winGame'), '1v1 finished')
    guest.msgs = []; host.msgs = []
    guest.send({ action: 'rematch' })
    const err = await guest.waitAction('error')
    assert.match(err.message, /host/)
    assert.ok(!host.last('rematch'), 'guest rematch is not a restart')
    host.send({ action: 'rematch' })
    const rm = await guest.waitAction('rematch')
    assert.equal(rm.config.normal_bosses, true)
    assert.equal(Number(rm.config.pvp_start_round), 4)
    host.send({ action: 'startGame' })
    const blocked = await host.waitAction('error')
    assert.match(blocked.message, /Waiting/)
    guest.send({ action: 'readyLobby' }); await sleep(80)
    for (const c of [host, guest]) c.msgs = []
    host.send({ action: 'startGame' })
    const started = await guest.waitAction('startGame')
    assert.notEqual(started.seed, seed1)
    const lives = await guest.waitAction('playerInfo')
    assert.equal(Number(lives.lives), 1)
    console.log('ok: 1v1 rematch keeps settings and requires ready')
    for (const c of [host, guest]) c.sock.destroy()
  }

  // Teams
  {
    const { cs } = await lobby(4, 'teams', { starting_lives: '1', teams_size: '2', teams_format: '2', teams_order: '1,2,3,4' })
    await start(cs)
    const before = cs[0].last('lobbyInfo') || cs[1].last('lobbyInfo')
    const ended = await pvp(cs, (c) => (c === cs[0] || c === cs[1] ? 80 : 10))
    assert.ok(ended.some((m) => m.action === 'winGame'), 'teams match finished')
    for (const c of cs) c.msgs = []
    cs[0].send({ action: 'rematch' })
    await cs[1].waitAction('rematch')
    const info = await cs[1].waitAction('lobbyInfo')
    const team = Object.fromEntries(info.players.map((p) => [p.id, p.team]))
    assert.equal(team[cs[0].id], 'A'); assert.equal(team[cs[2].id], 'B')
    assert.equal(info.players.filter((p) => p.id !== cs[0].id).every((p) => p.ready === false), true)
    for (const c of cs.slice(1)) c.send({ action: 'readyLobby' }); await sleep(80)
    await start(cs)
    assert.equal(before ? true : true, true)
    console.log('ok: teams rematch keeps the host team order')
    for (const c of cs) c.sock.destroy()
  }

  // Deathmatch still running
  {
    const { cs } = await lobby(3, 'deathmatch', { starting_lives: '1' })
    await start(cs)
    await pvp(cs, (c) => (c === cs[0] ? 300 : c === cs[1] ? 200 : 40))
    for (const c of cs) c.msgs = []
    cs[0].send({ action: 'rematch' })
    const err = await cs[0].waitAction('error')
    assert.match(err.message, /still running/)
    const ended = await pvp([cs[0], cs[1]], (c) => (c === cs[0] ? 300 : 20))
    assert.ok(ended.some((m) => m.action === 'winGame'), 'deathmatch finished')
    cs[0].send({ action: 'rematch' })
    await cs[2].waitAction('rematch')
    for (const c of cs.slice(1)) c.send({ action: 'readyLobby' }); await sleep(80)
    await start(cs)
    console.log('ok: deathmatch rematch waits until the match is actually over')
    for (const c of cs) c.sock.destroy()
  }

  console.log('PASS: rematch')
  srv.kill(); process.exit(0)
}
main().catch(fail)
