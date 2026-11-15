# Roadmap

Leitlinie: **Der Lauf muss weiterlaufen, wenn die Verbindung abbricht — ohne Hintergrunddienst.**
Neues kommt nur hinein, wenn es diese Zusage nicht aufweicht und keinen Dialog auf dem Mac-Schirm
auslöst.

## Als Nächstes

| Idee | Worum es geht |
|---|---|
| Homebrew-Tap | `brew install bingerminger/tap/update-all` statt `git clone` — der übliche Weg für Mac-CLIs. |
| `--detach` ohne tmux | Für Macs ohne tmux: Runner per `nohup` + `caffeinate`, Ansicht später per `--review` oder `tail -f`. Weiterhin kein Dienst. |
| Profil „Harness aktuell halten“ | `--only harness` bündelt, was KI-Werkzeuge braucht: Claude-Code-Plugins, codex, pi, uv tools, npm-Globale. |
| Englische Ausgaben | Heute ist alles Deutsch. Ausgaben und README zweisprachig zu machen, ist der größte Einzelposten. |

## Später

| Idee | Stand |
|---|---|
| `brew vulns` (OSV.dev) | Geprüft: ~14 s, viel Rauschen (Fuzz-Funde ohne Fix). Höchstens selten und nur „Fix verfügbar“. |
| Katalogabgleich „Cask hinkt dem Hersteller“ | Homebrews lokaler Katalog ist ein internes Format; im Test kein neuer Treffer. |
| Empfehlung mosh für iPhone/iPad | mosh hält die *Verbindung* über Funklöcher, tmux die *Arbeit*. Gehört in die Doku, nicht ins Skript. |
| Lint für zsh | ShellCheck kann zsh nur eingeschränkt; Kandidaten prüfen, bevor etwas in die CI kommt. |
| Scan-Modus mit Anhaken | Erst sehen, dann gezielt auswählen, was gehoben wird. |

## Bewusst nicht

- **Ein Dienst/LaunchAgent**, der regelmäßig aktualisiert — Updates passieren, wenn du sie startest.
- **Eine Vordergrund-App** statt tmux (z. B. Textual): Sie gäbe auf, was remote der eigentliche
  Zweck ist — dass der Lauf eine abgebrochene SSH-Verbindung übersteht.
- **Allzweck-Reiniger** (`mo clean` u. ä.) als Fix-Befehl: Sie leeren auch Caches, die laufende
  Werkzeuge gerade brauchen.
