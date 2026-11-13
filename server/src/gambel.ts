// Gambel Time rules. Same results as mod/networking/gambel_rules.lua.

export const GAMBEL_KEY = "gambel_time";
export const SPINS = ["double_interest", "inflation", "golden_hour", "wild_odds", "high_roller", "slim_hands"] as const;
export const TWISTS_SOLO = ["double", "house", "allin"] as const;
export const TWISTS = ["reverse", "double", "pot", "sabotage", "allin"] as const;
export const WHEEL = [
	{ id: "cash", amount: 8 },
	{ id: "cash", amount: 20 },
	{ id: "tag" },
	{ id: "edition" },
	{ id: "tax", amount: 4 },
	{ id: "discard" },
	{ id: "perish" },
] as const;

export type GambelEntry<S> = { id: string; score: S; hands?: number; give?: boolean; room?: boolean };

export function gambelRoll(seed: unknown, ante: unknown, salt: unknown, n: number): number {
	const count = Math.floor(Number(n) || 1);
	if (count < 1) return 1;
	const s = `${seed ?? "house"}:${Math.floor(Number(ante) || 1)}:${salt ?? ""}`;
	let h = 2166136261;
	for (let i = 0; i < s.length; i++) h = (Math.imul(h, 16777619) + s.charCodeAt(i)) >>> 0;
	return (h % count) + 1;
}

export function gambelLives(n: unknown): number {
	const v = Number(n);
	if (!Number.isFinite(v)) return 3;
	const i = Math.floor(v);
	if (i < 2) return 2;
	if (i > 5) return 5;
	return i;
}

export function gambelAnte(options: { gambel_ante?: unknown } | undefined): number {
	const v = Number(options?.gambel_ante);
	if (!Number.isFinite(v)) return 6;
	const i = Math.floor(v);
	if (i < 4) return 4;
	if (i > 12) return 12;
	return i;
}

export function gambelCut(n: number): number {
	const c = Math.floor(Number(n) || 0);
	if (c >= 6) return 2;
	if (c >= 2) return 1;
	return 0;
}

export function gambelTable(seed: unknown, ante: unknown): string {
	return SPINS[gambelRoll(seed, ante, "table", SPINS.length) - 1];
}

export function gambelTwist(seed: unknown, ante: unknown, seq: unknown, players: number): string {
	const pool = players <= 1 ? TWISTS_SOLO : TWISTS;
	return pool[gambelRoll(seed, ante, `twist:${seq ?? 1}`, pool.length) - 1];
}

export function gambelResolve<S>(
	entries: GambelEntry<S>[],
	twist: string | undefined,
	better: (a: S, b: S) => boolean,
): { losers: string[]; lives: number; hold: boolean } {
	const k = gambelCut(entries.length);
	const lives = twist === "double" ? 2 : 1;
	if (k === 0) return { losers: [], lives, hold: false };
	const played = (e: GambelEntry<S>) => (Number(e.hands) || 0) >= 1;
	const beats = (a: GambelEntry<S>, b: GambelEntry<S>) => {
		if (a === b) return false;
		if (twist === "reverse") {
			const ap = played(a);
			const bp = played(b);
			if (ap !== bp) return ap;
			if (!ap) return false;
			return better(b.score, a.score);
		}
		return better(a.score, b.score);
	};
	let hold = true;
	for (const a of entries) for (const b of entries) if (beats(a, b)) hold = false;
	if (hold) return { losers: [], lives, hold: true };
	const losers: string[] = [];
	for (const p of entries) {
		let n = 0;
		for (const q of entries) if (!beats(q, p)) n++;
		if (n <= k) losers.push(p.id);
	}
	return { losers, lives, hold };
}

const POT_CASH = 8;

/** Cash moved by Joker Pot or All-In. A joker only moves when one winner can take a card and a loser can give one. */
export function gambelPayout<S>(
	entries: GambelEntry<S>[],
	twist: string | undefined,
	losers: string[],
	better: (a: S, b: S) => boolean,
): { kind: "allin" | "pot"; cash: number; payout?: number; from: string[]; to: string | null; joker: boolean } | null {
	if (twist !== "pot" && twist !== "allin" && twist !== "house") return null;
	const lost = new Set(losers);
	const winners = entries.filter((e) => !lost.has(e.id));
	let best: GambelEntry<S> | null = null;
	let tied = false;
	for (const e of winners) {
		if (!best) best = e;
		else if (better(e.score, best.score)) { best = e; tied = false; }
		else if (!better(best.score, e.score)) tied = true;
	}
	const to = best && !tied ? best.id : null;
	let joker = false;
	if (twist === "pot" && to) {
		const give = entries.some((e) => lost.has(e.id) && e.give);
		const room = winners.some((e) => e.id === to && e.room);
		joker = give && room;
	}
	return {
		kind: twist === "allin" ? "allin" : "pot",
		cash: POT_CASH,
		payout: twist === "allin" ? 2 : undefined,
		from: losers,
		to,
		joker,
	};
}

export function gambelStake(money: unknown): number {
	const n = finiteMoney(money);
	if (n < 2) return 0;
	return Math.min(50, Math.floor(n / 2));
}

function finiteMoney(money: unknown): number {
	const n = Number(money);
	if (!Number.isFinite(n) || n < 0) return 0;
	return Math.floor(n);
}

const ACES = ["H", "D", "S", "C"] as const;

/** 32-bit FNV-1a. Same mix as mod/networking/gambel_rules.lua.
 *  The Ace uses this mix. gambelRoll is the shared 32-bit index roll (Math.imul). */
function fnv32(s: string): number {
	let h = 2166136261;
	for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619) >>> 0;
	return h;
}

function mix(seed: unknown, ante: unknown, salt: string): number {
	const s = `${seed ?? "house"}:${Math.floor(Number(ante) || 1)}:${salt}`;
	return fnv32(s);
}

/** One Ace. Red is hearts or diamonds, black is spades or clubs.
 *  A missing or other guess still wins on red. The guess is not part of the mix. */
export function gambelFlip(seed: unknown, id: unknown, ante: unknown, money: unknown, choice?: unknown) {
	const cash = finiteMoney(money);
	const stake = gambelStake(cash);
	if (stake < 1) return { ok: false as const, reason: "low" as const, stake: 0, delta: 0, money: cash };
	const suit = ACES[mix(seed, ante, `ace:${id}`) % 4];
	const drawn = suit === "H" || suit === "D" ? "red" as const : "black" as const;
	const picked = choice === "red" ? "red" as const : choice === "black" ? "black" as const : undefined;
	const won = picked ? picked === drawn : drawn === "red";
	const delta = won ? stake : -stake;
	return { ok: true as const, won, stake, delta, money: cash + delta, drawn, suit, choice: picked };
}

export function gambelWheel(seed: unknown, id: unknown, ante: unknown, money: unknown) {
	const cash = finiteMoney(money);
	const prize = WHEEL[gambelRoll(seed, ante, `wheel:${id}`, WHEEL.length) - 1];
	let delta = 0;
	if (prize.id === "cash") delta = prize.amount ?? 0;
	else if (prize.id === "tax") delta = -Math.min(prize.amount ?? 4, cash);
	return { ok: true, id: prize.id, amount: "amount" in prize ? prize.amount : undefined, delta, money: cash + delta };
}

export function gambelMusic(state: { mode?: string; watching?: boolean; stage?: string } | undefined): number | null {
	const mode = String(state?.mode ?? "");
	if (!mode.includes(GAMBEL_KEY)) return null;
	if (state?.watching || state?.stage === "run") return 10;
	return null;
}
