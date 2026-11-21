/** Heat Rush rules. Same numbers as mod/networking/heat_rules.lua. */

export const HEAT_MAX = 100;
export const HEAT_MULT = 1.5;
export const HEAT_CASH = 3;
export const HEAT_SOLO_ANTE = 8;
export const HEAT_TAG = "tag_charm";
const PAR_SECONDS: Record<string, number> = { small: 90, big: 120, boss: 150 };
const PAR_HANDS: Record<string, number> = { small: 2, big: 3, boss: 4 };

function kind(blind: unknown): string {
	const b = String(blind ?? "small");
	return b === "big" || b === "boss" ? b : "small";
}

export function heatGain(blind: unknown, hands: unknown, seconds: unknown): number {
	const k = kind(blind);
	let g = 25;
	const saved = (PAR_HANDS[k] ?? 2) - Math.max(0, Math.floor(Number(hands) || 0));
	if (saved > 0) g += Math.min(2, saved) * 15;
	if ((Number(seconds) || 1e9) <= (PAR_SECONDS[k] ?? 90)) g += 25;
	return g;
}

export function heatReward(blind: unknown, seconds: unknown): "reroll" | "cash" | null {
	const par = PAR_SECONDS[kind(blind)] ?? 90;
	const s = Number(seconds);
	const t = Number.isFinite(s) ? s : par + 1;
	if (t <= par * 0.75) return "reroll";
	if (t <= par) return "cash";
	return null;
}

export function heatMusic(state: { mode?: string; stage?: string; watching?: boolean; in_lobby?: boolean }): number | null {
	if (state.in_lobby === false) return null;
	if (!String(state.mode ?? "").includes("heat_rush")) return null;
	if (state.watching || state.stage === "run") return 10;
	return null;
}
