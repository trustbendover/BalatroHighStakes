Balatro High Stakes  v0.6.8~3P  (unofficial fork of Balatro Multiplayer, by Trust Ben Dover)
=========================================================================================
Balatro Multiplayer for 2 to 8 players: 1v1 Duel, Attrition, Showdown, King of the Hill and
Teams (2v2, 3v3, 4v4, 2v2v2, 2v2v2v2). Everyone in the match needs this mod.
(Formerly "Balatro Multiplayer 3P"; the install folder is still BalatroMultiplayer3P.)
Windows + Steam version of Balatro.

UPDATING FROM AN OLDER VERSION: everyone (host AND friends) must install 0.6.8. Just run Install.bat again;
it replaces the old version and keeps your settings.

INSTALL
1. Close Balatro. Unzip this whole zip (do not run it from inside the zip).
2. Double-click Install.bat.
   - Windows SmartScreen ("Windows protected your PC"): click "More info" -> "Run anyway".
     It's a plain batch/PowerShell script; you can read install.ps1 first.
3. The installer finds Balatro, installs Lovely (mod loader), Steamodded 1.0.0~BETA-1620a
   and the High Stakes mod, and backs up anything it replaces (see %APPDATA%\Balatro\MP3P-backup-*).
4. Choose how to play:
   1 = via Steam (DEFAULT, recommended): no server, no port forwarding, no Tailscale.
   2 = via a server address (playit.gg / Tailscale / public IP + port, default 8788).
5. Start Balatro normally from Steam. Version 0.6.8~3P shows in the main menu.

UPDATES (from 0.6.6 on)
- When a new version is released, the main menu shows an "Update available: vX" button (top left).
  Click it, then close Balatro: the updater downloads the new Installer zip from GitHub, checks its
  SHA256, installs it (your settings are kept) and tells you to start Balatro again.
- Or run Update.bat (in this folder, or in %APPDATA%\Balatro\Mods\BalatroMultiplayer3P\updater).
- Releases: https://github.com/trustbendover/BalatroHighStakes/releases
- Turn the update check off: add the line update_check=false to the .env file.

SUPPORT: like the mod? https://ko-fi.com/trustbendover

PLAYING IN STEAM MODE (option 1)
- Anyone can host: Play -> Create Lobby. The host's Balatro runs the game server,
  so the host must keep Balatro open until the match ends.
- Join by code: Play -> Join Lobby -> type the code. Wait ~10 seconds after the host
  created the lobby: Steam needs a moment before the lobby can be found.
- EXPERIMENTAL: "Invite Steam friend" button in the lobby (Steam overlay), and
  Steam friends list -> right-click the host -> "Join game". Accepting joins without a code.
  If it doesn't work: Play -> "Join Steam invite again", copy the code and use
  "Join From Clipboard" (also accepts a Steam lobby id / steam://joinlobby link), or type the code.
- Rejoin: lost connection / crashed? Start Balatro and join again with the same code and the
  same name: you get your seat, lives and ante back (seat is held until the match ends).
- Late join: another player (up to 8) can join a running match (not in 1v1 Duel or Teams);
  they start at the lowest ante/lives and sit out a blind that's already in progress.

SERVER MODE (option 2)
The host runs the High Stakes server (BalatroMultiplayer3P server, port 8788) and shares it via
playit.gg, Tailscale or port forwarding. Switch modes anytime by re-running Install.bat, or by
editing %APPDATA%\Balatro\Mods\BalatroMultiplayer3P\.env (mode=steam line = Steam mode).

TROUBLESHOOTING
- Game doesn't start / no "Mods" button: an old Lovely "version.dll" in the Balatro folder
  conflicts with Lovely 0.10 (winmm.dll). The installer removes it (backup kept); check the
  Balatro folder for version.dll if you installed mods manually.
- Crash in overrides.lua: wrong Steamodded version. This mod needs Steamodded
  1.0.0~BETA-1620a exactly; re-run Install.bat (it installs that version).
- "No Steam lobby found": wait 10 s and retry; check the code; host must still be in the lobby.
- Logs: %APPDATA%\Balatro\Mods\lovely\log\ (newest file). Look for "Steam P2P" lines.
- Uninstall: Uninstall.bat restores what the installer backed up.

CREDITS / LICENSE: see CREDITS.txt, LICENSE.txt (GPL-3.0), payload\LOVELY_LICENSE.txt (MIT).
