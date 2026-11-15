<!-- Danke für deinen Beitrag! / Thanks for contributing! Deutsch oder Englisch, beides ist willkommen. -->

## Worum geht es? / What does it change?

<!-- Ein Thema je Pull Request. Issue verlinken: „Closes #…“ / One topic per pull request. Link the issue. -->

## Wie geprüft? / How was it tested?

- [ ] `zsh -n update-all.sh && zsh -n update-all-tuitest.zsh`
- [ ] `./update-all.sh --selftest` grün / green
- [ ] `./update-all-tuitest.zsh all` grün, wenn die tmux-Ansicht betroffen ist / green where the tmux view is touched
- [ ] `--check` oder `--dry-run` auf einem echten Mac / on a real Mac

## Vor dem Absenden / Before submitting

- [ ] `VERSION` hochgezählt und `CHANGELOG.md` nachgezogen / bumped `VERSION`, updated `CHANGELOG.md`
- [ ] Ausgaben und Kommentare auf Deutsch, wie im Rest des Skripts / output and comments in German, like the rest of the script
- [ ] Keine echten Daten: keine Hostnamen, Benutzernamen, Pfade, App-Listen / no real data: no host names, user names, paths, app lists
- [ ] Mein Beitrag erscheint unter der [MIT-Lizenz](../LICENSE) des Projekts / my contribution is published under the project's MIT licence

Mehr in / More in [CONTRIBUTING.md](../CONTRIBUTING.md).
