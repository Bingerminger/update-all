#!/usr/bin/env zsh
# ╔══════════════════════════════════════════════════════════════╗
# ║  update-all-tuitest.zsh — Headless-Tests für die tmux-TUI    ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Fährt update-all.sh im Dry-Run auf einem EIGENEN tmux-Server hoch, drückt Tasten in
# die Panes und prüft Fenster, Sessions, Zustandsverzeichnisse und Prozesse.
#
# Aufruf: ./update-all-tuitest.zsh [quit|review|layout|remote|all] [-n N]
#   quit    Schließen der Ansicht: q im Status-/Aktionen-Pane, ⏎ im Runner, q während
#           des Laufs (muss ignoriert werden), Abschlussphase (phase=done, noch kein final)
#   review  --review: liegengebliebener Rückblick blockiert keinen Lauf, Doppelstart hängt
#           sich an, Rückblick ersetzt Rückblick, Arbeitssession mit Lauf + Rückblick
#   layout  Pane-Geometrie nach Fenstergröße (160x44 / 110x32 / 92x26 iPad / 80x20 iPhone),
#           dazu die Restzeit-Schätzung in Status-Pane und Pane-Rand
#   remote  von außen in die Arbeitssession (Layout nach dem Terminal), fertiger Lauf ohne q
#           blockiert nicht, Abschluss-Tafel passt ins Pane, Lock belegt → Meldung + Exit 2,
#           Verbindung bricht mitten im Lauf ab → Lauf läuft bis final weiter
#   all     alle vier (Standard)
#   -n N    Quit-Fall 1 N-mal wiederholen (Flakiness-Suche)
# Exit 0 = alle Prüfungen ✓, 1 = mindestens ein ✗. Dauer: quit ≈ 1 min, review ≈ 1 min,
# layout ≈ 40 s, remote ≈ 1,5 min. R4 schreibt kurz einen run.lock mit Dummy-PID — in das
# Konfigurationsverzeichnis des Tests, nie in das echte.
#
# Sicherheitsregeln — zwei Vorfälle (ein nacktes kill-server, ein TMUX_TMPDIR-Rückfall)
# haben die tmux-Session beendet, in der gearbeitet wurde, samt allem, was darin lief:
#   • tmux NUR über t() = `tmux -L qtest`. Nie nacktes tmux, nie kill-server ohne -L,
#     nie TMUX_TMPDIR (tmux 3.7c fällt still auf den Standard-Socket zurück, sobald das
#     Verzeichnis fehlt).
#   • „Außerhalb von tmux" simuliert $OUTSIDE: `unset TMUX` + PATH-Wrapper, der jeden
#     tmux-Aufruf des Skripts auf -L qtest zwingt. Fehlt der Wrapper, gibt es „command
#     not found" — nie den echten Server. Die Panes selbst haben $TMUX (qtest) gesetzt.
#   • Aufräumen: erst Pane-Prozesse des Test-Servers, dann Server, dann nur RUNDIRs, die
#     kein Prozess mehr benutzt. Läuft ein echter update-all-Lauf, startet der Test nicht.
#   • Logs/last/ des Tests liegen unter $TESTROOT/logs (UPDATE_ALL_LOGDIR), prefs/acks/
#     run.lock unter $TESTROOT/conf (UPDATE_ALL_CONFDIR) — runs/, last/, history.tsv und
#     die Einstellungen des echten Laufs bleiben unberührt, und die Tests hängen nicht an
#     ihnen. Die Test-prefs setzen tmux_session=work (die simulierte Arbeitssession).
# Fallen beim Schreiben von Testfällen: typografische Anführungszeichen „…" in doppelt
# gequoteten Strings öffnen mit dem ASCII-" eine neue Zeichenkette bis EOF (zsh führt alles
# davor trotzdem aus); Arrays per Name heißt ${(@P)1}; `print -rl -- pfad/*(N)` gibt bei null
# Treffern eine Leerzeile aus (wc -l = 1). Pane-IDs auf frischem Server: %1 Runner,
# %2 Status, %3 Aktionen; list-panes-Index 1 = Status (links), 2 = Runner, 3 = Aktionen.
# Ein ungequotetes Wort, das mit = beginnt (-t =work:x), macht zsh zur Befehlspfad-
# Expansion und bricht das Skript ab — '=work:x' quoten. Fensterindizes nie raten
# (qt:0 gibt es bei base-index 1 nicht): list-windows fragen.

setopt EXTENDED_GLOB NULL_GLOB
unset TMUX_TMPDIR   # siehe oben — hier hat es nichts zu suchen
# Die Prüfungen erwarten, dass das Grundfenster einer neuen Session "zsh" heißt. tmux nimmt
# als Shell $SHELL beim Serverstart — auf CI-Runnern ist das bash (dort hieß das Fenster
# "bash" und 14 Prüfungen schlugen fehl, obwohl die TUI richtig arbeitete).
export SHELL=${commands[zsh]:-/bin/zsh}

S=${0:A:h}/update-all.sh
[[ -x $S ]] || { echo "update-all.sh nicht gefunden neben ${0:A}"; exit 2; }
T=${TMPDIR:-/tmp}
TESTROOT="${T%/}/update-all-tuitest"; mkdir -p "$TESTROOT/bin" "$TESTROOT/logs" "$TESTROOT/conf"
export UPDATE_ALL_LOGDIR="$TESTROOT/logs" UPDATE_ALL_CONFDIR="$TESTROOT/conf"
print -r -- "tmux_session=work" > "$UPDATE_ALL_CONFDIR/prefs"; : > "$UPDATE_ALL_CONFDIR/acks"
SOCK=qtest
TMUX_BIN=${commands[tmux]}; [[ -x $TMUX_BIN ]] || { echo "tmux nicht gefunden"; exit 2; }   # absoluter Pfad, nie der Wrapper
t() { "$TMUX_BIN" -L $SOCK "$@" }
print -rl -- '#!/bin/sh' "exec '$TMUX_BIN' -L $SOCK \"\$@\"" > "$TESTROOT/bin/tmux"; chmod +x "$TESTROOT/bin/tmux"
OUTSIDE="unset TMUX; export PATH=$TESTROOT/bin:\$PATH UPDATE_ALL_LOGDIR=$UPDATE_ALL_LOGDIR UPDATE_ALL_CONFDIR=$UPDATE_ALL_CONFDIR"   # vor den Skriptaufruf im Pane

FAILS=0
chk() { if [[ $1 == "$2" ]]; then echo "   ✓ $3"; else echo "   ✗ $3 — ist: '$1', erwartet: '$2'"; (( FAILS+=1 )); fi }
say() { echo "\n=== $* ===" }
phase() { [[ -f $1/state ]] && sed -n 's/^phase=//p' "$1/state" }
rundirs() { local -a d; d=("$T"/update-all.*(N/)); (( ${#d} )) && print -rl -- "${d[@]}"; return 0 }
nrd() { rundirs | wc -l | tr -d ' ' }
procs() { pgrep -fl 'update-all.sh --_' 2>/dev/null }
nproc_() { procs | wc -l | tr -d ' ' }
wait_file()  { local i; for (( i=0; i<$2*4; i++ )); do [[ -e $1 ]] && return 0; sleep 0.25; done; return 1 }
wait_phase() { local i; for (( i=0; i<$3*4; i++ )); do [[ $(phase "$1") == "$2" ]] && return 0; sleep 0.25; done; return 1 }
wait_rundir() {   # wartet, bis ein RUNDIR da ist → $rd
  local i; rd=""; for (( i=0; i<40; i++ )); do rd=$(rundirs | head -1); [[ -n $rd ]] && return 0; sleep 0.25; done; return 1
}
sessions() { t ls -F '#S' 2>/dev/null | tr '\n' ' ' }
wins_of()  { t list-windows -t "=$1" -F '#{window_name}' 2>/dev/null | tr '\n' ' ' }
cmd_of()   { t display-message -p -t "$1" '#{pane_current_command}' 2>/dev/null }
status_pane() { t list-panes -t "=$1:$2" -F '#{pane_id}' 2>/dev/null | sed -n 1p }   # Index 1 = Status
lastlog()  { ls -t "$UPDATE_ALL_LOGDIR"/runs/*.log 2>/dev/null | head -1 }

teardown() {
  local -a pids; pids=(${(f)"$(t list-panes -a -F '#{pane_pid}' 2>/dev/null)"})
  local p; for p in "${pids[@]}"; do pkill -TERM -P "$p" 2>/dev/null; kill -TERM "$p" 2>/dev/null; done
  (( ${#pids} )) && sleep 0.5
  t kill-server 2>/dev/null
  local d; for d in "$T"/update-all.*(N/); do pgrep -qf -- "${d:t}" || rm -rf "$d"; done   # nur verwaiste
}
setup() { teardown; t new-session -d -s qt -x 160 -y 44; sleep 0.3 }
seed() {   # --review braucht einen abgeschlossenen Lauf unter $UPDATE_ALL_LOGDIR/last
  [[ -f "$UPDATE_ALL_LOGDIR/last/state" ]] && return 0
  zsh "$S" --dry-run --plain --only mas,php >/dev/null 2>&1
  [[ -f "$UPDATE_ALL_LOGDIR/last/state" ]] || { echo "✗ Seed-Lauf hat kein last/ erzeugt"; exit 2; }
}

# ── Quit-Verhalten (in tmux: Fenster in der aktuellen Session qt) ─────────────
start_run() {   # $1 = Abschnitte → $rd; wartet, bis alle drei Panes stehen
  setup; t send-keys -t qt "zsh $S --dry-run --only $1" Enter
  wait_rundir || { echo "   ✗ kein RUNDIR erschienen"; (( FAILS+=1 )); return 1; }
  local i; for (( i=0; i<40; i++ )); do t list-panes -t qt:update-all -F '#{pane_id}' 2>/dev/null | grep -q '^%3$' && return 0; sleep 0.25; done
  echo "   ✗ Panes nicht vollständig"; (( FAILS+=1 )); return 1
}
after_close() {   # $1 = Beschreibung
  sleep 2
  chk "$(wins_of qt)" "zsh " "$1: TUI-Fenster zu"
  chk "$(nrd)" "0" "$1: RUNDIR weg"
  chk "$(nproc_)" "0" "$1: keine Prozesse"
  local l; l=$(lastlog); [[ -n $l ]] && grep -q 'Abgebrochen' "$l" && { echo "   ✗ Log meldet Abbruch"; (( FAILS+=1 )); } || echo "   ✓ Log ohne Abbruch"
}
suite_quit() {
  local k n=${1:-1}
  local lbl
  for (( k=1; k<=n; k++ )); do
    lbl=""; (( n > 1 )) && lbl=" ($k/$n)"
    say "Quit 1$lbl: q im Status-Pane nach Abschluss"
    start_run mas,php && { wait_file "$rd/final" 60; sleep 1; t send-keys -t qt:update-all.%2 q; after_close "Status-q"; }
  done
  say "Quit 2: q im Aktionen-Pane (fzf/Liste) nach Abschluss"
  start_run mas,php && { wait_file "$rd/final" 60; sleep 1; t send-keys -t qt:update-all.%3 q; after_close "Aktionen-q"; }
  say "Quit 3: ⏎ im Runner-Pane nach Abschluss"
  start_run mas,php && { wait_file "$rd/final" 60; sleep 1; t send-keys -t qt:update-all.%1 Enter; after_close "Runner-⏎"; }
  say "Quit 4: q WÄHREND des Laufs wird ignoriert, danach schließt q"
  if start_run mas,php,node,python,editors,ai; then
    wait_phase "$rd" running 20
    t send-keys -t qt:update-all.%2 q; sleep 1.5
    chk "$(phase $rd)" "running" "Lauf läuft weiter"
    chk "$(wins_of qt)" "zsh update-all " "Fenster bleibt offen"
    t capture-pane -p -t qt:update-all.%2 | grep -q 'läuft …' && echo "   ✓ Status zeigt (läuft …)" || { echo "   ✗ Status zeigt nicht (läuft …)"; (( FAILS+=1 )); }
    wait_file "$rd/final" 90 || { echo "   ✗ kein final"; (( FAILS+=1 )); }
    sleep 1; t send-keys -t qt:update-all.%2 q; after_close "q nach Abschluss"
  fi
  say "Quit 5: Abschlussphase (phase=done, final noch nicht da) — Fußzeile, dann q"
  if start_run mas,php; then
    wait_phase "$rd" done 60
    local txt; txt=$(t capture-pane -p -t qt:update-all.%2 | grep -E 'schließt ab|schließt die Ansicht' | head -1 | sed 's/^ *//')
    [[ -n $txt ]] && echo "   ✓ Fußzeile: $txt" || echo "   · Fußzeile nicht erwischt (Abschluss zu schnell — kein Fehler)"
    wait_file "$rd/final" 60; sleep 1; t send-keys -t qt:update-all.%2 q; after_close "q"
  fi
  teardown
}

# ── --review und Platzierung (außerhalb von tmux, per $OUTSIDE) ───────────────
suite_review() {
  seed
  say "Review A: Rückblick in eigener Session liegen lassen (Detach), dann Lauf"
  setup
  t send-keys -t qt "$OUTSIDE; zsh $S --review" Enter; sleep 3
  chk "$(wins_of update-all)" "update-all-review " "Rückblick offen in Session update-all"
  t detach-client -s update-all 2>/dev/null; sleep 1
  t send-keys -t qt "$OUTSIDE; zsh $S --dry-run --only mas,php" Enter; sleep 4
  chk "$(wins_of update-all)" "update-all " "Lauf läuft in Session update-all, Rückblick weg"
  chk "$(cmd_of qt)" "tmux" "Terminal hängt am Lauf (attach)"
  chk "$(nrd)" "1" "genau ein RUNDIR (Rückblick-Kopie mit entfernt)"
  rd=$(rundirs | head -1)
  wait_file "$rd/final" 60 && echo "   ✓ final-Marker" || { echo "   ✗ kein final (Phase $(phase $rd))"; (( FAILS+=1 )); }
  sleep 1; t send-keys -t "$(status_pane update-all update-all)" q; sleep 2
  chk "$(sessions)" "qt " "nach q im Status-Pane: Session update-all weg"
  chk "$(nrd)" "0" "kein RUNDIR mehr"
  chk "$(nproc_)" "0" "keine Prozesse mehr"
  teardown

  say "Review B: Lauf läuft in eigener Session → zweiter Aufruf hängt sich an, startet nicht doppelt"
  setup
  t send-keys -t qt "$OUTSIDE; zsh $S --dry-run --only mas,php,node,python,editors,ai" Enter; sleep 3
  t new-session -d -s qt2 -x 160 -y 44
  t send-keys -t qt2 "$OUTSIDE; zsh $S --dry-run --only mas,php" Enter; sleep 3
  chk "$(cmd_of qt2)" "tmux" "zweites Terminal hängt am laufenden Lauf (attach)"
  chk "$(nrd)" "1" "kein zweiter Lauf"
  chk "$(wins_of update-all)" "update-all " "ein Fenster in update-all"
  rd=$(rundirs | head -1)
  wait_file "$rd/final" 90 && echo "   ✓ Lauf beendet" || { echo "   ✗ kein final"; (( FAILS+=1 )); }
  sleep 1; t send-keys -t "$(status_pane update-all update-all)" q; sleep 2
  chk "$(sessions)" "qt qt2 " "nach q: Session update-all weg, Terminals leben"
  chk "$(nrd)" "0" "kein RUNDIR mehr"
  teardown

  say "Review C: --review zweimal in eigener Session → der zweite ersetzt den ersten"
  setup
  t send-keys -t qt "$OUTSIDE; zsh $S --review" Enter; sleep 3
  t detach-client -s update-all 2>/dev/null; sleep 1
  t send-keys -t qt "$OUTSIDE; zsh $S --review" Enter; sleep 3
  chk "$(wins_of update-all)" "update-all-review " "genau ein Rückblick-Fenster"
  chk "$(cmd_of qt)" "tmux" "Terminal hängt am Rückblick"
  chk "$(nrd)" "1" "genau ein RUNDIR"
  local lp; lp=$(t list-panes -t "=update-all:update-all-review" -F '#{pane_id}' 2>/dev/null | sed -n 2p)   # Log-Pane (less)
  t send-keys -t "$lp" q; sleep 2
  chk "$(sessions)" "qt " "nach q im Log-Pane: Session weg"
  chk "$(nrd)" "0" "kein RUNDIR mehr"
  teardown

  say "Review D: Arbeitssession work — Rückblick liegt, Lauf kommt dazu, zweiter Rückblick ersetzt ersten"
  setup
  t new-session -d -s work -x 160 -y 44
  t send-keys -t qt "$OUTSIDE; zsh $S --review" Enter; sleep 3
  chk "$(wins_of work)" "zsh update-all-review " "Rückblick in work"
  t detach-client -s work 2>/dev/null; sleep 1
  t send-keys -t qt "$OUTSIDE; zsh $S --dry-run --only mas,php" Enter; sleep 4
  chk "$(wins_of work)" "zsh update-all-review update-all " "Lauf neben dem Rückblick, Rückblick bleibt"
  chk "$(nrd)" "2" "zwei RUNDIRs (Lauf + Rückblick)"
  rd=""; local d; for d in $(rundirs); do [[ -f $d/review ]] || rd=$d; done
  wait_file "$rd/final" 60 && echo "   ✓ Lauf beendet" || { echo "   ✗ kein final"; (( FAILS+=1 )); }
  t detach-client -s work 2>/dev/null; sleep 1
  local rev1 rev2; rev1=$(t display-message -p -t "=work:update-all-review" '#{window_id}')
  t send-keys -t qt "$OUTSIDE; zsh $S --review" Enter; sleep 3
  rev2=$(t display-message -p -t "=work:update-all-review" '#{window_id}')
  chk "$(wins_of work | tr ' ' '\n' | sort | tr '\n' ' ')" "update-all update-all-review zsh " "genau ein Rückblick-Fenster, Lauf bleibt"
  [[ -n $rev1 && -n $rev2 && $rev1 != $rev2 ]] && echo "   ✓ Rückblick-Fenster ist ein neues ($rev1 → $rev2)" || { echo "   ✗ Rückblick-Fenster nicht ersetzt ($rev1 → $rev2)"; (( FAILS+=1 )); }
  chk "$(nrd)" "2" "zwei RUNDIRs (alte Rückblick-Kopie entfernt)"
  local w; for w in update-all-review update-all; do t send-keys -t "$(status_pane work $w)" q; sleep 1.5; done
  chk "$(wins_of work)" "zsh " "nach q in beiden: nur das work-Fenster übrig"
  chk "$(nrd)" "0" "kein RUNDIR mehr"
  teardown
}

# ── Layout nach Fenstergröße (ab update-all 3.3.0) ────────────────────────────
# Das Status-Pane war fest 40 Spalten breit — auf einem iPhone im Querformat blieben dem
# Log 39. Jetzt bemisst tui_launch die Panes nach Fensterbreite/-höhe und schreibt die
# Entscheidung nach $RUNDIR/layout (sw<TAB>ah<TAB>cols<TAB>rows). Hier wird geprüft, dass
# die Schwellen greifen UND die Panes wirklich so entstehen.
# Multibyte-Falle: Zeilen mit █/░ (Fortschrittsbalken) nie durch sed/cut schicken — die
# verschlucken sie je nach Locale STILL. Zählen (grep -c) statt anzeigen.
suite_layout() {
  local -a cases; cases=("160 44 40 32%" "110 32 34 32%" "92 26 28 7" "80 20 0 0")
  local c cw ch esw eah sw ah np exp; local -a lay
  for c in "${cases[@]}"; do
    cw=${${(s: :)c}[1]}; ch=${${(s: :)c}[2]}; esw=${${(s: :)c}[3]}; eah=${${(s: :)c}[4]}
    say "Layout ${cw}x${ch}: Status $esw · Aktionen $eah"
    teardown; t new-session -d -s qt -x $cw -y $ch; sleep 0.3
    t send-keys -t qt "zsh $S --dry-run --only mas,php" Enter
    wait_rundir || { echo "   ✗ kein RUNDIR"; (( FAILS+=1 )); continue; }
    wait_file "$rd/layout" 20 || { echo "   ✗ keine Layout-Datei"; (( FAILS+=1 )); continue; }
    lay=(${(f)"$(tr '\t' '\n' < "$rd/layout")"}); sw=${lay[1]}; ah=${lay[2]}
    chk "$sw" "$esw" "Status-Pane-Breite"
    chk "$ah" "$eah" "Aktionen-Pane-Höhe"
    np=$(t list-panes -t qt:update-all -F x 2>/dev/null | grep -c x)
    exp=1; [[ $esw != 0 ]] && (( exp+=1 )); [[ $eah != 0 ]] && (( exp+=1 ))
    chk "$np" "$exp" "Panes insgesamt"
    # Inhalte erst prüfen, wenn gerendert ist: $RUNDIR/steps steht, dann einen Tick warten
    # (Status-Pane zeichnet im Sekundenrhythmus, der Pane-Titel kommt mit dem 1. Abschnitt)
    wait_file "$rd/steps" 20; sleep 2
    if [[ $esw == 0 ]]; then
      # Kompaktlayout: der Pane-Rand ist die einzige Daueranzeige
      t display-message -p -t qt:update-all.%1 '#{pane_title}' 2>/dev/null | grep -q 'update-all ·' \
        && echo "   ✓ Fortschritt im Pane-Rand" || { echo "   ✗ Pane-Rand ohne Fortschritt"; (( FAILS+=1 )); }
    else
      t capture-pane -p -t qt:update-all.%2 > "$TESTROOT/pane.txt" 2>/dev/null
      # auf █ UND ░ prüfen: bei 0 % besteht der Balken nur aus ░
      (( $(grep -c '[█░]' "$TESTROOT/pane.txt") )) && echo "   ✓ Fortschrittsbalken im Status-Pane" \
        || { echo "   ✗ kein Fortschrittsbalken"; (( FAILS+=1 )); }
      # im schmalen Pane ohne Label-Spalte (narrow): "brew 0 · MAS 0"
      if (( cw < 100 )); then
        grep -q 'MAS' "$TESTROOT/pane.txt" && echo "   ✓ KPIs im Kurzformat" \
          || { echo "   ✗ KPIs nicht gekürzt"; (( FAILS+=1 )); }
      fi
    fi
    wait_file "$rd/final" 60; sleep 0.5
  done
  teardown

  # Restzeit (ab 3.3.8): aus den Abschnittsdauern des letzten Laufs — hier ein untergeschobener
  # last/ mit je 300 s, damit die Schätzung sicher sichtbar ist (echte Dry-Run-Dauern sind 1–2 s)
  say "Restzeit: Status-Pane und Pane-Rand zeigen „noch ca. … min“ aus dem letzten Lauf"
  teardown; mkdir -p "$UPDATE_ALL_LOGDIR/last"
  print -r -- "mode=yes" > "$UPDATE_ALL_LOGDIR/last/state"
  print -rl -- $'mas\tMac App Store\tok\t300\t0\t0' $'php\tPHP\tok\t300\t0\t0' > "$UPDATE_ALL_LOGDIR/last/steps"
  t new-session -d -s qt -x 160 -y 44; sleep 0.3
  t send-keys -t qt "zsh $S --dry-run --only mas,php" Enter
  if wait_rundir; then
    wait_file "$rd/prev-steps" 10 && echo "   ✓ Vergleichslauf übernommen (prev-steps)" || { echo "   ✗ kein prev-steps"; (( FAILS+=1 )); }
    # Der Dry-Run ist in ~1,5 s durch, danach steht „fertig“ — deshalb WÄHREND des Laufs
    # fortlaufend nachsehen (einmal gesehen reicht), nicht einmal hinterher
    local seen_p=0 seen_t=0 k
    for (( k=0; k<300 && ! (seen_p && seen_t); k++ )); do
      (( seen_p )) || { t capture-pane -p -t qt:update-all.%2 2>/dev/null | grep -q 'noch ca\. [0-9]* min' && seen_p=1; }
      (( seen_t )) || { [[ $(t display-message -p -t qt:update-all.%1 '#{pane_title}' 2>/dev/null) == *'noch ca. '*' min'* ]] && seen_t=1; }
      [[ -f $rd/final ]] && break
      sleep 0.1
    done
    (( seen_p )) && echo "   ✓ Restzeit im Status-Pane" || { echo "   ✗ keine Restzeit im Status-Pane"; (( FAILS+=1 )); }
    (( seen_t )) && echo "   ✓ Restzeit im Pane-Rand" || { echo "   ✗ keine Restzeit im Pane-Rand"; (( FAILS+=1 )); }
    wait_file "$rd/final" 60; sleep 0.5
  else
    echo "   ✗ kein RUNDIR"; (( FAILS+=1 ))
  fi
  teardown
}

# ── Remote-Fälle (ab update-all 3.3.3) ────────────────────────────────────────
# Aus einem Review des Remote-Betriebs, jeder Fall war vorher reproduzierbar kaputt:
#   R1  von außen in die Arbeitssession: das Layout kam aus deren Fenster (200x50) statt
#       aus dem anhängenden Terminal — am iPhone Status-Pane 1 Spalte, Aktionen 1 Zeile
#   R2  fertiger, nicht mit q geschlossener Lauf (Verbindung einfach zu): der nächste
#       Aufruf sprang nur hin und startete nie neu
#   R3  Abschluss-Tafel 64 Zeichen im 63er-Pane (iPad) → Rahmen bricht um; ohne
#       Aktionen-Pane versprach sie Pfeile/^X
#   R4  Lock belegt, Aufruf aus anderer Session: Fenster blitzte auf, Meldung weg, Exit 0
#   R5  (ab 3.3.7) Verbindung bricht MITTEN im Lauf ab — das Hauptziel des Skripts, bis dahin
#       ungetestet (Review A/D trennen nur am Rückblick bzw. nach final). Einmal sauber per
#       detach-client, einmal per SIGHUP an den Client wie beim Abriss einer SSH-Sitzung.
#   R6  (ab 3.4.0) --resume über die TUI holt genau die Abschnitte aus der Abbruch-Notiz nach.
# Rahmenzeilen werden in zsh geprüft, nicht mit sed/cut (Multibyte, siehe oben).
frame_ok() {   # $1 = Pane, $2 = Beschreibung — jede Rahmenzeile muss im Pane geschlossen sein
  local l n=0 bad=0
  for l in "${(@f)$(t capture-pane -p -t "$1" 2>/dev/null)}"; do
    [[ $l == '  '[╭│╰]* ]] || continue
    (( n+=1 )); l=${l%%( )#}
    [[ $l == *[╮│╯] ]] || bad=1
  done
  if (( n >= 3 && ! bad )); then echo "   ✓ $2: $n Rahmenzeilen, keine umbrochen"
  else echo "   ✗ $2: Rahmen kaputt oder nicht sichtbar ($n Zeilen, umbrochen=$bad)"; (( FAILS+=1 )); fi
}
suite_remote() {
  local c tw th esw eah lay wsz pw first old new l0 out; local -a f
  # erwartet: sw ah cols rows — das Terminal-Pane hat die volle Sessionhöhe (abgekoppelt,
  # keine Statuszeile), das Fenster darin eine Zeile weniger (Statuszeile des Clients)
  for c in "80 20 0 0 80 19" "92 26 28 7 92 25"; do
    f=(${=c}); tw=$f[1]; th=$f[2]; esw=$f[3]; eah=$f[4]
    say "R1 ${tw}x${th}: von außen in die Arbeitssession (200x50) — Layout nach dem Terminal"
    teardown
    t new-session -d -s work -x 200 -y 50          # die Arbeitssession, bemessen vom Mac-Schirm
    t new-session -d -s qt -x $tw -y $th; sleep 0.3   # das Terminal am iPhone/iPad
    t send-keys -t qt "$OUTSIDE; zsh $S --dry-run --only mas,php" Enter
    wait_rundir || { echo "   ✗ kein RUNDIR"; (( FAILS+=1 )); continue; }
    wait_file "$rd/layout" 20 || { echo "   ✗ keine Layout-Datei"; (( FAILS+=1 )); continue; }
    chk "$(tr '\t' ' ' < "$rd/layout")" "${(j: :)f[3,6]}" "Layout (sw ah cols rows)"
    sleep 4   # tui_launch gibt window-size nach 3 s wieder frei
    chk "$(cmd_of qt)" "tmux" "Terminal hängt an der Arbeitssession"
    chk "$(t show-options -wqv -t '=work:update-all' window-size 2>/dev/null)" "" "window-size wieder freigegeben"
    chk "$(t display-message -p -t '=work:update-all' '#{window_width}x#{window_height}')" "${f[5]}x${f[6]}" "Fenster folgt dem Terminal"
    if [[ $esw != 0 ]]; then
      pw=$(t list-panes -t '=work:update-all' -F '#{pane_width}' | sed -n 1p)
      chk "$pw" "$esw" "Status-Pane-Breite nach dem Anhängen"
    else
      chk "$(t list-panes -t '=work:update-all' -F x | grep -c x)" "1" "nur das Log-Pane"
    fi
    wait_file "$rd/final" 60 || { echo "   ✗ kein final"; (( FAILS+=1 )); }
    sleep 1; t send-keys -t "$(t list-panes -t '=work:update-all' -F '#{pane_id}' | sed -n "$([[ $esw == 0 ]] && echo 1 || echo 2)p")" Enter; sleep 2
    chk "$(wins_of work)" "zsh " "nach Enter im Log-Pane: nur das work-Fenster übrig"
    chk "$(nrd)" "0" "kein RUNDIR mehr"
  done
  teardown

  say "R2: fertiger Lauf, Ansicht nicht geschlossen — der nächste Aufruf räumt ab und startet neu"
  setup
  first=$(t list-windows -t qt -F '#{window_index}' | head -1)
  t send-keys -t "qt:$first" "zsh $S --dry-run --only mas,php" Enter
  wait_rundir && wait_file "$rd/final" 60 || { echo "   ✗ erster Lauf nicht fertig"; (( FAILS+=1 )); }
  old=$rd; l0=$(lastlog); sleep 1.5
  t select-window -t "qt:$first"
  t send-keys -t "qt:$first" "zsh $S --dry-run --only mas,php" Enter; sleep 4
  t capture-pane -p -t "qt:$first" | grep -q 'Vorheriger Lauf ist fertig' && echo "   ✓ Meldung: Vorheriger Lauf ist fertig" \
    || { echo "   ✗ keine Abräum-Meldung"; (( FAILS+=1 )); }
  [[ ! -d $old ]] && echo "   ✓ altes RUNDIR entfernt" || { echo "   ✗ altes RUNDIR noch da"; (( FAILS+=1 )); }
  new=$(rundirs | head -1)
  [[ -n $new && $new != $old ]] && echo "   ✓ neuer Lauf gestartet" || { echo "   ✗ kein neuer Lauf"; (( FAILS+=1 )); }
  chk "$(wins_of qt)" "zsh update-all " "genau ein update-all-Fenster"
  wait_file "$new/final" 60
  [[ $(lastlog) != $l0 ]] && echo "   ✓ neues Laufprotokoll" || { echo "   ✗ kein neues Laufprotokoll"; (( FAILS+=1 )); }
  sleep 1; t send-keys -t "$(status_pane qt update-all)" q; sleep 2
  chk "$(nrd)" "0" "nach q: kein RUNDIR mehr"
  teardown

  for c in "92 26 1" "80 20 0"; do
    f=(${=c})
    say "R3 ${f[1]}x${f[2]}: Abschluss-Tafel passt ins Log-Pane$([[ ${f[3]} == 0 ]] && echo ', ohne Pfeile/^X')"
    teardown; t new-session -d -s qt -x ${f[1]} -y ${f[2]}; sleep 0.3
    t send-keys -t qt "zsh $S --dry-run --only mas,php" Enter
    wait_rundir && wait_file "$rd/final" 60 || { echo "   ✗ Lauf nicht fertig"; (( FAILS+=1 )); continue; }
    sleep 1.5
    out=$(t capture-pane -p -t qt:update-all.%1)
    [[ $out == *'Ansicht schließen'* ]] && echo "   ✓ Tafel sichtbar" || { echo "   ✗ Tafel nicht sichtbar"; (( FAILS+=1 )); }
    frame_ok qt:update-all.%1 "Rahmen"
    if [[ ${f[3]} == 0 ]]; then
      # Pfeile/^X stehen nur bei offenen Aktionen auf der Tafel — ohne welche wäre ein ✓ geschenkt
      # (die Gegenprobe gegen 3.3.2 bestand hier ebenfalls)
      if [[ $out == *Pfeile* || $out == *'^X'* ]]; then
        echo "   ✗ Tafel verspricht ein Aktionen-Pane, das es nicht gibt"; (( FAILS+=1 ))
      elif [[ $out == *'offene Aktion'* ]]; then
        echo "   ✓ keine Pfeile/^X ohne Aktionen-Pane, stattdessen --review"
      else
        echo "   · Pfeile/^X nicht prüfbar: der Dry-Run hat keine offenen Aktionen"
      fi
    fi
    t send-keys -t qt:update-all.%1 Enter; sleep 2
    chk "$(nrd)" "0" "nach Enter: kein RUNDIR mehr"
  done
  teardown

  say "R4: Lock belegt — kein Fenster, Meldung im aufrufenden Terminal, Exit 2"
  local LOCK=$UPDATE_ALL_CONFDIR/run.lock dpid   # Lock des Tests, nie der echte
  mkdir -p ${LOCK:h}
  # a) Halter ohne Ansicht (wie --plain/cron): Dummy-Prozess mit 'update-all' im Namen
  setup
  zsh -c 'exec -a update-all-dummy sleep 120' &!; dpid=$!; sleep 0.3
  print -rl -- $dpid "$(date '+%Y-%m-%d %H:%M:%S')" "test" > $LOCK
  # --only gibtsnicht: sollte die Sperre versagen, täte auch ein echter Lauf nichts
  t send-keys -t qt "zsh $S --only gibtsnicht -y; echo EXIT=\$?" Enter; sleep 3
  out=$(t capture-pane -p -t qt)
  [[ $out == *"läuft bereits (PID $dpid"* ]] && echo "   ✓ Meldung mit PID im Terminal" || { echo "   ✗ keine Meldung"; (( FAILS+=1 )); }
  [[ $out == *'ohne Ansicht'* ]] && echo "   ✓ Hinweis: ohne Ansicht, mitlesen per tail" || { echo "   ✗ kein tail-Hinweis"; (( FAILS+=1 )); }
  [[ $out == *EXIT=2* ]] && echo "   ✓ Exit 2" || { echo "   ✗ Exit nicht 2"; (( FAILS+=1 )); }
  chk "$(wins_of qt)" "zsh " "kein Fenster entstanden"
  chk "$(nrd)" "0" "kein RUNDIR"
  kill $dpid 2>/dev/null
  # b) Halter läuft in einem tmux-Pane einer anderen Session → hinspringen
  teardown; t new-session -d -s qt -x 160 -y 44
  t new-session -d -s work -x 160 -y 44 "exec -a update-all-dummy sleep 120"; sleep 0.5
  dpid=$(t list-panes -t '=work' -F '#{pane_pid}' | head -1)
  print -rl -- $dpid "$(date '+%Y-%m-%d %H:%M:%S')" "test" > $LOCK
  t send-keys -t qt "$OUTSIDE; zsh $S --only gibtsnicht -y; echo EXIT=\$?" Enter; sleep 3
  # kein exec-attach (danach folgt exit 2) — pane_current_command zeigt deshalb zsh; der
  # Client selbst wird über sein TTY gefunden
  chk "$(t list-clients -F '#{client_tty} #{session_name}' 2>/dev/null | grep -F "$(t display-message -p -t qt '#{pane_tty}') " | cut -d' ' -f2)" \
      "work" "Terminal springt zur Session des laufenden Laufs (attach)"
  chk "$(t list-windows -t '=work' -F x 2>/dev/null | grep -c x)" "1" "kein zusätzliches Fenster in work"
  chk "$(wins_of qt)" "zsh " "und keins in der aufrufenden Session"
  kill $dpid 2>/dev/null; sleep 1.5   # Halter weg → Session weg → Client endet → Exit 2
  [[ $(t capture-pane -p -t qt) == *EXIT=2* ]] && echo "   ✓ Exit 2 nach dem Zurückkehren" || { echo "   ✗ Exit nicht 2"; (( FAILS+=1 )); }
  rm -f $LOCK
  teardown

  local how cpid ll
  for how in detach hup; do
    say "R5 ($how): Verbindung bricht mitten im Lauf ab — der Lauf läuft weiter"
    setup
    t send-keys -t qt "$OUTSIDE; zsh $S --dry-run --only mas,php,node,python,editors,ai" Enter
    wait_rundir || { echo "   ✗ kein RUNDIR"; (( FAILS+=1 )); continue; }
    wait_phase "$rd" running 20; sleep 1
    chk "$(t list-clients -t '=update-all' -F x 2>/dev/null | grep -c x)" "1" "Terminal hängt am Lauf"
    if [[ $how == detach ]]; then
      t detach-client -s update-all 2>/dev/null
    else   # SSH-Abriss: sshd schließt das pty, der tmux-Client bekommt SIGHUP
      cpid=$(t list-clients -t '=update-all' -F '#{client_pid}' 2>/dev/null | head -1)
      [[ -n $cpid ]] && kill -HUP $cpid
    fi
    sleep 1
    chk "$(t list-clients -t '=update-all' -F x 2>/dev/null | grep -c x)" "0" "kein Client mehr an der Session"
    chk "$(phase $rd)" "running" "Lauf läuft ohne Client weiter"
    wait_file "$rd/final" 90 && echo "   ✓ Lauf bis zum Ende (final)" || { echo "   ✗ kein final (Phase $(phase $rd))"; (( FAILS+=1 )); }
    ll=$(lastlog)
    if [[ -n $ll ]] && ! grep -q 'Abgebrochen' "$ll"; then echo "   ✓ Log ohne Abbruch"; else echo "   ✗ Log meldet Abbruch oder fehlt"; (( FAILS+=1 )); fi
    chk "$(wins_of update-all)" "update-all " "Ansicht wartet auf die Rückkehr"
    sleep 1; t send-keys -t "$(status_pane update-all update-all)" q; sleep 2
    chk "$(nrd)" "0" "nach q: kein RUNDIR mehr"
    teardown
  done

  # R6 (ab 3.4.0): --resume über die TUI — der Weg Aufruf → args-Datei → Runner → resume_ids.
  # Untergeschobene Abbruch-Notiz (neuer als last/steps); der Dry-Run räumt sie nicht ab.
  say "R6: --resume über die TUI holt nur die Abschnitte aus der Abbruch-Notiz nach"
  setup
  print -rl -- $'macos\tmacOS\tok\t5\t0\t0' $'mas\tMac App Store\trunning\t0\t0\t0' $'php\tPHP\tpending\t0\t0\t0' > "$UPDATE_ALL_LOGDIR/resume-steps"
  touch "$UPDATE_ALL_LOGDIR/resume-steps"
  t send-keys -t qt "zsh $S --dry-run --resume" Enter
  if wait_rundir && wait_file "$rd/final" 60; then
    chk "$(cut -f1 "$rd/steps" | tr '\n' ' ')" "mas php " "nur die nachzuholenden Abschnitte"
    grep -q '^mode=.*resume: mas,php' "$rd/state" && echo "   ✓ Modus „resume: mas,php“ im Zustand" || { echo "   ✗ Modus fehlt im Zustand"; (( FAILS+=1 )); }
    sleep 1; t send-keys -t "$(status_pane qt update-all)" q; sleep 2
  else
    echo "   ✗ Resume-Lauf kam nicht bis final"; (( FAILS+=1 ))
  fi
  rm -f "$UPDATE_ALL_LOGDIR/resume-steps"
  chk "$(nrd)" "0" "kein RUNDIR mehr"
  teardown
}
# ── Start ─────────────────────────────────────────────────────────────────────
MODE=all N=1
while (( $# )); do
  case $1 in
    quit|review|layout|remote|all) MODE=$1 ;;
    -n) N=$2; shift ;;
    -h|--help) sed -n '2,/^# Fallen/p' "${0:A}" | sed 's/^# \{0,1\}//' | sed '$d'; exit 0 ;;
    *) echo "Unbekannt: $1 (quit|review|layout|remote|all, -n N)"; exit 2 ;;
  esac; shift
done
if (( $(nproc_) )); then
  echo "Es laufen update-all-Prozesse — Test nicht gestartet (er würde sie beim Aufräumen treffen):"; procs | cut -c1-120 | sed 's/^/   /'; exit 2
fi
echo "update-all-tuitest — Server: tmux -L $SOCK · Logs: $UPDATE_ALL_LOGDIR · $(zsh "$S" -V)"
[[ $MODE == (quit|all) ]] && suite_quit "$N"
[[ $MODE == (review|all) ]] && suite_review
[[ $MODE == (layout|all) ]] && suite_layout
[[ $MODE == (remote|all) ]] && suite_remote
teardown
echo
if (( FAILS )); then echo "✗ $FAILS Prüfung(en) fehlgeschlagen"; exit 1; else echo "✓ alle Prüfungen bestanden"; exit 0; fi
