// Same chat rules as mod/networking/chat_rules.lua.
export const CHAT_MAX = 80;
export const CHAT_KEEP = 30;
export const CHAT_PALETTE = 25;

export type ChatLine = {
	id: number;
	scope: "lobby" | "match";
	name: string;
	watch: boolean;
	text: string;
	col: number;
};

export const displayName = (u: string | undefined): string => {
	const s = (u || "").split("~")[0].replace(/[\u0000-\u001f]/g, "").trim().slice(0, 24);
	return s || "?";
};

export const chosenColor = (username: string | undefined): number | null => {
	const m = (username || "").match(/~(\d+)\s*$/);
	const n = m ? Number(m[1]) : NaN;
	if (Number.isInteger(n) && n >= 1 && n <= CHAT_PALETTE) return n;
	return null;
};

/** Unique chosen blind colors are kept. Everyone else gets the next free one, stable by id. */
export const chatColors = (people: { id: string; username?: string }[]): Map<string, number> => {
	const used = new Set<number>();
	const out = new Map<string, number>();
	const rest: { id: string; username?: string }[] = [];
	for (const p of people) {
		const c = chosenColor(p.username);
		if (c !== null && !used.has(c)) {
			out.set(p.id, c);
			used.add(c);
		} else rest.push(p);
	}
	rest.sort((a, b) => String(a.id).localeCompare(String(b.id)));
	let n = 1;
	for (const p of rest) {
		let guard = 0;
		while (used.has(n) && guard < CHAT_PALETTE) {
			n = (n % CHAT_PALETTE) + 1;
			guard += 1;
		}
		out.set(p.id, n);
		used.add(n);
		n = (n % CHAT_PALETTE) + 1;
	}
	return out;
};

export const acceptChat = (text: unknown): { ok: true; text: string } | { ok: false; reason: "empty" | "long" } => {
	if (typeof text !== "string") return { ok: false, reason: "empty" };
	const s = text.replace(/[\u0000-\u001f]/g, " ").replace(/\s+/g, " ").trim();
	if (!s) return { ok: false, reason: "empty" };
	if (s.length > CHAT_MAX) return { ok: false, reason: "long" };
	return { ok: true, text: s };
};

export const pushChat = (log: ChatLine[], line: ChatLine): ChatLine[] => {
	const next = [...log, line];
	while (next.length > CHAT_KEEP) next.shift();
	return next;
};
