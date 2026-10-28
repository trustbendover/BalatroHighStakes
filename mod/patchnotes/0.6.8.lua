-- Patch notes for 0.6.8 (see patchnotes/README.md)
return {
	version = "0.6.8",
	date = "in development",
	en = {
		title = "The host can leave now",
		new = {
			"Host migration (Steam): if the host leaves, quits or loses connection, the next player becomes host and the match just keeps going. No one loses their run.",
			"You'll see a short message like \"Host left - Bob is now host\".",
			"A frozen host (game hangs but stays in Steam) is replaced in about 10-15 seconds instead of a minute.",
			"These patch notes! They pop up once after an update. Reopen them any time with the Patch notes button.",
		},
		changed = {
			"A host who drops out can come back as a normal player and keeps their seat and lives.",
			"If only YOUR connection is bad, you go back to the menu after 30 seconds (was 60) and can rejoin with the code.",
		},
		fixed = {
			"Players joining with the code still find the right host after a migration.",
		},
		known = {
			"Everyone needs 0.6.8 for host migration to work.",
			"With 2 players, a guest whose own internet drops becomes host for a moment; it sorts itself out when the connection is back.",
			"Host migration only works in Steam mode, not with the TS server.",
		},
	},
	nl = {
		title = "De host mag nu weggaan",
		new = {
			"Host-migratie (Steam): als de host weggaat, afsluit of zijn verbinding kwijt is, wordt de volgende speler host en gaat de match gewoon door. Niemand verliest zijn run.",
			"Je ziet een korte melding zoals \"Host weg - Bob is nu host\".",
			"Een bevroren host (spel hangt maar blijft in Steam) wordt in ongeveer 10-15 seconden vervangen in plaats van na een minuut.",
			"Deze patch notes! Ze verschijnen een keer na een update. Open ze opnieuw met de knop Patch notes.",
		},
		changed = {
			"Een host die wegvalt kan terugkomen als gewone speler en houdt zijn plek en levens.",
			"Is alleen JOUW verbinding slecht, dan ga je na 30 seconden (was 60) terug naar het menu en kun je terug met de code.",
		},
		fixed = {
			"Wie met de code joint, vindt na een migratie nog steeds de juiste host.",
		},
		known = {
			"Iedereen heeft 0.6.8 nodig voor host-migratie.",
			"Met 2 spelers wordt een gast van wie het internet wegvalt even host; dat lost zich op zodra de verbinding terug is.",
			"Host-migratie werkt alleen in Steam-modus, niet met de TS-server.",
		},
	},
}
