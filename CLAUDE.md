# CLAUDE.md

Leitfaden für Claude Code (und Menschen) bei der Arbeit an diesem Repository. Persönliche Notizen
zu einem konkreten Mac gehören in `CLAUDE.local.md` (per `.gitignore` ausgeschlossen).

## Überblick

`update-all.sh` ist **ein** zsh-Skript, das einen Mac aus dem Terminal aktuell hält — gebaut für
den Betrieb per SSH: tmux-TUI, keine GUI-Dialoge, der Lauf übersteht einen Verbindungsabbruch.
`update-all-tuitest.zsh` testet die TUI headless und erwartet `update-all.sh` im selben Ordner.
Kein Build, keine Abhängigkeiten außer tmux (TUI) und fzf (Aktionen-Pane); alles andere ist optional
und wird nur genutzt, wenn es installiert ist.

Ausgaben, Kommentare und Doku sind **deutsch** — beibehalten.

## Projektseite

`site/index.html` (+ `404.html`) ist die Projektseite auf https://bingerminger.github.io/update-all/.
`tools/build-site.sh [ziel]` setzt sie mit den Bildern aus `docs/` und `.github/` zusammen und
ersetzt `{{VERSION}}`; `--check` prüft nur, ob jedes eingebundene Bild existiert. Der Workflow
`pages.yml` baut beim Veröffentlichen eines GitHub-Releases aus dessen Tag (oder von Hand) —
die Seite zeigt, was veröffentlicht ist, nicht den Stand von `main`. Lokal ansehen: bauen und
`python3 -m http.server -d dist/site`. Keine externen Ressourcen (Schriften, CDNs, Tracking).

## Versionierung

`VERSION` im Kopf von `update-all.sh`: MAJOR = neues Bedienkonzept, MINOR = neue Abschnitte/Schalter,
PATCH = Fixes. **Bei jeder Änderung hochzählen** und `CHANGELOG.md` nachziehen — die Nummer landet in
Banner, Status-Pane und `history.tsv`.

## Prüfen (vor jedem Commit)

```sh
zsh -n update-all.sh && zsh -n update-all-tuitest.zsh
./update-all.sh --selftest              # Ausgabe-Layer, Parser, Helfer — ohne Systemänderung
./update-all.sh --check                 # was anstünde, nichts installieren, kein sudo
./update-all.sh --dry-run --plain       # alles simuliert
./update-all-tuitest.zsh all            # TUI headless, ≈ 4,5 min (quit|review|layout|remote)
```

Nach Änderungen an `tui_launch`, `tui_close`, den Panes oder der Abschluss-Reihenfolge immer die
TUI-Suiten laufen lassen. Neue Fälle dort ergänzen statt Wegwerf-Skripte zu schreiben.

## Architektur

- **Ein Skript, mehrere Rollen.** Je nach internem Flag (`--_runner`, `--_status`, `--_actions`,
  `--_pane-log`, `--_action-*`) ist der Prozess Runner oder TUI-Pane. Der Runner läuft im Log-Pane;
  die anderen Panes lesen nur Dateien in `$RUNDIR`: `state` (Key=Value), `steps`/`actions` (TSV),
  `actions.d/<id>.txt`, `heartbeat`, `layout`, `final`.
- **Abschnitte** registriert `build_registry()` dynamisch (`reg <id> <Name>`, nur was installiert
  ist). Neue Sektion = `sec_<id>()` + `reg`-Zeile. Die Reihenfolge ist Absicht (macOS → brew →
  tlmgr direkt nach `brew upgrade` → mas → office → … → apps → cleanup), siehe sudo.
- **Befehle** laufen über `run <cmd>` (meldet Fehler, bricht nicht ab, perl-`alarm`-Timeout, Default
  2 h; `run_t <s>` für Tools, die hängen). Ein Netzfehler (`NET_ERR_RE`) bekommt einen zweiten
  Versuch nach `RETRY_DELAY`, Timeouts und `run_in` (stdin verbraucht) nicht.
- **Abfragen** in `$(…)` über `capture_t <s> <cmd>` und **direkt dahinter `capture_ok $? "<was>"`** —
  sonst liest sich die leere Ausgabe nach einem Timeout wie „nichts zu tun“. Der rc muss als `$?`
  übergeben werden (Subshell); in `$(capture_t … | grep …)` ist `$?` der von grep — erst einfangen,
  dann filtern. Mitten in einem Abschnitt kein `return`, sondern ein Flag (`q_ok`).
- **Meldungen:** `ok/info/warn/skip`; `action <err|warn|info> <Quelle> <Titel> [Fix] [Detail]` für
  alles, was nach dem Lauf zu entscheiden ist; `ask <key> <Frage>` für Rückfragen (j/n einmalig,
  i/x gemerkt in prefs; `-y` heißt ja; ohne TTY, mit `--check` oder nach 60 s nein);
  `journal <zeile>` für das Änderungsjournal.
- **Aktionen-IDs** sind md5 aus Quelle|Titel. Deshalb gehören wechselnde Zahlen (Patch-Versionen,
  Größen) **nie in den Titel**, sonst ist jede Version eine neue Aktion und `^A` wirkungslos.
  Spalte 5 der TSV-Zeile wird per `^X` ausgeführt: `action()` entfernt Tabs/Zeilenumbrüche,
  Befehlszeilen aus Fremdtext werden mit `shq()` gequotet.
- **Konfiguration:** `$CONFDIR` (`~/.config/update-all`, für Tests `UPDATE_ALL_CONFDIR`): `prefs`,
  `acks`, `run.lock`, `Brewfile`. Logs: `$LOGDIR` (`~/Library/Logs/update-all`, für Tests
  `UPDATE_ALL_LOGDIR`): `runs/*.log` (max. 40), `history.tsv`, `last/`. Alle Einstellungen:
  `prefs.example`.
- **Exit-Codes:** 0 ok · 1 Schritt fehlgeschlagen · 2 abgebrochen (Netz, Akku, ^C, Lock belegt).

## Fachliche Leitplanken

- **sudo:** Homebrews `brew.sh` macht bei jedem Start `sudo --reset-timestamp` — ein `sudo -v` mit
  Keep-Alive ist nutzlos. Modi: `askpass` (Passwort einmal, `SUDO_ASKPASS`-Helper; Standard per SSH)
  und `touchid` (lokal, sudo fragt bei Bedarf). Zwischen `brew upgrade` und tlmgr darf **kein**
  weiterer brew-Aufruf stehen; `brew_post_upgrade` prüft deshalb den Caskroom direkt.
- **Homebrew 7 und Self-Updater-Casks (`auto_updates`):** brew hebt sie sonst von sich aus.
  `sec_brew` setzt `HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS=1` und entscheidet selbst
  (`outdated` / `lagging` / `bookkeeping` nur mit `-g`). Verglichen wird die **Bundle-Version der
  App**, nicht brews Caskroom-Eintrag. Ausschlussliste `cask_exclude`, Major-Sperrliste `major_block`.
- **Parallels** nie per brew heben (der Cask-Postflight entfernt den Launch-Daemon). Die Daemon-Plist
  kommt und geht mit der App — ihr Fehlen ist kein Defekt; geprüft wird die Funktion (`prlctl`).
- **Remote ohne Dialog:** `cask_unquarantine` (nur, was Gatekeeper wirklich ablehnt; notarisierte Apps
  bleiben unberührt), `cask_quit_running` (SIGTERM statt AppleScript-`quit`, das die
  Automation-Abfrage auslöst), `cask_restart_quit`. Homebrew 7 kennt `--no-quarantine` nicht mehr.
- **macOS-Updates** mit Neustart werden nur gemeldet, nie installiert.
- **Time Machine:** Backup-Alter aus `/Library/Preferences/com.apple.TimeMachine.plist`, **nie**
  `tmutil latestbackup` (hängt bei schlafenden Netzwerkzielen).
- **Office:** Microsoft AutoUpdate wird nur stillgelegt, wenn alle Office-Apps über brew kommen
  (`mau_redundant`).
- **npm:** nie `npm update -g` (schreibt den ganzen globalen Baum neu); nur Veraltetes gezielt.
  Eine globale npm-Härtung (`ignore-scripts`/`allow-scripts`) nie umschalten — Ausnahmen prozesslokal.
- **Nichts löschen, was Arbeit kosten kann:** Speicherbericht (Docker, Agent-Worktrees) misst nur;
  Fix-Befehle nur, wo sie sicher sind.

## zsh-Fallen (alle schon einmal passiert)

- Shebang `#!/usr/bin/env zsh`, zsh-Semantik: `echo` interpretiert Escapes ohne `-e`; Fehlererkennung
  in `run()` hängt an `$pipestatus`; `EXTENDED_GLOB` ist an — `(`/`#` in Mustern quoten.
- **BSD-sed kennt kein `\S`** — in `sed -E` `[^ ]` schreiben, sonst bleibt die Zeile still unverändert.
- `$(<datei) 2>/dev/null` unterdrückt den Fehler bei fehlender Datei nicht — `[[ -f … ]] && cat`.
- `wait` ohne Argumente wartet auf **alle** Hintergrundjobs — gezielt `wait $pid`.
- `print -r a b` schreibt eine Zeile, `print -rl` je Argument eine.
- **`(( arr[$k]++ ))` mit Fremdtext als Schlüssel führt Backticks und `$(…)` darin aus** (zsh wertet
  den Subscript in Arithmetik erneut aus). Sicher: `arr[$k]=$(( ${arr[$k]:-0} + 1 ))`.
- Array-Ausschnitte in Anführungszeichen brauchen `(@)`: `"${a[41,-1]}"` ist **ein** Wort.
- tmux-Zielargumente als Array (`tgt=(-t ziel)`) — `${var:+-t "$var"}` wird in zsh ein Wort.
- `tput` misst in `$(…)` über stderr — nie `2>/dev/null` dahinter, sonst kommt 80×24.
- In Boxen/Tabellen keine Zeichen mit mehrdeutiger Breite (`⏎`, `↑`, `↓`) und keine Emojis.

## Testen der TUI — Sicherheitsregeln

- **Ausschließlich auf eigenem Socket:** `tmux -L qtest …`, Aufräumen mit `tmux -L qtest kill-server`.
  **Nie** ein nacktes `tmux kill-server` — das beendet die Session, in der gearbeitet wird.
- **Nie `TMUX_TMPDIR` zur Isolation:** tmux fällt still auf den Standard-Socket zurück, sobald das
  Verzeichnis fehlt.
- „Außerhalb von tmux“ simulieren: im Test-Pane `unset TMUX` und ein PATH-Wrapper `tmux` →
  `exec <tmux-Binary> -L qtest "$@"` (legt das Testskript an).
- Aufräumen in dieser Reihenfolge: Pane-Prozesse des Test-Servers, dann der Test-Server, dann nur
  verwaiste RUNDIRs. Kein nacktes `pkill -f 'update-all.sh --_'` — das träfe auch einen echten Lauf.
- Auf frischem Server: %1 = Runner, %2 = Status, %3 = Aktionen. `q` erst schicken, wenn
  `$RUNDIR/final` existiert.
- Testskript-Fallen: typografische Anführungszeichen „…" in doppelt gequoteten Strings öffnen mit
  dem ASCII-`"` eine neue Zeichenkette bis EOF; Arrays per Name heißt `${(@P)1}`; ein ungequotetes
  Wort mit führendem `=` löst Befehlspfad-Expansion aus; Fensterindizes nie raten.
