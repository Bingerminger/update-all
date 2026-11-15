# Changelog

Versionierung: **MAJOR** bei neuem Bedienkonzept (3 = tmux-TUI), **MINOR** bei neuen
Abschnitten oder Schaltern, **PATCH** bei Fehlerbehebungen. Die Nummer steht im Banner, im
Status-Pane, in `history.tsv` und hinter `--version`.

## 3.4.1 — 2026-11-15

- Eigenes Repository; persönliche Standards entkoppelt:
  - `tmux_session` hat keinen Standard mehr (eigene Session `update-all`, wenn nichts eingetragen ist).
  - Agent-Worktrees werden nur in Entwicklungsordnern gesucht (`worktree_roots`, Standard
    `~/Code,~/Developer,~/Projects,~/src`) — nie quer durchs Home, wo ein Blick in `~/Documents`
    eine Datenschutz-Abfrage auslösen kann.
  - Ollama-Sonderbehandlung nur mit `ollama_agent=<Label>` (eigener LaunchAgent).
- Microsoft AutoUpdate wird nur noch stillgelegt, wenn **alle** Office-Apps über brew kommen —
  sonst bräuchten manuell installierte Apps es für ihre Updates.
- `UPDATE_ALL_CONFDIR` für Tests: eigene prefs, eigener Lock; die TUI-Suiten hängen nicht mehr an
  der Konfiguration des Rechners, auf dem sie laufen.
- `prefs.example` mit allen Einstellungen.

## 3.4.0 — 2026-11-15

- **Beschädigte App-Pakete** erkennen (keine `Info.plist` oder kein Programm): Warnung plus
  Aktion `brew reinstall --cask <token>`. brew führt so eine App weiter als installiert und aktuell.
- **npm-Cache ab 3 GB leeren** (nur `_cacache`; per npx gestartete MCP-Server bleiben).
- **Speicherbericht**: Docker (nur bei laufendem Daemon) und alte Agent-Worktrees — nur messen und
  melden, nie löschen.
- Sparkle-Prüfung auch in Unterordnern von `/Applications` und in `~/Applications`.
- **`--resume`**: nach einem Abbruch nur nachholen, was nicht fertig wurde.
- **Netz-Wiederholung**: ein zweiter Versuch nach 15 s, wenn ein Befehl an einem Netzfehler scheitert.

## 3.3.8 — 2026-11-15

- **Nachkontrolle** am Ende (`brew outdated`, `mas outdated`) statt eines zweiten Laufs „zur Sicherheit“.
- Änderungsjournal im Fazit gruppiert (Zahlen je Quelle, wenige Einzelzeilen).
- **Restzeit** („noch ca. 4 min“) aus den Abschnittsdauern des letzten Laufs.
- Ein MacUpdater-Scan älter als 7 Tage gilt als veraltet statt als „alles aktuell“.

## 3.3.7 — 2026-11-15

- Bekannte Homebrew-Meldungen (hdiutil-Deprecation, Sammelzeile „Deprecated or disabled package“)
  erzeugen keine Aktion mehr.
- `adopt_ignore` mit Mustern gegen Cask-Namen oder Bundle-ID (ganze App-Familien ausnehmen).
- Der Mac bleibt während des Laufs wach (`caffeinate -i -w`, endet mit dem Lauf).
- Test: Verbindung bricht mitten im Lauf ab → der Lauf läuft bis zum Ende weiter.

## 3.3.6 — 2026-10-31

- Time-Machine-Alter aus der Einstellungsdatei statt `tmutil latestbackup` — das hängt bei einem
  schlafenden NAS-Ziel minutenlang.

## 3.3.5 — 2026-10-29

- Major-Sperre als **Sperrliste** (`major_block`) für Bezahl-Upgrades statt für jeden Sprung.
- macOS-Updates mit Neustart werden nur gemeldet (mit fertigem Befehl), nicht installiert.
- **Bekannte Hinweise**: eine unveränderte Info aus dem letzten Lauf zählt nicht mehr als offen.
- **mas-Nachprüfung**: was nach `mas upgrade` noch veraltet ist, wird gemeldet statt als erledigt gezählt.

## 3.3.4 — 2026-10-06

- Log-Rotation löscht wieder zuverlässig (zsh-Array-Ausschnitt als ein Wort).

## 3.3.3 — 2026-10-02

- Remote-Layout: Das Fenster folgt dem anhängenden Terminal, nicht der Größe einer bestehenden Session.
- Ein fertiger, stehengebliebener Lauf wird abgeräumt statt angesprungen.
- Lock belegt → kein Fenster, klare Meldung, Exit 2.
- Abschluss-Tafel bricht an der Pane-Breite um.

## 3.3.0 – 3.3.2 — 2026-10-02

- **Remote ohne Dialog**: Quarantäne gezielt entfernen, laufende Apps selbst beenden (keine
  Automation-Abfrage), Lauf-Lock, Exit-Code 2 für Abbrüche, Hänger-Alarm.
- **Layout nach Fenstergröße** (iPhone, iPad, großer Schirm) und Farben als Zustand.
- Parallels: Funktionsprüfung statt Dateiprüfung.

## 3.2.0 – 3.2.5 — 2026-09-18 bis 2026-10-02

- Self-Updater-Casks entscheidet update-all selbst (Homebrew 7 hebt sie sonst ungefragt).
- Office über brew, Microsoft AutoUpdate still. `-y` heißt ja.
- npm aktualisiert nur Veraltetes (kein Neuschreiben des globalen Baums).
- Headless-Tests für die tmux-TUI (`update-all-tuitest.zsh`).
- Timeouts für alle Abfragen; ein Timeout gilt nie als „nichts zu tun“.

## 3.1 — 2026-09-17

- **tmux-TUI** mit Status, Live-Log und Aktionen; sudo-Strategie gegen Homebrews Ticket-Reset;
  Verlauf und Rückblick.

## 2.x — 2026-07

- Ausgabe-Layer: Schrittzähler, eingerückte Tool-Ausgabe mit Dauer je Befehl, Fazit-Tabelle,
  Farben nur bei TTY, Log ohne Farbcodes.
