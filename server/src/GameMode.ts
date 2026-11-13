import type { GameMode } from "./actions.js";

type GameModeData = {
	startingLives: number;

	getBlindFromAnte: (
		ante: number,
		options: any,
	) => {
		small?: string;
		big?: string;
		boss?: string;
	};

	// TODO: Validate lobby options when they differ per gamemode
};

const GameModes: {
	[key in GameMode]: GameModeData;
} = {
	attrition: {
		startingLives: 4,
		getBlindFromAnte: (ante, options) => {
			return { boss: "bl_pvp" };
		},
	},
	showdown: {
		startingLives: 2,
		getBlindFromAnte: (ante, options) => {
			const starting_antes = options?.showdown_starting_antes ? parseInt(options.showdown_starting_antes) : 3
      if (ante <= starting_antes) return { }
      else return { small: 'bl_pvp', big: 'bl_pvp', boss: 'bl_pvp' }
		},
	},
	koth: {
		// King of the Hill / Bounty (3P): attrition blinds, crown + bounty rules in koth.ts
		startingLives: 3,
		getBlindFromAnte: (ante, options) => {
			return { boss: "bl_pvp" };
		},
	},
	duel: {
		// 1v1 Duel: exactly 2 players, classic Attrition
		startingLives: 4,
		getBlindFromAnte: (ante, options) => {
			return { boss: "bl_pvp" };
		},
	},
	deathmatch: {
		// Deathmatch (2-8 players): every PvP blind is all living players at once, no late join,
		// a disconnected player is eliminated after the grace period, last one standing wins
		startingLives: 4,
		getBlindFromAnte: (ante, options) => {
			return { boss: "bl_pvp" };
		},
	},
	teams: {
		// Teams (4-8 players: 2v2, 3v3, 4v4, 2v2v2, 2v2v2v2): attrition blinds, shared team lives (teams.ts)
		startingLives: 4,
		getBlindFromAnte: (ante, options) => {
			return { boss: "bl_pvp" };
		},
	},
	survival: {
		startingLives: 1,
		getBlindFromAnte: (ante, options) => {
			return { };
		},
	},
	gambel_time: {
		startingLives: 3,
		getBlindFromAnte: () => {
			return { boss: "bl_pvp" };
		},
	},
};

export default GameModes;
