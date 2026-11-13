// Balatro High Stakes: Deathmatch simulations (3, 5, 8 players, leave / disconnect / rejoin,
// grace elimination, spectators, simultaneous final deaths) over TCP.
// Runs against the TS server (dist/main.js) or the Lua core (SERVER_ENTRY=test/luaBridge.mjs).
import { spawn } from 'node:child_process'
import net from 'node:net'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import assert from 'node:assert/strict'

const here = path.dirname(fileURLToPath(import.meta.url))
const ENTRY = process.env.SERVER_ENTRY || 'dist/main.js'

// ---- 2. games
const PORT = 20788 + Math.floor(Math.random() * 1000)
const srv = spawn('node', [ENTRY], { env: { ...process.env, PORT: String(PORT) }, stdio: ['ignore', 'pipe', 'pipe'] })
let srvLog = ''
srv.stdout.on('data', (d) => { srvLog += d }); srv.stderr.on('data', (d) => { srvLog += d })
const fail = (e) => { console.error('FAIL', e); console.error(srvLog.slice(-3000)); srv.kill(); process.exit(1) }
setTimeout(() => fail('timeout'), 120000).unref()
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
      const t = setTimeout(() => rej(new Error(`${this.name} waiting for ${label}`)), 6000)
      this.waiters.push((m) => { if (pred(m)) { clearTimeout(t); this.msgs.splice(this.msgs.indexOf(m), 1); res(m); return true } return false })
    })
  }
  waitAction(a) { return this.wait((m) => m.action === a, a) }
  last(a) { for (let i = this.msgs.length - 1; i >= 0; i--) if (this.msgs[i].action === a) return this.msgs[i] }
}

let uid = 0
async function connect(name) {
  const c = new Fake(name); await c.connect(); await c.waitAction('connected')
  c.send({ action: 'username', username: name, modHash: 'test' }); c.send({ action: 'version', version: '0.7.0' })
  return c
}
async function lobby(n, mode, opts = {}) {
  const cs = []
  for (let i = 0; i < n; i++) cs.push(await connect(`P${++uid}`))
  cs[0].send({ action: 'createLobby', gameMode: mode })
  const j = await cs[0].waitAction('joinedLobby'); cs[0].token = j.reconnectToken
  if (Object.keys(opts).length) cs[0].send({ action: 'lobbyOptions', ...opts })
  for (const c of cs.slice(1)) { c.send({ action: 'joinLobby', code: j.code }); c.token = (await c.waitAction('joinedLobby')).reconnectToken }
  await sleep(150)
  const info = cs[0].last('lobbyInfo')
  if (info) for (const c of cs) c.id = info.players.find((p) => p.username === c.name).id
  return { code: j.code, cs, info }
}
async function start(cs) {
  for (const c of cs) c.msgs = []
  for (const c of cs.slice(1)) c.send({ action: 'readyLobby' }); await new Promise((r) => setTimeout(r, 100))
  cs[0].send({ action: 'startGame' })
  for (const c of cs) { await c.waitAction('startGame'); await c.waitAction('playerInfo') }
}
/** One PvP blind for the given players; scoreOf(c) -> score. Returns { results: Map(c -> msg) } */
async function blind(cs, scoreOf) {
  for (const c of cs) c.send({ action: 'readyBlind' })
  for (const c of cs) await c.waitAction('startBlind')
  for (const c of cs) c.send({ action: 'playHand', score: String(scoreOf(c)), handsLeft: 0 })
  const res = new Map()
  for (const c of cs) res.set(c, await c.wait((m) => ['endPvP', 'loseGame', 'winGame'].includes(m.action), 'end of PvP'))
  await sleep(30)
  return res
}

/** Free-for-all to the end: everyone scores by seat, so the lowest seats fall first. */
async function ffaGame(n, mode = 'attrition', lives = 2) {
  const { cs } = await lobby(n, mode, { starting_lives: String(lives) })
  await start(cs)
  let alive = [...cs]; let rounds = 0; let winner = null
  while (!winner && rounds < 60) {
    rounds++
    const before = alive.length
    const res = await blind(alive, (c) => (cs.indexOf(c) + 1) * 100)
    const endp = [...res.values()].find((m) => m.action === 'endPvP')
    if (endp) assert.equal(endp.loserIds.length, before >= 6 ? 2 : 1, `${n}p: losers per PvP with ${before} alive`)
    for (const [c, m] of res) {
      if (m.action === 'loseGame') alive = alive.filter((x) => x !== c)
      if (m.action === 'winGame') winner = c
    }
    if (!winner && alive.length === 1) winner = alive[0]
  }
  assert.equal(winner, cs[n - 1], `${n}p ${mode}: top seat wins`)
  for (const c of cs) c.sock.destroy()
  return rounds
}


const until = async (c, pred, label, ms = 6000) => c.wait(pred, label)
/** Deathmatch PvP for the given living players; returns Map(c -> endPvP | loseGame | winGame) */
const dmBlind = (cs, all) => blind(cs, (c) => (all.indexOf(c) + 1) * 100)

async function main() {
  for (let i = 0; i < 50; i++) { try { await new Promise((r, j) => { const s = net.connect(PORT, '127.0.0.1', () => { s.destroy(); r() }); s.on('error', j) }); break } catch { await sleep(100) } }

  // ---- 3 players: in-game Leave holds the seat. Immediate rejoin works. Grace expiry
  //      eliminates (not an instant "left"). The match then continues.
  {
    const { code, cs } = await lobby(3, 'deathmatch', { starting_lives: '2', deathmatch_grace: '1' })
    const [p1, p2, p3] = cs
    assert.equal(cs[0].last('lobbyInfo').maxPlayers, 8)
    await start(cs)
    let res = await dmBlind(cs, cs)
    assert.equal(res.get(p1).lost, true); assert.equal(res.get(p2).lost, false)
    for (const c of cs) c.msgs = []
    p2.send({ action: 'leaveLobby' })
    const held = await p1.wait((m) => m.action === 'enemyDisconnected' && m.held && m.playerId === p2.id, 'p2 seat held')
    assert.equal(held.held, true)
    assert.ok(held.grace == null || held.grace > 0, 'grace is a countdown when the host sends one')
    assert.ok(!p1.msgs.some((m) => m.action === 'playerEliminated' || m.action === 'playerLeft'), 'Leave does not eliminate on the spot')
    p2.send({ action: 'rejoinLobby', code, reconnectToken: p2.token })
    await p2.waitAction('rejoinedLobby')
    await p1.wait((m) => m.action === 'enemyReconnected' && m.playerId === p2.id, 'p2 back at once')
    for (const c of cs) c.msgs = []
    p2.send({ action: 'leaveLobby' })
    const el = await p1.wait((m) => m.action === 'playerEliminated' && m.playerId === p2.id, 'p2 grace expired', 6000)
    assert.equal(el.reason, 'disconnected')
    const st = await p3.wait((m) => m.action === 'deathmatchUpdate' && m.alive.length === 2, 'standings after expiry')
    assert.equal(st.running, true)
    assert.ok(st.out.some((o) => o.id === p2.id), 'expired seat is out')
    res = await dmBlind([p1, p3], cs)
    assert.equal(res.get(p1).action, 'loseGame'); assert.equal(res.get(p3).action, 'winGame')
    const fin = await p3.wait((m) => m.action === 'deathmatchUpdate' && !m.running, 'final standings')
    assert.equal(fin.winnerId, p3.id)
    console.log('ok: deathmatch 3 players: Leave holds the seat, immediate rejoin, grace expiry, match continues')
    for (const c of cs) c.sock.destroy()
  }

  // ---- Absent at PvP loses a life (Deathmatch). The connected players are not the lowest.
  {
    const { cs } = await lobby(3, 'deathmatch', { starting_lives: '2', deathmatch_grace: '30' })
    const [a, b, c] = cs
    await start(cs)
    for (const x of cs) x.msgs = []
    c.send({ action: 'leaveLobby' })
    await a.wait((m) => m.action === 'enemyDisconnected' && m.held && m.playerId === c.id, 'c held before PvP')
    let res = await dmBlind([a, b], cs)
    assert.equal(res.get(a).lost, false, 'lowest connected score is spared while a seat is absent')
    assert.equal(res.get(b).lost, false)
    const info = [...b.msgs].reverse().find((m) => m.action === 'enemyInfo' && m.playerId === c.id)
    assert.equal(info && info.lives, 1, 'absent seat lost a life')
    assert.ok(!a.msgs.some((m) => m.action === 'playerEliminated'), 'one life left: not eliminated yet')
    res = await dmBlind([a, b], cs)
    const gone = await a.wait((m) => m.action === 'playerEliminated' && m.playerId === c.id, 'absent eliminated')
    assert.equal(gone.reason, 'absent')
    assert.equal(res.get(a).lost, false)
    console.log('ok: deathmatch: absent at PvP loses a life, then is eliminated; connected players are spared')
    for (const x of cs) x.sock.destroy()
  }

  // ---- 5 players: disconnect + rejoin within grace, disconnect past grace = eliminated,
  //      eliminated player spectates / returns to the lobby without ending the match, no late join
  {
    const { code, cs } = await lobby(5, 'deathmatch', { starting_lives: '2', deathmatch_grace: '1' })
    const [p1, p2, p3, p4, p5] = cs
    await start(cs)
    let res = await dmBlind(cs, cs)
    assert.equal(res.get(p1).lost, true)
    p5.sock.destroy(); p4.sock.destroy(); await sleep(150)
    const back = await connect(p4.name); back.send({ action: 'rejoinLobby', code, reconnectToken: p4.token })
    await back.waitAction('rejoinedLobby'); back.id = p4.id
    const ex = await p2.wait((m) => m.action === 'playerEliminated' && m.playerId === p5.id, 'p5 eliminated after grace', 6000)
    assert.equal(ex.reason, 'disconnected')
    await sleep(1500)
    assert.ok(!p2.msgs.some((m) => m.action === 'playerEliminated' && m.playerId === p4.id), 'p4 rejoined in time: not eliminated')
    const late = await connect('Latecomer'); late.send({ action: 'joinLobby', code })
    // TS refuses with an error. The Lua host seats them as a spectator instead (Watch), never as a player.
    const lateMsg = await late.wait((m) => m.action === 'error' || m.action === 'spectateStart' || m.action === 'resumeGame', 'no playing seat for a newcomer')
    if (lateMsg.action === 'error') assert.match(lateMsg.message, /no late join/)
    else assert.equal(lateMsg.action, 'spectateStart', 'a newcomer may watch, not take a Deathmatch seat')
    late.sock.destroy()
    const order = [p1, p2, p3, back]
    res = await dmBlind(order, order)
    assert.equal(res.get(p1).action, 'loseGame'); assert.equal(res.get(back).lost, false)
    // the eliminated player goes back to the lobby: only he gets stopGame
    for (const c of [p1, p2, p3, back]) c.msgs = []
    p1.send({ action: 'stopGame' }); await p1.waitAction('stopGame'); await sleep(300)
    assert.ok(![p2, p3, back].some((c) => c.last('stopGame')), 'match not stopped for the others')
    // spectator still gets the standings
    res = await dmBlind([p2, p3, back], order)
    assert.equal(res.get(p2).lost, true)
    const spec = await p1.wait((m) => m.action === 'deathmatchUpdate', 'spectator standings')
    assert.equal(spec.running, true)
    let alive = [p2, p3, back]; let winner = null
    for (let r = 0; r < 10 && !winner; r++) {
      res = await dmBlind(alive, order)
      for (const [c, m] of res) { if (m.action === 'loseGame') alive = alive.filter((x) => x !== c); if (m.action === 'winGame') winner = c }
    }
    assert.equal(winner, back)
    console.log('ok: deathmatch 5 players: rejoin within grace, disconnect past grace eliminated, spectator returns to lobby without stopping the match, no late join')
    for (const c of [...cs, back]) c.sock.destroy()
  }

  // ---- 8 players: bottom two lose, a leave and a disconnect mid-match, play to the last one
  {
    const { cs } = await lobby(8, 'deathmatch', { starting_lives: '1', deathmatch_grace: '1' })
    await start(cs)
    let res = await dmBlind(cs, cs)
    assert.equal(res.get(cs[0]).action, 'loseGame'); assert.equal(res.get(cs[1]).action, 'loseGame')
    assert.equal(res.get(cs[2]).lost, false)
    const p8 = cs[7], p7 = cs[6]
    p8.send({ action: 'leaveLobby' })
    p7.sock.destroy()
    await cs[2].wait((m) => m.action === 'playerEliminated' && m.playerId === p7.id, 'p7 grace expired', 6000)
    await cs[2].wait((m) => m.action === 'playerEliminated' && m.playerId === p8.id, 'p8 grace expired', 6000)
    await cs[0].wait((m) => m.action === 'deathmatchUpdate' && m.alive.length === 4, 'spectator sees 4 left')
    let alive = cs.slice(2, 6); let winner = null; let rounds = 0
    while (!winner && rounds++ < 10) {
      res = await dmBlind(alive, cs)
      for (const [c, m] of res) { if (m.action === 'loseGame') alive = alive.filter((x) => x !== c); if (m.action === 'winGame') winner = c }
    }
    assert.equal(winner, cs[5])
    const fin = await cs[0].wait((m) => m.action === 'deathmatchUpdate' && !m.running, 'final standings for a spectator')
    assert.equal(fin.winnerId, cs[5].id); assert.equal(fin.out.length, 7)
    console.log(`ok: deathmatch 8 players: bottom two out, leave + disconnect eliminated, winner after ${rounds} more PvPs, spectators see the final standings`)
    for (const c of cs) c.sock.destroy()
  }

  // ---- simultaneous final deaths: highest score wins
  {
    const { cs } = await lobby(3, 'deathmatch', { starting_lives: '1' })
    const [a, b, c] = cs
    await start(cs)
    for (const x of cs) x.send({ action: 'readyBlind' })
    for (const x of cs) await x.waitAction('startBlind')
    a.send({ action: 'playHand', score: '300', handsLeft: 1 }); b.send({ action: 'playHand', score: '500', handsLeft: 1 }); c.send({ action: 'playHand', score: '100', handsLeft: 1 })
    await sleep(100)
    for (const x of cs) x.send({ action: 'failPvPTimer' })
    const rb = await b.wait((m) => m.action === 'winGame' || m.action === 'loseGame', 'b result')
    const ra = await a.wait((m) => m.action === 'winGame' || m.action === 'loseGame', 'a result')
    const rc = await c.wait((m) => m.action === 'winGame' || m.action === 'loseGame', 'c result')
    assert.equal(rb.action, 'winGame'); assert.equal(rb.reason, 'final_score'); assert.equal(ra.action, 'loseGame'); assert.equal(rc.action, 'loseGame')
    console.log('ok: deathmatch: all remaining players die in the same PvP -> highest score wins')
    for (const x of cs) x.sock.destroy()
  }

  // ---- Attrition keeps its own behaviour: late join still allowed
  {
    const { code, cs } = await lobby(3, 'attrition', { starting_lives: '2' })
    await start(cs)
    const late = await connect('LateA'); late.send({ action: 'joinLobby', code })
    await late.wait((m) => m.action === 'resumeGame' || m.action === 'joinedLobby', 'attrition late join')
    console.log('ok: attrition still allows late join (deathmatch does not)')
    for (const x of [...cs, late]) x.sock.destroy()
  }

  console.log('PASS: deathmatch simulations')
  srv.kill(); process.exit(0)
}
main().catch(fail)
