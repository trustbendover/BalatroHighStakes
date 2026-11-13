// Balatro High Stakes: "Teams" rules. Same rules as mod/networking/teams_rules.lua (in-game
// Steam P2P host); both are checked against mod/tests/teams_vectors.json. GPL-3.0.
//  * 4-8 players. Even counts split into teams of teams_size (2/3/4). 5 is 3v2 and 7 is 4v3:
//    the first seats in lobby order (or teams_order) are the larger side. Not 2v1 and not 5v3.
//  * A locked 2v2/3v3/4v4 still needs that exact count.
//  * PvP: team score = sum of the teammates' scores; the single lowest team loses a shared team
//    life (tie for lowest: nobody). A short side is scaled to the larger side (sum * larger / present),
//    the same average fill used when a teammate is away.
//  * Shared team lives (default 4); a team at 0 lives is out, the last team left wins.
import { InsaneInt } from "./InsaneInt.js";

export type Team = "A" | "B" | "C" | "D";
export const TEAM_LETTERS: Team[] = ["A", "B", "C", "D"];
export const TEAMS_DEFAULTS = { startingLives: 4, size: 2, minPlayers: 4, maxPlayers: 8 };

// biome-ignore lint/suspicious/noExplicitAny: lobby options are loosely typed
type Opts = { [k: string]: any };

export const teamsConfig = (options: Opts = {}) => {
	const c = { startingLives: TEAMS_DEFAULTS.startingLives };
	const s = Number(options.starting_lives);
	if (Number.isFinite(s) && s >= 1 && s <= 20) c.startingLives = Math.floor(s);
	return c;
};

/** [size, count] or [null, reason] */
export const teamsPlan = (n: number, options: Opts = {}): [number, number] | [null, string] => {
	if (n < TEAMS_DEFAULTS.minPlayers) return [null, "needs at least 4 players"];
	if (n > TEAMS_DEFAULTS.maxPlayers) return [null, "at most 8 players"];
	// 0.6.8 Versus formats (2v2 / 3v3 / 4v4): exactly two teams of teams_format players
	const fmt = Math.floor(Number(options.teams_format ?? 0));
	if (Number.isFinite(fmt) && fmt >= 2 && fmt <= 4) {
		if (n !== 2 * fmt) return [null, `needs exactly ${2 * fmt} players`];
		return [fmt, 2];
	}
	// Odd versus: two teams. First seats in host order are the larger side (3v2, 4v3).
	if (n === 5) return [3, 2];
	if (n === 7) return [4, 2];
	let size = Math.floor(Number(options.teams_size ?? TEAMS_DEFAULTS.size));
	if (!Number.isFinite(size) || size < 2 || size > 4) size = TEAMS_DEFAULTS.size;
	if (n % size !== 0 || n / size < 2) {
		if (n % 2 !== 0) return [null, "needs an even split"];
		size = 2;
	}
	return [size, n / size];
};

export const teamsOrder = (n: number, options: Opts = {}): number[] => {
	const nums = String(options.teams_order ?? "").match(/\d+/g)?.map(Number) ?? [];
	const ok = nums.length === n && new Set(nums).size === n && nums.every((v) => v >= 1 && v <= n);
	return ok ? nums : Array.from({ length: n }, (_, i) => i + 1);
};

export const assignTeams = (ids: string[], options: Opts = {}): Map<string, Team> | null => {
	const [size] = teamsPlan(ids.length, options);
	if (size === null) return null;
	const r = new Map<string, Team>();
	teamsOrder(ids.length, options).forEach((seat, pos) => r.set(ids[seat - 1], TEAM_LETTERS[Math.floor(pos / size)]));
	return r;
};

type Parsed = { ec: number; c: number; e: number };
type TeamValue = { tier: 0 | 1; v: number } | { tier: 2; list: Parsed[]; size: number };
const toParsed = (s: InsaneInt | string): Parsed => {
	const i = typeof s === "string" ? InsaneInt.fromString(s) : s;
	return { ec: i.startingECount, c: i.coefficient, e: i.exponent };
};
const pgt = (a: Parsed, b: Parsed) => new InsaneInt(a.ec, a.c, a.e).greaterThan(new InsaneInt(b.ec, b.c, b.e));
const peq = (a: Parsed, b: Parsed) => new InsaneInt(a.ec, a.c, a.e).equalTo(new InsaneInt(b.ec, b.c, b.e));
const log10 = (x: number) => Math.log(x) / Math.log(10);

export const teamValue = (scores: (InsaneInt | string)[], teamSize?: number): TeamValue => {
	const list = scores.map(toParsed);
	const n = list.length;
	const size = Math.max(teamSize ?? n, n);
	if (list.some((s) => s.ec > 0)) return { tier: 2, list, size };
	if (!list.some((s) => s.e > 290)) {
		let sum = 0;
		for (const s of list) sum += s.c * 10 ** s.e;
		if (n < size && n > 0) sum = (sum * size) / n;
		return { tier: 0, v: sum };
	}
	const logs = list.filter((s) => s.c > 0).map((s) => log10(s.c) + s.e).sort((a, b) => b - a);
	const m = logs[0] ?? Number.NEGATIVE_INFINITY;
	let acc = 0;
	for (const l of logs) acc += 10 ** (l - m);
	let v = m + log10(acc);
	if (n < size && n > 0) v += log10(size / n);
	return { tier: 1, v };
};

const asLog = (t: { tier: 0 | 1; v: number }) => (t.tier === 1 ? t.v : t.v <= 0 ? Number.NEGATIVE_INFINITY : log10(t.v));

export const compareTeams = (a: TeamValue, b: TeamValue): number => {
	if (a.tier === 2 || b.tier === 2) {
		if (a.tier !== b.tier) return a.tier === 2 ? 1 : -1;
		const full = (t: { list: Parsed[]; size: number }) => {
			const l = [...t.list].sort((x, y) => (pgt(x, y) ? -1 : pgt(y, x) ? 1 : 0));
			const n = l.length;
			for (let i = n; i < t.size; i++) l.push(l[i % n]);
			return l.sort((x, y) => (pgt(x, y) ? -1 : pgt(y, x) ? 1 : 0));
		};
		const x = full(a as { list: Parsed[]; size: number });
		const y = full(b as { list: Parsed[]; size: number });
		for (let i = 0; i < Math.max(x.length, y.length); i++) {
			if (x[i] && !y[i]) return 1;
			if (y[i] && !x[i]) return -1;
			if (!peq(x[i], y[i])) return pgt(x[i], y[i]) ? 1 : -1;
		}
		return 0;
	}
	if (a.tier === 0 && b.tier === 0) return a.v === b.v ? 0 : a.v > b.v ? 1 : -1;
	const la = asLog(a), lb = asLog(b);
	return la === lb ? 0 : la > lb ? 1 : -1;
};

/** The single lowest team, or null (tie for lowest / fewer than 2 teams took part). */
export const resolveTeams = (present: Partial<Record<Team, (InsaneInt | string)[]>>, teamSize?: number): Team | null => {
	const teams = TEAM_LETTERS.filter((t) => (present[t]?.length ?? 0) > 0).map((t) => ({ t, v: teamValue(present[t] ?? [], teamSize) }));
	if (teams.length < 2) return null;
	let low = teams[0];
	let tied = 1;
	for (const x of teams.slice(1)) {
		const c = compareTeams(x.v, low.v);
		if (c < 0) { low = x; tied = 1; } else if (c === 0) tied++;
	}
	return tied === 1 ? low.t : null;
};
