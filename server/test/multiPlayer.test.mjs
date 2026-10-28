// Balatro High Stakes: 2-8 player simulations (Attrition, 1v1 Duel, Teams, KotH) over TCP.
// Runs against the TS server (dist/main.js) or the Lua core (SERVER_ENTRY=test/luaBridge.mjs).
import { spawn } from 'node:child_process'
import net from 'node:net'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import assert from 'node:assert/strict'

const here = path.dirname(fileURLToPath(import.meta.url))
const ENTRY = process.env.SERVER_ENTRY || 'dist/main.js'

// ---- 1. shared rule vectors (TS; the Lua side is mod/tests/test_teams.lua)
if (!process.env.SERVER_ENTRY) {
  const { resolveTeams, teamsPlan, assignTeams } = await import(path.resolve(here, '../dist/teams.js'))
  const { pvpLosers } = await import(path.resolve(here, '../dist/pvpRules.js'))
  const V = JSON.parse(fs.readFileSync(path.resolve(here, '../../mod/tests/teams_vectors.json'), 'utf8'))
  for (const c of V.plans) {
    const [size, count] = teamsPlan(c.n, c.options)
    assert.equal(size, c.size ?? null, `plan ${c.n}`); if (size !== null) assert.equal(count, c.count)
  }
  for (const c of V.assign) {
    const ids = Array.from({ length: c.n }, (_, i) => 'p' + (i + 1))
    const t = assignTeams(ids, c.options)
    c.expect.forEach((want, i) => assert.equal(t.get(ids[i]), want, `assign ${JSON.stringify(c.options)} seat ${i + 1}`))
  }
  for (const c of V.cases) assert.equal(resolveTeams(c.teams, c.size), c.loser ?? null, c.name)
  for (const c of V.ffa) {
    const got = pvpLosers(c.scores.map((s, i) => ({ id: i, score: s })), (a, b) => a <= b).sort()
    assert.deepEqual(got, c.losers, c.name)
  }
  console.log(`ok: ${V.plans.length + V.assign.length + V.cases.length + V.ffa.length} teams/ffa rule vectors (TS)`)
}

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
  c.send({ action: 'username', username: name, modHash: 'test' }); c.send({ action: 'version', version: '0.6.8~3P' })
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

async function main() {
  for (let i = 0; i < 50; i++) { try { await new Promise((r, j) => { const s = net.connect(PORT, '127.0.0.1', () => { s.destroy(); r() }); s.on('error', j) }); break } catch { await sleep(100) } }

  // Attrition with 2, 3, 4, 6, 8 players
  for (const n of [2, 3, 4, 6, 8]) {
    const r = await ffaGame(n)
    console.log(`ok: attrition ${n} players finished in ${r} PvPs (bottom ${n >= 6 ? 'two' : 'one'} lose a life)`)
  }
  // Showdown/KotH-free lobbies also accept 2 players: Showdown duel
  console.log(`ok: showdown 2 players finished in ${await ffaGame(2, 'showdown', 2)} PvPs`)

  // 1v1 Duel: exactly 2
  {
    const { code, cs } = await lobby(2, 'duel', { starting_lives: '3' })
    assert.equal(cs[0].last('lobbyInfo').maxPlayers, 2)
    const x = await connect('Extra'); x.send({ action: 'joinLobby', code })
    assert.match((await x.waitAction('error')).message, /full/); x.sock.destroy()
    await start(cs)
    let lost = 0
    for (let r = 0; r < 3; r++) {
      const res = await blind(cs, (c) => (c === cs[0] ? 10 : 20))
      if (res.get(cs[0]).action === 'endPvP') { assert.equal(res.get(cs[0]).lost, true); lost++ }
      if (res.get(cs[1]).action === 'winGame') break
    }
    assert.equal(lost, 2)
    console.log('ok: 1v1 duel: 3rd player refused, 3 lives, host loses all three, guest wins')
    for (const c of cs) c.sock.destroy()
  }
  {
    const { cs } = await lobby(1, 'duel')
    cs[0].send({ action: 'startGame' }); assert.match((await cs[0].waitAction('error')).message, /2 players/)
    cs[0].sock.destroy()
    console.log('ok: a 1-player lobby cannot start')
  }

  // Teams: invalid splits
  for (const n of [3, 5]) {
    const { cs } = await lobby(n, 'teams')
    cs[0].send({ action: 'startGame' }); assert.match((await cs[0].waitAction('error')).message, /Teams/)
    for (const c of cs) c.sock.destroy()
  }
  console.log('ok: teams refuses 3 and 5 players')

  // Teams 2v2 with the host's order, teammate disconnect + rejoin
  {
    const { code, cs } = await lobby(4, 'teams', { starting_lives: '2', teams_order: '1,3,2,4' })
    await sleep(100)
    const info = cs[1].last('lobbyInfo')
    assert.deepEqual(cs.map((c) => info.players.find((p) => p.id === c.id).team), ['A', 'B', 'A', 'B'])
    // the host client re-sends all options after every lobbyInfo: unchanged team options must not re-broadcast (no loop)
    const infos = () => cs[1].msgs.filter((m) => m.action === 'lobbyInfo').length
    const before = infos()
    cs[0].send({ action: 'lobbyOptions', starting_lives: '2', teams_order: '1,3,2,4' }); await sleep(200)
    assert.equal(infos(), before, 'unchanged team options -> no new lobbyInfo')
    cs[0].send({ action: 'lobbyOptions', starting_lives: '2', teams_order: '1,2,3,4' }); await sleep(200)
    assert.equal(infos(), before + 1, 'changed team order -> one new lobbyInfo')
    assert.deepEqual(cs.map((c) => cs[1].last('lobbyInfo').players.find((p) => p.id === c.id).team), ['A', 'A', 'B', 'B'])
    cs[0].send({ action: 'lobbyOptions', starting_lives: '2', teams_order: '1,3,2,4' }); await sleep(200)
    console.log('ok: teams preview re-broadcast only when the split changes')
    await start(cs)
    const tu = await cs[0].waitAction('teamsUpdate')
    assert.equal(tu.team, 'A'); assert.equal(tu.teams.A.lives, 2); assert.equal(tu.teams.B.members.length, 2)
    const [a1, b1, a2, b2] = cs
    // team sums: A 100+250 = 350 vs B 300+40 = 340 -> B loses (both lose the shared life)
    let res = await blind(cs, (c) => ({ [a1.id]: 100, [a2.id]: 250, [b1.id]: 300, [b2.id]: 40 })[c.id])
    assert.equal(res.get(b1).lost, true); assert.equal(res.get(b2).lost, true); assert.equal(res.get(a1).lost, false)
    assert.equal(res.get(a1).loserTeam, 'B')
    assert.equal(b1.last('playerInfo').lives, 1); assert.equal(b2.last('playerInfo').lives, 1)
    console.log('ok: 2v2: team sums decide, both teammates lose the shared life')
    for (const c of cs) c.msgs = []
    a1.send({ action: 'asteroid' }); await b1.waitAction('asteroid'); await b2.waitAction('asteroid'); await sleep(150)
    assert.ok(!a2.last('asteroid'), 'teammate is not hit by an asteroid')
    console.log('ok: 2v2: nemesis effects (asteroid) only hit the other team')
    // A2 disconnects; A1 alone counts as a full team (x2): A 200x2 = 400 vs B 150+200 = 350 -> B out
    a2.sock.destroy(); await sleep(200)
    for (const c of [a1, b1, b2]) c.msgs = []
    res = await blind([a1, b1, b2], (c) => ({ [a1.id]: 200, [b1.id]: 150, [b2.id]: 200 })[c.id])
    assert.equal(res.get(b1).action, 'loseGame'); assert.equal(res.get(b2).action, 'loseGame'); assert.equal(res.get(a1).action, 'winGame')
    console.log('ok: 2v2: away teammate is filled in with the team average; team at 0 lives is out, team A wins')
    for (const c of cs) c.sock.destroy()
  }
  {
    const { code, cs } = await lobby(4, 'teams', { starting_lives: '3' })
    await start(cs)
    const [a1, a2, b1, b2] = cs
    a2.sock.destroy(); await sleep(200)
    const back = await connect(a2.name); back.send({ action: 'rejoinLobby', code, reconnectToken: a2.token })
    await back.waitAction('rejoinedLobby')
    const tu = await back.waitAction('teamsUpdate'); assert.equal(tu.team, 'A')
    back.id = tu.you
    const live = [a1, back, b1, b2]
    const res = await blind(live, (c) => (c === b1 || c === b2 ? 1 : 100))
    assert.equal(res.get(back).lost, false); assert.equal(res.get(b1).lost, true)
    console.log('ok: 2v2: a teammate rejoins into his team and plays on')
    for (const c of [...cs, back]) c.sock.destroy()
  }

  // Teams with 6 (3v3, 2v2v2) and 8 players (4v4, 2v2v2v2): play to the end
  for (const [n, size] of [[6, 3], [6, 2], [8, 4], [8, 2]]) {
    const { cs } = await lobby(n, 'teams', { starting_lives: '2', teams_size: String(size) })
    await start(cs)
    const tu = await cs[0].waitAction('teamsUpdate')
    const count = Object.keys(tu.teams).length
    assert.equal(count, n / size); assert.equal(tu.teamSize, size)
    const team = new Map(); for (const [t, v] of Object.entries(tu.teams)) for (const m of v.members) team.set(m.id, t)
    // team A strongest, then B, ...: the last letter loses first
    let alive = [...cs]; let rounds = 0; let winners = []
    while (!winners.length && rounds < 40) {
      rounds++
      const res = await blind(alive, (c) => 1000 - 'ABCD'.indexOf(team.get(c.id)) * 100)
      for (const [c, m] of res) {
        if (m.action === 'loseGame') alive = alive.filter((x) => x !== c)
        if (m.action === 'winGame') winners.push(c)
      }
    }
    assert.equal(winners.length, size, `${n}p teams of ${size}: whole winning team gets winGame`)
    assert.ok(winners.every((c) => team.get(c.id) === 'A'))
    console.log(`ok: teams ${n} players (${Array(n / size).fill(size).join('v')}) finished in ${rounds} PvPs, team A wins`)
    for (const c of cs) c.sock.destroy()
  }

  // King of the Hill scaling: hold target 5 (2p), 4 (3-4p), 3 (5-8p)
  for (const [n, hold] of [[2, 5], [4, 4], [5, 3], [8, 3]]) {
    const { cs } = await lobby(n, 'koth', { starting_lives: '9' })
    await start(cs)
    const k0 = await cs[0].waitAction('kothUpdate'); assert.equal(k0.holdTarget, hold, `koth ${n}p hold target`)
    let won = null; let rounds = 0
    while (!won && rounds < 10) {
      rounds++
      const res = await blind(cs, (c) => (c === cs[n - 1] ? 1000 : 100 + cs.indexOf(c)))
      for (const [c, m] of res) if (m.action === 'winGame') won = { c, m }
    }
    assert.equal(won.c, cs[n - 1]); assert.equal(won.m.reason, 'koth_hill'); assert.equal(rounds, hold)
    console.log(`ok: KotH ${n} players: hold target ${hold}, top player holds the hill`)
    for (const c of cs) c.sock.destroy()
  }

  // 9th player refused
  {
    const { code, cs } = await lobby(8, 'attrition')
    const x = await connect('Ninth'); x.send({ action: 'joinLobby', code })
    assert.match((await x.waitAction('error')).message, /full/)
    console.log('ok: 8-player lobby refuses a 9th player')
    for (const c of [...cs, x]) c.sock.destroy()
  }

  console.log('PASS: 2-8 player simulations')
  srv.kill(); process.exit(0)
}
main().catch(fail)
