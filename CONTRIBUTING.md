# Mitmachen · Contributing

**Deutsch** · [English](#english)

Danke fürs Mitmachen! Am meisten helfen:

- **Fehlerberichte** mit Version, macOS-Version und den Schritten bis zum Fehler — am besten mit dem passenden Ausschnitt aus `~/Library/Logs/update-all/runs/`.
- **Neue Abschnitte** für Werkzeuge, die update-all noch nicht kennt.
- **Doku:** Fehler, Lücken, unklare Stellen im README.

Sicherheitsprobleme bitte **nicht** als Issue, sondern wie in [SECURITY.md](SECURITY.md) beschrieben. Es gelten die [Verhaltensregeln](CODE_OF_CONDUCT.md).

## Keine echten Daten

Logs von update-all enthalten Hostnamen, Benutzernamen, Pfade und die Liste deiner Apps. Bitte vor dem Einfügen in ein Issue kürzen oder ersetzen.

## Entwickeln

update-all ist **ein** zsh-Skript ohne Build-Schritt. Ausgaben und Kommentare sind deutsch. Die Leitplanken und die zsh-Fallen, die schon einmal zugeschlagen haben, stehen in [CLAUDE.md](CLAUDE.md) — lesenswert auch ohne KI-Agent.

Vor einem Pull Request:

```sh
zsh -n update-all.sh && zsh -n update-all-tuitest.zsh
./update-all.sh --selftest
./update-all-tuitest.zsh all        # tmux-Ansicht headless, ≈ 4,5 min
```

- Die TUI-Tests laufen ausschließlich auf einem eigenen tmux-Server (`tmux -L qtest`) mit eigenen Logs und Einstellungen. Deine echte tmux-Session bleibt unberührt.
- Neuer Abschnitt: `sec_<id>()` plus eine `reg`-Zeile in `build_registry()`. Befehle über `run`, Abfragen über `capture_t` + `capture_ok`.
- `VERSION` im Kopf von `update-all.sh` hochzählen und `CHANGELOG.md` nachziehen.
- Ein Thema je Pull Request.

Beiträge erscheinen unter der [MIT-Lizenz](LICENSE) des Projekts.

---

## English

Thanks for joining in! Most helpful are bug reports (version, macOS version, steps, the relevant part of the log under `~/Library/Logs/update-all/runs/`), new sections for tools update-all does not know yet, and documentation fixes. Report security issues as described in [SECURITY.md](SECURITY.md), not as an issue; the [code of conduct](CODE_OF_CONDUCT.md) applies.

**No real data:** update-all logs contain host names, user names, paths and your app list — please trim or replace them before posting.

update-all is a single zsh script without a build step; output and comments are in German. Conventions and known zsh pitfalls are in [CLAUDE.md](CLAUDE.md). Before a pull request run `zsh -n`, `./update-all.sh --selftest` and `./update-all-tuitest.zsh all` (headless, on its own tmux server — your real session is never touched), bump `VERSION` and update `CHANGELOG.md`. One topic per pull request. Contributions are published under the project's [MIT licence](LICENSE).
