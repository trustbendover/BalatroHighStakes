// Gambel Time on the reference server: 1 player can start, other modes cannot,
// and a 3-player nemesis still removes a life under the host's twist.
import { spawn } from 'node:child_process'
import net from 'node:net'
import assert from 'node:assert/strict'
import { gambelCut, gambelFlip, gambelLives, gambelMusic, gambelResolve, gambelStake } from '../dist/gambel.js'
import { startError } from '../dist/Lobby.js'

assert.equal(gambelLives(9), 5)
assert.equal(gambelStake(0), 0)
assert.equal(gambelStake(1), 0)
assert.ok(gambelFlip('s', 'p', 1, 0).money >= 0)
assert.equal(gambelCut(6), 2)
assert.equal(gambelMusic({ mode: 'gamemode_mp_gambel_time', stage: 'run' }), 10)
assert.equal(gambelMusic({ mode: 'attrition', stage: 'run' }), null)
const losers = gambelResolve(
	[{ id: 'a', score: 1, hands: 1 }, { id: 'b', score: 5, hands: 1 }, { id: 'c', score: 9, hands: 1 }],
	undefined,
	(a, b) => a > b,
)
assert.deepEqual(losers.losers, ['a'])
assert.equal(startError('gambel_time', 1), null)
assert.equal(startError('attrition', 1) !== null, true)
assert.equal(startError('gambel_time', 9) !== null, true)
console.log('ok: rules allow 1-8, clamp a bet, and spare a tied house')

const PORT = 19000 + Math.floor(Math.random() * 1000)
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
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

async function boot(names) {
	const cs = names.map((n) => new Fake(n))
	for (const c of cs) {
		await c.connect()
		await c.waitAction('connected')
		c.send({ action: 'username', username: c.name, modHash: 'test' })
		c.send({ action: 'version', version: '0.6.9' })
	}
	return cs
}

async function main() {
	for (let i = 0; i < 50; i++) {
		try {
			await new Promise((r, j) => { const s = net.connect(PORT, '127.0.0.1', () => { s.destroy(); r() }); s.on('error', j) })
			break
		} catch { await sleep(100) }
	}
	const [solo] = await boot(['Ada'])
	solo.send({ action: 'createLobby', gameMode: 'gambel_time' })
	await solo.waitAction('joinedLobby')
	solo.send({ action: 'startGame' })
	const info = await solo.waitAction('playerInfo')
	assert.equal(info.lives, 3)
	assert.equal(solo.msgs.some((m) => m.action === 'winGame'), false)
	console.log('ok: one player starts Gambel Time with 3 lives and no instant win')
	solo.send({ action: 'failRound' })
	const lost = await solo.waitAction('playerInfo')
	assert.equal(lost.lives, 2)
	console.log('ok: failing a blind against The House costs a life')
	solo.send({ action: 'setAnte', ante: 9 })
	const won = await solo.waitAction('winGame')
	assert.equal(won.reason, 'house')
	console.log('ok: ante 9 beats The House')
	solo.send({ action: 'stopGame' })

	const [attr] = await boot(['No'])
	attr.send({ action: 'createLobby', gameMode: 'attrition' })
	await attr.waitAction('joinedLobby')
	attr.send({ action: 'startGame' })
	const err = await attr.waitAction('error')
	assert.match(err.message, /2/)
	console.log('ok: attrition still needs 2 players')

	const [a, b, c] = await boot(['Ann', 'Bob', 'Cam'])
	a.send({ action: 'createLobby', gameMode: 'gambel_time' })
	const { code } = await a.waitAction('joinedLobby')
	a.send({ action: 'lobbyOptions', starting_lives: '3' })
	b.send({ action: 'joinLobby', code }); await b.waitAction('joinedLobby')
	c.send({ action: 'joinLobby', code }); await c.waitAction('joinedLobby')
	b.send({ action: 'readyLobby' }); c.send({ action: 'readyLobby' })
	await sleep(100)
	a.send({ action: 'startGame' })
	await a.waitAction('startGame')
	for (const p of [a, b, c]) p.send({ action: 'readyBlind' })
	const twist = await a.waitAction('gambelTwist')
	const scores = { Ann: 10, Bob: 40, Cam: 20 }
	for (const p of [a, b, c]) p.send({ action: 'playHand', score: String(scores[p.name]), handsLeft: 0 })
	await sleep(200)
	const lives = {}
	for (const p of [a, b, c]) {
		const infos = p.msgs.filter((m) => m.action === 'playerInfo')
		lives[p.name] = infos.length ? infos[infos.length - 1].lives : 3
	}
	if (twist.twist === 'reverse') assert.ok(lives.Bob < 3 && lives.Ann === 3)
	else assert.ok(lives.Ann < 3)
	if (twist.twist === 'double') assert.ok(lives.Ann <= 1 || lives.Bob <= 1)
	console.log('ok: three-player nemesis follows the chaos spin (' + twist.twist + ')')
	console.log('PASS: gambel time server')
	srv.kill()
}

main().catch(fail)
