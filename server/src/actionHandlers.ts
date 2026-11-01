import type Client from "./Client.js";
import GameModes from "./GameMode.js";
import { InsaneInt } from "./InsaneInt.js";
import Lobby, { baseName, getEnemy, getOpponents, sendToOpponents, startError } from "./Lobby.js";
import type {
	ActionCreateLobby,
	ActionEatPizza,
	ActionHandlerArgs,
	ActionHandlers,
	ActionJoinLobby,
	ActionRejoinLobby,
	ActionMagnet,
	ActionMagnetResponse,
	ActionPlayHand,
	ActionReceiveEndGameJokersRequest,
	ActionReceiveNemesisDeckRequest,
	ActionReceiveNemesisStatsRequest,
	ActionRemovePhantom,
	ActionSendPhantom,
	ActionSetAnte,
	ActionSetLocation,
	ActionSetFurthestBlind,
	ActionSkip,
	ActionSpentLastShop,
	ActionStartAnteTimer,
	ActionPauseAnteTimer,
	ActionSyncClient,
	ActionSubmitLogHashes,
	ActionStreamLogLines,
	ActionUsername,
	ActionVersion,
	ActionTcgServerVersion,
	ActionTcgBet,
	ActionTcgPlayerStatusRequest,
	ActionTcgEndTurn,
	ActionModded,
	ActionModdedRequest,
	ActionHandyMPExtensionEnable,
	ActionHandyMPExtensionDisable,
    ActionDataSyncRequest,
} from "./actions.js";
import { generateSeed } from "./utils.js";
import {
	deleteLiveLog,
	recordLiveLogLines,
	recordLogHashes,
} from "./logHashStore.js";

/** Current TCG server version - clients must match this to use TCG features */
const TCG_SERVER_VERSION = 1;

const usernameAction = (
	{ username, modHash }: ActionHandlerArgs<ActionUsername>,
	client: Client,
) => {
	client.setUsername(username);
	client.setModHash(modHash);
};

const createLobbyAction = (
	{ gameMode }: ActionHandlerArgs<ActionCreateLobby>,
	client: Client,
) => {
	/** Also sets the client lobby to this newly created one */
	new Lobby(client, gameMode);
};

const joinLobbyAction = (
	{ code }: ActionHandlerArgs<ActionJoinLobby>,
	client: Client,
) => {
	const newLobby = Lobby.get(code);
	if (!newLobby) {
		client.sendAction({
			action: "error",
			message: "Lobby does not exist.",
		});
		return;
	}
	newLobby.join(client);
};

const leaveLobbyAction = (client: Client) => {
	client.lobby?.leave(client);
};

/** Called when a client's TCP connection drops (not voluntary) */
const disconnectFromLobbyAction = (client: Client) => {
	client.lobby?.disconnect(client);
};

/** 3P: the client restarted its run after a rejoin, so it can't finish the
 *  PvP blind that is running; it sits that one out. */
const resumeRestartedAction = (client: Client) => {
	const lobby = client.lobby;
	if (!lobby) return;
	if (lobby.blindActive) {
		client.sitOut = true;
		client.inPvp = false;
		lobby.tryResolvePvP();
	}
	client.isReady = false;
};

const rejoinLobbyAction = (
	{ code, reconnectToken }: ActionHandlerArgs<ActionRejoinLobby>,
	client: Client,
) => {
	const lobby = Lobby.get(code);
	if (!lobby) {
		client.sendAction({ action: "rejoinFailed", message: "Lobby no longer exists." });
		return;
	}

	if (!lobby.rejoin(client, reconnectToken)) {
		// 3P: try by name (same as joinLobby while a game is running)
		if (lobby.isInGame && lobby.disconnectedSlots.some((s) => baseName(s.old.username) === baseName(client.username))) {
			lobby.join(client);
			return;
		}
		client.sendAction({ action: "rejoinFailed", message: "Could not rejoin lobby. Token invalid or slot expired." });
	}
};

const lobbyInfoAction = (client: Client) => {
	client.lobby?.broadcastLobbyInfo();
};

const readyLobbyAction = (client: Client) => {
	client.isReadyLobby = true;
	client.lobby?.broadcastLobbyInfo();
};

const unreadyLobbyAction = (client: Client) => {
	client.isReadyLobby = false;
	client.lobby?.broadcastLobbyInfo();
};

const keepAliveAction = (client: Client) => {
	// Send an ack back to the received keepAlive
	client.sendAction({ action: "keepAliveAck" });
};

const startGameAction = (client: Client) => {
	const lobby = client.lobby;
	if (!lobby || lobby.host?.id !== client.id) return;
	if (lobby.isInGame) {
		client.sendAction({ action: "error", message: "A match is still running." });
		return;
	}
	const why = startError(lobby.gameMode, lobby.players.length, lobby.options);
	if (why) {
		client.sendAction({ action: "error", message: why });
		return;
	}
	lobby.startPlayers = lobby.players.length;

	const lives = lobby.options.starting_lives
		? Number.parseInt(lobby.options.starting_lives)
		: GameModes[lobby.gameMode].startingLives;

	const seed = lobby.options.different_seeds ? undefined : generateSeed();
	lobby.seed = seed ?? null;
	lobby.resetPlayers();

	lobby.isInGame = true;
	lobby.broadcastAction({
		action: "startGame",
		deck: "c_multiplayer_1",
		seed,
		playerCount: lobby.players.length,
	});

	lobby.setPlayersLives(lives);
	lobby.koth = null;
	lobby.kothBroadcast();
	lobby.teamsStart(lives);
	for (const p of lobby.players.slice(1)) p.isReadyLobby = false;
	// Let everyone know about every opponent up front
	for (const p of lobby.players) {
		for (const o of lobby.players) if (o.id !== p.id) p.sendAction(lobby.enemyInfoFor(o, true));
	}
};

const readyBlindAction = (client: Client) => {
	const lobby = client.lobby;
	if (!lobby || client.eliminated) return;
	client.isReady = true;

	const anyoneElseReady = lobby.alivePlayers().some((p) => p.id !== client.id && (p.isReady || p.firstReady));
	if (!client.firstReady && !anyoneElseReady) {
		client.firstReady = true;
		lobby.firstReadyAt = Date.now();
		client.sendAction({ action: "speedrun" });
	} else if (lobby.firstReadyAt && Date.now() - lobby.firstReadyAt <= 30000 && !client.firstReady) {
		client.sendAction({ action: "speedrun" });
	}

	lobby.tryStartBlind();
};

const unreadyBlindAction = (client: Client) => {
	client.isReady = false;
};

const playHandAction = (
	{ handsLeft, score }: ActionHandlerArgs<ActionPlayHand>,
	client: Client,
) => {
	const lobby = client.lobby;
	// 3P: opponents may be away (seat held); never stop the game here
	if (!lobby || !lobby.isInGame) return;
	if (client.eliminated) return;

	client.score = InsaneInt.fromString(String(score));
	client.handsLeft = Math.floor(typeof handsLeft === "number" ? handsLeft : Number(handsLeft));

	const hideScore = Boolean(lobby.options.hide_score_until_played);
	if (client.score.greaterThan(new InsaneInt(0, 0, 0))) client.playedThisBlind = true;
	if (client.handsLeft < 1) client.pvpDone = true;

	// Timer order: highest current score goes first (ties -> whoever readied first)
	const ranking = lobby.alivePlayers().slice().sort((a, b) =>
		a.score.equalTo(b.score) ? Number(b.firstReady) - Number(a.firstReady) : (b.score.greaterThan(a.score) ? 1 : -1));
	const order = ranking.map((p) => p.id);

	for (const o of getOpponents(client)) {
		// Our state to them
		const ours = lobby.enemyInfoFor(client, !hideScore || o.playedThisBlind);
		o.sendAction({ ...ours, pvpTimerOrder: order[0] === client.id ? "guest" : "host", pvpOrder: order });
		// Their state to us
		const theirs = lobby.enemyInfoFor(o, !hideScore || client.playedThisBlind);
		client.sendAction({ ...theirs, pvpTimerOrder: order[0] === client.id ? "host" : "guest", pvpOrder: order });
	}

	lobby.tryResolvePvP();
};

const failPvPTimerAction = (client: Client) => {
	const lobby = client.lobby;
	if (lobby) lobby.loseLifeFor(client, 'timer'); else client.loseLife('timer');
	if (!lobby) return;
	client.pvpDone = true;
	client.pvpTimerFailed = true;
	if (lobby.checkGameOver()) return;
	lobby.tryResolvePvP();
};

const stopGameAction = (client: Client) => {
	if (!client.lobby) {
		return;
	}
	// An eliminated player (or spectator) going back to the lobby must not end the match for the others
	if (client.lobby.isInGame && client.eliminated) {
		client.sendAction({ action: "stopGame" });
		return;
	}
	client.lobby.broadcastAction({ action: "stopGame" });
	client.lobby.resetPlayers();
};

// Deprecated
const gameInfoAction = (client: Client) => {
	client.lobby?.sendGameInfo(client);
};

const lobbyOptionsAction = (
	options: Record<string, string>,
	client: Client,
) => {
	client.lobby?.setOptions(options);
};

const failRoundAction = (client: Client) => {
	const lobby = client.lobby;
	if (!lobby) return;
	if (lobby.options.death_on_round_loss) lobby.loseLifeFor(client, 'round');
	// 3P fork: survival-specific furthest-blind logic is not supported; any mode
	// uses last-one-standing.
	lobby.checkGameOver();
};

const setAnteAction = (
	{ ante }: ActionHandlerArgs<ActionSetAnte>,
	client: Client,
) => {
	client.ante = ante;
};

// TODO: Fix this
const serverVersion = "0.6.8.1";
/** Verifies the client version and allows connection if it matches the server's */
const versionAction = (
	{ version }: ActionHandlerArgs<ActionVersion>,
	client: Client,
) => {
	const versionMatch = version.match(/^(\d+\.\d+\.\d+)/);
	if (versionMatch) {
		const clientVersion = versionMatch[1];
		const serverVersionNumber = serverVersion.split("-")[0];

		const [clientMajor, clientMinor, clientPatch] = clientVersion
			.split(".")
			.map(Number);
		const [serverMajor, serverMinor, serverPatch] = serverVersionNumber
			.split(".")
			.map(Number);

		if (
			clientMajor < serverMajor ||
			(clientMajor === serverMajor && clientMinor < serverMinor) ||
			(clientMajor === serverMajor &&
				clientMinor === serverMinor &&
				clientPatch < serverPatch)
		) {
			client.sendAction({
				action: "error",
				message: `[WARN] Server expecting version ${serverVersion}`,
			});
		}
	}
};

const setLocationAction = (
	{ location }: ActionHandlerArgs<ActionSetLocation>,
	client: Client,
) => {
	client.setLocation(location);
};

const newRoundAction = (client: Client) => {
	client.resetBlocker();
};

const setFurthestBlindAction = (
	{ furthestBlind }: ActionHandlerArgs<ActionSetFurthestBlind>,
	client: Client,
) => {
	const [lobby, enemy] = getEnemy(client);
	client.furthestBlind = furthestBlind;
	if (!lobby || !enemy) return;

	//If enemy died and client.furthestBlind is bigger, client wins
	if (
		lobby.gameMode === "survival" &&
		lobby.players.length === 2 &&
		enemy.lives === 0 &&
		client.furthestBlind > enemy.furthestBlind
	) {
		client.sendAction({ action: "winGame" });
		enemy.sendAction({ action: "loseGame" });
	}
};

const skipAction = (
	{ skips }: ActionHandlerArgs<ActionSkip>,
	client: Client,
) => {
	client.setSkips(skips);
	const lobby = client.lobby;
	if (!lobby) return;
	const info = lobby.enemyInfoFor(client, true);
	for (const o of getOpponents(client)) o.sendAction(info); // teammates see skips too
};

const sendPhantomAction = (
	{ key }: ActionHandlerArgs<ActionSendPhantom>,
	client: Client,
) => {
	const lobby = client.lobby;
	if (!lobby) return;
	sendToOpponents(client, { playerId: client.id,
		action: "sendPhantom",
		key,
	});
};

const removePhantomAction = (
	{ key }: ActionHandlerArgs<ActionRemovePhantom>,
	client: Client,
) => {
	const lobby = client.lobby;
	if (!lobby) return;
	sendToOpponents(client, { playerId: client.id,
		action: "removePhantom",
		key,
	});
};

const asteroidAction = (client: Client) => {
	const lobby = client.lobby;
	if (!lobby) return;
	sendToOpponents(client, { playerId: client.id,
		action: "asteroid",
	});
};

const letsGoGamblingNemesisAction = (client: Client) => {
	const lobby = client.lobby;
	if (!lobby) return;
	sendToOpponents(client, { playerId: client.id,
		action: "letsGoGamblingNemesis",
	});
};

const eatPizzaAction = (
	{ whole }: ActionHandlerArgs<ActionEatPizza>,
	client: Client,
) => {
	const lobby = client.lobby;
	if (!lobby) return;
	sendToOpponents(client, { playerId: client.id,
		action: "eatPizza",
		whole,
	});
};

const soldJokerAction = (client: Client) => {
	const lobby = client.lobby;
	if (!lobby) return;
	sendToOpponents(client, { playerId: client.id,
		action: "soldJoker",
	});
};

const spentLastShopAction = (
	{ amount }: ActionHandlerArgs<ActionSpentLastShop>,
	client: Client,
) => {
	const lobby = client.lobby;
	if (!lobby) return;
	sendToOpponents(client, { playerId: client.id,
		action: "spentLastShop",
		amount,
	});
};

const magnetAction = (client: Client) => {
	const lobby = client.lobby;
	if (!lobby) return;
	sendToOpponents(client, { playerId: client.id,
		action: "magnet",
	});
};

const magnetResponseAction = (
	{ key }: ActionHandlerArgs<ActionMagnetResponse>,
	client: Client,
) => {
	const lobby = client.lobby;
	if (!lobby) return;
	sendToOpponents(client, { playerId: client.id,
		action: "magnetResponse",
		key,
	});
};

/** 3P: deliver end-game request/response only to one player (targetId) when given, else to all opponents. */
const sendToTarget = (client: Client, targetId: unknown, action: any) => {
	if (typeof targetId === "string" && targetId) {
		const t = getOpponents(client).find((o) => o.id === targetId);
		if (t) { t.sendAction(action); return; }
	}
	sendToOpponents(client, action);
};

const getEndGameJokersAction = (client: Client, targetId?: unknown) => {
	const lobby = client.lobby;
	if (!lobby) return;
	sendToTarget(client, targetId, { playerId: client.id,
		action: "getEndGameJokers",
	});
};

const receiveEndGameJokersAction = (
	{ keys, targetId }: ActionHandlerArgs<ActionReceiveEndGameJokersRequest> & { targetId?: string },
	client: Client,
) => {
	const lobby = client.lobby;
	if (!lobby) return;
	sendToTarget(client, targetId, { playerId: client.id,
		action: "receiveEndGameJokers",
		keys,
	});
};

const getNemesisDeckAction = (client: Client, targetId?: unknown) => {
	const lobby = client.lobby;
	if (!lobby) return;
	sendToTarget(client, targetId, { playerId: client.id,
		action: "getNemesisDeck",
	});
};

const receiveNemesisDeckAction = (
	{ cards, targetId }: ActionHandlerArgs<ActionReceiveNemesisDeckRequest> & { targetId?: string },
	client: Client,
) => {
	const lobby = client.lobby;
	if (!lobby) return;
	sendToTarget(client, targetId, { playerId: client.id,
		action: "receiveNemesisDeck",
		cards,
	});
};

const requestNemesisStatsActionHandler = (client: Client, targetId?: unknown) => {
	const lobby = client.lobby;
	if (!lobby) return;
	sendToTarget(client, targetId, { playerId: client.id,
		action: "endGameStatsRequested",
	});
};

const receiveNemesisStatsActionHandler = (
	stats: ActionHandlerArgs<ActionReceiveNemesisStatsRequest>,
	client: Client,
) => {
	const lobby = client.lobby;
	if (!lobby) return;
	const { targetId, ...rest } = stats as any;
	sendToTarget(client, targetId, { ...rest, playerId: client.id,
		action: "nemesisEndGameStats",
	});
};

const startAnteTimerAction = (
	{ time, isPvP }: ActionHandlerArgs<ActionStartAnteTimer>,
	client: Client,
) => {
	const lobby = client.lobby;
	if (!lobby) return;
	sendToOpponents(client, { playerId: client.id,
		action: "startAnteTimer",
		time,
		...(isPvP ? { isPvP: true } : {}),
	});
};

const pauseAnteTimerAction = (
	{ time }: ActionHandlerArgs<ActionPauseAnteTimer>,
	client: Client,
) => {
	const lobby = client.lobby;
	if (!lobby) return;
	sendToOpponents(client, { playerId: client.id,
		action: "pauseAnteTimer",
		time,
	});
};

const failTimerAction = (client: Client) => {
	const lobby = client.lobby;
	if (lobby) lobby.loseLifeFor(client, 'timer'); else client.loseLife('timer');
	if (!lobby) return;
	lobby.checkGameOver();
};

const syncClientAction = (
	{ isCached }: ActionHandlerArgs<ActionSyncClient>,
	client: Client,
) => {
	client.isCached = isCached;
};

// TCG Action Handlers
const tcgServerVersionAction = (
	{ version }: ActionHandlerArgs<ActionTcgServerVersion>,
	client: Client,
) => {
	// Only send tcg_compatible if the client's version is compatible (>= server version)
	if (version >= TCG_SERVER_VERSION) {
		client.sendAction({ action: "tcg_compatible" });
	}
};

const startTcgBettingAction = (client: Client) => {
	const lobby = client.lobby;

	// Only allow the host to start the TCG game
	if (!lobby || lobby.host?.id !== client.id) {
		return;
	}

	// Clear any existing bets
	lobby.tcgBets.clear();

	// Broadcast startGame with seed to both players
	lobby.broadcastAction({
		action: "startGame",
		deck: "c_multiplayer_1",
		seed: generateSeed(),
	});
};

const tcgBetAction = (
	{ bet }: ActionHandlerArgs<ActionTcgBet>,
	client: Client,
) => {
	const [lobby, enemy] = getEnemy(client);
	if (!lobby || !enemy) return;

	// Store this client's bet
	lobby.tcgBets.set(client.id, bet);

	// Check if both players have bet
	if (!lobby.host || !lobby.guest) return;
	if (!lobby.tcgBets.has(lobby.host.id) || !lobby.tcgBets.has(lobby.guest.id)) {
		return;
	}

	// Both players have bet, determine winner
	const hostBet = lobby.tcgBets.get(lobby.host.id) ?? 0;
	const guestBet = lobby.tcgBets.get(lobby.guest.id) ?? 0;

	let winner: Client;
	let loser: Client;

	if (hostBet > guestBet) {
		winner = lobby.host;
		loser = lobby.guest;
	} else if (guestBet > hostBet) {
		winner = lobby.guest;
		loser = lobby.host;
	} else {
		// Equal bets - flip a coin
		if (Math.random() < 0.5) {
			winner = lobby.host;
			loser = lobby.guest;
		} else {
			winner = lobby.guest;
			loser = lobby.host;
		}
	}

	const winnerBet = lobby.tcgBets.get(winner.id) ?? 0;

	// Winner receives their bet as damage and starts first
	winner.sendAction({
		action: "tcgStartGame",
		damage: winnerBet,
		starting: true,
	});

	// Loser receives 0 damage and doesn't start
	loser.sendAction({
		action: "tcgStartGame",
		damage: 0,
		starting: false,
	});

	// Clear bets for next round
	lobby.tcgBets.clear();
};

const tcgPlayerStatusAction = (
	args: ActionHandlerArgs<ActionTcgPlayerStatusRequest>,
	client: Client,
) => {
	const [lobby, enemy] = getEnemy(client);
	if (!lobby || !enemy) return;

	// Echo the action to the other player
	enemy.sendAction({
		action: "tcgPlayerStatus",
		...args,
	});
};

const tcgEndTurnAction = (
	args: ActionHandlerArgs<ActionTcgEndTurn>,
	client: Client,
) => {
	const [lobby, enemy] = getEnemy(client);
	if (!lobby || !enemy) return;

	// Send tcgStartTurn to the other player with the same parameters
	enemy.sendAction({
		action: "tcgStartTurn",
		...args,
	});
};

const moddedAction = (
	args: ActionHandlerArgs<ActionModdedRequest>,
	client: Client,
) => {
	const [lobby, enemy] = getEnemy(client);
	if (!lobby || !enemy) return;

	const target = args.target as string | undefined;
	const { target: _, ...rest } = args;
	const from = lobby.host?.id === client.id ? "host" : "guest";
	const message = { action: "moddedAction" as const, from, ...rest } as ActionModded;
	const relayTarget = target ?? "nemesis";

	if (relayTarget === "all") {
		lobby.broadcastAction(message);
	} else {
		sendToOpponents(client, message);
	}
};

const handyMPExtensionEnable = (
	args: ActionHandlerArgs<ActionHandyMPExtensionEnable>,
	client: Client,
) => {
	if (!client.lobby) return

	client.lobby.handyAllowMPExtension.set(client.id, true)
	client.lobby.broadcastLobbyInfo()
}

const handyMPExtensionDisable = (
	args: ActionHandlerArgs<ActionHandyMPExtensionDisable>,
	client: Client,
) => {
	if (!client.lobby) return

	client.lobby.handyAllowMPExtension.set(client.id, false)
	client.lobby.broadcastLobbyInfo()
}

/**
 * Persist a player's end-of-game replay-log fingerprints. The relay just stores
 * them (keyed by the server seed + lobby/player context); cross-referencing a
 * presented log against these happens elsewhere. Best-effort and side-effect
 * only — it never relays anything to the other client.
 */
const submitLogHashesAction = (
	{ carbon, human, seed, log, gameId }: ActionHandlerArgs<ActionSubmitLogHashes>,
	client: Client,
) => {
	const lobby = client.lobby;
	const complete = recordLogHashes({
		lobbyCode: lobby?.code ?? null,
		serverSeed: lobby?.seed ?? null,
		claimedSeed: seed ?? null,
		gameMode: lobby?.gameMode ?? null,
		username: client.username ?? null,
		modHash: client.modHash ?? null,
		isHost: lobby?.host?.id === client.id,
		carbonHash: carbon,
		humanHash: human,
		carbonLog: log ?? null,
	});
	// The complete package supersedes the live stream — drop it. Only when the
	// full carbon block was actually stored, so an oversized/blob-less submit
	// leaves the streamed partial as the fallback record.
	if (complete && gameId) deleteLiveLog(gameId);
};

/**
 * Append a batch of streamed carbon lines for an in-progress game. Best-effort
 * and side-effect only (never relayed to the other client); rate/size limiting
 * lives in the store so abuse is dropped rather than crashing the relay.
 */
const streamLogLinesAction = (
	{ gameId, lines }: ActionHandlerArgs<ActionStreamLogLines>,
	client: Client,
) => {
	recordLiveLogLines({
		clientId: client.id,
		gameId,
		lobbyCode: client.lobby?.code ?? null,
		username: client.username ?? null,
		lines,
	});
};

const dataSyncAction = (
    { timer }: ActionHandlerArgs<ActionDataSyncRequest>,
    client: Client,
 ) => {
	const lobby = client.lobby;
    if (!lobby) return;

    sendToOpponents(client, { playerId: client.id,
        action: "dataSync",
        timer: Number.isNaN(timer) ? undefined : Number(timer)
    })
}

export const actionHandlers = {
	username: usernameAction,
	resumeRestarted: resumeRestartedAction,
	createLobby: createLobbyAction,
	joinLobby: joinLobbyAction,
	rejoinLobby: rejoinLobbyAction,
	lobbyInfo: lobbyInfoAction,
	leaveLobby: leaveLobbyAction,
	readyLobby: readyLobbyAction,
	unreadyLobby: unreadyLobbyAction,
	keepAlive: keepAliveAction,
	startGame: startGameAction,
	readyBlind: readyBlindAction,
	unreadyBlind: unreadyBlindAction,
	playHand: playHandAction,
	stopGame: stopGameAction,
	gameInfo: gameInfoAction,
	lobbyOptions: lobbyOptionsAction,
	failRound: failRoundAction,
	setAnte: setAnteAction,
	version: versionAction,
	setLocation: setLocationAction,
	newRound: newRoundAction,
	setFurthestBlind: setFurthestBlindAction,
	skip: skipAction,
	sendPhantom: sendPhantomAction,
	removePhantom: removePhantomAction,
	asteroid: asteroidAction,
	letsGoGamblingNemesis: letsGoGamblingNemesisAction,
	eatPizza: eatPizzaAction,
	soldJoker: soldJokerAction,
	spentLastShop: spentLastShopAction,
	magnet: magnetAction,
	magnetResponse: magnetResponseAction,
	getEndGameJokers: getEndGameJokersAction,
	receiveEndGameJokers: receiveEndGameJokersAction,
	getNemesisDeck: getNemesisDeckAction,
	receiveNemesisDeck: receiveNemesisDeckAction,
	endGameStatsRequested: requestNemesisStatsActionHandler,
	nemesisEndGameStats: receiveNemesisStatsActionHandler,
	startAnteTimer: startAnteTimerAction,
	pauseAnteTimer: pauseAnteTimerAction,
	failTimer: failTimerAction,
	syncClient: syncClientAction,
	submitLogHashes: submitLogHashesAction,
	streamLogLines: streamLogLinesAction,
	tcgServerVersion: tcgServerVersionAction,
	startTcgBetting: startTcgBettingAction,
	tcgBet: tcgBetAction,
	tcgPlayerStatus: tcgPlayerStatusAction,
	tcgEndTurn: tcgEndTurnAction,
	moddedAction: moddedAction,
	handyMPExtensionEnable: handyMPExtensionEnable,
	handyMPExtensionDisable: handyMPExtensionDisable,
    failPvPTimer: failPvPTimerAction,
    dataSync: dataSyncAction,
} satisfies Partial<ActionHandlers>;

/** Server-internal handler for connection drops (not a client action) */
export { disconnectFromLobbyAction };
