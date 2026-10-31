import type Client from "./Client.js";
import { InsaneInt } from "./InsaneInt.js";
import GameModes from "./GameMode.js";
import { type KothEvent, type KothState, kothConfig, kothSnapshot, newKothState, resolveKoth } from "./koth.js";
import { type Team, TEAM_LETTERS, assignTeams, resolveTeams, teamsPlan } from "./teams.js";
import { pvpLosers } from "./pvpRules.js";
import type {
	ActionLobbyInfo,
	ActionServerToClient,
	GameMode,
} from "./actions.js";

export const Lobbies = new Map<string, Lobby>();

const generateUniqueLobbyCode = (): string => {
	const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
	let result = "";
	for (let i = 0; i < 5; i++) {
		result += chars.charAt(Math.floor(Math.random() * chars.length));
	}
	return Lobbies.get(result) ? generateUniqueLobbyCode() : result;
};

/** Balatro High Stakes: 2 to 8 players. 1v1 Duel is exactly 2; Teams needs 4-8 (even split). */
export const MAX_PLAYERS = 8;
export const MIN_PLAYERS = 2;
export const maxPlayersFor = (mode: GameMode | string): number => (mode === "duel" ? 2 : MAX_PLAYERS);
/** null when a lobby of n players can start this mode, else the reason. */
// biome-ignore lint/suspicious/noExplicitAny: lobby options are loosely typed
export const startError = (mode: GameMode | string, n: number, options: { [k: string]: any } = {}): string | null => {
	if (n < MIN_PLAYERS) return "Need at least 2 players to start.";
	if (n > maxPlayersFor(mode)) return "Too many players for this mode.";
	if (mode === "duel" && n !== 2) return "1v1 Duel needs exactly 2 players.";
	if (mode === "teams") {
		const [size, why] = teamsPlan(n, options);
		const fmt = Number(options?.teams_format ?? 0);
		if (size === null && fmt >= 2 && fmt <= 4) return `${fmt}v${fmt} ${why}.`;
		if (size === null) return `Teams ${why} (4, 6 or 8 players).`;
	}
	return null;
};

/** Legacy helper: returns the first *other* player (prefers alive ones). */
export const getEnemy = (client: Client): [Lobby | null, Client | null] => {
	const lobby = client.lobby
	if (!lobby) return [null, null]
	if (!lobby.players.some((p) => p.id === client.id)) return [lobby, null]
	const others = lobby.players.filter((p) => p.id !== client.id)
	return [lobby, others.find((p) => !p.eliminated) ?? others[0] ?? null]
}

/** All other players in the client's lobby (alive and eliminated). */
export const getOpponents = (client: Client, aliveOnly = false): Client[] => {
	const lobby = client.lobby
	if (!lobby) return []
	return lobby.players.filter((p) => p.id !== client.id && (!aliveOnly || !p.eliminated))
}

/** Relay an action from client to every other player in the lobby. */
export const sendToOpponents = (client: Client, action: ActionServerToClient & { playerId?: string }, aliveOnly = false) => {
	// Teams: nemesis effects (phantoms, asteroid, timers, modded actions...) only hit the other team
	for (const p of getOpponents(client, aliveOnly)) if (!isTeammate(client, p)) p.sendAction(action)
}

/** Teams: same team (never true outside a running teams game). */
export const isTeammate = (a: Client, b: Client): boolean =>
	a.id !== b.id && a.team !== null && a.team === b.team && a.lobby?.gameMode === "teams"

/** Deathmatch: how long a disconnected player may rejoin before counting as eliminated (ms) */
export const DEATHMATCH_GRACE_MS = 60000;
export const deathmatchGraceMs = (options: { [key: string]: unknown } | undefined): number => {
	const g = Number(options?.deathmatch_grace);
	return Number.isFinite(g) && g >= 1 && g <= 300 ? g * 1000 : DEATHMATCH_GRACE_MS;
};
/** Modes without late join (teams are fixed; Deathmatch guarantees everyone fights every PvP) */
export const noLateJoin = (mode: string) => mode === "teams" || mode === "deathmatch";

/** How long an in-game lobby survives with nobody connected (ms) */
const EMPTY_LOBBY_TTL = 10 * 60 * 1000;

/** Disconnected player whose seat is held until the game ends. The old Client
 *  object is kept as the state snapshot. */
interface DisconnectedSlot {
	reconnectToken: string;
	index: number;
	old: Client;
	since: number;
}

/** "Name~3" -> "name" (usernames carry a blind colour suffix) */
export const baseName = (u: string) => (u || "").split("~")[0].trim().toLowerCase();

class Lobby {
	code: string;
	/** Ordered player list; players[0] is the host. Max MAX_PLAYERS. */
	players: Client[] = [];
	get host(): Client | null { return this.players[0] ?? null }
	get guest(): Client | null { return this.players[1] ?? null }
	gameMode: GameMode;
	// biome-ignore lint/suspicious/noExplicitAny:
	options: { [key: string]: any };
	tcgBets: Map<string, number>;
    handyAllowMPExtension: Map<string, boolean>;
	firstReadyAt: number | null;
	/** Tracks disconnected players awaiting reconnection */
	disconnectedSlots: DisconnectedSlot[] = [];
	/** Whether a game is currently in progress */
	isInGame = false;
	/** Authoritative seed generated for the current game (null until startGame,
	 *  or for different-seeds games where each client uses its own). */
	seed: string | null = null;
	/** a blind has started and its PvP result hasn't been resolved yet */
	blindActive = false;
	/** King of the Hill: crown state (null unless gameMode === "koth" and a game runs) */
	koth: KothState | null = null;
	/** Teams: shared lives per team while a teams game runs */
	teamLives: Partial<Record<Team, number>> | null = null;
	/** Teams: players per team for the running game */
	teamSize = 2;
	/** Players at game start (KotH scaling) */
	startPlayers = 0;
	/** Deathmatch: elimination order (ids) and the winner, for the standings */
	elimOrder: string[] = [];
	winnerId: string | null = null;
	graceTimers = new Map<string, ReturnType<typeof setTimeout>>();
	/** increments for every started PvP blind */
	blindSeq = 0;
	/** deletes the lobby if nobody reconnects while it's empty mid-game */
	emptyTimer: ReturnType<typeof setTimeout> | null = null;

	// Attrition is the default game mode
	constructor(host: Client, gameMode: GameMode = "attrition") {
		do {
			this.code = generateUniqueLobbyCode();
		} while (Lobbies.get(this.code));
		Lobbies.set(this.code, this);

		this.players = [host];
		this.gameMode = gameMode;
		this.options = {};
		this.tcgBets = new Map();
        this.handyAllowMPExtension = new Map();
		this.firstReadyAt = null;

		host.setLobby(this);
		host.isReadyLobby = false;
		host.sendAction({
			action: "joinedLobby",
			code: this.code,
			type: this.gameMode,
			reconnectToken: host.reconnectToken,
		});
	}

	/** Seats for this lobby's mode: 2 for 1v1 Duel, else up to 8. */
	get maxPlayers(): number { return maxPlayersFor(this.gameMode) }

	static get = (code: string) => {
		return Lobbies.get(code);
	};

	/** Voluntary leave — no grace period */
	leave = (client: Client) => {
		const wasMember = this.players.some((p) => p.id === client.id);
		this.players = this.players.filter((p) => p.id !== client.id);
		client.setLobby(null);
		const wasEliminated = client.eliminated;
		client.eliminated = false;
		if (!wasMember) return;
		this.handyAllowMPExtension.delete(client.id);

		if (this.players.length === 0) {
			this.destroy();
			return;
		}

		if (this.isInGame) {
			// A voluntary leaver mid-game is out; the game continues for the others.
			this.broadcastAction({ action: "playerLeft", playerId: client.id, username: client.username });
			if (this.gameMode === "deathmatch" && !wasEliminated) {
				// a leaver counts as eliminated
				this.elimOrder.push(client.id);
				this.broadcastAction({ action: "playerEliminated", playerId: client.id, username: client.username, reason: "left" });
			}
			client.team = null;
			this.deathmatchBroadcast();
			this.teamsBroadcast();
			this.checkGameOver();
			if (this.isInGame) {
				this.tryStartBlind();
				this.tryResolvePvP();
			}
		} else {
			this.broadcastAction({ action: "stopGame" });
			this.resetPlayers();
		}
		this.broadcastLobbyInfo();
	};

	destroy = () => {
		for (const t of this.graceTimers.values()) clearTimeout(t);
		this.graceTimers.clear();
		if (this.emptyTimer) clearTimeout(this.emptyTimer);
		this.emptyTimer = null;
		this.disconnectedSlots = [];
		Lobbies.delete(this.code);
	};

	/** Connection lost. Mid-game the seat is held until the game ends; the
	 *  player is skipped for PvP while away. */
	disconnect = (client: Client) => {
		const index = this.players.findIndex((p) => p.id === client.id);
		if (index === -1) return;

		if (!this.isInGame) {
			this.leave(client);
			return;
		}

		console.log(`Player ${client.id} (${client.username}) disconnected from lobby ${this.code}; holding seat until game ends`);
		const slot = { reconnectToken: client.reconnectToken, index, old: client, since: Date.now() };
		this.disconnectedSlots.push(slot);
		this.players.splice(index, 1);
		if (this.gameMode === "deathmatch" && !client.eliminated) {
			const t = setTimeout(() => this.deathmatchExpire(slot), deathmatchGraceMs(this.options));
			this.graceTimers.set(client.id, t);
		}
		client.setLobby(null);

		for (const p of this.players) {
			p.sendAction({ action: "enemyDisconnected", timeout: 0, playerId: client.id, held: true });
		}

		if (this.players.length === 0) {
			this.emptyTimer = setTimeout(() => {
				console.log(`Lobby ${this.code} empty for too long, deleting`);
				this.destroy();
			}, EMPTY_LOBBY_TTL);
			return;
		}
		// Don't let the others wait on someone who isn't there
		this.tryStartBlind();
		this.tryResolvePvP();
		this.broadcastLobbyInfo();
	};

	/** Seat a reconnecting client in a held slot, restoring their state. */
	reclaimSlot = (newClient: Client, slot: DisconnectedSlot) => {
		this.disconnectedSlots = this.disconnectedSlots.filter((s) => s !== slot);
		const gt = this.graceTimers.get(slot.old.id);
		if (gt) { clearTimeout(gt); this.graceTimers.delete(slot.old.id); }
		if (this.emptyTimer) { clearTimeout(this.emptyTimer); this.emptyTimer = null; }
		const o = slot.old;
		const fields = [
			"team", "lives", "score", "handsLeft", "ante", "skips", "furthestBlind", "isReady", "firstReady",
			"isReadyLobby", "roundLivesBlocker", "timerLivesBlocker", "location", "eliminated", "pvpDone",
			"pvpTimerFailed", "playedThisBlind", "blindSeq", "inPvp", "sitOut", "modHash", "isCached",
		] as const;
		for (const f of fields) (newClient as any)[f] = (o as any)[f];
		if (!newClient.username || newClient.username === "Guest") newClient.username = o.username;
		if (this.koth && this.koth.kingId === o.id) this.koth.kingId = newClient.id;

		this.players.splice(Math.min(slot.index, this.players.length), 0, newClient);
		newClient.setLobby(this);
		this.handyAllowMPExtension.set(newClient.id, false);

		// The PvP blind they were in finished while they were away: release them
		const missedBlind = newClient.inPvp && (!this.blindActive || newClient.blindSeq !== this.blindSeq);
		if (missedBlind) {
			newClient.inPvp = false;
			newClient.pvpDone = false;
			newClient.isReady = false;
		}

		newClient.sendAction({ action: "rejoinedLobby", code: this.code, type: this.gameMode, reconnectToken: newClient.reconnectToken });
		newClient.sendAction({ action: "lobbyOptions", gamemode: this.gameMode, ...this.options });
		this.sendResume(newClient, false);
		this.kothBroadcast();
		this.teamsBroadcast();
		if (missedBlind) newClient.sendAction({ action: "endPvP", lost: false, loserIds: [] });

		for (const p of this.players) {
			if (p.id !== newClient.id) {
				p.sendAction({ action: "enemyReconnected", playerId: newClient.id });
				p.sendAction(this.enemyInfoFor(newClient, true));
			}
		}
		console.log(`Player ${newClient.username} rejoined lobby ${this.code} (lives=${newClient.lives}, ante=${newClient.ante})`);
		this.broadcastLobbyInfo();
	};

	/** Tell a (re)joining client how to continue: seed, ante, lives, opponents. */
	sendResume = (client: Client, lateJoin: boolean) => {
		client.sendAction({
			action: "resumeGame",
			seed: this.seed ?? undefined,
			ante: Math.max(1, client.ante),
			lives: client.lives,
			lateJoin,
			eliminated: client.eliminated,
			blindActive: this.blindActive,
			inCurrentBlind: client.inPvp && this.blindActive && client.blindSeq === this.blindSeq,
		});
		client.sendAction({ action: "playerInfo", lives: client.lives });
		for (const o of this.players) if (o.id !== client.id) client.sendAction(this.enemyInfoFor(o, true));
		for (const s of this.disconnectedSlots) client.sendAction(this.enemyInfoFor(s.old, true));
	};

	/** Reconnect via token (automatic reconnect / restart with saved token). */
	rejoin = (newClient: Client, reconnectToken: string): boolean => {
		let slot = this.disconnectedSlots.find((s) => s.reconnectToken === reconnectToken);
		if (!slot) {
			// The server may not have noticed the old socket died yet: take it over
			const stale = this.players.find((p) => p.reconnectToken === reconnectToken && p.id !== newClient.id);
			if (stale && this.isInGame) {
				this.disconnect(stale);
				try { stale.closeConnection(); } catch {}
				slot = this.disconnectedSlots.find((s) => s.old === stale);
			}
		}
		if (!slot) return false;
		this.reclaimSlot(newClient, slot);
		return true;
	};

	join = (client: Client) => {
		if (this.isInGame) {
			const name = baseName(client.username);
			// 1) Rejoin by name (e.g. after a crash, without the saved token)
			const slot = this.disconnectedSlots.find((s) => baseName(s.old.username) === name);
			if (slot) {
				this.reclaimSlot(client, slot);
				return;
			}
			const stale = this.players.find((p) => baseName(p.username) === name && p.id !== client.id);
			if (stale) {
				this.disconnect(stale);
				try { stale.closeConnection(); } catch {}
				const s2 = this.disconnectedSlots.find((s) => s.old === stale);
				if (s2) { this.reclaimSlot(client, s2); return; }
			}
			// 2) Late join if there's a free seat (not in Teams: teams are fixed at the start)
			if (this.gameMode === "deathmatch") {
				client.sendAction({ action: "error", message: "Deathmatch in progress: no late join." });
				return;
			}
			if (!noLateJoin(this.gameMode) && this.players.length + this.disconnectedSlots.length < this.maxPlayers) {
				this.lateJoin(client);
				return;
			}
			client.sendAction({ action: "error", message: "Lobby is full." });
			return;
		}
		if (this.players.length >= this.maxPlayers) {
			client.sendAction({ action: "error", message: "Lobby is full or does not exist." });
			return;
		}
		this.players.push(client);
		client.eliminated = false;
		client.setLobby(this);
		client.isReadyLobby = false;
		this.handyAllowMPExtension.set(client.id, false);
		client.sendAction({ action: "joinedLobby", code: this.code, type: this.gameMode, reconnectToken: client.reconnectToken });
		client.sendAction({ action: "lobbyOptions", gamemode: this.gameMode, ...this.options });
		this.broadcastLobbyInfo();
	};

	/**
	 * Late join rule: the newcomer starts a fresh run on the lobby seed at the
	 * lowest ante any alive player is on, with the lowest life total among
	 * alive players (min 1). They sit out a PvP blind that's already running.
	 */
	lateJoin = (client: Client) => {
		const aliveConnected = this.alivePlayers();
		const aliveAway = this.awayAlive().map((s) => s.old);
		const all = [...aliveConnected, ...aliveAway];
		client.lives = Math.max(1, Math.min(...all.map((p) => p.lives)));
		client.ante = Math.max(1, Math.min(...(aliveConnected.length ? aliveConnected : all).map((p) => p.ante || 1)));
		client.eliminated = false;
		client.isReady = false;
		client.firstReady = false;
		client.score = new InsaneInt(0, 0, 0);
		client.handsLeft = 4;
		client.skips = 0;
		client.inPvp = false;
		client.pvpDone = false;
		client.sitOut = this.blindActive;
		client.resetBlocker();
		this.players.push(client);
		client.setLobby(this);
		client.isReadyLobby = true;
		this.handyAllowMPExtension.set(client.id, false);
		client.sendAction({ action: "joinedLobby", code: this.code, type: this.gameMode, reconnectToken: client.reconnectToken });
		client.sendAction({ action: "lobbyOptions", gamemode: this.gameMode, ...this.options });
		this.sendResume(client, true);
		this.kothBroadcast();
		for (const p of this.players) {
			if (p.id !== client.id) {
				p.sendAction({ action: "playerJoined", playerId: client.id, username: client.username });
				p.sendAction(this.enemyInfoFor(client, true));
			}
		}
		console.log(`Late join: ${client.username} joined ${this.code} at ante ${client.ante} with ${client.lives} lives`);
		this.broadcastLobbyInfo();
	};

	broadcastAction = (action: ActionServerToClient) => {
		for (const p of this.players) p.sendAction(action);
	};

	broadcastLobbyInfo = () => {
		const host = this.host;
		if (!host) return;

		// Teams: team of every seat (in game: fixed teams; in the lobby: the host's order/size)
		const teamPreview = this.gameMode === "teams" ? assignTeams(this.players.map((p) => p.id), this.options) : null;
		const players = this.players.map((p, i) => ({
			id: p.id,
			username: p.username,
			hash: p.modHash,
			cached: p.isCached,
			ready: p.isReadyLobby,
			isHost: i === 0,
			lives: p.lives,
			eliminated: p.eliminated,
			...(teamPreview ? { team: p.team ?? teamPreview.get(p.id) } : {}),
		}));

		for (const p of this.players) {
			const others = this.players.filter((o) => o.id !== p.id);
			// Legacy fields: "guest" = first opponent from the receiver's view
			// (for the host) so old UI code keeps working.
			const action: ActionLobbyInfo = {
				action: "lobbyInfo",
				host: host.username,
				hostHash: host.modHash,
				isHost: p.id === host.id,
				hostCached: host.isCached,
				players,
				you: p.id,
				maxPlayers: this.maxPlayers,
				away: this.disconnectedSlots.map((sl) => ({ id: sl.old.id, username: sl.old.username, lives: sl.old.lives })),
				inGame: this.isInGame,
			};
			const legacyGuest = this.guest;
			if (legacyGuest) {
				action.guest = legacyGuest.username;
				action.guestHash = legacyGuest.modHash;
				action.guestCached = legacyGuest.isCached;
				action.guestReady = others.every((o) => o.id === host.id || o.isReadyLobby);
			}
			p.sendAction(action);
		}

        this.broadcastAction({
            action: "handyMPExtensionLobbyEnabled",
            enabled: Array.from(this.handyAllowMPExtension.values()).every(Boolean)
        })
	};

	setPlayersLives = (lives: number) => {
		for (const p of this.players) {
			p.lives = lives;
			p.eliminated = false;
		}

		this.broadcastAction({ action: "playerInfo", lives });
	};

	// Deprecated
	sendGameInfo = (client: Client) => {
		if (!this.players.includes(client)) {
			return client.sendAction({
				action: "error",
				message: "Client not in Lobby",
			});
		}

		client.sendAction({
			action: "gameInfo",
			...GameModes[this.gameMode].getBlindFromAnte(client.ante, this.options),
		});
	};

	setOptions = (options: { [key: string]: string }) => {
		const teamsBefore = `${this.options.teams_order ?? ""}|${this.options.teams_size ?? ""}|${this.options.teams_format ?? ""}`;
		for (const key of Object.keys(options)) {
			if (options[key] === "true" || options[key] === "false") {
				this.options[key] = options[key] === "true";
			} else {
				this.options[key] = options[key];
			}
		}
		for (const p of this.players.slice(1)) p.sendAction({ action: "lobbyOptions", gamemode: this.gameMode, ...options });
		// Re-broadcast the team preview only when the split really changed (the host re-sends
		// all options after every lobbyInfo, so an unconditional broadcast would loop).
		const teamsAfter = `${this.options.teams_order ?? ""}|${this.options.teams_size ?? ""}|${this.options.teams_format ?? ""}`;
		if (this.gameMode === "teams" && !this.isInGame && teamsAfter !== teamsBefore) this.broadcastLobbyInfo();
	};

	resetPlayers = () => {
		this.isInGame = false;
		for (const p of this.players) {
			p.isReady = false;
			p.firstReady = false;
			p.resetBlocker();
			p.setLocation("Blind Select");
			p.furthestBlind = 0;
			p.skips = 0;
			p.score = new InsaneInt(0, 0, 0);
			p.handsLeft = 4;
			p.pvpDone = false;
			p.pvpTimerFailed = false;
			p.playedThisBlind = false;
			p.inPvp = false;
			p.sitOut = false;
			p.ante = 1;
			p.team = null;
		}
		this.teamLives = null;
		this.elimOrder = [];
		this.winnerId = null;
		for (const t of this.graceTimers.values()) clearTimeout(t);
		this.graceTimers.clear();
		this.tcgBets.clear();
		this.firstReadyAt = null;
		this.blindActive = false;
		this.disconnectedSlots = [];
	};

	/** Held seats of players who are away but still alive. */
	awayAlive = () => this.disconnectedSlots.filter((s) => !s.old.eliminated && s.old.lives > 0);

	/** Players taking part in the current PvP blind (connected, alive, not sitting out). */
	participants = (): Client[] => this.alivePlayers().filter((p) => !p.sitOut);

	/** Players still in the game (not eliminated). */
	alivePlayers = (): Client[] => this.players.filter((p) => !p.eliminated);

	/** Snapshot of one player's public state for enemyInfo. */
	enemyInfoFor = (p: Client, withScore: boolean) => ({
		action: "enemyInfo" as const,
		playerId: p.id,
		username: p.username,
		handsLeft: p.handsLeft,
		score: withScore ? p.score.toString() : null,
		...(withScore ? {} : { noScore: true as const }),
		skips: p.skips,
		lives: p.lives,
		eliminated: p.eliminated,
	});

	// ---------------- Teams (2v2 ... 4v4, 2v2v2, 2v2v2v2) ----------------
	teamsActive = () => this.gameMode === "teams" && this.teamLives !== null;

	/** Fix the teams at game start (exactly 4 players). */
	teamsStart = (lives: number) => {
		if (this.gameMode !== "teams") return;
		const teams = assignTeams(this.players.map((p) => p.id), this.options);
		const [size, count] = teamsPlan(this.players.length, this.options);
		if (!teams || size === null) return;
		for (const p of this.players) p.team = teams.get(p.id) ?? null;
		this.teamSize = size;
		this.teamLives = {};
		for (const t of TEAM_LETTERS.slice(0, count as number)) this.teamLives[t] = lives;
		this.teamsBroadcast();
	};

	/** Everyone on a team: connected players and held (away) seats. */
	teamMembers = (team: Team): Client[] => [
		...this.players.filter((p) => p.team === team),
		...this.disconnectedSlots.map((s) => s.old).filter((o) => o.team === team),
	];

	/** Set a team's shared lives and sync them to everyone. */
	setTeamLives = (team: Team, lives: number) => {
		if (!this.teamLives) return;
		this.teamLives[team] = lives;
		for (const m of this.teamMembers(team)) m.lives = lives;
		for (const p of this.players) {
			if (p.team !== team) continue;
			p.sendAction({ action: "playerInfo", lives });
			const info = this.enemyInfoFor(p, true);
			for (const o of this.players) if (o.id !== p.id) o.sendAction(info);
		}
	};

	/** Life loss outside the PvP resolution (timers, failed rounds). In Teams the whole team
	 *  loses one life, once per cause per round (the teammates' blockers are set too). */
	loseLifeFor = (client: Client, cause: "round" | "timer" = "round") => {
		if (!this.teamsActive() || !client.team) return client.loseLife(cause);
		const blocked = cause === "timer" ? client.timerLivesBlocker : client.roundLivesBlocker;
		if (blocked) return;
		for (const m of this.teamMembers(client.team)) {
			if (cause === "timer") m.timerLivesBlocker = true; else m.roundLivesBlocker = true;
		}
		this.setTeamLives(client.team, Math.max(0, (this.teamLives?.[client.team] ?? client.lives) - 1));
	};

	/** Tell everyone the teams, team lives and (optionally) which team lost the last PvP. */
	teamsBroadcast = (lastLoser?: Team | null) => {
		if (!this.teamsActive() || !this.teamLives) return;
		const all = [...this.players, ...this.disconnectedSlots.map((s) => s.old)];
		const teams: Partial<Record<Team, { members: { id: string; username: string }[]; lives: number }>> = {};
		for (const [t, lives] of Object.entries(this.teamLives) as [Team, number][]) teams[t] = { members: [], lives };
		for (const p of all) if (p.team && teams[p.team]) teams[p.team]?.members.push({ id: p.id, username: p.username });
		for (const p of this.players) {
			p.sendAction({
				action: "teamsUpdate",
				you: p.id,
				team: p.team,
				teamSize: this.teamSize,
				teams,
				...(lastLoser !== undefined ? { lastLoser: lastLoser ?? "none" } : {}),
			});
		}
	};

	/** Teams PvP: the single lowest team sum loses a team life. Returns the losing team (or null). */
	teamsResolve = (alive: Client[]): Team | null => {
		const present: Partial<Record<Team, InsaneInt[]>> = {};
		for (const p of alive) if (p.team) (present[p.team] ??= []).push(p.score);
		const loser = resolveTeams(present, this.teamSize);
		if (loser && this.teamLives) this.setTeamLives(loser, Math.max(0, (this.teamLives[loser] ?? 1) - 1));
		return loser;
	};

	// ---------------- King of the Hill ----------------
	kothActive = () => this.gameMode === "koth";

	kothResolve = (alive: Client[], roundLosers: Client[]): KothEvent | null => {
		if (!this.kothActive()) return null;
		if (!this.koth) this.koth = newKothState();
		const cfg = kothConfig(this.options, this.startPlayers || undefined);
		const ev = resolveKoth(
			this.koth,
			alive.map((p) => ({ id: p.id, name: p.username, score: p.score })),
			roundLosers.map((p) => p.id),
			(a, b) => a.greaterThan(b),
			(a, b) => a.equalTo(b),
			cfg,
		);
		if (ev.lifeBonus && ev.claimedBy) {
			const p = alive.find((x) => x.id === ev.claimedBy);
			if (p && p.lives < cfg.startingLives) {
				p.lives += 1;
				p.sendAction({ action: "playerInfo", lives: p.lives });
			} else ev.lifeBonus = false;
		}
		return ev;
	};

	/** Send the King state to everyone (personalised with "you" = their own id). */
	kothBroadcast = (ev?: KothEvent) => {
		if (!this.kothActive()) return;
		if (!this.koth) this.koth = newKothState();
		const e = ev ?? kothSnapshot(this.koth, new Map(this.players.map((p) => [p.id, p.username])), kothConfig(this.options, this.startPlayers || undefined));
		for (const p of this.players) p.sendAction({ ...e, action: "kothUpdate", you: p.id });
	};

	/** The King held the hill long enough: everyone else is out. */
	kothHillWin = (winnerId: string): boolean => {
		const winner = this.players.find((p) => p.id === winnerId);
		if (!winner) return false;
		for (const p of this.players) {
			if (p.id === winnerId || p.eliminated) continue;
			p.eliminated = true;
			p.sendAction({ action: "loseGame", reason: "koth_hill" });
			for (const o of this.players) if (o.id !== p.id) o.sendAction({ action: "playerEliminated", playerId: p.id, username: p.username });
		}
		winner.sendAction({ action: "winGame", reason: "koth_hill" });
		this.isInGame = false;
		this.blindActive = false;
		this.disconnectedSlots = [];
		return true;
	};

	/** Mark players with 0 lives eliminated; end the game if <=1 remains. */
	checkGameOver = (): boolean => {
		if (!this.isInGame) return true;
		// Deathmatch: a player at 0 lives during a PvP blind dies when that PvP resolves, so players
		// who die in the same PvP die together (simultaneous final deaths -> highest score wins).
		if (this.gameMode === "deathmatch" && this.blindActive) return false;
		// 0.6.8 final: every mode. A last life lost while others still play the same PvP is judged when
		// that PvP resolves, so two players dying on the same tick never depend on message order.
		if (this.blindActive) {
			const live = this.players.filter((p) => !p.eliminated);
			const dyingAny = live.some((p) => p.lives <= 0);
			const playing = live.some((p) => p.lives > 0 && !p.sitOut && !p.pvpDone && p.handsLeft >= 1);
			if (dyingAny && playing) return false;
		}
		const dying = this.players.filter((p) => !p.eliminated && p.lives <= 0);
		const survivors = this.players.filter((p) => !p.eliminated && p.lives > 0).length + this.awayAlive().length;
		const spared = new Set<Client>();
		if (survivors === 0 && dying.length > 0 && !this.teamsActive()) {
			// nobody left standing: the highest score among those dying now wins (ties: all of them)
			let best = dying[0].score;
			for (const p of dying) if (p.score.greaterThan(best)) best = p.score;
			for (const p of dying) if (!best.greaterThan(p.score) && !p.score.greaterThan(best)) spared.add(p);
		}
		for (const p of dying) {
			p.eliminated = true;
			if (!spared.has(p)) p.sendAction({ action: "loseGame" });
			for (const o of this.players) {
				if (o.id !== p.id) o.sendAction({ action: "playerEliminated", playerId: p.id, username: p.username });
			}
			this.elimOrder.push(p.id);
		}
		if (spared.size > 0) {
			for (const p of spared) { p.sendAction({ action: "winGame", reason: "final_score" }); this.winnerId ??= p.id; }
			this.isInGame = false;
			this.blindActive = false;
			this.disconnectedSlots = [];
			this.deathmatchBroadcast();
			return true;
		}
		if (dying.length > 0 || this.gameMode === "deathmatch") this.deathmatchBroadcast();
		const alive = this.alivePlayers();
		if (this.teamsActive()) {
			// Teams: the game ends when only one team has anyone left (connected or seat held)
			const left = new Set([...alive, ...this.awayAlive().map((s) => s.old)].map((p) => p.team));
			if (left.size <= 1) {
				for (const p of alive) p.sendAction({ action: "winGame", reason: "teams" });
				this.isInGame = false;
				this.blindActive = false;
				this.disconnectedSlots = [];
				return true;
			}
			return false;
		}
		// Away players with lives left still count: their seat is held
		if (alive.length + this.awayAlive().length <= 1) {
			alive[0]?.sendAction({ action: "winGame" });
			this.isInGame = false;
			this.blindActive = false;
			this.disconnectedSlots = [];
			this.winnerId = alive[0]?.id ?? null;
			this.deathmatchBroadcast();
			return true;
		}
		return false;
	};

	/** Deathmatch standings for everyone in the lobby (also eliminated players who spectate). */
	deathmatchBroadcast = () => {
		if (this.gameMode !== "deathmatch") return;
		const alive = [
			...this.players.filter((p) => !p.eliminated).map((p) => ({ id: p.id, username: p.username, lives: p.lives })),
			...this.disconnectedSlots.filter((s) => !s.old.eliminated)
				.map((s) => ({ id: s.old.id, username: s.old.username, lives: s.old.lives, away: true })),
		];
		const n = this.elimOrder.length;
		const out = this.elimOrder.map((id, i) => ({ id, place: alive.length + (n - i) }));
		for (const p of this.players) {
			p.sendAction({ action: "deathmatchUpdate", you: p.id, alive, out, running: this.isInGame,
				...(!this.isInGame && this.winnerId ? { winnerId: this.winnerId } : {}) });
		}
	};

	/** Deathmatch: a held seat whose grace ran out counts as eliminated (the seat stays, so a
	 *  late reconnect comes back as a spectator). */
	deathmatchExpire = (slot: DisconnectedSlot) => {
		this.graceTimers.delete(slot.old.id);
		const o = slot.old;
		if (!this.isInGame || o.eliminated || !this.disconnectedSlots.includes(slot)) return;
		o.eliminated = true;
		o.lives = 0;
		this.elimOrder.push(o.id);
		for (const p of this.players) {
			p.sendAction({ action: "playerEliminated", playerId: o.id, username: o.username, reason: "disconnected" });
			p.sendAction(this.enemyInfoFor(o, true));
		}
		this.deathmatchBroadcast();
		if (this.checkGameOver()) return;
		this.tryStartBlind();
		this.tryResolvePvP();
	};

	/** If every alive player is ready for the blind, start it. */
	tryStartBlind = () => {
		if (!this.isInGame || this.blindActive) return false;
		const alive = this.alivePlayers();
		if (alive.length === 0 || !alive.every((p) => p.isReady)) return false;
		this.blindSeq++;
		for (const p of alive) {
			p.sitOut = false;
			p.inPvp = true;
			p.blindSeq = this.blindSeq;
			p.isReady = false;
			p.score = new InsaneInt(0, 0, 0);
			p.handsLeft = 4;
			p.playedThisBlind = false;
			p.pvpDone = false;
			p.resetBlocker();
		}
		const first = alive.find((p) => p.firstReady);
		const firstPlayer = first ? (first.id === this.host?.id ? "host" : "guest") : undefined;
		this.firstReadyAt = null;
		this.blindActive = true;
		this.broadcastAction({ action: "startBlind", firstPlayer, firstPlayerId: first?.id });
		return true;
	};

	/**
	 * PvP resolution: once every alive player is out of hands (or failed the
	 * PvP timer), the single lowest score loses a life (6-8 players: the bottom two,
	 * see pvpRules.ts). Ties at the cut cost nobody a life. Players at 0 lives are
	 * eliminated; last one standing wins. Teams mode: tryResolveTeamsPvP.
	 */
	tryResolvePvP = () => {
		if (!this.isInGame || !this.blindActive) return;
		// Away / sitting-out players are skipped, so nobody waits forever
		const alive = this.participants();
		if (alive.length === 0) return;
		if (!alive.every((p) => p.pvpDone || p.handsLeft < 1)) return;
		this.blindActive = false;
		for (const p of this.players) p.inPvp = false;
		if (alive.length === 1) {
			// Opponents are away: nobody loses a life this blind
			const p = alive[0];
			p.firstReady = false;
			p.pvpDone = false;
			p.pvpTimerFailed = false;
			p.sendAction({ action: "endPvP", lost: false, loserIds: [], opponentsAway: true });
			return;
		}

		if (this.teamsActive()) {
			this.tryResolveTeamsPvP(alive);
			return;
		}
		const timerLosers = alive.filter((p) => p.pvpTimerFailed);
		let roundLosers: Client[] = [];
		if (timerLosers.length === 0) {
			// 2-5 players: the single lowest score; 6-8: the bottom two (pvpRules.ts)
			const ids = new Set(pvpLosers(alive.map((p) => ({ id: p.id, score: p.score })), (a, b) => !a.greaterThan(b)));
			roundLosers = alive.filter((p) => ids.has(p.id));
		}
		const kothEv = this.kothResolve(alive, roundLosers);
		if (kothEv?.shieldedId) roundLosers = roundLosers.filter((p) => p.id !== kothEv.shieldedId);
		for (const p of roundLosers) p.loseLife("round");

		for (const p of alive) {
			p.firstReady = false;
			p.pvpDone = false;
			p.pvpTimerFailed = false;
		}
		// Send final scores of everyone to everyone
		for (const p of alive) {
			for (const o of this.players) if (o.id !== p.id) p.sendAction(this.enemyInfoFor(o, true));
		}
		if (kothEv) {
			this.kothBroadcast(kothEv);
			if (kothEv.winnerId && this.kothHillWin(kothEv.winnerId)) return;
		}
		if (this.checkGameOver()) return;
		// sit-out players (mid-blind late joiners) were not in this PvP: no endPvP for them
		for (const p of alive) {
			p.sendAction({
				action: "endPvP",
				lost: roundLosers.includes(p) || timerLosers.includes(p),
				...(timerLosers.length ? { pvpTimerLost: true } : {}),
				loserIds: [...roundLosers, ...timerLosers].map((l) => l.id),
			});
		}
	};

	/** Teams PvP resolution (called by tryResolvePvP once everyone present is done). */
	private tryResolveTeamsPvP = (alive: Client[]) => {
		const teamsPresent = new Set(alive.map((p) => p.team));
		const timerLosers = alive.filter((p) => p.pvpTimerFailed);
		let loser: Team | null = null;
		// Timer failures already cost their team a life (failPvPTimer); otherwise compare team sums
		if (timerLosers.length === 0 && teamsPresent.size >= 2) loser = this.teamsResolve(alive);
		for (const p of alive) {
			p.firstReady = false;
			p.pvpDone = false;
			p.pvpTimerFailed = false;
		}
		for (const p of alive) {
			for (const o of this.players) if (o.id !== p.id) p.sendAction(this.enemyInfoFor(o, true));
		}
		this.teamsBroadcast(loser);
		if (this.checkGameOver()) return;
		const timerTeams = new Set(timerLosers.map((p) => p.team));
		const loserIds = [
			...(loser ? this.teamMembers(loser) : []),
			...this.players.filter((p) => p.team && timerTeams.has(p.team)),
		].map((p) => p.id);
		for (const p of alive) {
			p.sendAction({
				action: "endPvP",
				lost: (loser !== null && p.team === loser) || (p.team !== null && timerTeams.has(p.team)),
				...(timerLosers.length ? { pvpTimerLost: true } : {}),
				...(teamsPresent.size < 2 ? { opponentsAway: true } : {}),
				loserIds: [...new Set(loserIds)],
				...(loser ? { loserTeam: loser } : {}),
			});
		}
	};
}

export default Lobby;
