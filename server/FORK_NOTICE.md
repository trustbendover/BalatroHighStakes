# Balatro High Stakes server (fork, formerly "Balatro Multiplayer 3P")

This is a modified version of [Balatro Multiplayer](https://github.com/Balatro-Multiplayer/BalatroMultiplayer)
by Virtualized and contributors, licensed under GPL-3.0 (see LICENSE.md, unchanged).
Modified 2026-10 to support 3-player Attrition lobbies. It requires the matching
3P server fork (based on https://github.com/Balatro-Multiplayer/BalatroMultiplayerAPI-Server, GPL-3.0).

Server changes: src/Lobby.ts (player list, max 3, N-player PvP resolution), src/Client.ts, src/actionHandlers.ts, src/actions.ts, test/threePlayer.test.mjs.

0.6.7: 2-8 players, 1v1 Duel and Teams modes, scaled free-for-all life loss and King of the Hill -
src/Lobby.ts, src/actionHandlers.ts, src/actions.ts, src/Client.ts, src/GameMode.ts, src/koth.ts,
src/teams.ts and src/pvpRules.ts (new), test/multiPlayer.test.mjs (new).
0.6.7: Deathmatch mode - src/Lobby.ts, src/actionHandlers.ts, src/actions.ts, src/GameMode.ts,
test/deathmatch.test.mjs (new), test/lua_harness.lua and test/luaBridge.mjs (tick).
0.6.8 (in development): server version 0.6.8 only. Balatro High Stakes is Steam P2P only from 0.6.8: this server is no longer
hosted or shipped; it stays as the reference implementation and test harness (Docker/compose/standalone build files removed).

Fork (Balatro High Stakes) by Trust Ben Dover. Unofficial; not affiliated with LocalThunk, Playstack, or the Balatro Multiplayer team.
