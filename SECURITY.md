# Sicherheitsrichtlinie · Security policy

**Deutsch** · [English](#english)

## Eine Lücke melden

Bitte **kein** öffentliches Issue für ein Sicherheitsproblem. Melde es stattdessen privat über GitHub:
**[Security → Report a vulnerability](https://github.com/Bingerminger/update-all/security/advisories/new)**.

update-all ruft `sudo` auf, stellt das Admin-Passwort per `SUDO_ASKPASS` bereit und führt auf Tastendruck (`^X`) Fix-Befehle aus der Aktionsliste aus. Berichte zu diesen Stellen sind besonders willkommen — etwa, wenn Text aus einer Tool-Ausgabe in einen ausführbaren Befehl gelangen kann.

Hilfreich sind:

- die Version (`update-all.sh --version`) und die macOS-Version,
- wie update-all lief (lokal, per SSH, `--plain`, `-y`),
- die Schritte zum Nachstellen und was ein Angreifer damit erreicht.

Eine Eingangsbestätigung kommt innerhalb von **7 Tagen**. update-all wird in der Freizeit gepflegt; gemeldete Lücken werden so schnell wie möglich behoben. Bitte gib Zeit für einen Fix, bevor du Details veröffentlichst.

## Unterstützte Versionen

Behoben wird in der jeweils neuesten Version. Bitte vor einer Meldung aktualisieren — was sich geändert hat, steht im [CHANGELOG](CHANGELOG.md).

---

## English

### Reporting a vulnerability

Please do **not** open a public issue for a security problem. Report it privately via GitHub:
**[Security → Report a vulnerability](https://github.com/Bingerminger/update-all/security/advisories/new)**.

update-all runs `sudo`, provides the admin password via `SUDO_ASKPASS` and, on a key press (`^X`), runs fix commands from its action list. Reports about these areas are especially welcome — for example if text from a tool's output can end up in an executable command.

Helpful details: the version (`update-all.sh --version`) and macOS version, how update-all ran (local, via SSH, `--plain`, `-y`), steps to reproduce and what an attacker gains.

You will receive an acknowledgement within **7 days**. update-all is maintained in spare time; reports are handled as quickly as possible. Please allow time for a fix before publishing details.

### Supported versions

Fixes are made on the latest version. Please update before reporting — see the [CHANGELOG](CHANGELOG.md).
