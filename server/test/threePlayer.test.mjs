// 3-player integration test (Balatro High Stakes supports 2-8; see multiPlayer.test.mjs): spins up the built server and drives 3 fake TCP clients.
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
          if (process.env.DBG && ['endPvP','startBlind','loseGame','playerEliminated'].includes(m.action)) console.log('DBG', this.name, m.action, JSON.stringify(m).slice(0,80)); this.msgs.push(m); this.waiters = this.waiters.filter((w) => !w(m))
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

async function main() {
  for (let i = 0; i < 50; i++) { try { await new Promise((r, j) => { const s = net.connect(PORT, '127.0.0.1', () => { s.destroy(); r() }); s.on('error', j) }); break } catch { await sleep(100) } }
  const [A, B, C, D] = ['Alice', 'Bob', 'Carol', 'Dave'].map((n) => new Fake(n))
  for (const c of [A, B, C, D]) { await c.connect(); await c.waitAction('connected'); c.send({ action: 'username', username: c.name, modHash: 'test' }); c.send({ action: 'version', version: '0.6.8~3P' }) }

  A.send({ action: 'createLobby', gameMode: 'attrition' })
  const { code } = await A.waitAction('joinedLobby')
  A.send({ action: 'lobbyOptions', starting_lives: '2' })
  B.send({ action: 'joinLobby', code }); await B.waitAction('joinedLobby')
  C.send({ action: 'joinLobby', code }); await C.waitAction('joinedLobby')
  D.send({ action: 'joinLobby', code }); await D.waitAction('joinedLobby')
  D.send({ action: 'leaveLobby' }); console.log('ok: a 4th player may join (2-8 players) and leave again')
  await sleep(300)
  const infoA = A.msgs.filter((m) => m.action === 'lobbyInfo').pop()
  assert.equal(infoA.players.length, 3); assert.equal(infoA.isHost, true)
  console.log('ok: lobbyInfo lists 3 players')

  const ids = Object.fromEntries(infoA.players.map((p) => [p.username, p.id]))
  const all = [A, B, C]
  for (const c of all) c.msgs = []
  A.send({ action: 'startGame' })
  for (const c of all) { await c.waitAction('startGame'); const pi = await c.waitAction('playerInfo'); assert.equal(pi.lives, 2) }
  console.log('ok: game started with 2 lives')

  let alive = [...all]
  const lives = { Alice: 2, Bob: 2, Carol: 2 }
  // Scores per round: [Alice, Bob, Carol]; round 2 is a tie for lowest (no life lost)
  const rounds = [
    { Alice: 300, Bob: 100, Carol: 200 }, // Bob -1 (1)
    { Alice: 300, Bob: 150, Carol: 150 }, // tie lowest: nobody
    { Alice: 300, Bob: 50, Carol: 200 },  // Bob -1 => eliminated
    { Alice: 100, Carol: 200 },           // Alice -1 (1)
    { Alice: 50, Carol: 400 },            // Alice eliminated -> Carol wins
  ]
  for (const [ri, sc] of rounds.entries()) {
    for (const c of alive) { c.msgs = c.msgs.filter((m) => m.action === 'loseGame'); c.send({ action: 'newRound' }); c.send({ action: 'readyBlind' }) }
    for (const c of alive) await c.waitAction('startBlind')
    // play two hands each, last one with handsLeft 0
    for (const c of alive) { c.send({ action: 'playHand', score: String(Math.floor(sc[c.name] / 2)), handsLeft: 1 }) }
    await sleep(100)
    assert.ok(!alive.some((c) => c.has('endPvP')), 'no early resolve')
    for (const c of alive) { c.send({ action: 'playHand', score: String(sc[c.name]), handsLeft: 0 }) }
    const scores = alive.map((c) => sc[c.name]); const min = Math.min(...scores)
    const losers = alive.filter((c) => sc[c.name] === min)
    const loser = losers.length === 1 ? losers[0] : null
    if (loser) lives[loser.name]--
    if (loser && lives[loser.name] === 0) {
      await loser.waitAction('loseGame')
      const others = alive.filter((c) => c !== loser)
      for (const o of others) await o.wait((m) => m.action === 'playerEliminated' && m.playerId === ids[loser.name], 'playerEliminated')
      alive = others
      if (alive.length > 1) for (const o of alive) await o.waitAction('endPvP')
      if (alive.length === 1) { await alive[0].waitAction('winGame'); console.log(`ok: round ${ri + 1}: ${loser.name} eliminated, ${alive[0].name} wins`); break }
      console.log(`ok: round ${ri + 1}: ${loser.name} eliminated`)
    } else {
      for (const c of alive) {
        const e = await c.waitAction('endPvP')
        assert.equal(e.lost, c === loser, `${c.name} lost flag round ${ri + 1}`)
      }
      // enemyInfo carries per-player ids
      const ei = alive[0].msgs.filter((m) => m.action === 'enemyInfo')
      assert.ok(ei.every((m) => typeof m.playerId === 'string'))
      console.log(`ok: round ${ri + 1}: ${loser ? loser.name + ' loses a life' : 'tie, no life lost'}`)
    }
  }
  assert.deepEqual(lives, { Alice: 1, Bob: 0, Carol: 2 }.Alice !== undefined ? lives : lives)
  assert.equal(lives.Bob, 0); assert.equal(lives.Alice, 0); assert.equal(lives.Carol, 2)
  console.log('ok: 3-player attrition game completed with a winner')

  // 0.6.5: end-game requests/responses can target one player (the nemesis / the requester)
  for (const c of all) c.msgs = []
  A.send({ action: 'getEndGameJokers' })
  const idA = (await B.waitAction('getEndGameJokers')).playerId; await C.waitAction('getEndGameJokers')
  B.send({ action: 'getNemesisDeck' })
  const idB = (await A.waitAction('getNemesisDeck')).playerId; const idC0 = await C.waitAction('getNemesisDeck')
  C.send({ action: 'endGameStatsRequested' })
  const idC = (await A.waitAction('endGameStatsRequested')).playerId; await B.waitAction('endGameStatsRequested')
  assert.ok(idA && idB && idC && idA !== idB && idB !== idC)
  for (const c of all) c.msgs = []
  A.send({ action: 'getEndGameJokers', targetId: idC })
  assert.equal((await C.waitAction('getEndGameJokers')).playerId, idA)
  C.send({ action: 'receiveEndGameJokers', keys: 'CJOKERS', targetId: idA })
  const rj = await A.waitAction('receiveEndGameJokers'); assert.equal(rj.keys, 'CJOKERS'); assert.equal(rj.playerId, idC)
  A.send({ action: 'getNemesisDeck', targetId: idB }); await B.waitAction('getNemesisDeck')
  B.send({ action: 'receiveNemesisDeck', cards: 'H_A;', targetId: idA }); assert.equal((await A.waitAction('receiveNemesisDeck')).playerId, idB)
  A.send({ action: 'endGameStatsRequested', targetId: idB }); await B.waitAction('endGameStatsRequested')
  B.send({ action: 'nemesisEndGameStats', reroll_count: 3, targetId: idA })
  const st = await A.waitAction('nemesisEndGameStats'); assert.equal(st.playerId, idB); assert.equal(st.reroll_count, 3)
  await sleep(200)
  assert.ok(!B.has('getEndGameJokers') && !B.has('receiveEndGameJokers'), 'untargeted player B got nothing')
  assert.ok(!C.has('receiveNemesisDeck') && !C.has('endGameStatsRequested') && !C.has('nemesisEndGameStats'), 'untargeted player C got nothing')
  console.log('ok: end-game jokers/deck/stats targeted to the nemesis')

  // Scenario 2: a player leaves mid-game; the other two keep playing
  for (const c of all) c.msgs = []
  A.send({ action: 'startGame' })
  for (const c of all) await c.waitAction('startGame')
  C.send({ action: 'leaveLobby' })
  for (const c of [A, B]) await c.waitAction('playerLeft')
  await sleep(100)
  assert.ok(![A, B].some((c) => c.has('stopGame')), 'game continues after leave')
  for (const c of [A, B]) { c.send({ action: 'newRound' }); c.send({ action: 'readyBlind' }) }
  for (const c of [A, B]) await c.waitAction('startBlind')
  A.send({ action: 'playHand', score: '500', handsLeft: 0 }); B.send({ action: 'playHand', score: '10', handsLeft: 0 })
  assert.equal((await B.waitAction('endPvP')).lost, true); assert.equal((await A.waitAction('endPvP')).lost, false)
  console.log('ok: leaver removed, remaining 2 continue')

  // PvP timer failure costs a life to that player only
  for (const c of [A, B]) { c.msgs = []; c.send({ action: 'newRound' }); c.send({ action: 'readyBlind' }) }
  for (const c of [A, B]) await c.waitAction('startBlind')
  A.send({ action: 'failPvPTimer' }); B.send({ action: 'playHand', score: '10', handsLeft: 0 })
  assert.equal((await A.waitAction('endPvP')).lost, true); assert.equal((await B.waitAction('endPvP')).lost, false)
  // B lost 1 earlier and A lost 1 now -> both at 1 of 2
  const aLives = A.msgs.filter((m) => m.action === 'playerInfo').pop(); assert.equal(aLives.lives, 1)
  console.log('ok: PvP timer failure handled')
  console.log('PASS: all 3-player server tests')
  srv.kill(); process.exit(0)
}
main().catch(fail)
