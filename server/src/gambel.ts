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

export function gambelFlip(seed: unknown, id: unknown, ante: unknown, money: unknown) {
	const cash = finiteMoney(money);
	const stake = gambelStake(cash);
	if (stake < 1) return { ok: false, reason: "low" as const, stake: 0, delta: 0, money: cash };
	const won = gambelRoll(seed, ante, `flip:${id}`, 2) === 1;
	const delta = won ? stake : -stake;
	return { ok: true, won, stake, delta, money: cash + delta };
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
