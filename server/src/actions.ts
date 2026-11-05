// Server to Client
export type ActionConnected = { action: 'connected' }
export type ActionError = { action: 'error'; message: string }
export type ActionJoinedLobby = { action: 'joinedLobby'; code: string; type: GameMode; reconnectToken?: string }
export type ActionRejoinedLobby = { action: 'rejoinedLobby'; code: string; type: GameMode; reconnectToken: string }
export type ActionEnemyDisconnected = { action: 'enemyDisconnected'; timeout: number; playerId?: string; held?: boolean }
export type ActionEnemyReconnected = { action: 'enemyReconnected'; playerId?: string }
export type LobbyPlayer = { id: string; username: string; hash: string; cached: boolean; ready: boolean; isHost: boolean; lives: number; eliminated: boolean; team?: 'A' | 'B' | 'C' | 'D' }
export type ActionResumeGame = { action: 'resumeGame'; seed?: string; ante: number; lives: number; lateJoin: boolean; eliminated: boolean; blindActive: boolean; inCurrentBlind: boolean }
export type ActionRejoinFailed = { action: 'rejoinFailed'; message: string }
export type ActionPlayerJoined = { action: 'playerJoined'; playerId: string; username: string }
export type ActionResumeRestarted = { action: 'resumeRestarted' }
export type ActionPlayerLeft = { action: 'playerLeft'; playerId: string; username: string }
export type ActionPlayerEliminated = { action: 'playerEliminated'; playerId: string; username: string; reason?: 'left' | 'disconnected' | 'absent' }
export type ActionLobbyInfo = {
	action: 'lobbyInfo'
	host: string
	hostHash: string
	hostCached: boolean
	guest?: string
	guestHash?: string
	guestCached?: boolean
	guestReady?: boolean
	isHost: boolean
	players?: LobbyPlayer[]
	you?: string
	maxPlayers?: number
	away?: { id: string; username: string; lives: number }[]
	inGame?: boolean
}
export type ActionStopGame = { action: 'stopGame' }
export type ActionStartGame = {
	action: 'startGame'
	deck: string
	stake?: number
	seed?: string
	playerCount?: number
}
export type ActionStartBlind = { action: 'startBlind', firstPlayer?: "host" | "guest", firstPlayerId?: string }
export type ActionWinGame = { action: 'winGame'; reason?: string }
export type ActionLoseGame = { action: 'loseGame'; reason?: string }
export type ActionTeamsUpdate = {
	action: 'teamsUpdate'
	you: string
	team: 'A' | 'B' | 'C' | 'D' | null
	teamSize: number
	teams: { [team: string]: { members: { id: string; username: string }[]; lives: number } }
	lastLoser?: 'A' | 'B' | 'C' | 'D' | 'none'
}
export type ActionDeathmatchUpdate = {
	action: 'deathmatchUpdate'
	you: string
	alive: { id: string; username: string; lives: number; away?: boolean }[]
	out: { id: string; place: number }[]
	running: boolean
	winnerId?: string
}
export type ActionKothUpdate = { action: 'kothUpdate'; you: string } & import('./koth.js').KothEvent
export type ActionGameInfo = {
	action: 'gameInfo'
	small?: string
	big?: string
	boss?: string
}
export type ActionPlayerInfo = { action: 'playerInfo'; lives: number }
export type ActionEnemyInfo = {
	action: 'enemyInfo'
	playerId?: string
	username?: string
	score: string | null
	noScore?: true
	handsLeft: number
	skips: number
	lives: number
	eliminated?: boolean
	pvpTimerOrder?: "guest" | "host"
	pvpOrder?: string[]
}
export type ActionEndPvP = { action: 'endPvP'; lost: boolean, pvpTimerLost?: boolean, loserIds?: string[], opponentsAway?: boolean, loserTeam?: string }
export type ActionLobbyOptions = { action: 'lobbyOptions', gamemode: string }
export type ActionRequestVersion = { action: 'version' }
export type ActionEnemyLocation = { action: 'enemyLocation'; location: string; playerId?: string }
export type ActionSendPhantom = { action: 'sendPhantom', key: string }
export type ActionRemovePhantom = { action: 'removePhantom', key: string }
export type ActionSpeedrun = { action: 'speedrun' }
export type ActionAsteroid = { action: 'asteroid' }
export type ActionLetsGoGamblingNemesis = { action: 'letsGoGamblingNemesis' }
export type ActionEatPizza = { action: 'eatPizza', whole: boolean }
export type ActionSoldJoker = { action: 'soldJoker' }
export type ActionSpentLastShop = { action: 'spentLastShop', amount: number }
export type ActionMagnet = { action: 'magnet' }
export type ActionMagnetResponse = { action: 'magnetResponse', key: string }
export type ActionGetEndGameJokersRequest = { action: 'getEndGameJokers' }
export type ActionReceiveEndGameJokersRequest = { action: 'receiveEndGameJokers', keys: string }
export type ActionGetNemesisDeckRequest = { action: 'getNemesisDeck' }
export type ActionReceiveNemesisDeckRequest = { action: 'receiveNemesisDeck', cards: string }
export type ActionGetNemesisStatsRequest = { action: 'endGameStatsRequested' }
export type ActionReceiveNemesisStatsRequest = { action: 'nemesisEndGameStats', reroll_count: string, reroll_cost_total:string, vouchers:string }
export type ActionStartAnteTimer = { action: 'startAnteTimer', time: number, isPvP?: boolean }
export type ActionPauseAnteTimer = { action: 'pauseAnteTimer', time: number }
export type ActionDataSyncResponse = { action: "dataSync", timer?: number }
// Handy Actions (Server to Client)
export type ActionHandyMPExtensionLobbyEnabled = { action: 'handyMPExtensionLobbyEnabled', enabled: boolean }
// TCG Actions (Server to Client)
export type ActionTcgCompatible = { action: 'tcg_compatible' }
export type ActionTcgStartGame = { action: 'tcgStartGame', damage: number, starting: boolean }
export type ActionTcgPlayerStatus = { action: 'tcgPlayerStatus', [key: string]: unknown }
export type ActionTcgStartTurn = { action: 'tcgStartTurn', [key: string]: unknown }
// Modded Actions
export type ActionModded = { action: 'moddedAction', modId: string, modAction: string, from: 'host' | 'guest', target?: 'nemesis' | 'all', [key: string]: unknown }
export type ActionServerToClient =
	| ActionKothUpdate
	| ActionTeamsUpdate
	| ActionDeathmatchUpdate
	| ActionResumeGame
	| ActionPlayerJoined
	| ActionRejoinFailed
	| ActionPlayerLeft
	| ActionPlayerEliminated
	| ActionConnected
	| ActionError
	| ActionJoinedLobby
	| ActionRejoinedLobby
	| ActionEnemyDisconnected
	| ActionEnemyReconnected
	| ActionLobbyInfo
	| ActionStopGame
	| ActionStartGame
	| ActionStartBlind
	| ActionWinGame
	| ActionLoseGame
	| ActionGameInfo
	| ActionPlayerInfo
	| ActionEnemyInfo
	| ActionEndPvP
	| ActionLobbyOptions
	| ActionRequestVersion
	| ActionUtility
	| ActionEnemyLocation
	| ActionSendPhantom
	| ActionRemovePhantom
	| ActionSpeedrun
	| ActionAsteroid
	| ActionLetsGoGamblingNemesis
	| ActionEatPizza
	| ActionSoldJoker
	| ActionSpentLastShop
	| ActionMagnet
	| ActionMagnetResponse
	| ActionGetEndGameJokersRequest
	| ActionReceiveEndGameJokersRequest
	| ActionGetNemesisDeckRequest
	| ActionReceiveNemesisDeckRequest
	| ActionGetNemesisStatsRequest
	| ActionReceiveNemesisStatsRequest
	| ActionStartAnteTimer
	| ActionPauseAnteTimer
	| ActionTcgCompatible
	| ActionTcgStartGame
	| ActionTcgPlayerStatus
	| ActionTcgStartTurn
	| ActionModded
    | ActionDataSyncResponse
    | ActionHandyMPExtensionLobbyEnabled
// Client to Server
export type ActionUsername = { action: 'username'; username: string; modHash: string }
export type ActionCreateLobby = { action: 'createLobby'; gameMode: GameMode }
export type ActionJoinLobby = { action: 'joinLobby'; code: string }
export type ActionLeaveLobby = { action: 'leaveLobby' }
export type ActionReadyLobby = { action: 'readyLobby' }
export type ActionUnreadyLobby = { action: 'unreadyLobby' }
export type ActionLobbyInfoRequest = { action: 'lobbyInfo' }
export type ActionStopGameRequest = { action: 'stopGame' }
export type ActionStartGameRequest = { action: 'startGame' }
export type ActionReadyBlind = { action: 'readyBlind' }
export type ActionUnreadyBlind = { action: 'unreadyBlind' }
export type ActionPlayHand = {
	action: 'playHand'
	score: string
	handsLeft: number
	hasSpeedrun: boolean
}
export type ActionGameInfoRequest = { action: 'gameInfo' }
export type ActionPlayerInfoRequest = { action: 'playerInfo' }
export type ActionEnemyInfoRequest = { action: 'enemyInfo' }
export type ActionFailRound = { action: 'failRound' }
export type ActionSetAnte = {
	action: 'setAnte'
	ante: number
}
export type ActionVersion = { action: 'version'; version: string }
export type ActionSetLocation = { action: 'setLocation'; location: string }
export type ActionNewRound = { action: 'newRound' }
export type ActionSetFurthestBlind = { action: 'setFurthestBlind', furthestBlind: number}
export type ActionSkip = { action: 'skip', skips: number }
export type ActionLetsGoGamblingNemesisRequest = { action: 'letsGoGamblingNemesis' }
export type ActionEatPizzaRequest = { action: 'eatPizza', whole: boolean }
export type ActionSoldJokerRequest = { action: 'soldJoker' }
export type ActionSpentLastShopRequest = { action: 'spentLastShop', amount: number }
export type ActionMagnetRequest = { action: 'magnet' }
export type ActionMagnetResponseRequest = { action: 'magnetResponse', key: string }
export type ActionGetEndGameJokersResponse = { action: 'getEndGameJokers' }
export type ActionReceiveEndGameJokersResponse = { action: 'receiveEndGameJokers', keys: string }
export type ActionGetNemesisDeckResponse = { action: 'getNemesisDeck' }
export type ActionReceiveNemesisDeckResponse = { action: 'receiveNemesisDeck', cards: string }
export type ActionGetNemesisStatsResponse = { action: 'endGameStatsRequested' }
export type ActionReceiveNemesisStatsResponse = { action: 'nemesisEndGameStats', reroll_count: string,reroll_cost_total:string, vouchers:string }
export type ActionStartAnteTimerRequest = { action: 'startAnteTimer', time: number, isPvP?: boolean }
export type ActionPauseAnteTimerRequest = { action: 'pauseAnteTimer', time: number }
export type ActionFailTimer = { action: 'failTimer' }
export type ActionFailPvPTimer = { action: 'failPvPTimer' }
export type ActionSyncClient = { action: 'syncClient', isCached: boolean }
export type ActionSubmitLogHashes = { action: 'submitLogHashes', carbon: string, human: string, seed?: string, log?: string, gameId?: string }
export type ActionStreamLogLines = { action: 'streamLogLines', gameId: string, lines: string[] }
// TCG Actions (Client to Server)
export type ActionTcgServerVersion = { action: 'tcgServerVersion', version: number }
export type ActionStartTcgBetting = { action: 'startTcgBetting' }
export type ActionTcgBet = { action: 'tcgBet', bet: number }
export type ActionTcgPlayerStatusRequest = { action: 'tcgPlayerStatus', [key: string]: unknown }
export type ActionTcgEndTurn = { action: 'tcgEndTurn', [key: string]: unknown }
export type ActionModdedRequest = { action: 'moddedAction', modId: string, modAction: string, target?: 'nemesis' | 'all', [key: string]: unknown }
// Handy Actions (Client to Server)
export type ActionRejoinLobby = { action: 'rejoinLobby'; code: string; reconnectToken: string }
export type ActionDataSyncRequest = { action: "dataSync", timer?: number }
export type ActionHandyMPExtensionEnable = { action: 'handyMPExtensionEnable', [key: string]: unknown }
export type ActionHandyMPExtensionDisable = { action: 'handyMPExtensionDisable', [key: string]: unknown }
export type ActionClientToServer =
	| ActionResumeRestarted
	| ActionUsername
	| ActionCreateLobby
	| ActionJoinLobby
	| ActionLeaveLobby
	| ActionReadyLobby
	| ActionUnreadyLobby
	| ActionLobbyInfoRequest
	| ActionStopGameRequest
	| ActionStartGameRequest
	| ActionReadyBlind
	| ActionPlayHand
	| ActionGameInfoRequest
	| ActionPlayerInfoRequest
	| ActionEnemyInfoRequest
	| ActionUnreadyBlind
	| ActionLobbyOptions
	| ActionFailRound
	| ActionSetAnte
	| ActionVersion
	| ActionSetLocation
	| ActionNewRound
	| ActionSetFurthestBlind
	| ActionSkip
	| ActionSendPhantom
	| ActionRemovePhantom
	| ActionAsteroid
	| ActionLetsGoGamblingNemesisRequest
	| ActionEatPizzaRequest
	| ActionSoldJokerRequest
	| ActionSpentLastShopRequest
	| ActionMagnetRequest
	| ActionMagnetResponseRequest
	| ActionGetEndGameJokersResponse
	| ActionReceiveEndGameJokersResponse
	| ActionGetNemesisDeckResponse
	| ActionReceiveNemesisDeckResponse
	| ActionGetNemesisStatsResponse
	| ActionReceiveNemesisStatsResponse
	| ActionStartAnteTimerRequest
	| ActionPauseAnteTimerRequest
	| ActionFailTimer
	| ActionFailPvPTimer
	| ActionSyncClient
	| ActionSubmitLogHashes
	| ActionStreamLogLines
	| ActionTcgServerVersion
	| ActionStartTcgBetting
	| ActionTcgBet
	| ActionTcgPlayerStatusRequest
	| ActionTcgEndTurn
	| ActionModdedRequest
	| ActionRejoinLobby
    | ActionDataSyncRequest
    | ActionHandyMPExtensionEnable
    | ActionHandyMPExtensionDisable
// Utility actions
export type ActionKeepAlive = { action: 'keepAlive' }
export type ActionKeepAliveAck = { action: 'keepAliveAck' }

export type ActionUtility = ActionKeepAlive | ActionKeepAliveAck

export type Action = ActionServerToClient | ActionClientToServer | ActionUtility

type HandledActions = ActionClientToServer | ActionUtility
export type ActionHandlers = {
	[K in HandledActions['action']]: keyof ActionHandlerArgs<
		Extract<HandledActions, { action: K }>
	> extends never
	? (
		// biome-ignore lint/suspicious/noExplicitAny: Function can receive any arguments
		...args: any[]
	) => void
	: (
		action: ActionHandlerArgs<Extract<HandledActions, { action: K }>>,
		// biome-ignore lint/suspicious/noExplicitAny: Function can receive any arguments
		...args: any[]
	) => void
}

export type ActionHandlerArgs<T extends HandledActions> = Omit<T, 'action'>

// Other types
export type GameMode = 'attrition' | 'showdown' | 'survival' | 'koth' | 'teams' | 'duel' | 'deathmatch'
