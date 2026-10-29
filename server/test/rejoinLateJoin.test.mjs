// 3-player integration test: spins up the built server and drives 3 fake TCP clients.
import { spawn } from 'node:child_process'
import net from 'node:net'
import assert from 'node:assert/strict'

const PORT = 18788 + Math.floor(Math.random() * 1000)
const srv = spawn('node', [process.env.SERVER_ENTRY || 'dist/main.js'], { env: { ...process.env, PORT: String(PORT) }, stdio: ['ignore', 'pipe', 'pipe'] })
let srvLog = ''
srv.stdout.on('data', (d) => { srvLog += d })
srv.stderr.on('data', (d) => { srvLog += d })
const fail = (e) => { console.error('FAIL', e); console.error(srvLog.slice(-3000)); srv.kill(); process.exit(1) }
setTimeout(() => fail('timeout'), 30000).unref()

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
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))


async function connect(name) {
  const c = new Fake(name); await c.connect(); await c.waitAction('connected')
  c.send({ action: 'username', username: name + '~3', modHash: 'test' }); c.send({ action: 'version', version: '0.6.8~3P' })
  return c
}
async function lobbyOf(names, lives = '3') {
  const cs = []; for (const n of names) cs.push(await connect(n))
  cs[0].send({ action: 'createLobby', gameMode: 'attrition' })
  const j = await cs[0].waitAction('joinedLobby'); cs[0].token = j.reconnectToken
  cs[0].send({ action: 'lobbyOptions', starting_lives: lives })
  for (const c of cs.slice(1)) { c.send({ action: 'joinLobby', code: j.code }); c.token = (await c.waitAction('joinedLobby')).reconnectToken }
  await sleep(100)
  for (const c of cs) c.msgs = []
  for (const c of cs.slice(1)) c.send({ action: 'readyLobby' }); await new Promise((r) => setTimeout(r, 100))
  cs[0].send({ action: 'startGame' })
  for (const c of cs) await c.waitAction('startGame')
  await sleep(100)
  return { code: j.code, cs }
}
const clear = (cs) => { for (const c of cs) c.msgs = [] }
async function startBlind(cs) { clear(cs); for (const c of cs) { c.send({ action: 'newRound' }); c.send({ action: 'readyBlind' }) } for (const c of cs) await c.waitAction('startBlind') }
const kill = async (c) => { c.sock.destroy(); await sleep(150) }

async function main() {
  for (let i = 0; i < 50; i++) { try { await new Promise((r, j) => { const s = net.connect(PORT, '127.0.0.1', () => { s.destroy(); r() }); s.on('error', j) }); break } catch { await sleep(100) } }

  // 1) Disconnect in the shop, others play PvP without them, rejoin with token keeps state
  {
    const { code, cs: [A, B, C] } = await lobbyOf(['Ann', 'Ben', 'Cas'])
    C.send({ action: 'setAnte', ante: 3 }); await sleep(50)
    await kill(C)
    await A.waitAction('enemyDisconnected'); await B.waitAction('enemyDisconnected')
    await startBlind([A, B])
    A.send({ action: 'playHand', score: '500', handsLeft: 0 }); B.send({ action: 'playHand', score: '100', handsLeft: 0 })
    assert.equal((await B.waitAction('endPvP')).lost, true); assert.equal((await A.waitAction('endPvP')).lost, false)
    console.log('ok: PvP resolved without the disconnected player')
    const C2 = await connect('Cas'); C2.send({ action: 'rejoinLobby', code, reconnectToken: C.token })
    await C2.waitAction('rejoinedLobby')
    const r = await C2.waitAction('resumeGame'); assert.equal(r.lateJoin, false); assert.equal(r.ante, 3); assert.equal(r.lives, 3); assert.ok(r.seed)
    assert.ok(!C2.has('endPvP'), 'not in a missed blind')
    await A.waitAction('enemyReconnected')
    await startBlind([A, B, C2])
    console.log('ok: rejoin by token restores lives/ante/seed and next blind includes all 3')
    for (const c of [A, B, C2]) c.sock.destroy()
  }

  // 2) Disconnect mid-blind: no waiting; crash-rejoin by NAME (no token) after the blind resolved gets released
  {
    const { code, cs: [A, B, C] } = await lobbyOf(['Ada', 'Bo', 'Cy'])
    await startBlind([A, B, C])
    A.send({ action: 'playHand', score: '300', handsLeft: 0 })
    await kill(B)
    C.send({ action: 'playHand', score: '200', handsLeft: 0 })
    assert.equal((await C.waitAction('endPvP')).lost, true); assert.equal((await A.waitAction('endPvP')).lost, false)
    console.log('ok: mid-blind disconnect does not block PvP resolution')
    const B2 = await connect('Bo'); B2.send({ action: 'joinLobby', code })
    await B2.waitAction('rejoinedLobby'); const r = await B2.waitAction('resumeGame')
    assert.equal(r.lives, 3); assert.equal(r.inCurrentBlind, false)
    assert.equal((await B2.waitAction('endPvP')).lost, false)
    console.log('ok: rejoin by name after crash; missed blind is released with no life loss')
    // restarted client sits out nothing (no blind active) and joins the next blind
    B2.send({ action: 'resumeRestarted' })
    await startBlind([A, B2, C])
    console.log('ok: rejoined player is back in the next blind')
    for (const c of [A, B2, C]) c.sock.destroy()
  }

  // 2b) Network blip mid-blind: quick rejoin with token continues the same blind
  {
    const { code, cs: [A, B, C] } = await lobbyOf(['Ivy', 'Jo', 'Kai'])
    await startBlind([A, B, C])
    await kill(C)
    A.send({ action: 'playHand', score: '400', handsLeft: 0 })
    const C2 = await connect('Kai'); C2.send({ action: 'rejoinLobby', code, reconnectToken: C.token })
    const r = await C2.waitAction('resumeGame'); assert.equal(r.inCurrentBlind, true)
    C2.send({ action: 'playHand', score: '10', handsLeft: 0 }); B.send({ action: 'playHand', score: '200', handsLeft: 0 })
    assert.equal((await C2.waitAction('endPvP')).lost, true); assert.equal((await B.waitAction('endPvP')).lost, false)
    console.log('ok: network blip mid-blind -> rejoined player finishes the same blind')
    for (const c of [A, B, C2]) c.sock.destroy()
  }

  // 3) Stale-socket takeover: rejoin with token while the server still thinks the old socket is alive
  {
    const { code, cs: [A, B] } = await lobbyOf(['Al', 'Bea'])
    B.sock.on('close', () => { B.closed = true })
    const B2 = await connect('Bea'); B2.send({ action: 'rejoinLobby', code, reconnectToken: B.token })
    await B2.waitAction('rejoinedLobby'); await B2.waitAction('resumeGame')
    await sleep(300); assert.ok(B.closed, 'stale socket closed by server')
    await startBlind([A, B2])
    console.log('ok: takeover of a stale connection')
    for (const c of [A, B, B2]) c.sock.destroy()
  }

  // 4) Late join into a running 2-player game, then late join mid-blind sits out
  {
    const { code, cs: [A, B] } = await lobbyOf(['Ari', 'Bas'], '3')
    A.send({ action: 'setAnte', ante: 4 }); B.send({ action: 'setAnte', ante: 3 })
    await startBlind([A, B])
    A.send({ action: 'playHand', score: '9', handsLeft: 0 }); B.send({ action: 'playHand', score: '99', handsLeft: 0 })
    await A.waitAction('endPvP'); await B.waitAction('endPvP')  // A now 2 lives
    const D = await connect('Dex'); D.send({ action: 'joinLobby', code })
    await D.waitAction('joinedLobby'); const r = await D.waitAction('resumeGame')
    assert.equal(r.lateJoin, true); assert.equal(r.lives, 2); assert.equal(r.ante, 3); assert.ok(r.seed)
    await A.waitAction('playerJoined')
    console.log('ok: late join gets lowest lives (2) and lowest ante (3) with the lobby seed')
    await startBlind([A, B, D])
    console.log('ok: late joiner is in the next PvP blind')
    // 2-8 players: a 4th late joiner is welcome too
    const E = await connect('Eve'); E.send({ action: 'joinLobby', code })
    await E.waitAction('joinedLobby'); assert.equal((await E.waitAction('resumeGame')).lateJoin, true)
    console.log('ok: 4th player can late-join a running game (2-8 players)')
    for (const c of [A, B, D, E]) c.sock.destroy()
  }
  {
    const { code, cs: [A, B] } = await lobbyOf(['Ava', 'Bix'])
    await startBlind([A, B])
    const D = await connect('Dot'); D.send({ action: 'joinLobby', code }); await D.waitAction('resumeGame')
    A.send({ action: 'playHand', score: '50', handsLeft: 0 }); B.send({ action: 'playHand', score: '60', handsLeft: 0 })
    assert.equal((await A.waitAction('endPvP')).lost, true)
    await B.waitAction('endPvP'); await sleep(200)
    assert.ok(!D.has('endPvP'))
    console.log('ok: mid-blind late joiner sits out and does not block resolution')
    for (const c of [A, B, D]) c.sock.destroy()
  }

  // 5) Only one connected player left: PvP resolves with no life lost and no premature win
  {
    const { code, cs: [A, B] } = await lobbyOf(['Ace', 'Bud'])
    await startBlind([A, B]); await kill(B)
    A.send({ action: 'playHand', score: '1', handsLeft: 0 })
    const e = await A.waitAction('endPvP'); assert.equal(e.lost, false); assert.equal(e.opponentsAway, true)
    assert.ok(!A.has('winGame'))
    console.log('ok: solo-connected PvP: no life lost, no win while opponent seat is held')
    A.sock.destroy()
  }
  console.log('PASS: rejoin + late join tests')
  srv.kill(); process.exit(0)
}
main().catch(fail)
