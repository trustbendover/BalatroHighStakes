Balatro High Stakes - DEV local test build (NOT a release)

What it is
  Several Balatro instances on one PC play a real High Stakes match against each other. The normal
  host code (p2p_server.lua) and message path are used; only the Steam transport is swapped for small
  files in a shared folder. Bots (autoplay) can play the guests, or all players.

Safety
  - Each instance has its own test profile and Mods folder under
    %USERPROFILE%\GrokBot\Projects\BalatroMP3P\DevLocal\profiles\devN
    (APPDATA override + Lovely --mod-dir). Your real %APPDATA%\Balatro is not touched.
  - The dev code only runs with mod\dev\DEV_BUILD present AND HS_DEV_LOCAL=1 (set by the launcher).
    Release zips never contain mod\dev\ (the build script refuses).
  - The launcher refuses to start while Balatro is running and only stops the instances it started.

Use (PowerShell)
  .\dev_local_match.ps1 -DevZip .\BalatroHighStakes-DEV-LOCALTEST-0.6.8.zip -Players 3 -Scenario full_match
  .\dev_local_match.ps1 -Stop

  -Scenario    full_match | host_leave | guest_rejoin | elimination | presets | ready_gating
  -Mode        attrition | deathmatch | duel | showdown | survival | koth | teams
  -HostManual  you play dev1 yourself, the others are bots
  -ShotEvery   extra screenshot every N seconds

Screenshots
  F9 in any instance, plus automatic ones at scenario points, in DevLocal\captures\<time>-<scenario>\.

Logs
  DevLocal\profiles\devN\AppData\Balatro\Mods\lovely\log\  (look for HS-DEV and "Lobby presets:" lines)
