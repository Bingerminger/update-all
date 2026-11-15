#!/usr/bin/env zsh
# ╔══════════════════════════════════════════════════════════════╗
# ║    update-all.sh — diesen Mac aus dem Terminal aktuell halten ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Standard ist eine tmux-TUI mit drei Panes: links Status/Fortschritt/KPIs,
# rechts oben das Live-Log, rechts unten die Aktionen (Dinge, die im Nachgang
# zu entscheiden oder zu beheben sind — nach dem Lauf interaktiv via fzf).
# Außerhalb von tmux landet das Fenster in deiner Arbeitssession (prefs
# tmux_session) oder einer eigenen Session "update-all"; bricht die SSH-Verbindung
# ab, läuft das Update darin weiter (`tmux attach`).
#
# Optionen:
#   -g, --greedy     Buchführungs-Abgleich: auch Self-Updater-Casks nachziehen, deren
#                    App schon aktuell ist und nur brews Stand hinkt (lädt die aktuelle
#                    Version einmal neu). Ohne -g hebt brew Self-Updater-Apps nur, wenn
#                    die App wirklich hinterherhinkt — nie die Ausschlussliste (prefs
#                    cask_exclude=…, Standard parallels,parallels-toolbox), nie Major-Sprünge
#   -y, --yes        Keine Rückfragen, Antwort ja (TeX Live läuft mit, Akku-Check
#                    übergangen); ohne Terminal (launchd/Pipe) bleibt es bei nein
#   -m, --models     Ollama-Modelle aktualisieren (kann mehrere GB laden)
#       --apps       Manuell installierte Apps per MacUpdater-CLI aktualisieren
#                    (Standard: nur melden)
#       --docker     Docker-Images mit Floating-Tags (latest/main/…) neu ziehen
#       --askpass    Admin-Passwort EINMAL abfragen und allen sudo-Aufrufen des
#                    Laufs bereitstellen (SUDO_ASKPASS) — per SSH automatisch
#       --notify URL Fazit per ntfy schicken (https://ntfy.sh/<topic> oder eigener
#                    Server; dauerhaft: notify=URL in ~/.config/update-all/prefs)
#       --no-macos   macOS-Systemupdates überspringen
#       --only a,b   Nur diese Abschnitte (IDs siehe --list)
#       --skip a,b   Diese Abschnitte auslassen
#       --resume     Nur nachholen, was zuletzt nicht fertig wurde: nach einem Abbruch die
#                    unfertigen Abschnitte, sonst die fehlgeschlagenen des letzten Laufs
#       --plain      Klassische Inline-Ausgabe, keine tmux-TUI
#       --check      Nur zeigen, was anstünde — nichts installieren, kein sudo
#       --review     TUI für den letzten Lauf öffnen (Log + offene Aktionen)
#       --history    Tabelle der letzten Läufe
#       --list       Abschnitte mit IDs zeigen (was auf diesem Mac aktiv ist)
#       --dry-run    Alles simulieren — zum Ausprobieren der TUI
#       --selftest   Ausgabe-Layer prüfen (run/stream/fail/scan/box), ohne System-Änderung
#       --tmuxinator Projektdatei ~/.config/tmuxinator/update-all.yml schreiben
#                    (danach: tmuxinator start update-all)
#   -V, --version    Version zeigen
#   -h, --help       Diese Hilfe
#
# Umgebung:
#   NO_COLOR         Farbausgabe aus · CLICOLOR_FORCE   Farben erzwingen
#   UPDATE_ALL_LOGDIR  Log-Verzeichnis umbiegen (nur für Tests: update-all-tuitest.zsh
#                    hält so runs/, last/ und history.tsv des echten Laufs sauber)
#   UPDATE_ALL_CONFDIR Konfigurationsverzeichnis umbiegen (nur für Tests: eigene prefs,
#                    eigener run.lock — der echte Lauf und seine Einstellungen bleiben unberührt)
#
# Dateien:
#   ~/Library/Logs/update-all.log            Gesamtprotokoll (farbcodefrei)
#   ~/Library/Logs/update-all/runs/*.log     Ein Log je Lauf
#   ~/Library/Logs/update-all/history.tsv    Kennzahlen je Lauf (--history)
#   ~/Library/Logs/update-all/last/          Zustand des letzten Laufs (--review)
#   ~/.config/update-all/acks                Als erledigt markierte Aktionen
#   ~/.config/update-all/prefs               Gemerkte Antworten und Listen:
#                                              texlive=always|never · notify=URL
#                                              cask_exclude=a,b   (nie per brew heben; Muster erlaubt)
#                                              major_block=a,b    (Major-Sprünge dieser Self-Updater
#                                                                  sperren — Bezahl-Upgrades; Muster
#                                                                  erlaubt; Standard geekbench*)
#                                              never_quit=a,b     (diese Casks nie über eine laufende
#                                                                  App hinweg heben; Muster erlaubt)
#                                              adopt_ignore=a,b   (nie als Cask vorschlagen; Muster gegen
#                                                                  Cask-Namen ODER Bundle-ID, z. B.
#                                                                  parallels,com.example.*)
#                                              npm_cache=always|never (npm-Cache ab 3 GB leeren; mit -y
#                                                                  ohne Nachfrage)
#                                              tmux_session=NAME  (Fenster dort öffnen, wenn die Session
#                                                                  läuft; Standard: keine → eigene Session)
#                                              worktree_roots=a,b (wo Agent-Worktrees gesucht werden:
#                                                                  <dir>/*/.claude/worktrees; Standard
#                                                                  ~/Code,~/Developer,~/Projects,~/src)
#                                              ollama_agent=LABEL (eigener LaunchAgent für Ollama: nach
#                                                                  einem Cask-Upgrade neu starten, den
#                                                                  App-Login-Eintrag stilllegen)
#                                              layout=auto|wide|compact (Pane-Größen; auto richtet
#                                                                  sich nach der Fenstergröße)
#   ~/.config/update-all/Brewfile            Snapshot nach jedem Lauf
#   ~/.config/update-all/run.lock            Läuft gerade ein Lauf? (PID; --check/--dry-run nehmen ihn nicht)
#
# Rückfragen (z. B. TeX Live): j/n gelten einmal, i = immer, x = nie (→ prefs).
# Mit -y lautet die Antwort ja; ohne Terminal wird nicht gefragt: gemerkte Antwort, sonst nein.
# Jeder Befehl läuft unter einem Timeout (2 h) — nichts hängt.
#
# tmux: In tmux öffnet sich ein Fenster "update-all" in der aktuellen Session. Außerhalb
# wird es in der Session aus prefs tmux_session geöffnet, falls eine eingetragen ist und
# läuft — sonst in einer eigenen Session "update-all". Läuft schon eins, springt der
# Aufruf dorthin statt doppelt zu starten.
#
# Exit: 0 = alles ok (oder --check) · 1 = mindestens ein Schritt fehlgeschlagen
#       2 = Lauf abgebrochen (kein Netz, Akku, ^C) oder es läuft schon einer
#
# Admin-Rechte — warum es früher mehrfach fragte:
#   Homebrews brew.sh ruft bei JEDEM Start `sudo --reset-timestamp` auf
#   ("Reset sudo timestamp to avoid running unauthorized sudo commands").
#   Das Ticket aus einem `sudo -v` am Anfang war nach `brew update` also weg,
#   der Keep-Alive lief ins Leere, und jeder Cask mit pkg-Installer fragte neu.
#   Deshalb zwei Modi:
#     askpass — Passwort einmal lesen, per SUDO_ASKPASS-Helper bereitstellen.
#               Homebrew erkennt SUDO_ASKPASS und ruft sudo mit -A auf; im
#               ganzen Lauf kommt keine weitere Abfrage. Standard per SSH.
#     touchid — lokal: KEINE Vorab-Abfrage (wäre nach brew sofort wieder weg).
#               sudo fragt erst, wenn es nötig ist; die Abschnittsreihenfolge
#               hält alle sudo-Schritte beisammen (brew upgrade → tlmgr), damit
#               es bei höchstens einer Abfrage bleibt. Der Preflight sagt vorher,
#               ob eine kommt.

setopt EXTENDED_GLOB NULL_GLOB
zmodload zsh/datetime

# Versionierung: MAJOR bei neuem Bedienkonzept (3 = tmux-TUI), MINOR bei neuen
# Abschnitten/Schaltern, PATCH bei Fixes. Steht im Banner, im Status-Pane,
# in history.tsv und hinter --version.
VERSION="3.4.1"

# ── Guards ──────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] && { echo "❌  Nicht als root ausführen."; exit 1; }

SELF=${0:A}
LOGDIR=${UPDATE_ALL_LOGDIR:-$HOME/Library/Logs/update-all}   # Tests biegen das um (update-all-tuitest.zsh)
LOGFILE="$LOGDIR.log"                                       # …/update-all.log
CONFDIR=${UPDATE_ALL_CONFDIR:-$HOME/.config/update-all}      # Tests biegen das um (eigene prefs/Lock)
MSUPDATE="/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app/Contents/MacOS/msupdate"
MACUPDATER="/Applications/MacUpdater.app/Contents/Resources/macupdater_client"

# ── Optionen ────────────────────────────────────────────────────
GREEDY=0 ASSUME_YES=0 NO_MACOS=0 UPDATE_MODELS=0 CHECK_ONLY=0 DRY_RUN=0
APPS=0 DOCKER=0 ASKPASS=0 PLAIN=0 RESUME=0 MODE=run
ONLY="" SKIP="" NOTIFY_URL=""
INTERNAL="" RUNDIR=""

usage() { sed -n '2,/^# Exit:/p' "$SELF" | sed 's/^# \{0,1\}//'; }

parse_args() {
  while (( $# )); do
    case "$1" in
      -g|--greedy)   GREEDY=1 ;;
      -y|--yes)      ASSUME_YES=1 ;;
      -m|--models)   UPDATE_MODELS=1 ;;
      --apps)        APPS=1 ;;
      --docker)      DOCKER=1 ;;
      --askpass)     ASKPASS=1 ;;
      --notify)      NOTIFY_URL="$2"; shift ;;
      --notify=*)    NOTIFY_URL="${1#*=}" ;;
      --no-macos)    NO_MACOS=1 ;;
      --only)        ONLY="$2"; shift ;;
      --only=*)      ONLY="${1#*=}" ;;
      --skip)        SKIP="$2"; shift ;;
      --skip=*)      SKIP="${1#*=}" ;;
      --plain)       PLAIN=1 ;;
      --resume)      RESUME=1 ;;
      --check)       CHECK_ONLY=1; PLAIN=1 ;;
      --dry-run)     DRY_RUN=1 ;;
      --selftest)    MODE=selftest ;;
      --tmuxinator)  MODE=tmuxinator ;;
      -V|--version)  echo "update-all.sh $VERSION"; exit 0 ;;
      --review)      MODE=review ;;
      --history)     MODE=history ;;
      --list)        MODE=list ;;
      -h|--help)     usage; exit 0 ;;
      --_runner|--_status|--_actions|--_pane-log)
                     INTERNAL="${1#--_}"; RUNDIR="$2"; shift ;;
      --_action-list|--_action-fix|--_action-ack)
                     INTERNAL="${1#--_}"; RUNDIR="$2"; ACTION_ID="${3:-}"; shift; (( $# > 1 )) && shift ;;
      *)             echo "Unbekannte Option: $1"; usage; exit 1 ;;
    esac
    shift
  done
}
parse_args "$@"

# Der Runner in der TUI bekommt die Original-Argumente über eine Datei
if [[ $INTERNAL == runner && -s "$RUNDIR/args" ]]; then
  parse_args "${(@f)$(<"$RUNDIR/args")}"
fi

# ── Terminal & Farben ───────────────────────────────────────────
HAS_TTY=0; [[ -t 1 ]] && HAS_TTY=1
USE_COLOR=$HAS_TTY
[[ -n "$CLICOLOR_FORCE" && "$CLICOLOR_FORCE" != "0" ]] && USE_COLOR=1
[[ -n "$NO_COLOR" || "$TERM" == "dumb" ]] && USE_COLOR=0
if (( USE_COLOR )); then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[0;31m'; GREEN=$'\033[0;32m'
  YELLOW=$'\033[1;33m'; MAGENTA=$'\033[0;35m'; CYAN=$'\033[0;36m'; BLUE=$'\033[0;34m'; NC=$'\033[0m'
else
  BOLD=''; DIM=''; RED=''; GREEN=''; YELLOW=''; MAGENTA=''; CYAN=''; BLUE=''; NC=''
fi
ESC=$'\033'

# ── Kleine Helfer ───────────────────────────────────────────────
has()   { command -v "$1" &>/dev/null; }
vlen()  { local s="${1//$ESC\[[0-9;]#[mK]/}"; print -rn -- ${#s}; }   # sichtbare Länge
fmt_dur() {
  local s=$1
  if   (( s >= 3600 )); then print -r -- "$((s/3600))h $(( (s%3600)/60 ))m"
  elif (( s >= 60 ));   then print -r -- "$((s/60))m $((s%60))s"
  elif (( s >= 1 ));    then print -r -- "${s}s"
  else                       print -r -- "<1s"; fi
}
fmt_age() {  # Sekunden → "vor 23 h" / "vor 3 d"
  local s=$1
  if   (( s < 3600 ));   then print -r -- "vor $((s/60)) min"
  elif (( s < 172800 )); then print -r -- "vor $((s/3600)) h"
  else                        print -r -- "vor $((s/86400)) d"; fi
}
# eta_left [rundir] — geschätzte Restdauer in Sekunden aus den Abschnittsdauern des letzten
# Laufs (prev-steps, beim Start aus last/ kopiert): offene Abschnitte voll, der laufende
# abzüglich seiner bisherigen Zeit. Ohne Vergleichslauf: nichts. Grob — Homebrew schwankt
# zwischen 30 s und über 3 min, je nach Paketzahl; reicht aber für „wann komme ich wieder“.
eta_left() {
  local d=${1:-$RUNDIR} line rem=0 run_el; local -a f; local -A prev
  [[ -s $d/prev-steps && -s $d/steps ]] || return 1
  while IFS= read -r line; do f=("${(@s:	:)line}"); [[ ${f[1]} == [a-z]## && ${f[4]} == <-> ]] && prev[${f[1]}]=${f[4]}; done < "$d/prev-steps"
  run_el=$(( EPOCHSECONDS - ${ST[section_t0]:-$EPOCHSECONDS} ))
  while IFS= read -r line; do
    f=("${(@s:	:)line}"); [[ ${f[1]} == [a-z]## ]] || continue
    # Fehlt einem offenen Abschnitt der Vergleichswert (letzter Lauf war z. B. --only texlive),
    # lieber keine Schätzung als eine viel zu kleine
    [[ ${f[3]} == (pending|running) && -z ${prev[${f[1]}]} ]] && return 1
    case ${f[3]} in
      pending) rem=$(( rem + ${prev[${f[1]}]:-0} )) ;;
      running) (( ${prev[${f[1]}]:-0} > run_el )) && rem=$(( rem + ${prev[${f[1]}]:-0} - run_el )) ;;
    esac
  done < "$d/steps"
  print -r -- $rem
}
fmt_eta() {   # Sekunden → „noch ca. 3 min“ / „noch < 1 min“; 0 oder leer → nichts
  local s=$1; [[ $s == <-> ]] && (( s > 0 )) || return 0
  if (( s < 60 )); then print -r -- "noch < 1 min"; else print -r -- "noch ca. $(( (s + 59) / 60 )) min"; fi
}
count_lines() { print -rn -- "$1" | grep -c .; }
# vercmp A B → 0 gleich · 1 A>B · 2 A<B (numerische Segmente)
vercmp() {
  local -a a b; local i x y
  a=(${(s:.:)${${1%%,*}//[^0-9.]/}}); b=(${(s:.:)${${2%%,*}//[^0-9.]/}})
  for (( i=1; i <= (${#a} > ${#b} ? ${#a} : ${#b}); i++ )); do
    x=${a[i]:-0}; y=${b[i]:-0}
    (( x > y )) && return 1; (( x < y )) && return 2
  done
  return 0
}

# ═════════════════════════════════════════════════════════════════
# Abschnittsregister — nur, was auf diesem Mac vorhanden ist
# ═════════════════════════════════════════════════════════════════
typeset -A SEC_NAME; typeset -a SEC_ORDER MISSING
reg() { SEC_ORDER+=("$1"); SEC_NAME[$1]="$2"; }
OFFICE_APPS=( /Applications/Microsoft\ (Word|Excel|PowerPoint|Outlook|OneNote|Teams).app(N) )

build_registry() {
  (( ! NO_MACOS ))          && reg macos    "macOS Softwareupdate"
  has brew                  && reg brew     "Homebrew"
  has tlmgr                 && reg texlive  "TeX Live — tlmgr"           || MISSING+=(tlmgr)
  has mas                   && reg mas      "Mac App Store"              || MISSING+=(mas)
  (( ${#OFFICE_APPS} ))     && reg office   "Microsoft Office — brew, MAU still"
  { has npm || has bun || has pnpm; } && reg node "Node.js — npm/bun/pnpm/yarn"
  { has pipx || has uv; }   && reg python   "Python — pipx/uv"
  has rustup                && reg rust     "Rust — rustup/cargo"        || MISSING+=(rustup)
  has composer              && reg php      "PHP — Composer (global)"
  { has mise || has asdf; } && reg runtimes "Runtime-Manager — mise/asdf" || MISSING+=(mise asdf)
  { has gcloud || has helm || has gh; } && reg cloud "Cloud & DevOps — gcloud/helm/gh"
  has gcloud || MISSING+=(gcloud); has helm || MISSING+=(helm)
  { [[ -f "$HOME/.oh-my-zsh/tools/upgrade.sh" || -f "$HOME/.zinit/bin/zinit.zsh" ]]; } \
                            && reg shell    "Shell — Oh My Zsh/zinit"    || MISSING+=(oh-my-zsh zinit)
  has code                  && reg editors  "Editoren — VS Code Extensions"
  { has tldr || has claude || has opencode || has pi; } && reg ai "AI-CLIs & tldr"
  (( UPDATE_MODELS )) && has ollama && reg ollama "Ollama — Modelle"
  (( DOCKER ))        && has docker && reg docker "Docker — Images"
  reg apps    "Apps-Radar — MacUpdater/Sparkle"
  (( CHECK_ONLY )) || reg cleanup "Aufräumen & Snapshot"

  local -a keep; local id
  (( RESUME )) && ONLY=$(resume_ids)   # leer fängt der Aufrufer vorher ab („nichts nachzuholen“)
  if [[ -n $ONLY ]]; then
    for id in "${SEC_ORDER[@]}"; do [[ ",$ONLY," == *",$id,"* ]] && keep+=("$id"); done
    SEC_ORDER=("${keep[@]}")
  fi
  if [[ -n $SKIP ]]; then
    keep=()
    for id in "${SEC_ORDER[@]}"; do [[ ",$SKIP," == *",$id,"* ]] || keep+=("$id"); done
    SEC_ORDER=("${keep[@]}")
  fi
}

# ═════════════════════════════════════════════════════════════════
# resume_ids [logdir] — Abschnitte für --resume, kommagetrennt. Nach einem Abbruch (abort_run
# legt resume-steps ab) alles, was nicht ok wurde; sonst die fehlgeschlagenen des letzten
# vollständigen Laufs. resume-steps gilt nur, wenn es neuer ist als last/steps.
resume_ids() {
  local d=${1:-$LOGDIR} f src="" line; local -a ids parts
  if [[ -s $d/resume-steps && ( ! -e $d/last/steps || $d/resume-steps -nt $d/last/steps ) ]]; then
    src=$d/resume-steps
    while IFS= read -r line; do parts=("${(@s:	:)line}"); [[ ${parts[1]} == [a-z]## && ${parts[3]} != (ok|skip) ]] && ids+=(${parts[1]}); done < "$src"
  elif [[ -s $d/last/steps ]]; then
    while IFS= read -r line; do parts=("${(@s:	:)line}"); [[ ${parts[1]} == [a-z]## && ${parts[3]} == fail ]] && ids+=(${parts[1]}); done < "$d/last/steps"
  fi
  print -r -- "${(j:,:)ids}"
}

# Zustand für die TUI: state (Key=Value), steps (TSV), actions (TSV),
# heartbeat (letzte Ausgabezeile) — alle in $RUNDIR
# ═════════════════════════════════════════════════════════════════
typeset -A ST
typeset -a S_ID S_NAME S_STATUS S_DUR S_ERRS S_WARN
st()       { ST[$1]="$2"; }
# Die Flush-Funktionen schreiben nur, solange $RUNDIR existiert — ein anderes Pane
# kann die Ansicht (und damit das Verzeichnis) bereits geschlossen haben.
st_flush() {
  local k; [[ -d $RUNDIR ]] || return 0
  { for k in "${(k)ST[@]}"; do print -r -- "$k=${ST[$k]}"; done } > "$RUNDIR/state.tmp" \
    && mv -f "$RUNDIR/state.tmp" "$RUNDIR/state"
}
steps_flush() {
  local i; [[ -d $RUNDIR ]] || return 0
  # Feld 6 (Warnungen je Abschnitt) kam mit 3.3.0 dazu — ältere last/steps haben fünf Felder,
  # das Status-Pane liest deshalb ${f[6]:-0}
  { for (( i=1; i <= ${#S_ID}; i++ )); do
      print -r -- "${S_ID[i]}	${S_NAME[i]}	${S_STATUS[i]}	${S_DUR[i]}	${S_ERRS[i]}	${S_WARN[i]:-0}"
    done } > "$RUNDIR/steps.tmp" && mv -f "$RUNDIR/steps.tmp" "$RUNDIR/steps"
}
load_state() {   # liest $1/state in ST
  ST=(); local line
  [[ -f "$1/state" ]] || return 1
  while IFS= read -r line; do ST[${line%%=*}]="${line#*=}"; done < "$1/state"
}

# action <err|warn|info> <quelle> <titel> [fix-befehl] [detail]
# → Aktionen-Pane; Details in actions.d/<id>.txt; gleiche Aktion wird gebündelt
# Bekannte Hinweise: eine INFO mit derselben ID wie im letzten Lauf (gleiche Quelle, gleicher
# Titel — ändert sich der Titel, gilt sie als neu) landet zusätzlich in $RUNDIR/known. Sie
# bleibt in actions, damit sie im nächsten Lauf wieder als bekannt gilt und --review sie
# zeigt, zählt aber nicht als offen: Aktionen-Pane, Fazit, Tafel und ntfy lassen sie weg.
# Warnungen und Fehler sind nie „bekannt“. Bis 3.3.4 stand jeder unveränderte Hinweis in
# jedem Lauf wieder als offen da, bis man ihn per ^A quittierte (z. B. „uv cache prune
# wartet auf laufende uvx-Prozesse“ in 33 von 40 Läufen eines Monats).
ACTIONS_N=0 ACTION_LAST_ID="" ACTION_LAST_NEW=0
action() {
  local sev=$1 src=$2 title=$3 fix=${4:-} detail=${5:-} id
  [[ -d $RUNDIR ]] || return 0   # Ansicht schon geschlossen — Verzeichnis nicht wiederbeleben
  # Tabs/Zeilenumbrüche raus: die Zeile ist TSV, und Spalte 5 wird per ^X ausgeführt —
  # ein Tab in einem Titel aus Fremddaten (Sparkle-Feed) würde sonst zum Fix-Befehl
  title=${title//[$'\t\n\r']/ }; fix=${fix//[$'\t\n\r']/ }; src=${src//[$'\t\n\r']/ }
  id=$(print -rn -- "$src|$title" | md5 -q)
  mkdir -p "$RUNDIR/actions.d"
  ACTION_LAST_ID=$id; ACTION_LAST_NEW=0
  if ! grep -q "^$id	" "$RUNDIR/actions" 2>/dev/null; then
    print -r -- "$id	$sev	$src	$title	$fix" >> "$RUNDIR/actions"
    ACTION_LAST_NEW=1
    if [[ $sev == info ]] && grep -q "^$id	info	" "$LOGDIR/last/actions" 2>/dev/null; then
      print -r -- "$id" >> "$RUNDIR/known"
    else
      (( ACTIONS_N+=1 )); st actions $ACTIONS_N; st_flush
    fi
    { print -r -- "$title"; print -r -- "Quelle: $src"; [[ -n $fix ]] && print -r -- "Fix:    $fix"; print; } > "$RUNDIR/actions.d/$id.txt"
  fi
  [[ -n $detail ]] && print -r -- "$detail" >> "$RUNDIR/actions.d/$id.txt"
  return 0
}
# shq <wort…> — Befehlszeile für Menschen lesbar UND für 'zsh -lc' korrekt: nur Wörter
# mit Sonderzeichen werden gequotet (Fix-Befehle aus fail(), Pfade mit Leerzeichen)
shq() {
  local w out=""
  for w in "$@"; do
    if [[ $w == *[^A-Za-z0-9_./=:@%+,-]* ]]; then out+="${(qq)w} "; else out+="$w "; fi
  done
  print -rn -- "${out% }"
}

# ═════════════════════════════════════════════════════════════════
# Ausgabe-Layer des Runners
# ═════════════════════════════════════════════════════════════════
ERRORS=0 WARNINGS=0 SKIPPED=0 REBOOT_NEEDED=0 STEP=0 CMD_N=0
SECTION_ID="" SECTION_NAME="" SECTION_T0=0 SECTION_E0=0 SECTION_W0=0 SECTION_RUNS=0
FAILED_CMDS=() LAST_OUT=""
PKG_BREW=0 PKG_MAS=0 PKG_OTHER=0

hr()    { echo "${DIM}  ────────────────────────────────────────────────────${NC}"; }
info()  { echo "  ${CYAN}·${NC}  $1"; }
ok()    { echo "  ${GREEN}✓${NC}  $1"; (( SECTION_RUNS+=1 )); }
skip()  { echo "  ${DIM}◦  $1 — nicht installiert${NC}"; (( SKIPPED+=1 )); }
warn()  { echo "  ${YELLOW}⚠${NC}  $1"; (( WARNINGS+=1 )); (( SECTION_RUNS+=1 )); st warnings $WARNINGS; st_flush; }
bullets() { /usr/bin/sed "s/^/       ${DIM}•${NC} /"; }
settitle() { (( HAS_TTY )) && print -n "\e]0;$1\a" 2>/dev/null > /dev/tty; return 0; }

fail() {   # <befehl> <detail> [ausgabedatei]
  echo "     ${RED}└ ✗ Fehlgeschlagen${2:+ ($2)} — Lauf wird fortgesetzt${NC}"
  (( ERRORS+=1 )); st errors $ERRORS; st_flush
  FAILED_CMDS+=("${1}${2:+ — $2}")
  local detail=""
  if [[ -n ${3:-} && -s "$3" ]]; then
    detail=$(grep -E 'Error|error:|fatal|failed|Failed' "$3" | tail -12)
    [[ -z $detail ]] && detail=$(tail -12 "$3")
  fi
  # Fix-Befehl ohne den askpass-Kontext des Laufs: ^X läuft interaktiv, da fragt sudo selbst
  local fixcmd=$1; fixcmd=${fixcmd//sudo -A /sudo }; fixcmd=${fixcmd// --user $USER --stdinpass/}
  action err "$SECTION_NAME" "Fehlgeschlagen: ${1[1,70]}" "$fixcmd" "$detail"
}

# Letzten Fehlschlag zurücknehmen (wenn ein Abschnitt ihn als erwartbar einstuft).
# Entfernt nur die Aktion, die fail() gerade NEU angelegt hat — war sie ein
# Duplikat, bliebe sonst eine fremde Zeile auf der Strecke.
undo_last_fail() {
  (( ERRORS > 0 )) && (( ERRORS-=1 )); FAILED_CMDS[-1]=()
  if (( ACTION_LAST_NEW )) && [[ -n $ACTION_LAST_ID && -s "$RUNDIR/actions" ]]; then
    /usr/bin/sed -i '' "/^$ACTION_LAST_ID	/d" "$RUNDIR/actions"; rm -f "$RUNDIR/actions.d/$ACTION_LAST_ID.txt"
    (( ACTIONS_N > 0 )) && (( ACTIONS_N-=1 )); ACTION_LAST_NEW=0
  fi
  st errors $ERRORS; st actions $ACTIONS_N; st_flush
}

_close_section() {
  [[ -z "$SECTION_ID" ]] && return 0
  local i dur=$(( SECONDS - SECTION_T0 )) errs=$(( ERRORS - SECTION_E0 )) warns=$(( WARNINGS - SECTION_W0 ))
  for (( i=1; i <= ${#S_ID}; i++ )); do
    [[ ${S_ID[i]} == $SECTION_ID ]] || continue
    S_DUR[i]=$dur; S_ERRS[i]=$errs; S_WARN[i]=$warns
    if (( errs > 0 )); then S_STATUS[i]=fail
    elif (( SECTION_RUNS == 0 )); then S_STATUS[i]=skip
    else S_STATUS[i]=ok; fi
  done
  steps_flush
  SECTION_ID=""
}

section() {   # <id>
  _close_section
  (( STEP+=1 ))
  SECTION_ID=$1; SECTION_NAME=${SEC_NAME[$1]}
  SECTION_T0=$SECONDS; SECTION_E0=$ERRORS; SECTION_W0=$WARNINGS; SECTION_RUNS=0
  local i
  for (( i=1; i <= ${#S_ID}; i++ )); do [[ ${S_ID[i]} == $1 ]] && S_STATUS[i]=running; done
  steps_flush
  st step $STEP; st section "$SECTION_NAME"; st section_t0 $EPOCHSECONDS; st cmd ""; st_flush
  # Im Kompaktlayout (iPhone) ist der Pane-Rand die einzige Daueranzeige — die Restzeit
  # steht deshalb auch dort (Stand: Beginn des Abschnitts)
  local eta; eta=$(fmt_eta "$(eta_left)")
  settitle "update-all · $STEP/${#SEC_ORDER} · $SECTION_NAME${eta:+ · $eta}"
  echo "\n${CYAN}${BOLD}  ▍ $STEP/${#SEC_ORDER} · $SECTION_NAME${NC}"
  hr
}

# stream <datei> — Tool-Ausgabe einrücken, mitschreiben, Heartbeat setzen
stream() {
  local line last=0
  while IFS= read -r line || [[ -n $line ]]; do
    print -r -- "     ${DIM}│${NC} $line"
    print -r -- "$line" >> "$1"
    if (( EPOCHSECONDS != last )); then
      last=$EPOCHSECONDS
      print -r -- "$last	${line[1,100]}" > "$RUNDIR/heartbeat"
    fi
  done
}

# run <cmd…> — ausführen, Ausgabe live einrücken, Dauer messen, Ausgabe
# nach Auffälligkeiten scannen. Fehler werden gesammelt, brechen nicht ab.
# Fehlererkennung hängt an zshs $pipestatus — direkt nach der Pipe lesen!
# Jeder Befehl läuft unter einem Alarm-Timeout (perl: alarm überlebt exec),
# damit ein hängendes Tool (mas, Installer-Dialoge) nie den ganzen Lauf blockiert.
DEFAULT_TIMEOUT=7200   # Sicherheitsnetz je Befehl: 2 h
RUN_TIMEOUT=""         # run_t setzt es für einen Befehl
# Muster für Netzfehler in Tool-Ausgaben (curl, brew, npm, pip, git) — bewusst eng
NET_ERR_RE='Could not resolve host|Failed to connect to|Connection (timed out|reset by peer|refused)|Operation timed out|[Nn]etwork is (unreachable|down)|curl: \((6|7|28|35|52|56)\)|ETIMEDOUT|ECONNRESET|EAI_AGAIN|ENOTFOUND|Temporary failure in name resolution|TLS handshake timeout'
RETRY_DELAY=${RETRY_DELAY:-15}
run() {
  local t0=$SECONDS rc dt out to=${RUN_TIMEOUT:-$DEFAULT_TIMEOUT}; local -a cmd; cmd=("$@")
  (( SECTION_RUNS+=1 )); (( CMD_N+=1 ))
  out="$RUNDIR/out/$CMD_N.txt"; : > "$out"; LAST_OUT="$out"
  echo "  ${MAGENTA}▶${NC}  ${BOLD}$*${NC}${RUN_TIMEOUT:+ ${DIM}· Timeout $(fmt_dur $RUN_TIMEOUT)${NC}}"
  st cmd "$*"; st_flush
  if (( CHECK_ONLY )); then
    echo "     ${DIM}└ ▷ nur Anzeige — nicht ausgeführt${NC}"; return 0
  fi
  if (( DRY_RUN )); then
    sleep 0.6; print -r -- "(dry-run) $*" > "$out"
    echo "     ${DIM}│ (dry-run — nichts ausgeführt)${NC}"
    echo "     ${DIM}└ ${GREEN}✓${NC}${DIM} simuliert${NC}"; return 0
  fi
  [[ -x /usr/bin/perl ]] && cmd=(/usr/bin/perl -e 'alarm shift @ARGV; exec @ARGV' "$to" "$@")
  "${cmd[@]}" 2>&1 | stream "$out"
  rc=${pipestatus[1]}
  dt=$(( SECONDS - t0 ))
  scan_output "$out" "$*"
  # Netzfehler bekommen einen zweiten Versuch (einmal, nach RETRY_DELAY s): ein Funkloch oder
  # ein kurz nicht erreichbarer Spiegel soll nicht den ganzen Abschnitt kosten. Timeouts (142)
  # nicht — die hängen, ein zweiter Versuch hinge genauso.
  if (( rc != 0 && rc != 142 && ! ${RUN_RETRIED:-0} )) && grep -qiE "$NET_ERR_RE" "$out" 2>/dev/null; then
    echo "     ${YELLOW}↻${NC}  Netzfehler (Exit $rc) — zweiter Versuch in ${RETRY_DELAY}s"
    sleep $RETRY_DELAY
    RUN_RETRIED=1 run "$@"; return $?
  fi
  # fail() bekommt die Befehlszeile gequotet (shq): sie wird per ^X wieder ausgeführt
  if (( rc == 142 )); then fail "$(shq "$@")" "Timeout nach $(fmt_dur $to) — abgebrochen" "$out"; return $rc; fi
  if (( rc != 0 )); then fail "$(shq "$@")" "Exit $rc · $(fmt_dur $dt)" "$out"; return $rc; fi
  echo "     ${DIM}└ ${GREEN}✓${NC}${DIM} $(fmt_dur $dt)${NC}"
  return 0
}
# run_t <sekunden> <cmd…> — wie run, mit eigenem Timeout (für Tools, die gern hängen)
run_t() { RUN_TIMEOUT=$1; shift; run "$@"; local rc=$?; RUN_TIMEOUT=""; return $rc; }
# capture_t <sekunden> <cmd…> — Ausgabe einfangen (für Substitutionen), ebenfalls mit
# Alarm-Timeout: 'mas outdated' oder 'tlmgr --list' hängen sonst genauso wie ihre Updates.
# Ohne Prüfung des Rückgabecodes liest sich eine leere Ausgabe nach dem Timeout wie
# „nichts zu tun": ein hängendes Tool sah bis 3.2.4 aus wie ein grüner Lauf („Alle
# Formulae & Casks aktuell", „TeX Live aktuell — nichts zu tun").
capture_t() {
  local to=$1; shift
  if [[ -x /usr/bin/perl ]]; then /usr/bin/perl -e 'alarm shift @ARGV; exec @ARGV' "$to" "$@"; else "$@"; fi
}
# capture_ok <rc> <beschreibung> — 0 = Ergebnis brauchbar, 1 = Zeitlimit gerissen
# (dann NICHT entwarnen). Der rc MUSS als $? übergeben werden, direkt hinter der
# Zuweisung: capture_t läuft in der Subshell von $(…), eine Variable aus der Funktion
# erreicht den Aufrufer nie. Bei einer Pipe ($(capture_t … | grep …)) ist $? der rc
# des LETZTEN Pipe-Glieds — dort erst einfangen, dann filtern.
capture_ok() {
  (( $1 != 142 )) && return 0
  warn "Abfrage überschritt das Zeitlimit: $2 — Stand unbekannt, nichts aktualisiert"
  action warn "$SECTION_NAME" "Abfrage hängt: $2" "" \
    "Die Abfrage wurde nach ihrem Zeitlimit abgebrochen (Alarm, rc 142) und lieferte nichts. Der Abschnitt hat deshalb nichts gemeldet und nichts aktualisiert — der Stand ist unbekannt, nicht aktuell."
  return 1
}
# run_in <stdin-text> <cmd…> — wie run, mit Eingabe auf stdin (softwareupdate --stdinpass)
# Ohne Netz-Wiederholung: der zweite Versuch läse ein leeres stdin — der erste hat die Eingabe
# verbraucht, softwareupdate --stdinpass scheiterte dann an der Anmeldung statt am Netz.
run_in() { local input=$1; shift; RUN_RETRIED=1 run "$@" <<< "$input"; }

# ask <key> <frage> — j/n einmalig · i = immer · x = nie (gemerkt in
# ~/.config/update-all/prefs). Gemerkte Antwort geht vor. -y heißt ja (assume-yes).
# Ohne TTY (launchd/Pipe), mit --check oder nach 60 s: nein — ein
# unbeaufsichtigter Lauf bleibt nie hängen und installiert nichts Großes ungefragt.
ask() {
  local key=$1 q=$2 pref k
  pref=$(grep -s "^$key=" "$CONFDIR/prefs" | cut -d= -f2)
  [[ $pref == always ]] && { info "$q ${DIM}→ ja (gemerkt: prefs)${NC}"; return 0; }
  [[ $pref == never ]]  && { info "$q ${DIM}→ nein (gemerkt: prefs)${NC}"; return 1; }
  if (( CHECK_ONLY )) || [[ ! -t 0 ]]; then
    info "$q ${DIM}→ nein (--check/nicht interaktiv; dauerhaft: $key=always in ${CONFDIR/#$HOME/~}/prefs)${NC}"
    return 1
  fi
  (( ASSUME_YES )) && { info "$q ${DIM}→ ja (-y)${NC}"; return 0; }
  print -n -- "  ${YELLOW}?${NC}  $q ${DIM}[j]a · [n]ein · [i]mmer · nie [x] · 60 s → nein:${NC} "
  read -t 60 -k1 -s k < /dev/tty; echo "${k:-⏱}"
  case $k in
    j|J|y|Y) return 0 ;;
    i|I) remember_pref "$key" always; return 0 ;;
    x|X) remember_pref "$key" never; return 1 ;;
    *)   return 1 ;;
  esac
}
remember_pref() {
  mkdir -p "$CONFDIR"; touch "$CONFDIR/prefs"
  /usr/bin/sed -i '' "/^$1=/d" "$CONFDIR/prefs"; print -r -- "$1=$2" >> "$CONFDIR/prefs"
  info "${DIM}gemerkt: $1=$2 (${CONFDIR/#$HOME/~}/prefs)${NC}"
}

# journal_summary <datei> [max] — erste Zeile: Zahlen je Quelle („brew 44 · tex 31 · npm 9“),
# dann bis zu max Einzelzeilen, TeX-Pakete zuletzt, zum Schluss „… und N weitere“. Vorher
# standen nach einem großen Lauf 20 von 112 Zeilen im Fazit, darunter viele TeX-Pakete, die
# die Apps verdrängten — am iPhone zu lang. Die volle Liste bleibt in der Aktion und im Rückblick.
journal_summary() {
  local f=$1 max=${2:-8} l s n=0; local -A cnt; local -a rows tex
  [[ -s $f ]] || return 0
  while IFS= read -r l; do
    [[ -n $l ]] || continue
    s=${l%%:*}; [[ $l == *:* && $s == [a-z]## ]] || s=andere   # Quelle als Schlüssel nur, wenn sie harmlos ist
    cnt[$s]=$(( ${cnt[$s]:-0} + 1 )); (( n+=1 ))
    if [[ $s == tex ]]; then tex+=("$l"); else rows+=("$l"); fi
  done < "$f"
  for s in ${(k)cnt}; do print -r -- "${cnt[$s]} $s"; done | sort -k1,1nr -k2,2 | awk '{ printf "%s%s %s", (NR > 1 ? " · " : ""), $2, $1 } END { print "" }'
  rows+=("${tex[@]}")
  print -rl -- "${(@)rows[1,max]}"
  (( n > max )) && print -r -- "… und $(( n - max )) weitere"
  return 0
}

# journal_block <datei> <anzahl> — der Block „Aktualisiert“ im Fazit (eigene Funktion, damit
# der Selbsttest ihn prüfen kann — Test- und Prüfläufe schreiben kein Journal)
journal_block() {
  local -a jsum; local jl; jsum=("${(@f)$(journal_summary "$1" 8)}")
  echo "\n  ${GREEN}${BOLD}Aktualisiert ($2):${NC} ${jsum[1]}"
  for jl in "${(@)jsum[2,-1]}"; do
    if [[ $jl == "… und "* ]]; then echo "     ${DIM}$jl (Aktion Änderungsjournal, --review)${NC}"
    else echo "     ${GREEN}↑${NC} $jl"; fi
  done
}

# journal <zeile> — Änderungsjournal des Laufs (was wurde konkret aktualisiert)
JOURNAL_N=0
journal() {
  [[ -n $1 ]] || return 0
  local l; for l in ${(f)1}; do print -r -- "$l" >> "$RUNDIR/journal"; (( JOURNAL_N+=1 )); done
  st changes $JOURNAL_N; st_flush
}
# Journal-Einträge aus Tool-Ausgaben — je Tool ein Muster, Rest liefern die
# Abschnitte selbst (brew/mas aus ihren Outdated-Listen, npm aus npm outdated)
journal_from_output() {   # <datei> <cmd>
  local f=$1 cmd=$2
  case $cmd in
    "claude update"*)   journal "$(grep -oE 'updated from [0-9.]+ to version [0-9.]+' "$f" | sed 's/^/claude: /; s/updated from //; s/ to version / → /')" ;;
    "bun upgrade"*)     journal "$(grep -oiE 'upgraded.*v[0-9]+\.[0-9]+[0-9.]*' "$f" | head -1 | sed 's/^/bun: /')" ;;
    # Achtung: BSD-sed kennt kein \S — hier überall [^ ] (mit \S blieben die Zeilen unverändert)
    "pipx upgrade"*)    journal "$(grep -oE 'upgraded package [^ ]+ from [^ ]+ to [^ ]+' "$f" | sed -E 's/upgraded package ([^ ]+) from ([^ ]+) to ([^ ]+)/pipx: \1 \2 → \3/')" ;;
    "uv tool upgrade"*) journal "$(grep -E '^(Updated|Upgraded) ' "$f" | sed -E 's/^(Updated|Upgraded) /uv: /; s/ -> / → /')" ;;
    *"softwareupdate -i"*) journal "$(grep -E '^(Installed|Done with) ' "$f" | sed 's/^Installed /macOS: /; s/^Done with /macOS: /')" ;;
    "docker pull"*)     grep -q 'Downloaded newer image' "$f" && journal "docker: ${cmd#docker pull } aktualisiert" ;;
    "code --update"*)   journal "$(grep -oE "Extension '[^']+' v[0-9.]+ was successfully (installed|updated)" "$f" | sed -E "s/Extension '([^']+)' v([0-9.]+).*/vscode: \1 \2/")" ;;
    *tlmgr*update*)     journal "$(grep -oE '\] update: +[^ ]+ +\[[^]]*\] \([^ ]+ -> [^ )]+\)' "$f" | sed -E 's/\] update: +([^ ]+) +\[[^]]*\] \(([^ ]+) -> ([^ )]+)\)/tex: \1 \2 → \3/')" ;;
    *"pi update"*)      journal "$(grep -oE '^Updating (npm:)?[^ ]+' "$f" | sed -E 's/^Updating (npm:)?([^ ]+)/pi: \2/; s/\.\.\.$//')" ;;
    "gh extension"*)    journal "$(grep -oiE 'upgraded extension [^ ]+' "$f" | sed 's/^/gh: /')" ;;
    "mas upgrade"*|"brew upgrade"*|"npm "*) ;;   # liefern die Abschnitte selbst
  esac
  return 0
}

# Auffälligkeiten in Tool-Ausgaben → Aktionen (nur hochsignalige Muster)
scan_output() {
  local f=$1 cmd=$2 n blk
  [[ -s "$f" ]] || return 0
  journal_from_output "$f" "$cmd"
  if grep -q '^==> Caveats' "$f"; then
    blk=$(awk '/^==> Caveats/{p=1;next} /^==>/{p=0} p' "$f")
    action info "$SECTION_NAME" "Caveats von: ${cmd[1,50]}" "" "$blk"
  fi
  n=$(grep -oE '[0-9]+ vulnerabilit(y|ies)' "$f" | head -1)
  if [[ -n $n ]]; then
    local fix="npm audit -g 2>/dev/null || npm outdated -g"; [[ $cmd == *"pi update"* ]] && fix="cd ~/.pi/agent/npm && npm audit"   # nicht *pi*: träfe auch pipx, anthropic…
    action warn "$SECTION_NAME" "npm audit: $n (${cmd[1,40]})" "$fix" "$(grep -E 'vulnerabilit|npm audit' "$f" | head -6)"
  fi
  if grep -qiE 'Warning: Skipping|conflicting formulae|Cannot install' "$f"; then
    action warn "$SECTION_NAME" "brew überspringt Pakete (${cmd[1,40]})" "brew doctor" "$(grep -iE 'Warning: Skipping|conflicting|Cannot install' "$f" | head -8)"
  fi
  # Deprecation-Hinweise — ohne zwei bekannte brew-Meldungen, bei denen nichts zu tun ist:
  #  • „hdiutil: WARNING: 'hdiutil attach …' is deprecated“: Homebrew selbst entpackt DMG-
  #    Casks mit hdiutil, macOS 27 meldet das. Der Homebrew-Fix (#23414, diskutil image) kam
  #    am 04.08.2026 und wurde am 05.08. zurückgenommen (#23444) — nichts, was wir ändern
  #    können. Im Log bleibt die Zeile stehen; dazu ein grauer Hinweis.
  #  • „==> N Deprecated or disabled package(s)“: brews Sammelzeile, deren Paketnamen erst
  #    in der Folgezeile stehen — die Aktion zeigte nur die Zahl. Der Apps-Radar meldet
  #    veraltete/deaktivierte Pakete ohnehin mit Namen.
  # Bis 3.3.6 wurde daraus 7× in 40 Läufen eine Aktion, die niemandem half.
  local dep; dep=$(grep -i 'deprecated' "$f" | grep -viE "^hdiutil: WARNING: 'hdiutil attach|^==> [0-9]+ Deprecated or disabled package" | head -8)
  [[ -n $dep ]] && action info "$SECTION_NAME" "Deprecation-Hinweise (${cmd[1,40]})" "" "$dep"
  grep -q "^hdiutil: WARNING: 'hdiutil attach" "$f" && echo "     ${DIM}· hdiutil-Warnung kommt von Homebrew (DMG-Entpacken, macOS 27) — nichts zu tun${NC}"
  return 0
}

# adopt_ignored <liste> <cask-token> <bundle-id> — 0, wenn ein Eintrag der Liste (Komma,
# zsh-Muster) auf den Cask-Namen ODER die Bundle-ID der App passt. Über die Bundle-ID lässt
# sich eine ganze Herstellerfamilie ausnehmen: adopt_ignore=parallels,com.example.* — etwa
# eine App-Familie, die ihr eigener Launcher installiert und aktualisiert. Bis 3.3.6 schlug
# der Radar ein Dutzend solcher Apps in jedem Lauf zum --adopt vor, und eine Namensliste wäre
# mit jeder neuen App der Familie veraltet.
adopt_ignored() {
  local e
  for e in ${(s:,:)1}; do
    [[ -n $e ]] || continue
    [[ $2 == ${~e} ]] && return 0
    [[ -n $3 && $3 == ${~e} ]] && return 0
  done
  return 1
}

# box <farbe> <zeile>… — Breite passt sich dem Inhalt an, höchstens dem Terminal (keine Emojis!)
# Zu lange Zeilen werden an Wortgrenzen umbrochen statt abgeschnitten: ein Umbruch durchs
# Terminal zerreißt den Rahmen (Abschluss-Tafel auf dem iPad: 64 Zeichen im 63er-Pane), und
# Abschneiden verlöre Inhalt auch im Log. Umbrochene Zeilen verlieren ihre Farben.
box() {
  local color=$1; shift
  local -a lines src; src=("$@")
  local w=0 l border="" _e="" n tw max s word cur
  # Breite vom Terminal selbst: im Runner geht stdout durch tee, tput sähe dort nichts.
  # BOX_COLS übersteuert (nur für --selftest).
  if [[ -n ${BOX_COLS:-} ]]; then tw=$BOX_COLS
  else tw=$( { stty size < /dev/tty } 2>/dev/null ); tw=${tw#* }; fi
  [[ $tw == <-> ]] || tw=${COLUMNS:-0}
  max=$(( tw > 16 ? tw - 6 : 0 ))   # "  │ " + " │" = 6 Zellen; 0 = nicht begrenzen (cron, Pipe)
  for l in "${src[@]}"; do
    n=$(vlen "$l")
    if (( ! max || n <= max )); then lines+=("$l"); continue; fi
    s=${l//$ESC\[[0-9;]#[mK]/}; cur=""
    for word in ${=s}; do
      while (( ${#word} > max )); do   # Wort länger als die Zeile → hart trennen
        [[ -n $cur ]] && { lines+=("$cur"); cur=""; }
        lines+=("${word[1,max]}"); word=${word[max+1,-1]}
      done
      [[ -z $word ]] && continue
      if [[ -z $cur ]]; then cur=$word
      elif (( ${#cur} + 1 + ${#word} <= max )); then cur+=" $word"
      else lines+=("$cur"); (( ${#word} + 2 <= max )) && cur="  $word" || cur=$word; fi
    done
    [[ -n $cur ]] && lines+=("$cur")
  done
  for l in "${lines[@]}"; do n=$(vlen "$l"); (( n > w )) && w=$n; done
  local bw=$(( w + 2 )) pad
  border=${(l:$bw::─:)_e}
  echo "  ${color}╭${border}╮${NC}"
  for l in "${lines[@]}"; do
    n=$(vlen "$l"); pad=$(( w - n ))
    echo "  ${color}│${NC} ${l}${(l:$pad:: :)_e} ${color}│${NC}"
  done
  echo "  ${color}╰${border}╯${NC}"
}

# ═════════════════════════════════════════════════════════════════
# Admin-Rechte
# ═════════════════════════════════════════════════════════════════
SUDO_MODE=none SUDO_PW="" ASKPASS_DIR=""
typeset -a SUDO; SUDO=(sudo)

cleanup_askpass() {
  [[ -n $ASKPASS_DIR && -d $ASKPASS_DIR ]] || return 0
  : > "$ASKPASS_DIR/pw" 2>/dev/null; rm -rf "$ASKPASS_DIR"; ASKPASS_DIR=""
}

setup_sudo() {
  (( CHECK_ONLY )) && { SUDO_MODE=check; st sudo "nicht nötig (--check)"; return 0; }
  if (( DRY_RUN )); then SUDO_MODE=dry; st sudo "dry-run"; return 0; fi
  # sudo-Bedarf außerhalb von brew (statisch vorhersagbar)
  local -a need
  if (( ! NO_MACOS )) && [[ ",${(j:,:)SEC_ORDER}," == *,macos,* ]] && ! sudo -n -l /usr/sbin/softwareupdate &>/dev/null; then
    need+=("softwareupdate (keine NOPASSWD-Regel)")
  fi
  [[ ",${(j:,:)SEC_ORDER}," == *,texlive,* ]] && [[ ! -w /usr/local/texlive ]] && need+=("tlmgr")

  if (( ! ASKPASS )) && [[ -n $SSH_TTY || -n $SSH_CONNECTION ]] && [[ -t 0 ]]; then
    ASKPASS=1; info "SSH-Sitzung erkannt — Passwort wird einmal abgefragt (kein Touch ID möglich)"
  fi

  if (( ASKPASS )) && [[ -t 0 ]]; then
    local um; um=$(umask); umask 077
    ASKPASS_DIR=$(mktemp -d "${TMPDIR:-/tmp}/update-all-ask.XXXXXX") || { umask "$um"; return 1; }
    # -l: je Argument eine Zeile. Mit -r stand Shebang und Befehl in EINER Zeile,
    # der Helper lieferte rc 127 und askpass/SSH-Modus scheiterte still (Review 18.09.).
    print -rl -- '#!/bin/sh' "exec cat '$ASKPASS_DIR/pw'" > "$ASKPASS_DIR/askpass"
    chmod 700 "$ASKPASS_DIR/askpass"
    export SUDO_ASKPASS="$ASKPASS_DIR/askpass"
    local try pw
    for try in 1 2 3; do
      print -n -- "  ${CYAN}·${NC}  Admin-Passwort ${DIM}(einmalig, bleibt nur für diesen Lauf im Speicher)${NC}: "
      read -rs pw < /dev/tty; echo
      print -rn -- "$pw" > "$ASKPASS_DIR/pw"
      if sudo -A -k -v 2>/dev/null; then
        SUDO_PW="$pw"; SUDO=(sudo -A); SUDO_MODE=askpass
        ok "sudo freigeschaltet ${DIM}(askpass — keine weitere Abfrage in diesem Lauf, auch nicht durch brew)${NC}"
        st sudo "askpass · 1 Abfrage erledigt"; umask "$um"; return 0
      fi
      warn "Passwort falsch ($try/3)"
    done
    cleanup_askpass; unset SUDO_ASKPASS; umask "$um"
    warn "Kein sudo — Schritte mit Admin-Rechten werden fehlschlagen oder übersprungen"
    SUDO_MODE=none; st sudo "kein sudo"; return 1
  fi

  # Touch-ID-/Lazy-Modus: keine Vorab-Abfrage
  SUDO_MODE=touchid
  local tid="Passwort"; grep -qs pam_tid /etc/pam.d/sudo_local /etc/pam.d/sudo && tid="Touch ID"
  if [[ ! -t 0 ]]; then
    SUDO_MODE=none
    warn "Nicht interaktiv — sudo-Schritte werden übersprungen (NOPASSWD-Regeln gelten weiter)"
    st sudo "nicht interaktiv"; return 0
  fi
  if (( ${#need} )); then
    info "Admin-Abfrage ($tid) kommt bei: ${(j:, :)need} — plus ggf. 1× bei brew (pkg-Casks, Vorschau folgt)"
  else
    info "Keine Admin-Abfrage vorab nötig — höchstens 1× $tid bei brew, falls ein Cask einen pkg-Installer hat"
  fi
  info "${DIM}Tipp: --askpass = Passwort einmal tippen, danach garantiert keine Abfrage mehr${NC}"
  st sudo "$tid bei Bedarf"
  return 0
}

# Casks, die bei 'brew upgrade' sudo brauchen (pkg/installer/launchctl/pkgutil)
casks_needing_sudo() {   # <cask…> → Namen auf stdout
  (( $# )) || return 0
  local -a known=(parallels docker-desktop windows-app adobe-dng-converter logi-options+ zoom microsoft-auto-update)
  if has jq; then
    brew info --json=v2 --cask "$@" 2>/dev/null | jq -r '
      .casks[] | select( ([ .artifacts[] | (has("pkg") or has("installer")
        or (has("uninstall") and ([ .uninstall[] | (has("launchctl") or has("pkgutil")) ] | any))) ] | any) ) | .token'
  else
    local c; for c in "$@"; do (( ${known[(Ie)$c]} )) && print -r -- "$c"; done
  fi
}

# cask_app_versions <token…> → je Zeile "token<TAB>App-Name<TAB>installierte Version"
# Zwei Dinge, die brews Ausgabe NICHT liefert:
#   • die Version der installierten App (Bundle). Bei Self-Updater-Casks hinkt brews
#     Caskroom-Eintrag ihr regelmäßig hinterher — genau daraus entstand bis 3.2.4 die
#     falsche Major-Warnung (WebCatalog-App 80.2.1, Caskroom 79.1.1, Tap 80.2.1 →
#     „Major-Upgrade 79.1.1 → 80.2.1", obwohl die App den Sprung längst gemacht hat).
#   • den App-Namen: 'open -a google-chrome' findet nichts, 'open -a "Google Chrome"' schon.
# Ein brew-Aufruf für alle Tokens — und nur VOR dem Upgrade (jeder brew-Start setzt
# das sudo-Ticket zurück, siehe Reihenfolge in sec_brew).
cask_app_versions() {
  (( $# )) || return 0
  has jq || return 0
  local json line tok app q ver; local -a f
  json=$(capture_t 120 brew info --cask --json=v2 "$@" 2>/dev/null)
  # Ohne diese Angaben fällt die Major-Prüfung auf brews Caskroom-Eintrag zurück —
  # das ist die alte, zu strenge Basis, also nicht still durchgehen lassen
  capture_ok $? "brew info --cask (App-Versionen)" || return 0
  # Feld 4: 'quit' im uninstall-Block — bei solchen Casks beendet brew die laufende App
  # per AppleScript, was remote die Automation-Abfrage auf dem Mac-Schirm auslöst
  for line in ${(f)"$(print -r -- "$json" | jq -r '.casks[] | [.token, ([.artifacts[]? | .app? // empty | .[]? | if type=="string" then . else (.target? // empty) end] | first // ""), (if [.artifacts[]? | .uninstall? // empty | .[]? | has("quit")] | any then "quit" else "" end)] | @tsv' 2>/dev/null)"}; do
    f=("${(@s:	:)line}"); tok=${f[1]}; app=${f[2]}; q=${f[3]:-}
    [[ -n $tok ]] || continue
    if [[ -n $app && -d "/Applications/$app" ]]; then
      ver=$(defaults read "/Applications/$app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)
    else
      app=""; ver=""
    fi
    print -r -- "$tok	${app:r}	$ver	$q"
  done
}

# cask_unquarantine <token…> — Quarantäne-Attribut aus dem Caskroom nehmen.
# Homebrew 7 kennt --no-quarantine nicht mehr (HOMEBREW_CASK_OPTS damit wird still
# ignoriert, bis 3.3.2 stand es hier trotzdem): jeder Download trägt die Quarantäne. Beim
# Upgrade erbt eine App die Freigabe ihrer Vorversion, wenn die freigegeben war und der
# Signierer gleich bleibt (cask/upgrade.rb, quarantine_release_decision) — für 'binary'-
# Casks gibt es diese Vererbung nicht. Die behalten das Attribut, und beim ersten Aufruf
# kommt der Gatekeeper-Dialog
# „… aus dem Internet geladen · Öffnen/Abbrechen" — remote auf dem Mac-Schirm, also nur
# per VNC wegklickbar (belegt an codex 0.160.0: alle 12 Dateien unter
# Caskroom/codex/0.160.0 trugen com.apple.quarantine, das Binary ist von OpenAI signiert).
# Gilt nur für Casks, die brew in diesem Lauf selbst installiert hat — dieselbe
# Vertrauensgrundlage wie früher --no-quarantine: die Quelle ist der Tap.
cask_unquarantine() {
  (( $# )) || return 0
  (( CHECK_ONLY || DRY_RUN )) && return 0
  local t dir hit lnk tgt; local -a targets done_q rest
  for t in "$@"; do
    for dir in ${HOMEBREW_PREFIX:-/opt/homebrew}/Caskroom/$t/*(N/); do
      targets=("$dir")
      # App-Casks lagern im Caskroom nur einen SYMLINK auf /Applications — die echte App
      # trägt die Quarantäne, und zwar jede Datei darin (Google Chrome 154: 740 Stück;
      # brew warnt selbst: „couldn't inherit quarantine approval so macOS may
      # prompt at next launch"). Nur Ziele unter /Applications, nichts Beliebiges.
      for lnk in $dir/*(N@); do
        tgt=${lnk:A}
        [[ -d $tgt && $tgt == /Applications/* ]] && targets+=("$tgt")
      done
      for tgt in "${targets[@]}"; do
        hit=$(find "$tgt" -xattrname com.apple.quarantine -print -quit 2>/dev/null)
        [[ -n $hit ]] || continue
        # Eine NOTARISIERTE App öffnet trotz Quarantäne ohne Dialog (spctl: „accepted"), und
        # ihr Bundle-Root gehört oft root (Chrome/Keystone) — xattr scheitert dort mit EACCES.
        # Also nur anfassen, was Gatekeeper wirklich ablehnt: codex (binary, „rejected: does
        # not seem to be an app") ja, Chrome nein. Sonst scheitert das Skript an fremden
        # Rechten und meldet Arbeit, die niemandem hilft.
        if [[ $tgt == /Applications/*.app ]] && capture_t 20 spctl -a -t exec "$tgt" &>/dev/null; then
          continue
        fi
        xattr -dr com.apple.quarantine "$tgt" 2>/dev/null
        # ehrlich bleiben: nur als erledigt melden, was danach wirklich sauber ist
        if [[ -z $(find "$tgt" -xattrname com.apple.quarantine -print -quit 2>/dev/null) ]]; then
          done_q+=("$t")
        else
          rest+=("$t")
        fi
      done
    done
  done
  (( ${#done_q} )) && info "Quarantäne entfernt: ${(j:, :)${(u)done_q}} ${DIM}(sonst Gatekeeper-Dialog beim ersten Start — nur per VNC wegklickbar)${NC}"
  (( ${#rest} )) && info "Quarantäne teils geblieben: ${(j:, :)${(u)rest}} ${DIM}(Reste gehören root — nur mit sudo entfernbar; Gatekeeper lehnt sie ab, also beim ersten Start einmal per GUI bestätigen)${NC}"
  return 0
}

# cask_quit_running — läuft eine App, die brew gleich beenden würde? Dann JETZT selbst
# beenden, per Signal statt AppleScript: brews 'quit' geht über Automation, und die fragt
# remote auf dem Mac-Schirm nach Erlaubnis. Lässt sich eine App nicht beenden, wird ihr
# Cask übersprungen (kein SIGKILL — ungespeicherte Arbeit bleibt ungespeicherte Arbeit).
# Erwartet die Map APPN/APPQ aus cask_app_versions. Ausnahmen: prefs never_quit=
# Füllt QUIT_SENT (jede App, die ein TERM bekommen hat — für den Neustart) und
# QUIT_FAILED (Casks zum Aussortieren).
typeset -ga QUIT_SENT QUIT_FAILED
# Prozessmuster für pgrep/pkill -f (ERE): App-Namen sind keine Regex — ein Punkt oder
# Plus im Namen ('logi-options+') würde sonst zum Quantor und fremde Prozesse treffen.
app_pat() {
  local a=$1
  a=${a//(#m)[][.^$|?*+(){}\\]/\\$MATCH}
  print -r -- "/Applications/$a\\.app/Contents/MacOS/"
}
cask_quit_running() {   # <token…>
  QUIT_SENT=(); QUIT_FAILED=()
  (( $# )) || return 0
  (( CHECK_ONLY || DRY_RUN )) && return 0
  local nq t app pat e i
  nq=$(grep -s '^never_quit=' "$CONFDIR/prefs" | cut -d= -f2-)
  for t in "$@"; do
    [[ ${APPQ[$t]:-} == quit ]] || continue
    app=${APPN[$t]:-}; [[ -n $app ]] || continue
    pat=$(app_pat "$app")
    pgrep -qf "$pat" 2>/dev/null || continue
    for e in ${(s:,:)nq}; do [[ -n $e && $t == ${~e} ]] && { info "$app läuft — bleibt offen (never_quit)"; QUIT_FAILED+=("$t"); break; }; done
    (( ${QUIT_FAILED[(Ie)$t]} )) && continue
    info "$app läuft — wird für das Cask-Upgrade beendet ${DIM}(sonst fragt brew per Automation nach)${NC}"
    pkill -TERM -f "$pat" 2>/dev/null; QUIT_SENT+=("$app")
    # 15 s: Docker Desktop fährt beim Beenden erst seine VM herunter
    for (( i=0; i<30; i++ )); do pgrep -qf "$pat" 2>/dev/null || break; sleep 0.5; done
    if pgrep -qf "$pat" 2>/dev/null; then
      QUIT_FAILED+=("$t")
      warn "$app hat sich in 15 s nicht beendet — $t wird übersprungen"
      action warn "$SECTION_NAME" "$t übersprungen: $app hat sich nicht beendet" "brew upgrade --cask $t" \
        "Die App wurde absichtlich nicht hart beendet (ungespeicherte Arbeit). Beende sie von Hand, dann hält der nächste Lauf das Cask nach."
    fi
  done
  return 0
}
# Nach dem Upgrade wieder starten, was wir beendet haben (Menüleisten-Apps fänden sonst
# niemand wieder) — auch Apps, die für die Wartezeit zu langsam waren und erst danach
# zugegangen sind; bis 3.3.2 blieben die einfach aus. Was wieder läuft (selbst
# neugestartet oder nie beendet), bleibt unberührt. 'open -a' braucht den App-Namen.
cask_restart_quit() {
  (( ${#QUIT_SENT} )) || return 0
  local app; local -a started
  for app in ${(u)QUIT_SENT}; do
    pgrep -qf "$(app_pat "$app")" 2>/dev/null && continue
    open -a "$app" 2>/dev/null && started+=("$app")
  done
  (( ${#started} )) && info "Wieder gestartet: ${(j:, :)started}"
  QUIT_SENT=()
  return 0
}

# ═════════════════════════════════════════════════════════════════
# Abschnitte
# ═════════════════════════════════════════════════════════════════
# su_parse — liest 'softwareupdate -l' von stdin, je Update eine TSV-Zeile:
#   <now|later> <label> <titel> <version> <größe>
# later = braucht einen Neustart (Action: restart, bei Firmware Action: shut down).
# Format seit macOS 13 — Label-Zeile, darunter eine Title-Zeile mit Kommafeldern:
#   * Label: macOS Tahoe 26.1-25B78
#   	Title: macOS Tahoe 26.1, Version: 26.1, Size: 7354880KiB, Recommended: YES, Action: restart,
su_parse() {
  local line label="" title ver size kib kind
  while IFS= read -r line; do
    if [[ $line == '* Label: '* ]]; then label=${line#\* Label: }; continue; fi
    [[ -n $label && $line == *'Title: '* ]] || continue
    title=${${line#*Title: }%%, Version:*}; ver=${${line#*Version: }%%,*}
    size=${${line#*Size: }%%,*}; kib=${size%KiB}
    # Ganzzahlig rechnen: printf mit %.1f folgt der Locale (de: Komma) und stolpert dann
    [[ $kib == <-> ]] && size="$(( kib / 1048576 )).$(( kib % 1048576 * 10 / 1048576 )) GB"
    kind=now; [[ $line == *'Action: restart'* || $line == *'Action: shut down'* ]] && kind=later
    print -r -- "$kind	$label	$title	$ver	$size"
    label=""
  done
}

# macOS: nur Updates OHNE Neustart werden im Lauf installiert (Safari, XProtect, …).
# Punkt- und Major-Updates mit Neustart werden gemeldet — Aktion mit Größe und fertigem
# Befehl, den Zeitpunkt wählst du. Bis 3.3.4 lief 'softwareupdate -i -a': einmal stand der
# Lauf minutenlang bei „Downloading macOS 27.2" (kein Fortschritt im Log) und wurde
# abgebrochen, 27.2 kam danach außerhalb des Skripts. Remote ist ein Neustart ohnehin das
# Ende der SSH-Sitzung; und mit -y hätte eine Rückfrage nichts gebremst.
sec_macos() {
  local list rc line t; local -a ups now later f cmd
  echo "  ${MAGENTA}▶${NC}  ${BOLD}softwareupdate -l${NC}"
  (( SECTION_RUNS+=1 ))
  if (( DRY_RUN )); then echo "     ${DIM}└ ${GREEN}✓${NC}${DIM} simuliert${NC}"; return 0; fi
  list=$(capture_t 300 softwareupdate -l 2>&1); rc=$?
  [[ -d $RUNDIR/out ]] && print -r -- "$list" > "$RUNDIR/out/su-list.txt"
  capture_ok $rc "softwareupdate -l" || return 0
  ups=(${(f)"$(print -r -- "$list" | su_parse)"})
  if (( ! ${#ups} )); then
    if [[ $list == *'found the following'* ]]; then
      # Updates da, aber das Format kennen wir nicht — lieber nichts installieren als raten
      warn "softwareupdate meldet Updates in unbekanntem Format — nichts installiert"
      action warn "$SECTION_NAME" "macOS-Updates: Ausgabe nicht lesbar" "softwareupdate -l" "$list"
    else
      ok "macOS aktuell — keine Updates"
    fi
    return 0
  fi
  for line in "${ups[@]}"; do
    f=("${(@s:	:)line}")
    if [[ ${f[1]} == later ]]; then later+=("$line"); else now+=("${f[2]}"); fi
  done
  for line in "${later[@]}"; do
    f=("${(@s:	:)line}"); t=${f[3]}; [[ $t == *"${f[4]}"* ]] || t+=" ${f[4]}"
    warn "$t wartet auf dich (${f[5]}, Neustart) — der Lauf installiert es nicht"
    action warn "$SECTION_NAME" "macOS-Update wartet: $t (Neustart)" \
      "sudo softwareupdate -i $(shq "${f[2]}") --agree-to-license -R" \
      "Größe: ${f[5]} · Label: ${f[2]}
Updates mit Neustart installiert der Lauf nicht selbst (seit 3.3.5) — du wählst den Zeitpunkt.
Der Fix-Befehl startet mit -R danach sofort neu; per SSH bricht dabei die Verbindung ab.
Ohne sofortigen Neustart: sudo softwareupdate -i $(shq "${f[2]}") --agree-to-license — später sudo shutdown -r now"
  done
  (( ${#now} )) || return 0
  if (( CHECK_ONLY )); then info "Ohne Neustart, würde installiert: ${(j:, :)now}"; return 0; fi
  cmd=("${SUDO[@]}" softwareupdate -i "${now[@]}" --agree-to-license)
  if [[ $SUDO_MODE == none ]] && ! sudo -n -l /usr/sbin/softwareupdate &>/dev/null; then
    warn "Übersprungen — bei Bedarf manuell: sudo softwareupdate -i $(shq "${now[@]}")"; (( SKIPPED+=1 )); return 0
  fi
  if [[ $SUDO_MODE == askpass ]]; then
    # Apple Silicon: OS-Updates verlangen zusätzlich das Passwort eines Volume-
    # Owners — mit --stdinpass kommt es aus dem askpass-Speicher statt vom Prompt
    run_in "$SUDO_PW" "${cmd[@]}" --user "$USER" --stdinpass
  else
    run "${cmd[@]}"
  fi
  if [[ -n $LAST_OUT ]] && grep -Eqi 'restart|neustart' "$LAST_OUT" 2>/dev/null; then
    REBOOT_NEEDED=1; st reboot 1
    warn "Mindestens ein installiertes Update erfordert einen Neustart"
    action warn "$SECTION_NAME" "Neustart erforderlich (macOS-Update installiert)" "sudo shutdown -r +1" "$(grep -Ei 'restart|neustart' "$LAST_OUT" | head -3)"
  fi
}

sec_brew() {
  export HOMEBREW_NO_ENV_HINTS=1
  # Quarantäne: kein HOMEBREW_CASK_OPTS=--no-quarantine mehr — Homebrew 7 ignoriert es
  # still. Was nach dem Upgrade noch Gatekeeper-Dialoge auslösen würde, räumt
  # cask_unquarantine gezielt ab.
  # Homebrew 7 hebt Casks mit auto_updates VON SICH AUS, sobald die App-Version im
  # Bundle hinter dem Tap liegt (HOMEBREW_UPGRADE_AUTO_UPDATES_CASKS, Standard an) —
  # so hat ein normales 'brew upgrade' Parallels 27.0.1 → 27.0.2
  # gehoben und den Launch-Daemon erneut entfernt (siehe Vorfall unten). Wir
  # schalten das ab und entscheiden selbst: namentlich, mit Ausschlussliste und
  # Major-Sprung-Sperre. Gilt nur für diesen Prozess; ~/.zshrc setzt es zusätzlich
  # für manuelle brew-Aufrufe.
  export HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS=1
  run brew update

  # Alle Abfragen VOR dem Upgrade: jeder brew-Aufruf setzt das sudo-Ticket
  # zurück, und 'brew upgrade' soll der letzte brew-Aufruf vor tlmgr sein
  # (dessen sudo dann das Ticket aus dem Upgrade weiterverwenden kann).
  #   outdated      Formulae + klassische Casks (ohne auto_updates)
  #   lagging       Self-Updater-Casks, deren App wirklich hinterherhinkt (Homebrew
  #                 vergleicht dafür die Bundle-Version) → werden gehoben
  #   bookkeeping   App aktuell, nur brews Buchführung hinkt → nur mit -g
  local outdated greedy_v n; local -a classic_casks lagging all_greedy bookkeeping
  outdated=$(capture_t 300 brew outdated --verbose 2>/dev/null); capture_ok $? "brew outdated" || return 0
  (( CHECK_ONLY )) && [[ -n $outdated ]] && info "${DIM}(Stand des letzten 'brew update')${NC}"
  classic_casks=(${(f)"$(capture_t 300 brew outdated --cask --quiet 2>/dev/null)"}); capture_ok $? "brew outdated --cask" || return 0
  lagging=(${(f)"$(capture_t 300 env -u HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS brew outdated --cask --quiet 2>/dev/null)"})
  capture_ok $? "brew outdated --cask (Self-Updater)" || return 0
  lagging=(${lagging:|classic_casks})
  greedy_v=$(capture_t 300 brew outdated --cask --greedy-auto-updates --verbose 2>/dev/null)   # "name (alt) != neu"
  capture_ok $? "brew outdated --cask --greedy-auto-updates" || return 0
  all_greedy=(${(f)"$(print -r -- "$greedy_v" | awk '{print $1}')"})
  bookkeeping=(${${all_greedy:|classic_casks}:|lagging})

  # Self-Updater-Casks: brew springt bei ihnen ohne Rücksicht auf Lizenz oder
  # Erst-Initialisierung über Major-Versionen (Vorfall: Parallels 26 → 27;
  # der Cask-Postflight ruft nur 'inittool2 init', das den alten Launch-Daemon
  # entfernt und den neuen erst beim GUI-Start installiert → prlctl kaputt).
  # Deshalb: Ausschlussliste (prefs cask_exclude=…, Muster erlaubt) und
  # Major-Sprung-Sperre — auf JEDEM Pfad, nicht nur mit -g.
  #
  # Verglichen wird die INSTALLIERTE App-Version gegen den Tap, nicht brews
  # Caskroom-Eintrag: der hinkt bei Self-Updater-Casks hinterher, und bis 3.2.4
  # erzeugte das falsche Major-Warnungen für Apps, die den Sprung längst gemacht
  # hatten (WebCatalog-App 80.2.1 bei Caskroom 79.1.1; Chrome-App 154.0.8037.93
  # bei Caskroom 153.0.8010.53 — real stand nur ein Patch an). Weil die Titel die
  # Patch-Version trugen, bekam jede Browser-Version eine neue Aktions-ID, und ^A
  # (erledigt) konnte nichts dauerhaft stillstellen.
  #
  # Seit 3.3.5 eine SPERRLISTE statt einer Sperre für alle (prefs major_block=, Muster
  # erlaubt, Standard geekbench*): In einem Monat gab es rund 65 Major-Warnungen und
  # keinen einzigen Lizenzfall — Teams zählt Datumsversionen (26261 → 26276, jede Version
  # ein „Major“), Sonos trägt die Tap-Version nur als Build (Kurzversion 17.2.5, Build
  # 90.0.82050 = Tap), Firefox/Thunderbird/Chrome/Claude springen regelmäßig. Der
  # Homebrew-Abschnitt war dadurch in 35 von 40 Läufen gelb. Gesperrt wird nur noch, was
  # beim Sprung Geld oder eine neue Lizenz kostet. 'major_block=' (leer) schaltet ganz ab.
  local excl=$(grep -s '^cask_exclude=' "$CONFDIR/prefs" | cut -d= -f2-); excl=${excl:-parallels,parallels-toolbox}
  local mblk='geekbench*'
  grep -qs '^major_block=' "$CONFDIR/prefs" && mblk=$(grep -s '^major_block=' "$CONFDIR/prefs" | tail -1 | cut -d= -f2-)
  local -a self_safe self_skip cand; local pv pname pold pnew base e hit
  typeset -A APPV APPN APPQ
  local line; local -a mf
  # ein brew-info-Aufruf für alle Kandidaten (Self-Updater UND klassische Casks):
  # App-Name, installierte Version, 'quit'-Flag
  for line in ${(f)"$(cask_app_versions "${all_greedy[@]}" "${classic_casks[@]}")"}; do
    mf=("${(@s:	:)line}")
    APPN[${mf[1]}]=${mf[2]:-}; APPV[${mf[1]}]=${mf[3]:-}; APPQ[${mf[1]}]=${mf[4]:-}
  done
  # major_blocked <token> <alt> <neu> → 0, wenn der Sprung gesperrt ist (Major wechselt UND
  # der Cask steht auf der Sperrliste)
  major_blocked() {
    local t=$1 a=$2 b=$3 p
    [[ ${a%%.*} != ${b%%.*} ]] || return 1
    for p in ${(s:,:)mblk}; do [[ -n $p && $t == ${~p} ]] && return 0; done
    return 1
  }
  # open_fix <token> → Fix-Befehl, der die App wirklich öffnet ('open -a google-chrome'
  # findet nichts: $pname ist der Cask-Token, nicht der App-Name)
  open_fix() { [[ -n ${APPN[$1]} ]] && print -rn -- "open -a ${(qq)APPN[$1]}"; }
  major_detail() {   # <token> <installiert> <tap>
    print -r -- "Installiert: $2 · Tap: $3. $1 steht auf der Sperrliste (major_block=$mblk in ${CONFDIR/#$HOME/~}/prefs): ein Major-Sprung kostet dort oft eine neue Lizenz oder ein Bezahl-Upgrade. Bewusst per Hand: brew upgrade --cask --greedy-auto-updates $1
Dauerhaft freigeben: $1 aus major_block= entfernen."
  }
  cand=("${lagging[@]}"); (( GREEDY )) && cand+=("${bookkeeping[@]}")
  for pv in ${(f)greedy_v}; do
    pname=${pv%% *}; (( ${cand[(Ie)$pname]} )) || continue
    pold=${${pv#* \(}%%\)*}; pnew=${pv##* }; hit=""
    base=${APPV[$pname]:-$pold}   # installierte App-Version; brews Caskroom-Eintrag nur als Rückfall
    for e in ${(s:,:)excl}; do [[ $pname == ${~e} ]] && { hit=$e; break; }; done
    if [[ -n $hit ]]; then
      self_skip+=("$pname"); action info "$SECTION_NAME" "$pname $base → $pnew nur über den eigenen Updater (cask_exclude)" "$(open_fix $pname)" "Ausschlussliste in ${CONFDIR/#$HOME/~}/prefs: cask_exclude=$excl"
    elif major_blocked "$pname" "$base" "$pnew"; then
      self_skip+=("$pname"); action warn "$SECTION_NAME" "Major-Upgrade $pname ${base%%.*} → ${pnew%%.*} gesperrt (major_block)" "$(open_fix $pname)" "$(major_detail $pname $base $pnew)"
    else
      self_safe+=("$pname")
    fi
  done
  # Ohne -g bleiben Buchführungs-Fälle liegen (die App ist aktuell, nur brews Caskroom-
  # Eintrag hinkt) — dort wird nichts gehoben, also gibt es auch nichts zu sperren. Bis
  # 3.3.4 prüfte eine zweite Schleife sie trotzdem und warnte: daher kam „sonos 17 → 90“
  # in 19 Läufen, obwohl brew Sonos nie angefasst hätte. Mit -g laufen sie durch die
  # Schleife oben (cand) und damit durch Ausschlussliste und Sperrliste.
  local -a lag_safe book_safe; lag_safe=(${lagging:*self_safe}); book_safe=(${bookkeeping:*self_safe})
  (( ${#lag_safe} ))  && info "${#lag_safe} Self-Updater-App(s) hinken hinterher — brew hebt sie: ${(j:, :)lag_safe}"
  (( ${#book_safe} )) && info "-g: ${#book_safe} Cask(s) Buchführungs-Abgleich (App schon aktuell): ${(j:, :)book_safe}"
  (( ${#self_skip} )) && warn "${#self_skip} Self-Updater-Cask(s) bewusst ausgelassen (cask_exclude/major_block): ${(j:, :)self_skip}"
  if (( ! GREEDY && ${#bookkeeping} )); then
    info "${#bookkeeping} App(s) aktuell, nur brews Buchführung hinkt ${DIM}(${(j:, :)bookkeeping} — -g gleicht ab)${NC}"
  fi
  # Dialogfrei heben: läuft eine der betroffenen Apps, beenden wir sie selbst per Signal,
  # bevor brew es per Automation versucht (siehe cask_quit_running). Was sich nicht beenden
  # lässt, nehmen wir aus der namentlichen Self-Updater-Liste; 'brew upgrade' läuft pauschal
  # und kann einzelne Casks nicht auslassen — dafür gibt es nur die Warnung.
  cask_quit_running "${classic_casks[@]}" "${self_safe[@]}"
  if (( ${#QUIT_FAILED} )); then
    self_safe=(${self_safe:|QUIT_FAILED})
    local -a cl_block; cl_block=(${classic_casks:*QUIT_FAILED})
    (( ${#cl_block} )) && warn "${(j:, :)cl_block}: 'brew upgrade' fasst sie trotzdem an — dort kann die Automation-Abfrage kommen"
  fi
  # Zeilen der geprüften Self-Updater-Casks — zsh-Vergleich statt grep-Regex: Cask-Namen
  # sind keine Muster, 'logi-options+' machte das '+' zum ERE-Quantor und fiel heraus
  # (kein Journal-Eintrag, PKG_BREW zu niedrig).
  local self_v=""
  if (( ${#self_safe} )); then
    for pv in ${(f)greedy_v}; do (( ${self_safe[(Ie)${pv%% *}]} )) && self_v+="$pv"$'\n'; done
    self_v=${self_v%$'\n'}
  fi
  local all_v; all_v=$(print -rl -- "$outdated" "$self_v" | grep .); n=$(count_lines "$all_v")
  PKG_BREW=$n; st pkg_brew $n; st_flush
  # sudo-Bedarf je Aufruf getrennt: es gibt bis zu ZWEI brew-Prozesse (klassisch +
  # Self-Updater namentlich), und jeder brew-Start setzt das sudo-Ticket zurück. Der
  # Aufruf mit den sudo-Casks läuft deshalb als LETZTER, direkt vor tlmgr — so bleibt
  # es bei höchstens einer Abfrage, solange nicht beide Aufrufe sudo brauchen.
  local -a sudo_classic sudo_self
  sudo_classic=(${(f)"$(casks_needing_sudo "${classic_casks[@]}")"})
  sudo_self=(${(f)"$(casks_needing_sudo "${self_safe[@]}")"})
  if (( n == 0 )); then
    # Nur noch übersprungene Self-Updater übrig? Dann ist nicht „alles aktuell", und was
    # wir dafür beendet haben (langsam zugegangen), muss trotzdem wieder starten.
    cask_restart_quit
    if (( ${#QUIT_FAILED} )); then info "Nichts mehr zu heben — übersprungen: ${(j:, :)QUIT_FAILED}"
    else ok "Alle Formulae & Casks aktuell — kein Upgrade nötig"; fi
    return 0
  fi
  info "$n Paket(e) veraltet:"; print -r -- "$all_v" | bullets
  local -a sudo_casks; sudo_casks=("${sudo_classic[@]}" "${sudo_self[@]}")
  if (( ${#sudo_casks} )); then
    local twice=""; (( ${#sudo_classic} && ${#sudo_self} )) && twice=" (zweimal: klassische und Self-Updater-Casks laufen getrennt)"
    case $SUDO_MODE in
      askpass) info "${#sudo_casks} Cask(s) mit Admin-Rechten (${(j:, :)sudo_casks}) — askpass übernimmt, keine Abfrage" ;;
      touchid) warn "${#sudo_casks} Cask(s) brauchen Admin-Rechte: ${(j:, :)sudo_casks} — JETZT kommt die Touch-ID-/Passwort-Abfrage$twice" ;;
      dry|check) ;;
      *)       warn "${#sudo_casks} Cask(s) brauchen Admin-Rechte (${(j:, :)sudo_casks}) — ohne sudo schlagen sie fehl" ;;
    esac
  fi
  local rc=0 grc=0; local -a done_names order
  # Reihenfolge: der Aufruf, der sudo braucht, zuletzt (siehe oben)
  if (( ${#sudo_classic} )); then order=(self classic); else order=(classic self); fi
  local step
  for step in "${order[@]}"; do
    if [[ $step == classic && -n $outdated ]]; then
      run brew upgrade || rc=$?
      (( rc == 0 && ! CHECK_ONLY && ! DRY_RUN )) && { brew_journal "$outdated" except; done_names+=(${(f)"$(print -r -- "$outdated" | awk '{print $1}')"}); }
    elif [[ $step == self ]] && (( ${#self_safe} )); then   # geprüfte Self-Updater-Casks, namentlich
      run brew upgrade --cask --greedy-auto-updates "${self_safe[@]}" || grc=$?
      (( grc == 0 && ! CHECK_ONLY && ! DRY_RUN )) && { brew_journal "$self_v" only "${self_safe[@]}"; done_names+=("${self_safe[@]}"); }
    fi
  done
  (( ${#done_names} )) && brew_post_upgrade "${done_names[@]}"
  cask_restart_quit   # was wir vorher beendet haben, wieder starten
  # brew autoremove/cleanup folgen im Abschnitt 'cleanup'.
}
# Nacharbeiten nach erfolgreichem Upgrade bestimmter Pakete
brew_post_upgrade() {   # <name…>
  local -a names; names=("$@")
  cask_unquarantine "${names[@]}"   # 'binary'-Casks (codex) bringen sonst den Gatekeeper-Dialog
  # Ollama mit eigenem LaunchAgent (prefs ollama_agent=<Label>; er startet Ollama.app mit
  # Server-Env, z. B. Kontextlänge, und ohne Autostart): Lief der Dienst, nach dem
  # Cask-Upgrade neu starten, sonst läuft der alte Server weiter; war er aus, bleibt er aus.
  # Die frische App registriert beim ersten Start ihren eigenen Login-Eintrag
  # (com.ollama.ollama, SMAppService) — der startet eine zweite Instanz ohne das Env und fragt
  # nach dem Passwort (CLI-Symlink /usr/local/bin/ollama) → wieder stilllegen. Ohne
  # ollama_agent bleibt alles, wie die App es einrichtet.
  local oa; oa=$(grep -s '^ollama_agent=' "$CONFDIR/prefs" | tail -1 | cut -d= -f2-)
  if (( ${names[(Ie)ollama-app]} )) && [[ -n $oa ]]; then
    local ua="gui/$(id -u)"
    if launchctl print "$ua/$oa" >/dev/null 2>&1; then
      if launchctl kickstart -k "$ua/$oa" 2>/dev/null; then ok "Ollama-Dienst neu gestartet ($oa)"
      else warn "Ollama-Dienst konnte nicht neu gestartet werden — launchctl kickstart -k $ua/$oa"; fi
    else info "Ollama war nicht gestartet — bleibt aus ${DIM}($oa)${NC}"; fi
    launchctl bootout "$ua/com.ollama.ollama" 2>/dev/null; launchctl disable "$ua/com.ollama.ollama" 2>/dev/null
  fi
  # Office-Installer bringen Microsoft AutoUpdate wieder mit → erneut stilllegen
  (( ${#${(M)names:#microsoft-*}} )) && mau_redundant && mau_silence
  return 0
}
# brew_journal <outdated-liste> <only|except> <cask…> — "glib (2.88.3) < 2.90.0" → "brew: glib 2.88.3 → 2.90.0"
brew_journal() {
  local list=$1 mode=$2; shift 2; local -a names; names=("$@"); local line name
  for line in ${(f)list}; do
    name=${line%% *}
    case $mode in
      only)   (( ${names[(Ie)$name]} )) || continue ;;
      except) (( ${names[(Ie)$name]} )) && continue ;;
    esac
    journal "$(print -r -- "$line" | sed -E 's/^([^ ]+) \(([^)]+)\) (<|!=) (.+)$/brew: \1 \2 → \4/')"
  done
}

sec_texlive() {
  # Erst ohne Root nachsehen, ob es überhaupt etwas gibt — sonst kostet der
  # Abschnitt lokal jedes Mal eine Touch-ID-Abfrage für nichts.
  local list n repo
  list=$(capture_t 300 tlmgr update --list --self --all 2>&1); capture_ok $? "tlmgr update --list" || return 0
  n=$(print -r -- "$list" | grep -cE '^(update|auto-install):|tlmgr itself')
  # mirror.ctan.org verteilt jeden Aufruf auf einen anderen Spiegel, und die sind
  # nicht synchron: am 18.09. listete der eine 4 Updates, der nächste hatte keine.
  # Deshalb den Spiegel der Liste für das Update festhalten.
  repo=$(grep -oE 'package repository [^ ]+' <<< "$list" | head -1 | awk '{print $3}')
  if grep -q 'older than remote repository' <<< "$list"; then
    action warn "$SECTION_NAME" "Neue TeX-Live-Jahresversion — MacTeX-Cask upgraden" "brew upgrade --cask mactex" "$(grep -A2 'older than' <<< "$list")"
    warn "TeX Live ist eine Jahresversion hinterher — MacTeX per brew upgraden (siehe Aktionen)"; return 0
  fi
  if (( n == 0 )); then ok "TeX Live aktuell — nichts zu tun"; return 0; fi
  info "$n Paket(e) mit Update:"; print -r -- "$list" | grep -E '^(update|auto-install):' | awk '{print $2}' | head -24 | paste -sd' ' - | fold -s -w 70 | bullets
  # TeX-Updates sind groß und brauchen sudo — Rückfrage (Antwort merkbar)
  if ! ask texlive "TeX Live: $n Paket(e) jetzt aktualisieren (sudo)?"; then
    warn "TeX Live übersprungen"
    action info "$SECTION_NAME" "$n TeX-Live-Paket(e) warten" "$SELF --plain --only texlive" "Antwort merken: beim interaktiven Lauf 'i' (immer) bzw. 'x' (nie) drücken — oder texlive=always in ${CONFDIR/#$HOME/~}/prefs eintragen."
    return 0
  fi
  local tlroot; tlroot=$(kpsewhich -var-value TEXMFROOT 2>/dev/null)
  local -a cmd; cmd=(tlmgr); [[ -n $repo ]] && cmd+=(--repository "$repo"); cmd+=(update --self --all)   # kein ${x:+a "$b"} — wird in zsh EIN Wort
  [[ -n $tlroot && ! -w $tlroot ]] && cmd=("${SUDO[@]}" "${cmd[@]}")
  if [[ $SUDO_MODE == none && ${cmd[1]} == sudo ]]; then
    warn "Übersprungen — braucht sudo: ${cmd[*]}"; (( SKIPPED+=1 )); return 0
  fi
  if ! run "${cmd[@]}" && grep -q 'older than remote repository' "$LAST_OUT" 2>/dev/null; then
    # Jahreswechsel bei TeX Live: tlmgr verweigert, bis MacTeX neu installiert ist —
    # kein Fehler des Laufs, sondern eine Entscheidung für den Nachgang
    undo_last_fail
    action warn "$SECTION_NAME" "Neue TeX-Live-Jahresversion — MacTeX-Cask upgraden" "brew upgrade --cask mactex" "$(grep -A2 'older than' "$LAST_OUT")"
    warn "TeX Live ist eine Jahresversion hinterher — MacTeX per brew upgraden (siehe Aktionen)"
  fi
}

# mas_verify <outdated-vorher> — mas meldet Erfolg auch dann, wenn das Update nicht ankommt:
# Eine App stand in 8 Läufen hintereinander als „Updated … 2026.0.3“ im Log
# und blieb doch 2026.0.2 (eine zweite Kopie der App; mas: „Multiple installations …
# exist“) — der Abschnitt war grün, das Journal zählte es 6× als Änderung. Deshalb
# nachfragen: was danach noch veraltet ist, wurde nicht aktualisiert. Kopien einer App
# findet Spotlight über die Store-ID (kMDItemAppStoreAdamID), unabhängig vom Ordnernamen.
mas_verify() {
  local before=$1 after l id rest name; local -a still copies done_l
  after=$(capture_t 120 mas outdated 2>/dev/null)
  capture_ok $? "mas outdated (Nachprüfung)" || return 0
  still=(${(f)"$(print -r -- "$after" | awk '{print $1}')"})
  for l in ${(f)before}; do
    l=${l##[[:space:]]#}; id=${l%%[[:space:]]*}; [[ $id == <-> ]] || continue
    rest=${${l#$id}##[[:space:]]#}; name=${rest% \(*}; name=${name%%[[:space:]]##}
    copies=(${(f)"$(mdfind "kMDItemAppStoreAdamID == $id" 2>/dev/null | grep -v '/\.Trash/')"})
    if (( ${still[(Ie)$id]} )); then
      warn "$name: mas meldet Erfolg, die App ist aber weiter veraltet"
      action warn "$SECTION_NAME" "App Store: $name bleibt veraltet" "mas upgrade $id" \
        "mas upgrade lief ohne Fehler durch, aber 'mas outdated' meldet $name danach weiter (${rest##* \(}.
${#copies} Kopie(n) laut Spotlight:
$(print -rl -- "${copies[@]}")"
    else
      done_l+=("$l")
    fi
    if (( ${#copies} > 1 )); then
      action warn "$SECTION_NAME" "Mehrfachinstallation: $name (${#copies} Kopien)" "" \
        "$(print -rl -- "${copies[@]}")
mas aktualisiert nur eine Kopie — die andere bleibt alt und steht im nächsten Lauf wieder als veraltet da. Die überzählige Kopie in den Papierkorb legen."
    fi
  done
  (( ${#done_l} )) && journal "$(print -rl -- "${done_l[@]}" | sed -E 's/^[0-9]+ +(.+) \(([^)]+) -> ([^)]+)\)$/mas: \1 \2 → \3/')"
  return 0
}

sec_mas() {
  local out n; out=$(capture_t 120 mas outdated 2>/dev/null)   # mas hängt gern am Apple-ID-Dialog
  capture_ok $? "mas outdated" || return 0
  n=$(count_lines "$out")
  PKG_MAS=$n; st pkg_mas $n; st_flush
  if (( n )); then
    info "$n App(s) mit Update:"; print -r -- "$out" | bullets
    # mas bleibt gern still an einem Apple-ID-Dialog hängen → Timeout
    if run_t 1800 mas upgrade && (( ! CHECK_ONLY && ! DRY_RUN )); then
      mas_verify "$out"
    fi
  else
    ok "Alle App-Store-Apps aktuell"
  fi
}

# Microsoft Office kommt über die Casks (microsoft-word, …; Updates im Abschnitt
# Homebrew, wenn die App hinter dem Current Channel liegt — Homebrew vergleicht die
# Bundle-Version). Microsoft AutoUpdate (MAU) bleibt physisch da, weil jeder
# Office-Installer es wieder mitbringt — es wird nur stillgelegt: kein eigener
# Prüflauf (msupdate --list kostete 25 s je Lauf), kein Hintergrund-Agent.
# Beides ohne sudo und idempotent; brew_post_upgrade ruft es nach Office-Upgrades.
# Nur wenn mau_redundant: kommt auch nur eine Office-App NICHT über brew, braucht sie MAU
# für ihre Updates — dann bleibt es aktiv.
mau_silence() {
  local changed=0 u; u=$(id -u)
  (( CHECK_ONLY || DRY_RUN )) && return 0
  if [[ $(defaults read com.microsoft.autoupdate2 HowToCheck 2>/dev/null) != Manual ]]; then
    defaults write com.microsoft.autoupdate2 HowToCheck -string Manual; changed=1
  fi
  # Der Agent liegt in /Library/LaunchAgents und würde bei jedem Login neu geladen —
  # 'disable' hält ihn dauerhaft draußen (Override-DB), 'bootout' beendet die Instanz.
  if ! launchctl print-disabled "gui/$u" 2>/dev/null | grep -q '"com.microsoft.update.agent" => disabled'; then
    launchctl disable "gui/$u/com.microsoft.update.agent" 2>/dev/null; changed=1
  fi
  if launchctl print "gui/$u/com.microsoft.update.agent" &>/dev/null; then
    launchctl bootout "gui/$u/com.microsoft.update.agent" 2>/dev/null; changed=1
  fi
  (( changed )) && info "Microsoft AutoUpdate wieder stillgelegt ${DIM}(Prüfmodus Manual, Agent dauerhaft aus)${NC}"
  return 0
}
# mau_redundant — 0, wenn ALLE installierten Office-Apps (Word … Teams; OneDrive hat einen
# eigenen Updater) von einem brew-Cask kommen. Prüft den Caskroom direkt statt 'brew list':
# brew_post_upgrade läuft zwischen 'brew upgrade' und tlmgr, und jeder brew-Start setzt dort
# das sudo-Ticket zurück.
mau_redundant() {
  local app tok n=0 cr=${HOMEBREW_PREFIX:-/opt/homebrew}/Caskroom
  for app in "${OFFICE_APPS[@]}"; do
    tok=${${${app:t:r}:l}// /-}
    [[ -d $cr/$tok ]] || return 1
    n=$(( n + 1 ))
  done
  (( n > 0 ))
}
sec_office() {
  local -a casks via_brew manual; local app tok why
  casks=(${(f)"$(brew list --cask 2>/dev/null)"})
  for app in "${OFFICE_APPS[@]}" /Applications/OneDrive.app(N); do
    tok=${${${app:t:r}:l}// /-}                 # "Microsoft Word.app" → microsoft-word, OneDrive.app → onedrive
    if why=$(app_broken "$app"); then         # nicht als „über brew“ zählen, sondern melden
      warn "${app:t:r} ist beschädigt ($why) — die App startet so nicht"
      action err "$SECTION_NAME" "${app:t:r} beschädigt — App-Paket unvollständig" "$( (( ${casks[(Ie)$tok]} )) && print -rn -- "brew reinstall --cask $tok")" \
        "$app: $why. brew führt die App weiter als installiert, und ohne Bundle-Version gilt sie dort als aktuell — deshalb sieht sie in brew upgrade und in der Nachkontrolle gesund aus. brew reinstall --cask $tok installiert sie neu (pkg-Installer, sudo, Office-großer Download); Microsoft AutoUpdate legt der nächste Lauf wieder still."
      continue
    fi
    if (( ${casks[(Ie)$tok]} )); then via_brew+=("${app:t:r}"); else manual+=("${app:t:r}	$tok"); fi
  done
  (( ${#via_brew} )) && ok "${#via_brew} Office-App(s) über brew ${DIM}(${(j:, :)via_brew} — Updates im Abschnitt Homebrew)${NC}"
  if (( ${#manual} )); then
    # Nicht per brew: übernehmen — die Office-Casks sind pkg-Installer, '--adopt' greift
    # dort nicht, brew installiert dieselbe Version einfach neu (sudo, 1–2 GB je App).
    # Ist die App NEUER als der Cask (OneDrive eilt dem Cask oft voraus), warten.
    local line name ver cver; local -a now later
    for line in "${manual[@]}"; do
      name=${line%%	*}; tok=${line#*	}
      ver=$(defaults read "/Applications/$name.app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)
      cver=$(brew info --cask --json=v2 "$tok" 2>/dev/null | jq -r '.casks[0].version // ""' 2>/dev/null)
      [[ -z $cver ]] && continue
      vercmp "${ver:-0}" "$cver"
      if (( $? == 1 )); then later+=("$name $ver (Cask: $cver)"); else now+=("$tok"); fi
    done
    (( ${#now} )) && action info "$SECTION_NAME" "${#now} Office-App(s) in brew übernehmen" "brew install --cask ${(j: :)now}" \
      "Installiert dieselbe Version neu (pkg, sudo, 1–2 GB je App). Danach hält brew sie aktuell; Microsoft AutoUpdate wird nach dem Lauf automatisch wieder stillgelegt."
    (( ${#later} )) && info "Cask hinkt der App hinterher — später übernehmen: ${(j:, :)later}"
    (( ${#now} )) && info "${#now} Office-App(s) noch nicht über brew: ${(j:, :)now} ${DIM}(siehe Aktionen)${NC}"
  fi
  if [[ -x "$MSUPDATE" ]] && mau_redundant; then
    mau_silence
    (( CHECK_ONLY || DRY_RUN )) && info "Microsoft AutoUpdate: stillgelegt (Prüfung im Check-/Dry-Run übersprungen)" || ok "Microsoft AutoUpdate stillgelegt ${DIM}(Prüfmodus Manual, Agent dauerhaft aus — Office kommt über brew)${NC}"
  elif [[ -x "$MSUPDATE" ]]; then
    info "Microsoft AutoUpdate bleibt aktiv ${DIM}(nicht alle Office-Apps kommen über brew)${NC}"
  fi
  (( SECTION_RUNS == 0 )) && (( SECTION_RUNS+=1 ))
  return 0
}

sec_node() {
  # Node kommt von brew (Formel node, Current-Linie) — Runtime-Update im Abschnitt
  # Homebrew. Versionsmanager wie nvm laufen hier nicht mit: ein ins Leere zeigender
  # Default fällt nicht auf, weil Shells dann still den brew-Node nehmen.
  has node && info "Node $(node --version 2>/dev/null) ${DIM}(brew)${NC}"
  if has npm; then
    # KEIN 'npm update -g': ohne Lockdatei schreibt es jedes Mal den ganzen globalen
    # Baum neu (1775 Pakete, 2 min, bei jedem Lauf) — und dabei Binaries wie
    # lean-ctx, die gerade ein MCP-Server braucht. Stattdessen: erst fragen, dann
    # nur das Veraltete installieren ('wanted' = innerhalb der Major-Version, wie
    # npm update; Major-Sprünge nur melden).
    if has jq; then
      local oj q_ok=1; oj=$(capture_t 180 npm outdated -g --json 2>/dev/null)   # rc 1 ist normal (= es gibt Veraltetes)
      capture_ok $? "npm outdated -g" || q_ok=0   # kein return: bun/pnpm/yarn unten laufen weiter
      [[ $oj == \{* ]] || oj='{}'
      local -a todo majors; local line name cur want latest; local -a f
      for line in ${(f)"$(jq -r 'to_entries[] | "\(.key)\t\(.value.current // "")\t\(.value.wanted // "")\t\(.value.latest // "")"' <<< "$oj" 2>/dev/null)"}; do
        f=("${(@s:	:)line}"); name=${f[1]}; cur=${f[2]}; want=${f[3]}; latest=${f[4]}
        [[ -n $want && $want != "$cur" ]] && todo+=("$name@$want")
        [[ -n $latest && $latest != "$want" ]] && majors+=("$name $cur → $latest")
      done
      if (( ${#todo} )); then
        info "${#todo} globale(s) npm-Paket(e) veraltet:"; print -rl -- "${todo[@]}" | bullets
        if run npm install -g "${todo[@]}" && (( ! CHECK_ONLY && ! DRY_RUN )); then
          for line in ${(f)"$(jq -r 'to_entries[] | select(.value.wanted != .value.current) | "npm: \(.key) \(.value.current) → \(.value.wanted)"' <<< "$oj" 2>/dev/null)"}; do journal "$line"; done
        fi
      elif (( q_ok )); then
        ok "Globale npm-Pakete aktuell ${DIM}($(npm ls -g --depth=0 --parseable 2>/dev/null | tail -n +2 | grep -c .) Pakete)${NC}"
      fi
      (( ${#majors} )) && action info "$SECTION_NAME" "npm: Major-Updates verfügbar" "npm outdated -g" "${(F)majors}"
    else
      run npm update -g
    fi
  else skip "npm"; fi
  if has bun; then run bun upgrade; else skip "bun"; fi   # kein 'bun update' — würde package.json im CWD anfassen
  if has pnpm; then run pnpm up -g; else skip "pnpm"; fi
  if has yarn; then
    if yarn --version 2>/dev/null | grep -q '^1\.'; then run yarn global upgrade
    else ok "yarn ≥2 (corepack) — kein 'global upgrade' nötig"; fi
  else skip "yarn"; fi
}

sec_python() {
  if has pipx; then run pipx upgrade-all; run pipx upgrade-shared; else skip "pipx"; fi
  if has uv; then
    run uv tool upgrade --all
    brew list --formula uv &>/dev/null || run uv self update
  else skip "uv"; fi
}

sec_rust() {
  run rustup update
  if has cargo-install-update; then run cargo install-update -a
  else warn "cargo-install-update fehlt — 'cargo install cargo-update' zum Aktivieren"; fi
}

sec_php() { run composer global update; }

sec_runtimes() {
  if has mise; then
    brew list --formula mise &>/dev/null || run mise self-update
    run mise upgrade
  fi
  if has asdf; then run asdf update; run asdf plugin update --all; fi
}

sec_cloud() {
  if has gcloud; then run gcloud components update --quiet; else skip "gcloud"; fi
  if has helm; then run helm repo update; else skip "helm"; fi
  if has gh; then
    if [[ -n "$(gh extension list 2>/dev/null)" ]]; then run gh extension upgrade --all
    else ok "gh ohne Extensions — nichts zu tun"; fi
  else skip "gh"; fi
}

sec_shell() {
  [[ -f "$HOME/.oh-my-zsh/tools/upgrade.sh" ]] && run zsh "$HOME/.oh-my-zsh/tools/upgrade.sh"
  [[ -f "$HOME/.zinit/bin/zinit.zsh" ]] && run zsh -c "source $HOME/.zinit/bin/zinit.zsh && zinit self-update && zinit update --all"
}

sec_editors() {
  local n; n=$(code --list-extensions 2>/dev/null | grep -c .)
  info "VS Code: $n Extension(s) installiert"
  # NODE_NO_WARNINGS: die code-CLI (Electron als Node) meldet sonst bei jedem Lauf eine
  # DeprecationWarning (DEP0169 url.parse) — Rauschen, das nichts mit den Extensions zu tun hat
  NODE_NO_WARNINGS=1 run code --update-extensions
}

sec_ai() {
  if has tldr; then run tldr --update; else skip "tldr"; fi
  if has claude; then
    run claude update
    local plugins="$HOME/.claude/plugins/installed_plugins.json"
    if [[ -f $plugins ]] && has jq; then
      run claude plugin marketplace update
      # Nur aktivierte Plugins im user-Scope; projektgebundene (scope=project)
      # lassen sich nur aus dem Projektordner heraus aktualisieren → Hinweis.
      local line p scope ppath enabled; local -a f; local skipped=0
      for line in ${(f)"$(jq -r '.plugins | to_entries[] | .key as $k | .value[] | "\($k)\t\(.scope)\t\(.projectPath // "")"' "$plugins" 2>/dev/null)"}; do
        f=("${(@s:	:)line}"); p=${f[1]}; scope=${f[2]}; ppath=${f[3]}
        enabled=$(jq -r --arg p "$p" '.enabledPlugins[$p] // false' "$HOME/.claude/settings.json" 2>/dev/null)
        [[ $enabled == true ]] || { (( skipped+=1 )); continue; }
        case $scope in
          user) run claude plugin update "$p" ;;
          *)    action info "$SECTION_NAME" "Claude-Plugin $p ist ${scope}-gebunden" "cd '${ppath:-.}' && claude plugin update -s $scope $p" "Scope: $scope${ppath:+ · Projekt: $ppath}" ;;
        esac
      done
      (( skipped )) && info "${DIM}$skipped deaktivierte(s) Plugin(s) übersprungen${NC}"
    fi
  else skip "claude"; fi
  # opencode (Formel) und codex (Cask) kommen über brew — beides prüfen, sonst
  # meldet der Abschnitt fälschlich „Installationsweg prüfen"
  if has opencode; then
    if brew list --formula opencode &>/dev/null || brew list --cask opencode &>/dev/null; then ok "opencode wird bereits von Homebrew aktualisiert"
    else run opencode upgrade; fi
  else skip "opencode"; fi
  if has codex; then
    if brew list --formula codex &>/dev/null || brew list --cask codex &>/dev/null; then ok "codex wird bereits von Homebrew aktualisiert"
    else ok "codex: Update über den Installationsweg (npm) prüfen"; fi
  fi
  if has pi; then
    # pi (brew-Formula pi-coding-agent) kommt über brew. Seine Extensions sind
    # npm-Pakete mit Lifecycle-Scripts (heute regelt ~/.npmrc allow-scripts=…);
    # falls dort je wieder ignore-scripts=true steht, hebt npm_config_ignore_scripts=false
    # das NUR für diesen Befehl auf.
    if ! pi --version &>/dev/null; then
      warn "pi ist defekt — repariere (brew reinstall mit aktivierten npm-Scripts)"
      run env npm_config_ignore_scripts=false brew reinstall pi-coding-agent
    fi
    run env npm_config_ignore_scripts=false pi update --extensions
  else skip "pi"; fi
}

sec_ollama() {
  if ! ollama list >/dev/null 2>&1; then
    warn "Ollama-Server nicht erreichbar — Modelle übersprungen"; return 0
  fi
  local models m n; models=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}'); n=$(count_lines "$models")
  if (( n == 0 )); then ok "Keine Modelle installiert"; return 0; fi
  info "$n Modell(e) installiert — prüfe auf neue Versionen"
  for m in ${(f)models}; do run ollama pull "$m"; done
}

sec_docker() {
  if ! docker info >/dev/null 2>&1; then warn "Docker läuft nicht — Images übersprungen"; return 0; fi
  local -a imgs; local i
  imgs=(${(f)"$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -E ':(latest|main|master|stable|dev|edge)$')"})
  if (( ${#imgs} == 0 )); then ok "Keine Images mit Floating-Tags"; return 0; fi
  info "${#imgs} Image(s) mit Floating-Tag:"; print -rl -- "${imgs[@]}" | bullets
  for i in "${imgs[@]}"; do run docker pull "$i"; done
  run docker image prune -f
}

# app_broken <app> — 0 + Grund auf stdout, wenn das App-Paket unvollständig ist (keine
# Info.plist oder kein Programm in Contents/MacOS). Anlass: Eine Office-App war ein leeres
# Gerüst (0 B): brew führte sie als installiert, ohne Bundle-Version galt sie in brews
# Vergleich als „aktuell, nur Buchführung hinkt“, der Office-Abschnitt zählte sie als
# „über brew“, die Nachkontrolle meldete „nichts offen“ — gut zwei Wochen lang unbemerkt.
app_broken() {
  local a=$1; local -a exe
  [[ -d $a/Wrapper ]] && return 1              # iOS-App, anderer Aufbau
  [[ -f $a/Contents/Info.plist ]] || { print -r -- "Info.plist fehlt"; return 0; }
  exe=("$a"/Contents/MacOS/*(N))
  (( ${#exe} )) || { print -r -- "kein Programm in Contents/MacOS"; return 0; }
  return 1
}

# Apps-Radar: Was wird von brew/mas NICHT abgedeckt — und ist es aktuell?
sec_apps() {
  local -a casks masapps
  casks=(${(f)"$(brew list --cask 2>/dev/null)"})
  masapps=(${(f)"$(mas list 2>/dev/null | sed -E 's/^[0-9]+ +//; s/ +\([^)]*\)$//')"})

  # 1) MacUpdater-CLI (kennt auch Apps ohne Sparkle-Feed)
  if [[ -x "$MACUPDATER" ]]; then
    # 'list' startet die App nicht, 'scan'/'update' schon — nach einem Remote-Lauf soll keine
    # fremde GUI offen bleiben, also merken, ob sie vorher lief, und sie sonst wieder beenden
    local mu_was=0; pgrep -qx MacUpdater 2>/dev/null && mu_was=1
    (( APPS && ! CHECK_ONLY && ! DRY_RUN )) && run "$MACUPDATER" scan --outdated --quiet
    # erst einfangen, dann filtern: in $(capture_t … | grep …) wäre $? der rc von grep
    local list q_ok=1; list=$(capture_t 120 "$MACUPDATER" list --hide-uptodate-apps --hide-mas-apps --hide-unsupported-apps --quiet 2>/dev/null)
    capture_ok $? "macupdater list" || q_ok=0   # kein return: Sparkle-Abgleich und Cask-Migration unten laufen weiter
    list=$(print -r -- "$list" | grep -v '^Last Scan')
    local nl=$(count_lines "$list")
    if (( nl )); then
      warn "MacUpdater meldet $nl veraltete App(s):"; print -r -- "$list" | bullets
      action warn "$SECTION_NAME" "$nl manuell installierte App(s) veraltet (MacUpdater)" "$SELF --plain --apps --only apps" "$list"
      if (( APPS && ! CHECK_ONLY )); then
        local l app
        for l in ${(f)list}; do
          app=$(print -r -- "$l" | grep -oE '/Applications/[^:]+\.app' | head -1)
          [[ -n $app ]] && run "$MACUPDATER" update --quiet "$app"
        done
      fi
    elif (( q_ok )); then
      # Ehrlich bleiben: MacUpdater scannt hier nur mit --apps, sonst gilt sein letzter eigener
      # Scan — der war einmal über zwei Wochen alt, und der Radar meldete trotzdem grün „alle
      # aktuell“. Ab 7 Tagen ist das ein unbekannter Stand, kein aktueller (MacUpdater ist
      # eingestellt; 3.4.0 ersetzt ihn).
      local mu_d mu_e
      mu_d=$(capture_t 60 "$MACUPDATER" list --quiet 2>/dev/null | grep '^Last Scan' | sed 's/Last Scan Date : //')
      mu_e=$(date -j -f '%d.%m.%y, %H:%M:%S' "$mu_d" +%s 2>/dev/null)
      if [[ $mu_e == <-> ]] && (( EPOCHSECONDS - mu_e > 7 * 86400 )); then
        info "MacUpdater: letzter Scan $(fmt_age $(( EPOCHSECONDS - mu_e ))) ($mu_d) — Stand veraltet, nicht als aktuell gewertet ${DIM}(frisch scannen: --apps)${NC}"
      else
        ok "MacUpdater: alle bekannten Apps aktuell ${DIM}($mu_d)${NC}"
      fi
    fi
    if (( ! mu_was )) && pgrep -qx MacUpdater 2>/dev/null; then
      pkill -TERM -x MacUpdater 2>/dev/null && info "MacUpdater wieder beendet ${DIM}(lief vor dem Lauf nicht)${NC}"
    fi
  fi

  # Welche .app gehört zu einem installierten Cask? Exakt aus den Cask-Artefakten
  # (App-Namen), nicht aus geratenen Slugs.
  local -a caskapps unmanaged; local -A app2tok; local ca_t ca_a
  if has jq; then   # eine Abfrage: Cask-Name und App je Zeile — der Name liefert den Reparaturbefehl
    while IFS=$'\t' read -r ca_t ca_a; do
      [[ -n $ca_a ]] || continue; ca_a=${ca_a:t}; caskapps+=("$ca_a"); app2tok[$ca_a]=$ca_t
    done < <(brew info --cask --json=v2 --installed 2>/dev/null | jq -r '.casks[] | .token as $t | .artifacts[] | .app? // empty | .[] | (if type=="string" then . elif type=="object" then (.target // empty) else empty end) | "\($t)\t\(.)"' 2>/dev/null)
  fi
  # Beschädigte App-Pakete (app_broken) — Office meldet sein Abschnitt selbst
  local app name why btok; local -a broken
  for app in /Applications/*.app(N); do
    (( ${OFFICE_APPS[(Ie)$app]} )) && continue; [[ ${app:t} == OneDrive.app ]] && continue
    why=$(app_broken "$app") || continue
    btok=${app2tok[${app:t}]:-}; [[ -z $btok && ${casks[(Ie)${${${app:t:r}:l}// /-}]} -gt 0 ]] && btok=${${${app:t:r}:l}// /-}
    broken+=("${app:t:r}")
    local bdet="$app: $why — die App startet so nicht. "
    if [[ -n $btok ]]; then bdet+="Sie gehört zum Cask $btok; brew reinstall --cask $btok stellt sie wieder her (pkg-Casks fragen nach sudo)."
    else bdet+="Keinem installierten Cask zugeordnet: über den Hersteller oder den App Store neu installieren."; fi
    action err "$SECTION_NAME" "${app:t:r} beschädigt — App-Paket unvollständig" "${btok:+brew reinstall --cask $btok}" "$bdet"
  done
  (( ${#broken} )) && warn "${#broken} App(s) beschädigt — App-Paket unvollständig: ${(j:, :)broken}"
  for app in /Applications/*.app(N); do
    name=${app:t:r}
    [[ -d "$app/Wrapper" || -d "$app/Contents/_MASReceipt" ]] && continue      # iOS-App / App Store
    (( ${masapps[(Ie)$name]} )) && continue
    (( ${caskapps[(Ie)${app:t}]} )) && continue
    [[ $name == Safari ]] && continue
    unmanaged+=("$app")
  done

  # 2) Sparkle-Feeds der Apps, die weder Cask noch App Store sind — seit 3.4.0 auch in
  #    Unterordnern und ~/Applications (TeX-Werkzeuge: BibDesk, LaTeXiT, TeX Live Utility,
  #    TeXShop). Nur dieser Teil schaut dorthin; Übernahme-Vorschläge bleiben oberste Ebene.
  local -a sparkle_extra
  for app in /Applications/*/*.app(N) ~/Applications/*.app(N) ~/Applications/*/*.app(N); do
    [[ ${app:h} == *.app ]] && continue                                         # Helfer in einem Bundle
    [[ -d "$app/Wrapper" || -d "$app/Contents/_MASReceipt" ]] && continue
    (( ${caskapps[(Ie)${app:t}]} )) && continue
    sparkle_extra+=("$app")
  done
  local feed cur; local -a jobs pids; local tmp="$RUNDIR/sparkle"; mkdir -p "$tmp"
  for app in "${unmanaged[@]}" "${sparkle_extra[@]}"; do
    name=${app:t:r}
    feed=$(defaults read "$app/Contents/Info.plist" SUFeedURL 2>/dev/null)
    [[ $feed == http* ]] || continue
    cur=$(defaults read "$app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)
    # Versionsstrings aus dem Feed sind Fremddaten: nur Versionszeichen durchlassen
    ( curl -sL --max-time 6 "$feed" 2>/dev/null \
        | grep -oE 'sparkle:shortVersionString="[^"]+"|<sparkle:shortVersionString>[^<]+' \
        | sed -E 's/.*"([^"]+)"$/\1/; s/.*>//' | tr -cd '0-9A-Za-z.,+_\n-' > "$tmp/${name// /_}" ) &
    pids+=($!); jobs+=("$name	$cur")
  done
  (( ${#pids} )) && wait "${pids[@]}"   # NICHT 'wait' ohne Argument: das wartete auch auf die Cache-Messung (du, Minuten)
  local checked=0 behind=0 line v best
  for line in "${jobs[@]}"; do
    name=${line%%	*}; cur=${line#*	}; best=""
    [[ -f "$tmp/${name// /_}" ]] || continue
    for v in ${(f)"$(<"$tmp/${name// /_}")"}; do
      [[ -z $best ]] && { best=$v; continue; }
      vercmp "$v" "$best"; (( $? == 1 )) && best=$v
    done
    [[ -z $best ]] && continue
    (( checked+=1 ))
    vercmp "$best" "$cur"
    if (( $? == 1 )); then
      (( behind+=1 ))
      action warn "$SECTION_NAME" "$name $cur → $best (Sparkle)" "open -a ${(qq)name}" \
        "Nicht über brew upgrade oder den App Store aktualisiert (manuell installiert oder Teil eines pkg-Casks wie mactex). Update über das App-Menü (Nach Updates suchen); gibt es einen eigenen Cask, lässt sie sich migrieren: brew search --cask ${(qq)${name%% *}}"
    fi
  done
  if (( checked )); then
    (( behind )) && warn "$behind von $checked Sparkle-App(s) veraltet (siehe Aktionen)" || ok "$checked Sparkle-App(s) außerhalb brew/mas sind aktuell"
  fi

  # 3) Cask-Migration: manuell installierte Apps, die es als Cask gibt.
  #    'brew install --cask --adopt' übernimmt die vorhandene App, wenn die
  #    Version passt — danach ist sie Teil von 'brew upgrade'. Bewusst
  #    ausgenommen: prefs adopt_ignore (Standard parallels — bei brew abgemeldet,
  #    weil Cask-Upgrades seinen Launch-Daemon zerstören). Muster gegen Cask-Namen und
  #    Bundle-ID, siehe adopt_ignored. Gilt auch für „Cask hinkt“ weiter unten.
  local -a alltokens cands; local tok base t found bid
  local ign=$(grep -s '^adopt_ignore=' "$CONFDIR/prefs" | cut -d= -f2-); ign=${ign:-parallels}
  alltokens=(${(f)"$(brew casks 2>/dev/null)"})
  for app in "${unmanaged[@]}"; do
    name=${app:t:r}
    (( ${OFFICE_APPS[(Ie)$app]} )) && continue; [[ $name == OneDrive ]] && continue   # Abschnitt Office
    base=${${name:l}//[^a-z0-9 +.-]/}; base=${base%% [0-9]*}; base=${base%%-[0-9]*}   # "GraphicConverter 12" → "graphicconverter", "texstudio-4.9.7-osx-m1" → "texstudio"
    found=""
    for t in "${base// /-}" "${base// /}" "${base// /-}-app" "${base// /}-app"; do   # kein Erstwort-Fallback: "Digital Paper App" ≠ Cask "digital"
      [[ -n $t && ${#t} -ge 3 ]] || continue
      (( ${alltokens[(Ie)$t]} )) || continue
      (( ${casks[(Ie)$t]} )) && { found=""; break; }   # Cask ist schon installiert (pkg-Cask ohne .app-Artefakt)
      found=$t; break
    done
    if [[ -n $found ]]; then   # Bundle-ID erst hier lesen — nur für Apps, die es als Cask gibt
      bid=$(defaults read "$app/Contents/Info.plist" CFBundleIdentifier 2>/dev/null)
      adopt_ignored "$ign" "$found" "$bid" && found=""
    fi
    [[ -n $found ]] && cands+=("$name	$found")
  done
  if (( ${#cands} )); then
    # Versionsabgleich: --adopt greift nur, wenn App- und Cask-Version gleich sind.
    # Neuere App → Cask hinkt, warten. Ältere App → App zuerst aktualisieren.
    local -a fit older newer; local cver ver build
    local cv_json; cv_json=$(brew info --cask --json=v2 ${(f)"$(print -rl -- "${cands[@]}" | cut -f2)"} 2>/dev/null)
    for t in "${cands[@]}"; do
      name=${t%%	*}; tok=${t#*	}
      cver=$(jq -r --arg t "$tok" '.casks[] | select(.token==$t) | .version // ""' <<< "$cv_json" 2>/dev/null)
      ver=$(defaults read "/Applications/$name.app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)
      build=$(defaults read "/Applications/$name.app/Contents/Info.plist" CFBundleVersion 2>/dev/null)
      if [[ -z $cver || -z $ver ]]; then fit+=("$tok"); continue; fi
      # Cask-Versionen tragen oft Build/Kommasuffix ("16.113.26091433", "4.9,1234") — Kurz-
      # oder Build-Version der App, die den Cask-Anfang bildet, gilt als passend
      if [[ $cver == $ver || $cver == $build || $cver == ${ver}[.,]* || $cver == ${build}[.,]* ]]; then fit+=("$tok"); continue; fi
      vercmp "$ver" "$cver"
      case $? in 0) fit+=("$tok") ;; 1) newer+=("$name $ver > Cask $cver") ;; 2) older+=("$name $ver < Cask $cver") ;; esac
    done
    if (( ${#fit} )); then
      info "${#fit} manuell installierte App(s) gibt es als Cask — Übernahme macht sie Teil von brew upgrade"
      action info "$SECTION_NAME" "${#fit} App(s) als Cask übernehmbar (--adopt)" "brew install --cask --adopt ${(j: :)fit}" \
        "${(F)fit}

--adopt übernimmt die vorhandene App unverändert (Version passt zum Cask). Danach hält brew sie aktuell; Self-Updater-Casks nur, wenn die App hinterherhinkt."
    fi
    (( ${#newer} )) && info "Cask hinkt der App hinterher — Übernahme später: ${(j:, :)newer}"
    (( ${#older} )) && action info "$SECTION_NAME" "${#older} App(s) älter als ihr Cask — erst aktualisieren, dann übernehmen" "" "${(F)older}

App über ihren eigenen Updater aktualisieren, dann brew install --cask --adopt <token>; oder direkt ersetzen: brew install --cask --force <token>."
  fi

  # 4) Einzelfälle mit bekanntem Update-Kanal
  if [[ -d /Applications/Ollama.app ]] && (( ${casks[(Ie)ollama-app]} == 0 )); then
    local ov gv; ov=$(defaults read /Applications/Ollama.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null)
    gv=$(curl -s --max-time 6 https://api.github.com/repos/ollama/ollama/releases/latest 2>/dev/null | grep -oE '"tag_name": *"v?[0-9.]+"' | grep -oE '[0-9.]+')
    if [[ -n $ov && -n $gv ]]; then
      vercmp "$gv" "$ov"
      if (( $? == 1 )); then
        warn "Ollama.app $ov — GitHub: $gv"
        action warn "$SECTION_NAME" "Ollama.app $ov → $gv" "brew install --cask ollama-app" "Ollama ist manuell installiert (Self-Updater). Migration auf den Cask macht es Teil von brew upgrade."
      else ok "Ollama.app $ov aktuell"; fi
    fi
  fi
  # Parallels: NICHT die Existenz der Daemon-Plist prüfen — Parallels legt
  # /Library/LaunchDaemons/com.parallels.desktop.launchdaemon.plist beim App-Start an und
  # entfernt sie beim Beenden wieder (im Systemlog belegt: backgroundtaskmanagementd
  # „removing … launchd_wrapper", dann launchd „removing service", während die App endet).
  # Die fehlende Plist ist also der Normalzustand, solange Parallels aus ist; 3.3.1 hat
  # daraus fälschlich einen Defekt gemacht und bei jedem Lauf gemeckert.
  # Was wirklich zählt: ob der laufende Dienst ansprechbar ist. Deshalb nur prüfen, wenn
  # prl_disp_service läuft — dann ist 'prlctl list' eine echte Funktionsprobe (kein sudo,
  # startet nichts). Meldet sie „unattended mode", fehlt dem Dienst der Daemon und die
  # Plist-Reparatur ist der Fix.
  if [[ -d "/Applications/Parallels Desktop.app" ]] && pgrep -qf 'MacOS/prl_disp_service' 2>/dev/null; then
    local pout prlc=/usr/local/bin/prlctl
    [[ -x $prlc ]] || prlc="/Applications/Parallels Desktop.app/Contents/MacOS/prlctl"
    if [[ -x $prlc ]]; then
      pout=$(capture_t 30 "$prlc" list --all 2>&1)
      if print -r -- "$pout" | grep -qiE 'unattended mode|failed to (initialize|connect)'; then
        local pld=/Library/LaunchDaemons/com.parallels.desktop.launchdaemon.plist
        local psrc="/Applications/Parallels Desktop.app/Contents/MacOS/Parallels Service.app/Contents/Resources/com.parallels.desktop.launchdaemon.plist"
        warn "Parallels-Dienst läuft, antwortet aber nicht — Launch-Daemon fehlt"
        action err "$SECTION_NAME" "Parallels: Dienst antwortet nicht (Launch-Daemon fehlt)" \
          "sudo cp ${(qq)psrc} $pld && sudo xattr -dr com.apple.quarantine $pld && sudo launchctl bootstrap system $pld" \
          "prlctl meldete: ${pout[1,200]}
Die Daemon-Plist liegt im App-Bundle; der Fix kopiert sie nach /Library/LaunchDaemons, entfernt die Quarantäne (launchd lädt quarantinierte Plists nicht) und lädt den Daemon. Danach VMs erneut starten. Hinweis: Parallels entfernt die Plist beim Beenden der App wieder — das ist normal und kein Fehler."
      else
        ok "Parallels: Dienst antwortet ${DIM}($(print -r -- "$pout" | grep -c '^{') VM(s))${NC}"
      fi
    fi
  fi
  if [[ -d "/Library/Internet Plug-Ins/JavaAppletPlugin.plugin" ]]; then
    local jv; jv=$("/Library/Internet Plug-Ins/JavaAppletPlugin.plugin/Contents/Home/bin/java" -version 2>&1 | head -1 | grep -oE '"[^"]+"' | tr -d '"')
    action info "$SECTION_NAME" "Oracle-Java-Plugin $jv installiert — Updates nur über Systemeinstellungen › Java" \
      "open '/Library/PreferencePanes/JavaControlPanel.prefPane' 2>/dev/null || open -b com.oracle.java.Java-Updater" \
      "Falls nicht mehr benötigt: sudo rm -rf '/Library/Internet Plug-Ins/JavaAppletPlugin.plugin' '/Library/PreferencePanes/JavaControlPanel.prefPane'"
  fi
  if has jq && has brew; then
    # Namen im Titel: dann lässt sich genau dieser Stand als erledigt markieren (^A),
    # und ein neues veraltetes Paket erzeugt wieder eine frische Aktion
    local dep; dep=$(brew info --json=v2 --installed 2>/dev/null | jq -r '(.formulae[] | select(.deprecated or .disabled) | "\(.name) — \(if .disabled then "deaktiviert" else "veraltet" end): \(.disable_reason // .deprecation_reason // "?")"), (.casks[] | select(.deprecated or .disabled) | "\(.token) — \(if .disabled then "deaktiviert" else "veraltet" end): \(.disable_reason // .deprecation_reason // "?")")' 2>/dev/null)
    [[ -n $dep ]] && action info "$SECTION_NAME" "Homebrew: veraltet/deaktiviert: $(print -r -- "$dep" | cut -d' ' -f1 | sort | paste -sd, - | cut -c1-60)" "brew doctor" "$dep

Bewusst behalten? Dann hier ^A (erledigt) — ein neues veraltetes Paket erscheint als neue Aktion."
  fi
  (( SECTION_RUNS == 0 )) && (( SECTION_RUNS+=1 ))
  return 0
}

sec_cleanup() {
  run brew autoremove
  run brew cleanup --prune=7
  if has uv; then
    # Ein laufender uvx-Prozess (z. B. ein MCP-Server wie chroma-mcp) hält den
    # Cache-Lock — 'uv cache prune' würde ewig warten. --force wäre riskant,
    # weil uvx-Umgebungen im Cache liegen.
    local uvbusy; uvbusy=$(pgrep -fl '(^|/)uvx?( |$)' 2>/dev/null | head -3 | cut -c1-90)
    if [[ -n $uvbusy ]]; then
      info "uv-Cache belegt (uv/uvx-Prozess läuft) — 'uv cache prune' übersprungen"
      action info "$SECTION_NAME" "uv cache prune wartet auf laufende uvx-Prozesse" "uv cache prune" "Laufende Prozesse:
$uvbusy

Ausführen, wenn keine MCP-Server/uvx-Tools laufen (z. B. Claude Code beendet). '--force' meiden: uvx-Umgebungen liegen im Cache."
    else
      run_t 300 uv cache prune
    fi
  fi
  # Brewfile-Snapshot: Wiederaufsetzen mit 'brew bundle --file ~/.config/update-all/Brewfile'
  mkdir -p "$CONFDIR"
  if (( ! DRY_RUN )) && brew bundle dump --force --file="$CONFDIR/Brewfile" 2>/dev/null; then
    ok "Brewfile-Snapshot: ${CONFDIR/#$HOME/~}/Brewfile ($(grep -cE '^(brew|cask|tap|mas|vscode) ' "$CONFDIR/Brewfile") Einträge)"
  fi
  # Cache-Kennzahlen (uv legt gern zweistellige GB ab) — gemessen im Hintergrund seit Laufstart
  [[ -n $CACHE_PID ]] && { wait "$CACHE_PID" 2>/dev/null; CACHE_PID=""; }
  local line total=0 lines="" uv_kb=0 npm_kb=0; local -a f
  for line in ${(f)"$([[ -f "$RUNDIR/caches" ]] && cat "$RUNDIR/caches")"}; do   # $(<…) ignoriert 2>/dev/null in zsh
    f=("${(@s:	:)line}"); (( total += f[1] ))
    [[ ${f[2]} == */.cache/uv ]] && uv_kb=${f[1]}
    [[ ${f[2]} == */.npm/_cacache ]] && npm_kb=${f[1]}
    lines+="$(printf '%6.1f GB  %s' $(( f[1] / 1048576.0 )) "${f[2]/#$HOME/~}")"$'\n'
  done
  st caches "$(printf '%.1f' $(( total / 1048576.0 )))"
  info "Caches gesamt: $(printf '%.1f' $(( total / 1048576.0 ))) GB"; print -rn -- "$lines" | bullets
  (( uv_kb > 10485760 )) && action info "$SECTION_NAME" "uv-Cache > 10 GB" "uv cache clean" "$lines"
  npm_cache_trim "$npm_kb"
  storage_report
  return 0
}

# npm_cache_trim <kb> — npm-Cache ab 3 GB leeren (er wuchs in sechs Wochen von 2,7 auf 6,0 GB).
# 'npm cache clean --force' löscht nur ~/.npm/_cacache — ~/.npm/_npx mit den per npx
# gestarteten MCP-Servern bleibt (im Scratch-Cache geprüft). Danach laden npm/npx nur wieder,
# was sie brauchen. Mit -y ohne Nachfrage; prefs npm_cache=never schaltet es ab.
# Nicht, solange eine npm-Installation läuft (die schreibt gerade in den Cache) — ein laufender
# npx-Server ('npm exec') stört nicht, sein Paket liegt in _npx.
npm_cache_trim() {
  local kb=${1:-0} gb busy
  has npm && [[ $kb == <-> ]] && (( kb > 3 * 1048576 )) || return 0
  gb=$(printf '%.1f' $(( kb / 1048576.0 )))
  if (( DRY_RUN )); then info "(dry-run) npm-Cache $gb GB — würde ab 3 GB geleert"; return 0; fi
  busy=$(pgrep -fl 'npm(-cli\.js)? (install|i|ci|update|up|uninstall|rm|add)( |$)' 2>/dev/null | head -2 | cut -c1-90)
  if [[ -n $busy ]]; then info "npm-Cache $gb GB — nicht geleert, eine npm-Installation läuft ${DIM}($busy)${NC}"; return 0; fi
  if ask npm_cache "npm-Cache ist $gb GB — leeren? (npm cache clean --force; _npx bleibt)"; then
    run npm cache clean --force && journal "npm: Cache geleert ($gb GB)"
  fi
  return 0
}

# storage_report — große Brocken, die kein Cache-Aufräumen erfasst. Bewusst kein Aufruf eines
# Allzweck-Reinigers wie Mole: dessen Vorschau brauchte im Test 109–112 s, meldete nur 673 MB als
# frei, und 'mo clean' hätte auch den uv-Cache eines laufenden MCP-Servers geleert. Nur messen und
# melden, nie löschen.
#   Docker       nur, wenn der Daemon schon läuft — Docker Desktop wird dafür nie gestartet
#   Worktrees    alte Agent-Worktrees (<worktree_roots>/*/.claude/worktrees), gemessen in measure_caches
storage_report() {
  local out img bc tot l kb=0; local -a wl
  if has docker && capture_t 15 docker info >/dev/null 2>&1; then
    out=$(capture_t 30 docker system df --format '{{.Type}}	{{.Reclaimable}}' 2>/dev/null)
    # „9.78GB (45%)“ → GB; docker nennt B/kB/MB/GB/TB
    img=$(print -r -- "$out" | awk -F'\t' '$1=="Images"' | docker_gb)
    bc=$(print -r -- "$out" | awk -F'\t' '$1=="Build Cache"' | docker_gb)
    tot=$(awk -v a="${img:-0}" -v b="${bc:-0}" 'BEGIN { printf "%.1f", a + b }')
    if awk -v t="$tot" 'BEGIN { exit !(t >= 5) }'; then
      info "Docker: $tot GB freigebbar ${DIM}(Images $img GB · Build-Cache $bc GB)${NC}"
      action info "$SECTION_NAME" "Docker belegt freigebbaren Platz" "$(awk -v b="${bc:-0}" 'BEGIN { exit !(b >= 1) }' && print -rn -- 'docker builder prune -f')" \
        "Freigebbar laut docker system df („Reclaimable“): Images $img GB, Build-Cache $bc GB.
docker builder prune -f — entfernt verwaisten Build-Cache (sicher; wie viel davon frei wird, zeigt der Befehl selbst). Mit -a auch noch verwendbare Schichten — der nächste Build dauert dann länger.
docker image prune -a — entfernt ALLE nicht von einem Container genutzten Images; die müssen danach neu geladen werden. Bewusst nicht als Fix hinterlegt."
    fi
  fi
  [[ -f "$RUNDIR/worktrees" ]] && wl=("${(@f)$(<"$RUNDIR/worktrees")}")
  for l in "${wl[@]}"; do [[ ${l%%	*} == <-> ]] && (( kb += ${l%%	*} )); done
  if (( kb > 2 * 1048576 )); then
    local det="" gbw p; local -a repos; gbw=$(printf '%.1f' $(( kb / 1048576.0 )))
    for l in "${wl[@]}"; do
      [[ ${l%%	*} == <-> ]] || continue
      p=${l#*	}; repos+=("${${p%/.claude/worktrees}:t}")
      det+="$(printf '%6.1f GB  %s' $(( ${l%%	*} / 1048576.0 )) "${p/#$HOME/~}")"$'\n'
    done
    info "Agent-Worktrees: $gbw GB ${DIM}(${(j:, :)repos})${NC}"
    action info "$SECTION_NAME" "Alte Agent-Worktrees belegen Platz" "" \
      "${det}Worktrees bleiben liegen, wenn eine Agent-Sitzung endet. Erst prüfen, ob dort noch Arbeit liegt: git -C <repo> worktree list, dann je Worktree git worktree remove <pfad> (verweigert bei uncommitteten Änderungen). Bewusst kein Fix-Befehl — Löschen kann Arbeit kosten."
  fi
  return 0
}
# docker_gb — liest „Typ<TAB>9.78GB (45%)“ von stdin, gibt die Größe in GB aus
docker_gb() {
  awk -F'\t' '{ s = $2; sub(/ .*/, "", s); n = s + 0; u = s; gsub(/[0-9.]/, "", u)
    f = (u == "TB") ? 1024 : (u == "GB") ? 1 : (u == "MB") ? 1/1024 : (u == "kB" || u == "KB") ? 1/1048576 : 0
    printf "%.1f", n * f }'
}
measure_caches() {   # läuft im Hintergrund, schreibt "KB<TAB>Pfad" je Cache
  local d out=""
  for d in ~/.cache/uv ~/Library/Caches/Homebrew ~/.npm/_cacache ~/Library/Caches/pip ~/.cache/huggingface; do
    [[ -d $d ]] && out+="$(du -sk "$d" 2>/dev/null | cut -f1)	$d"$'\n'
  done
  # Agent-Worktrees (storage_report) — eigene Datei, sie zählen nicht zu den Caches. Gesucht
  # wird nur in Entwicklungsordnern (prefs worktree_roots), nie quer durchs Home: ein Blick in
  # ~/Documents oder ~/Desktop kann eine Datenschutz-Abfrage auslösen.
  local wt="" r; local -a roots
  r=$(grep -s '^worktree_roots=' "$CONFDIR/prefs" | tail -1 | cut -d= -f2-)
  roots=(${(s:,:)${r:-~/Code,~/Developer,~/Projects,~/src}})
  for r in "${roots[@]}"; do
    r=${r/#\~/$HOME}
    for d in "$r"/*/.claude/worktrees(N/); do
      wt+="$(du -sk "$d" 2>/dev/null | cut -f1)	$d"$'\n'
    done
  done
  [[ -d $RUNDIR ]] && [[ -n $wt ]] && print -rn -- "$wt" > "$RUNDIR/worktrees" 2>/dev/null
  # Erst am Ende schreiben — und nur, wenn der Lauf noch existiert (du über ~/.cache/uv
  # dauert Minuten; ohne Abschnitt 'cleanup' ist $RUNDIR dann längst weg)
  [[ -d $RUNDIR ]] || return 0
  print -rn -- "$out" > "$RUNDIR/caches.tmp" 2>/dev/null && mv -f "$RUNDIR/caches.tmp" "$RUNDIR/caches" 2>/dev/null
  return 0
}
# Hintergrund-Messung beenden, bevor $RUNDIR verschwindet (du-Kinder gleich mit)
stop_measure() {
  [[ -n ${CACHE_PID:-} ]] || return 0
  pkill -P "$CACHE_PID" 2>/dev/null; kill "$CACHE_PID" 2>/dev/null; wait "$CACHE_PID" 2>/dev/null; CACHE_PID=""
  return 0
}

# ═════════════════════════════════════════════════════════════════
# Preflight
# ═════════════════════════════════════════════════════════════════
preflight() {
  echo "\n${BOLD}  Preflight${NC}"
  local h ms out net=0
  for h in 8.8.8.8 1.1.1.1; do
    # macOS-ping: -t = Gesamt-Timeout in Sekunden (-W wären Millisekunden!)
    if out=$(ping -c 1 -t 3 "$h" 2>/dev/null); then
      ms=$(print -r -- "$out" | /usr/bin/sed -n 's/.*time=\([0-9.]*\).*/\1/p' | head -1); ms=${ms%%.*}
      ok "Netzwerk erreichbar ${DIM}(${h}${ms:+ · ${ms} ms})${NC}"; st net "$h${ms:+ · ${ms} ms}"; net=1; break
    fi
  done
  (( net )) || abort_run 2 "Kein Netzwerk — Abbruch."

  if (( ! CHECK_ONLY )); then
    local power; power=$(pmset -g ps | head -1)
    if [[ "$power" == *"AC Power"* ]]; then ok "Netzteil angeschlossen"
    else
      local batt; batt=$(pmset -g batt 2>/dev/null | grep -Eo '[0-9]+%' | head -1)
      if (( ASSUME_YES )) || [[ ! -t 0 ]]; then warn "Läuft auf Akku${batt:+ ($batt)} — fahre ohne Rückfrage fort"
      else
        warn "Läuft auf Akku${batt:+ ($batt)} — trotzdem fortfahren? (y/N)"
        local reply; read -r reply < /dev/tty
        [[ "$reply" =~ ^[Yy]$ ]] || abort_run 2 "Abgebrochen (Akku)."
      fi
    fi
  fi

  # Letztes Time-Machine-Backup — vor OS-Updates gut zu wissen
  local ts; ts=$(tm_latest)
  if [[ $ts == <-> ]]; then
    local age=$(( EPOCHSECONDS - ts )); st backup "$(fmt_age $age)"
    if (( age > 259200 )); then
      warn "Letztes Time-Machine-Backup $(fmt_age $age)"
      action warn "Preflight" "Time-Machine-Backup ist $(fmt_age $age) alt" "tmutil startbackup --auto" ""
    else ok "Time-Machine-Backup $(fmt_age $age)"; fi
  else
    st backup "keins"
  fi

  security_check
  (( ${#MISSING} )) && echo "  ${DIM}◦  Nicht installiert, übersprungen: ${(j:, :)MISSING}${NC}"
  setup_sudo
  st_flush
}

# tm_latest [plist] — Zeitpunkt (Epoch) des jüngsten Time-Machine-Backups über alle Ziele,
# gelesen aus der lokalen Einstellungsdatei (Destinations.N.SnapshotDates, UTC). NICHT
# 'tmutil latestbackup': das hängt bei einem Netzwerkziel das verschlüsselte Sparsebundle
# per SMB ein — 11–14 s bei wachem NAS, und einmal hing der Preflight daran über eine
# Minute ohne Zeitlimit (das NAS schlief; Kernel: „smbfs_lookup: Server failed Query
# Info“), bis der Lauf abgebrochen wurde. Die Plist liefert dasselbe Datum in 0,01 s.
tm_latest() {
  local p=${1:-/Library/Preferences/com.apple.TimeMachine.plist} i=0 d best=""
  [[ -r $p ]] || return 0
  while plutil -extract "Destinations.$i" xml1 -o /dev/null "$p" 2>/dev/null; do
    for d in ${(f)"$(plutil -extract "Destinations.$i.SnapshotDates" xml1 -o - "$p" 2>/dev/null | /usr/bin/sed -n 's#.*<date>\(.*\)</date>.*#\1#p')"}; do
      [[ $d > $best ]] && best=$d   # ISO-8601 in UTC: Textvergleich = Zeitvergleich
    done
    (( i++ ))
  done
  [[ -n $best ]] && date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$best" +%s 2>/dev/null
  return 0
}

# Sicherheitsstand in einer Zeile: FileVault · Firewall · Gatekeeper · SIP ·
# XProtect-Version + Datum. Alles ohne sudo lesbar; Abweichungen werden Aktionen.
security_check() {
  local -a bad; local -a parts; local s
  s=$(fdesetup status 2>/dev/null);                      [[ $s == *"is On"* ]]      && parts+=("FileVault ✓") || { parts+=("FileVault ✗"); bad+=("FileVault aus — Systemeinstellungen › Datenschutz & Sicherheit › FileVault"); }
  s=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null); [[ $s == *enabled* ]] && parts+=("Firewall ✓") || { parts+=("Firewall ✗"); bad+=("Firewall aus — sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on"); }
  # 'spctl --master-enable' ist seit macOS 15 abgeschafft (macOS 27: „Operation not
  # permitted") — Gatekeeper lässt sich nur noch in den Systemeinstellungen einschalten
  s=$(spctl --status 2>/dev/null);                        [[ $s == *"assessments enabled"* ]] && parts+=("Gatekeeper ✓") || { parts+=("Gatekeeper ✗"); bad+=("Gatekeeper aus — open 'x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension'"); }
  s=$(csrutil status 2>/dev/null);                        [[ $s == *enabled* ]]      && parts+=("SIP ✓") || { parts+=("SIP ✗"); bad+=("SIP deaktiviert — im Recovery-Modus: csrutil enable"); }
  local xp=/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist xv xd xage=0
  if [[ -f $xp ]]; then
    xv=$(defaults read "$xp" CFBundleShortVersionString 2>/dev/null); xd=$(stat -f '%Sm' -t '%d.%m.' "$xp" 2>/dev/null)
    xage=$(( (EPOCHSECONDS - $(stat -f %m "$xp")) / 86400 ))
    parts+=("XProtect $xv ($xd)")
    (( xage > 30 )) && bad+=("XProtect-Definitionen $xage Tage alt — sudo softwareupdate --background-critical")
  fi
  st security "${(j: · :)parts}"
  if (( ${#bad} )); then
    warn "Sicherheit: ${(j: · :)parts}"
    local b; for b in "${bad[@]}"; do action warn "Preflight" "${b%% — *}" "${b#* — }" ""; done
  else
    ok "Sicherheit: ${(j: · :)parts}"
  fi
}

# ═════════════════════════════════════════════════════════════════
# Runner — führt den Lauf aus (in der TUI im Log-Pane, sonst inline)
# ═════════════════════════════════════════════════════════════════
# Der Runner startet in tmux als 'zsh -c' — ohne .zprofile/.zshrc. Damit brew,
# Node, bun, pipx und TeX unabhängig von der Startumgebung gefunden werden:
setup_path() {
  [[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
  path+=("$HOME/.local/bin" "$HOME/.bun/bin" /Library/TeX/texbin "$HOME/.docker/bin")
  typeset -U path
}

TUI=0
# Die Panes geben 'q' erst frei, wenn $RUNDIR/final existiert — nicht schon bei
# phase=done. Dazwischen liegen Verlauf, Kopie nach last/ und ntfy (bis 10 s); ein
# q in dieser Spanne hätte die Kopie zerrissen und den Runner per SIGHUP abgeschossen.
mark_final() { [[ -d $RUNDIR ]] && : > "$RUNDIR/final"; return 0; }

# ---- Lauf-Lock: nur EIN Runner gleichzeitig -------------------------------
# Zwei parallele Läufe (Alias in zwei SSH-Sitzungen, cron neben Handbetrieb) kollidieren
# in brews eigenen Locks und verwirren $RUNDIR/last. Die TUI verhindert das nur, wenn sie
# ihr Fenster wiederfindet — --plain lief bisher beliebig oft parallel.
LOCKFILE="$CONFDIR/run.lock"
lock_holder() {   # gibt die PID eines laufenden Runners aus, sonst nichts
  [[ -s $LOCKFILE ]] || return 1
  local p; p=$(head -1 "$LOCKFILE" 2>/dev/null)
  [[ $p == <-> ]] || return 1
  # nur gelten lassen, wenn die PID lebt UND ein update-all-Runner ist (PIDs werden wiederverwendet)
  ps -o command= -p "$p" 2>/dev/null | grep -q 'update-all' || return 1
  print -r -- "$p"
}
lock_acquire() {
  local p; p=$(lock_holder) && { print -r -- "$p"; return 1; }
  mkdir -p "$CONFDIR"; print -rl -- "$$" "$(date '+%Y-%m-%d %H:%M:%S')" "${ST[mode]:-}" > "$LOCKFILE"
  return 0
}
lock_release() { [[ -s $LOCKFILE ]] && [[ $(head -1 "$LOCKFILE" 2>/dev/null) == $$ ]] && rm -f "$LOCKFILE"; return 0; }
# Lauf vorzeitig beenden (Preflight: kein Netz, Akku) — in der TUI mit Taste und
# tui_close, sonst verschwände das Log-Pane samt Meldung und der Status zeigte „✓ Fertig"
# Exit-Codes: 0 = ok · 1 = mindestens ein Schritt fehlgeschlagen · 2 = Lauf abgebrochen
# (Preflight, ^C). Getrennt, damit launchd/cron/ntfy „nichts getan" von „durchgelaufen"
# unterscheiden können — ein Akku-Abbruch endete bis 3.2.5 mit 0.
abort_run() {   # <exit-code> <meldung>
  local rc=$1 msg=$2
  trap - INT TERM HUP; stop_measure; cleanup_askpass
  # Für --resume: Abschnittsstände aufheben (last/ schreibt nur ein vollständiger Lauf)
  [[ -s "$RUNDIR/steps" ]] && (( ! CHECK_ONLY && ! DRY_RUN )) && cp "$RUNDIR/steps" "$LOGDIR/resume-steps" 2>/dev/null
  echo "\n  ${RED}${BOLD}✗ $msg${NC}"
  (( ! CHECK_ONLY && ! DRY_RUN )) && echo "  ${DIM}Nachholen, was nicht fertig wurde: $SELF --resume${NC}"
  st phase done; st end $EPOCHSECONDS; st aborted 1; st_flush; mark_final
  notify_push "⚠️ update-all abgebrochen" "$msg" high warning
  lock_release
  if (( TUI )); then
    echo "  ${DIM}⏎ schließt die Ansicht${NC}"; read -k1 -s < /dev/tty 2>/dev/null
    tui_close
  fi
  rm -rf "$RUNDIR"
  exit $rc
}
on_interrupt() { abort_run 2 "Abgebrochen"; }

# notify_push <titel> <text> [prio] [tags] — ntfy, wenn eine URL konfiguriert ist.
# Remote ist das der einzige Kanal: osascript-Mitteilungen landen auf dem Mac-Schirm,
# den per SSH niemand sieht. Wird auch beim Abbruch und vom Status-Pane (Hänger) genutzt.
notify_push() {
  local title=$1 body=$2 prio=${3:-default} tags=${4:-}
  (( DRY_RUN )) && return 0
  [[ -z $NOTIFY_URL ]] && NOTIFY_URL=$(grep -s '^notify=' "$CONFDIR/prefs" | cut -d= -f2-)
  [[ -n $NOTIFY_URL ]] || return 0
  local -a hdr; hdr=(-H "Title: $title" -H "Priority: $prio")   # Array, nicht ${x:+…}: das wäre in zsh EIN Wort
  [[ -n $tags ]] && hdr+=(-H "Tags: $tags")
  curl -s --max-time 10 -o /dev/null "${hdr[@]}" --data-binary "$body" "$NOTIFY_URL" 2>/dev/null
  return 0
}

# rotate_logs <verzeichnis> <behalten> — nur die neuesten N Laufprotokolle bleiben.
# Über zsh-Glob (om = neueste zuerst): 'ls | xargs rm' hätte bei leerem Glob das
# Arbeitsverzeichnis ($HOME!) gelistet. Der Ausschnitt braucht (@) — "${a[41,-1]}" ist in
# zsh EIN Wort: bis 3.3.3 bekam rm alle überzähligen Pfade als einen Namen („File name
# too long“) und löschte nichts, sobald mehr als einer zu viel war (bis 60 Logs statt 40).
rotate_logs() {
  local -a logs; logs=("$1"/*.log(N.om))
  (( ${#logs} > $2 )) && rm -f -- "${(@)logs[$2+1,-1]}"
  return 0
}

# post_check — Nachkontrolle nach dem Lauf: steht bei brew oder im App Store noch etwas an?
# Ersetzt den Zweitlauf „zur Sicherheit“ — in zwei Wochen gab es ihn viermal direkt nach
# einem großen Lauf, jedes Mal mit 0 Paketen (60–90 s). brew outdated ohne --greedy (Self-Updater-Casks gelten
# nicht als offen, siehe sec_brew) und ohne neues 'brew update': geprüft wird der Stand vom
# Anfang des Laufs. Nichts davon ist ein Fehler — nur eine Info, was übrig ist.
post_check() {
  (( CHECK_ONLY || DRY_RUN )) && return 0
  local out rc; local -a left asked
  if (( ${SEC_ORDER[(Ie)brew]} )); then
    out=$(capture_t 120 brew outdated --quiet 2>/dev/null); rc=$?
    (( rc == 142 )) && { info "Nachkontrolle: brew outdated überschritt das Zeitlimit — Stand unbekannt"; return 0; }
    left+=(${(f)out}); asked+=(brew)
  fi
  if (( ${SEC_ORDER[(Ie)mas]} )) && has mas; then
    out=$(capture_t 60 mas outdated 2>/dev/null); rc=$?
    (( rc == 142 )) && { info "Nachkontrolle: mas outdated überschritt das Zeitlimit — Stand unbekannt"; return 0; }
    left+=(${(f)"$(print -r -- "$out" | awk 'NF { $1 = ""; sub(/^ +/, ""); sub(/ +\(.*$/, ""); print }')"}); asked+=("App Store")
  fi
  # Nur nennen, was wirklich gefragt wurde — bei --only texlive fragt die Nachkontrolle niemanden
  # und darf dann auch nichts als „nichts offen“ melden
  (( ${#asked} )) || return 0
  local verb=meldet; (( ${#asked} > 1 )) && verb=melden
  if (( ${#left} )); then info "Nachkontrolle: noch offen — ${(j:, :)left}"
  else ok "Nachkontrolle: ${(j: und :)asked} $verb nichts mehr offen ${DIM}(kein Zweitlauf nötig)${NC}"; fi
  return 0
}

runner() {
  TUI=${1:-0}
  [[ -d $RUNDIR ]] || RUNDIR=$(mktemp -d "${TMPDIR:-/tmp}/update-all.XXXXXX")
  mkdir -p "$RUNDIR/out" "$LOGDIR/runs" "$CONFDIR"
  : > "$RUNDIR/actions"
  # Vergleichslauf für die Restzeit (eta_left): Abschnittsdauern des letzten Laufs — nicht von
  # einem --check (installiert nichts, seine Dauern wären viel zu kurz)
  [[ -s "$LOGDIR/last/steps" ]] && ! grep -q '^mode=.*check' "$LOGDIR/last/state" 2>/dev/null \
    && cp "$LOGDIR/last/steps" "$RUNDIR/prev-steps" 2>/dev/null
  setup_path
  # Nur ein Runner: --check/--dry-run dürfen immer (sie ändern nichts)
  local other
  if (( ! CHECK_ONLY && ! DRY_RUN )) && ! other=$(lock_acquire); then
    echo "  ${YELLOW}⚠${NC}  Es läuft bereits ein update-all (PID $other) — dieser Aufruf macht nichts."
    echo "  ${DIM}Ansicht des laufenden: $SELF --review (nach dem Lauf) · in tmux: Fenster update-all${NC}"
    # In der TUI sähe das niemand — das Pane ginge sofort zu. tui_launch fängt den Fall
    # vorher ab; hier landet nur noch ein Wettlauf zweier gleichzeitiger Starts.
    if (( TUI )); then
      echo "  ${DIM}⏎ schließt die Ansicht (sonst nach 30 s)${NC}"; read -t 30 -k1 -s < /dev/tty 2>/dev/null
      tui_close
    fi
    rm -rf "$RUNDIR"; exit 2
  fi

  # Logs: Gesamtprotokoll (Rotation ab 2 MB) + eine Datei je Lauf
  if [[ -f "$LOGFILE" ]] && (( $(stat -f%z "$LOGFILE") > 2097152 )); then mv "$LOGFILE" "${LOGFILE}.old"; fi
  local runlog="$LOGDIR/runs/$(date '+%Y-%m-%d_%H%M%S').log"; st runlog "$runlog"
  print -r -- "── $(date '+%Y-%m-%d %H:%M:%S') ── Neuer Lauf ──────────────────────────── ${runlog:t}" >> "$LOGFILE"
  if (( USE_COLOR )); then
    exec > >(tee >(/usr/bin/sed -l "s/${ESC}\[[0-9;]*[mK]//g" | tee -a "$LOGFILE" >> "$runlog")) 2>&1
  else
    exec > >(tee -a "$LOGFILE" "$runlog") 2>&1
  fi
  trap 'cleanup_askpass; lock_release' EXIT
  trap 'on_interrupt' INT TERM HUP
  # Wachhalten, solange der Runner lebt: auf Akku schläft der Mac nach 1 min Leerlauf
  # (pmset sleep 1), sobald die SSH-Sitzung weg ist und niemand sonst eine Zusicherung hält
  # (das caffeinate, das man oft sieht, gehört Claude Code). -w bindet es an die Runner-PID:
  # kein Dienst, endet mit dem Lauf — auch beim Abbruch. -i = kein Leerlauf-Schlaf; den
  # zugeklappten Deckel ohne Netzteil hält auch caffeinate nicht auf.
  if (( ! CHECK_ONLY && ! DRY_RUN )) && [[ -x /usr/bin/caffeinate ]]; then
    /usr/bin/caffeinate -i -w $$ </dev/null >/dev/null 2>&1 &!
  fi

  build_registry
  local id i
  for id in "${SEC_ORDER[@]}"; do S_ID+=("$id"); S_NAME+=("${SEC_NAME[$id]}"); S_STATUS+=(pending); S_DUR+=(0); S_ERRS+=(0); S_WARN+=(0); done
  steps_flush

  local disk0; disk0=$(df -k / 2>/dev/null | awk 'NR==2{print $4}')
  local -a mode; (( GREEDY )) && mode+=(greedy); (( ASSUME_YES )) && mode+=(yes); (( UPDATE_MODELS )) && mode+=(models)
  (( APPS )) && mode+=(apps); (( DOCKER )) && mode+=(docker); (( NO_MACOS )) && mode+=(no-macos)
  (( CHECK_ONLY )) && mode+=("check — nur Anzeige"); (( DRY_RUN )) && mode+=(dry-run); (( RESUME )) && mode+=("resume: $ONLY")
  st host "$(hostname -s 2>/dev/null || hostname)"; st os "macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
  st arch "$(uname -m)"; st start $EPOCHSECONDS; st start_h "$(date '+%d.%m. %H:%M')"; st mode "${(j: · :)mode}"; st version "$VERSION"
  st phase running; st step 0; st total ${#SEC_ORDER}; st errors 0; st warnings 0; st actions 0; st pkg_brew 0; st pkg_mas 0
  st disk0 "$disk0"; st reboot 0; st_flush

  local -a banner
  banner=("◆ update-all v$VERSION — System-Update" "${ST[host]} · ${ST[os]} · ${ST[arch]}" "$(date '+%A, %d. %B %Y · %H:%M') Uhr")
  (( ${#mode} )) && banner+=("Modus: ${(j: · :)mode}")
  echo ""; box "$CYAN$BOLD" "${banner[@]}"
  echo "  ${DIM}Log: ${runlog/#$HOME/~}${NC}"
  preflight
  CACHE_PID=""; if (( ${SEC_ORDER[(Ie)cleanup]} )); then measure_caches & CACHE_PID=$!; fi   # nur, wenn 'cleanup' das Ergebnis auch zeigt

  for id in "${SEC_ORDER[@]}"; do section "$id"; "sec_$id"; done
  _close_section
  cleanup_askpass

  # ── Abschluss ──
  local elapsed=$SECONDS; settitle "update-all · fertig ($(fmt_dur $elapsed))"
  echo "\n${CYAN}${BOLD}  ▍ Zusammenfassung${NC}"; hr
  local hdr_a="Abschnitt" hdr_d="Dauer"
  echo "  ${DIM}${(r:34:)hdr_a} ${(l:6:)hdr_d}  Status${NC}"
  local ok_n=0 fail_n=0 skip_n=0 stt
  for (( i=1; i <= ${#S_ID}; i++ )); do
    case ${S_STATUS[i]} in
      fail) stt="${RED}✗ ${S_ERRS[i]} Fehler${NC}"; (( fail_n+=1 )) ;;
      skip) stt="${DIM}◦ übersprungen${NC}"; (( skip_n+=1 )) ;;
      *)    if (( ${S_WARN[i]:-0} > 0 )); then stt="${GREEN}✓ ok${NC} ${YELLOW}⚠ ${S_WARN[i]}${NC}"
            else stt="${GREEN}✓ ok${NC}"; fi; (( ok_n+=1 )) ;;
    esac
    echo "  ${(r:34:)S_NAME[i]} ${DIM}${(l:6:)$(fmt_dur ${S_DUR[i]})}${NC}  $stt"
  done
  hr
  if (( ERRORS > 0 )); then
    echo "\n  ${RED}${BOLD}Fehlgeschlagene Schritte:${NC}"
    local c; for c in "${FAILED_CMDS[@]}"; do echo "     ${RED}✗${NC} $c"; done
  fi

  echo ""; post_check

  local disk1 disk_line=""; disk1=$(df -k / 2>/dev/null | awk 'NR==2{print $4}')
  if [[ -n "$disk0" && -n "$disk1" ]]; then
    disk_line=$(awk -v a="$disk0" -v b="$disk1" 'BEGIN{
      line = sprintf("Freier Speicher: %.1f GB", b/1048576); d=(b-a)/1024; m=(d<0?-d:d)
      if (m >= 50) { s=(d>=0?"+":"-"); if (m>=1024) line=line sprintf(" (%s%.1f GB)", s, m/1024); else line=line sprintf(" (%s%.0f MB)", s, m) }
      print line }')
    st disk "$disk_line"
  fi

  # Änderungsjournal: was wurde in diesem Lauf konkret aktualisiert
  if [[ -s "$RUNDIR/journal" ]]; then
    journal_block "$RUNDIR/journal" "$JOURNAL_N"
    # Zeitpunkt im Titel: sonst gälte ein Journal mit gleicher Anzahl wie im letzten Lauf als
    # „bekannter Hinweis“ und verschwände aus der Liste
    action info "Abschluss" "Änderungsjournal $(date -r ${ST[start]} '+%d.%m. %H:%M'): $JOURNAL_N Aktualisierung(en)" "" "$(<"$RUNDIR/journal")"
  fi

  # Offene Aktionen (ohne die als erledigt markierten und ohne unveränderte Hinweise)
  local -a open; local line aid; local known_n=0
  while IFS= read -r line; do
    aid=${line%%	*}; grep -qx "$aid" "$CONFDIR/acks" 2>/dev/null && continue
    grep -qx "$aid" "$RUNDIR/known" 2>/dev/null && { (( known_n+=1 )); continue; }
    open+=("$line")
  done < "$RUNDIR/actions"
  if (( ${#open} )); then
    echo "\n  ${YELLOW}${BOLD}Offene Aktionen (${#open}):${NC}"
    for line in "${open[@]}"; do
      local -a f; f=("${(@s:	:)line}")
      case ${f[2]} in err) stt="${RED}✗${NC}" ;; warn) stt="${YELLOW}⚠${NC}" ;; *) stt="${CYAN}·${NC}" ;; esac
      echo "     $stt ${f[4]}${f[5]:+ ${DIM}→ ${f[5]}${NC}}"
    done
    (( TUI )) || echo "     ${DIM}Interaktiv: $SELF --review${NC}"
  fi
  (( known_n )) && info "$known_n bekannte(r) Hinweis(e) unverändert ${DIM}(--review zeigt sie)${NC}"

  local -a boxl; local bc
  if (( ERRORS > 0 )); then bc="$YELLOW$BOLD"; boxl+=("✗ $ERRORS Schritt(e) fehlgeschlagen — Details oben")
  elif (( CHECK_ONLY )); then bc="$CYAN$BOLD"; boxl+=("✓ Check abgeschlossen — es wurde nichts installiert")
  else bc="$GREEN$BOLD"; boxl+=("✓ Alle Updates erfolgreich abgeschlossen"); fi
  local sumline="Laufzeit $(fmt_dur $elapsed) · $ok_n/$STEP Abschnitte ok"
  (( fail_n )) && sumline+=" · $fail_n mit Fehlern"; (( skip_n )) && sumline+=" · $skip_n übersprungen"
  boxl+=("$sumline")
  boxl+=("Pakete: brew $PKG_BREW · App Store $PKG_MAS · Aktionen offen ${#open}")
  [[ -n "$disk_line" ]] && boxl+=("$disk_line")
  boxl+=("Log: ${runlog/#$HOME/~}")
  echo ""; box "$bc" "${boxl[@]}"
  (( REBOOT_NEEDED )) && echo "\n  ${YELLOW}${BOLD}⚠  Neustart erforderlich — bitte zeitnah neu starten.${NC}"
  echo ""

  # Verlauf + letzter Zustand für --review / --history
  # Ab hier ist der Lauf inhaltlich fertig: Traps aus, BEVOR phase=done sichtbar wird.
  # Schließt ein anderes Pane die Ansicht (q), kommt SIGHUP — mit Trap liefe on_interrupt
  # und schriebe „✗ Abgebrochen" samt st_flush-Fehler ins Log eines erfolgreichen Laufs
  # (13:14-Log vom 18.09.). Die Panes geben q ohnehin erst mit $RUNDIR/final frei (unten).
  trap - INT TERM HUP; stop_measure
  st phase done; st end $EPOCHSECONDS; st elapsed $elapsed; st open ${#open}; st_flush
  if (( ! CHECK_ONLY && ! DRY_RUN )); then
    [[ -f "$LOGDIR/history.tsv" ]] || print -r -- "start	dauer_s	ok	fehler	uebersprungen	errors	aktionen_offen	brew	mas	speicher	neustart	modus	log	version" > "$LOGDIR/history.tsv"
    print -r -- "$(date -r ${ST[start]} '+%Y-%m-%d %H:%M')	$elapsed	$ok_n	$fail_n	$skip_n	$ERRORS	${#open}	$PKG_BREW	$PKG_MAS	${disk_line#Freier Speicher: }	$REBOOT_NEEDED	${ST[mode]}	${runlog:t}	$VERSION" >> "$LOGDIR/history.tsv"
  fi
  rm -rf "$LOGDIR/last"; mkdir -p "$LOGDIR/last"
  cp -R "$RUNDIR/." "$LOGDIR/last/" 2>/dev/null; cp "$runlog" "$LOGDIR/last/run.log" 2>/dev/null
  rotate_logs "$LOGDIR/runs" 40
  # Abbruch-Notiz für --resume erledigt: ein vollständiger Lauf oder der Resume-Lauf selbst
  if (( ! CHECK_ONLY && ! DRY_RUN )) && { [[ -z $ONLY && -z $SKIP ]] || (( RESUME )); }; then rm -f "$LOGDIR/resume-steps"; fi

  # Benachrichtigung: lokal via Mitteilungszentrale, unterwegs via ntfy
  local note title first
  if (( ERRORS > 0 )); then
    first="${FAILED_CMDS[1]//\"/}"; note="Fertig in $(fmt_dur $elapsed) — $ERRORS Fehler (u.a. ${first[1,60]})."; title="🚀 update-all ⚠️"
  elif (( CHECK_ONLY )); then
    note="Check: brew $PKG_BREW · App Store $PKG_MAS · ${#open} offene Aktionen."; title="🔎 update-all check"
  else note="Fertig in $(fmt_dur $elapsed) — $JOURNAL_N aktualisiert, ${#open} offene Aktionen."; title="🚀 update-all ✅"; fi
  (( REBOOT_NEEDED )) && note="$note Neustart erforderlich!"
  (( CHECK_ONLY || DRY_RUN )) || osascript -e "display notification \"$note\" with title \"$title\"" 2>/dev/null
  [[ -z $NOTIFY_URL ]] && NOTIFY_URL=$(grep -s '^notify=' "$CONFDIR/prefs" | cut -d= -f2-)
  if [[ -n $NOTIFY_URL ]] && (( ! DRY_RUN )); then
    local body="$note" prio=default tags=white_check_mark
    (( ERRORS > 0 )) && { prio=high; tags=warning; }
    (( ${#open} )) && body+=$'\n'"$(print -rl -- "${open[@]}" | cut -f4 | head -6 | sed 's/^/• /')"
    if curl -s --max-time 10 -o /dev/null -H "Title: update-all ${ST[host]}" -H "Priority: $prio" -H "Tags: $tags" --data-binary "$body" "$NOTIFY_URL"; then
      echo "  ${DIM}Benachrichtigung gesendet (ntfy)${NC}"
    else
      warn "ntfy-Benachrichtigung fehlgeschlagen ($NOTIFY_URL)"
    fi
  fi

  lock_release
  mark_final   # jetzt dürfen die Panes auf q reagieren
  if (( TUI )); then
    # Abschluss-Tafel: der Lauf ist fertig, aber die Ansicht bleibt stehen, bis jemand
    # drückt — remote auf einem kleinen Schirm war der alte zweizeilige Hinweis zu leise.
    # Rot heißt hier nicht „Fehler", sondern „hier wird etwas von dir erwartet"; die Farbe
    # kommt aus dem Rahmen, damit die Zeilen ihre eigene Bedeutung behalten.
    # Keine Mehrfachbreiten-Zeichen (⏎ zählt je Terminal 1 oder 2 Zellen und würde den
    # Rahmen verschieben) — deshalb „Enter" ausgeschrieben; box() rechnet mit vlen.
    # Ohne Aktionen-Pane (Kompaktlayout, iPhone) keine Pfeile/^X versprechen, die ins Leere
    # gehen; der Log-Name steht schon in der Fazit-Box darüber.
    local -a keys; local lay_ah=""
    [[ -f "$RUNDIR/layout" ]] && lay_ah=$(cut -f2 "$RUNDIR/layout")
    keys=("${BOLD}q${NC}        Ansicht schließen (in jedem Pane)"
          "${BOLD}Enter${NC}    hier im Log-Pane: ebenfalls schließen")
    if (( ${#open} )) && [[ $lay_ah != 0 ]]; then
      keys+=("${BOLD}Pfeile${NC}   Aktionen-Pane unten: ${#open} offene"
             "${BOLD}^X${NC}       markierte Aktion ausführen · ${BOLD}^A${NC} als erledigt"
             "${BOLD}--review${NC} später wieder öffnen")
    elif (( ${#open} )); then
      keys+=("${BOLD}--review${NC} ${#open} offene Aktion(en) ansehen und erledigen")
    else
      keys+=("${BOLD}--review${NC} später wieder öffnen")
    fi
    echo ""; box "$RED$BOLD" "${keys[@]}"
    echo "  ${DIM}Der Lauf ist durch — nichts läuft mehr. Die Ansicht wartet nur noch auf dich.${NC}"
    local key; while true; do read -k1 -s key < /dev/tty || break; [[ $key == $'\n' || $key == $'\r' || $key == q ]] && break; done
    tui_close
  fi
  rm -rf "$RUNDIR"
  exit $(( ERRORS > 0 ? 1 : 0 ))   # 2 bleibt dem Abbruch vorbehalten (abort_run)
}

# ═════════════════════════════════════════════════════════════════
# TUI — tmux-Layout: [Status | Log ; Aktionen]
# ═════════════════════════════════════════════════════════════════
# Schließt die ganze Ansicht (alle drei Panes) — aus jedem Pane heraus aufrufbar.
# Räumt $RUNDIR vorher weg; der Aufrufer stirbt mit dem Fenster.
tui_close() {
  [[ -f "$RUNDIR/tmux" ]] || return 0
  local win sess; win=$(sed -n 1p "$RUNDIR/tmux"); sess=$(sed -n 2p "$RUNDIR/tmux")
  rm -rf "$RUNDIR"
  if [[ -n $sess ]]; then tmux kill-session -t "$sess" 2>/dev/null; else tmux kill-window -t "$win" 2>/dev/null; fi
}

# Wo das Fenster hinkommt: in tmux → aktuelle Session. Außerhalb → die Session
# aus prefs tmux_session (z. B. die tmuxinator-Arbeitssession; Standard: keine), wenn
# sie läuft — so taucht der Lauf dort auf, wo ohnehin gearbeitet wird. Sonst eine
# eigene Session "update-all" (fester Name statt PID: wiederfindbar, kein
# zweiter Lauf daneben). --tmuxinator schreibt zusätzlich eine Projektdatei.
tui_launch() {   # $1 = run|review
  local wname=update-all; [[ $1 == review ]] && wname=update-all-review
  local target="" sess="" pref old tc="" tr=""; local -a tgt   # tgt = (-t ziel) oder leer (aktuelle Session)
  if [[ -z $TMUX ]]; then
    # Größe des aufrufenden Terminals — nur hier bekannt; das Fenster entsteht in einer
    # Session, die vielleicht ein ganz anderer Client (der 200er-Schirm am Mac) bemessen hat
    # (tput misst in $(…) über stderr — das darf hier NICHT nach /dev/null, sonst kommt
    # der terminfo-Standard 80×24 zurück)
    tc=$(tput cols); tr=$(tput lines)
    pref=$(grep -s '^tmux_session=' "$CONFDIR/prefs" | tail -1 | cut -d= -f2-)
    if tmux has-session -t "=update-all" 2>/dev/null; then target="=update-all:"
    elif [[ -n $pref ]] && tmux has-session -t "=$pref" 2>/dev/null; then target="=$pref:"
    else sess=update-all; fi
    [[ -n $target ]] && tgt=(-t "$target")
  fi
  if [[ -z $sess ]]; then
    # Läuft im Ziel schon ein Lauf? Dann hinspringen statt doppelt starten. Ist er dagegen
    # FERTIG und steht nur noch da (remote: Verbindung zu statt q), wird er abgeräumt — bis
    # 3.3.2 sprang der Aufruf dann nur in den alten Lauf und startete nie einen neuen.
    if [[ $1 == run ]] && tmux list-windows "${tgt[@]}" -F '#{window_name}' 2>/dev/null | grep -qx update-all; then
      old=$(tmux show-options -wqv -t "${target}update-all" @rundir 2>/dev/null)
      if [[ -n $old && $old == "${TMPDIR:-/tmp}"/update-all.* && -f $old/final ]]; then
        echo "Vorheriger Lauf ist fertig, die Ansicht stand noch — räume sie ab"
        rm -rf "$old"
        tmux kill-window -t "${target}update-all" 2>/dev/null
        if [[ -n $target ]] && ! tmux has-session -t "${target%:}" 2>/dev/null; then sess=update-all; target=""; tgt=(); fi
      else
        echo "update-all läuft bereits — springe hin"
        tmux select-window -t "${target}update-all"; [[ -n $TMUX ]] || exec tmux attach -t "${target%:}"; exit 0
      fi
    fi
    # Ein liegengebliebener Rückblick (Detach statt q) weicht: vor einem neuen Rückblick immer,
    # vor einem Lauf nur in der eigenen Session update-all (dort blockierte er den Lauf, weil
    # die Session als „läuft bereits" galt). In der Arbeitssession dürfen Lauf und Rückblick
    # nebeneinander stehen. Die Panes sterben per SIGHUP, ohne aufzuräumen — deshalb hängt
    # das Zustandsverzeichnis als Fensteroption @rundir am Fenster und wird hier mit entfernt.
    if tmux list-windows "${tgt[@]}" -F '#{window_name}' 2>/dev/null | grep -qx update-all-review \
       && [[ $1 == review || $target == "=update-all:" ]]; then
      old=$(tmux show-options -wqv -t "${target}update-all-review" @rundir 2>/dev/null)
      [[ -n $old && $old == "${TMPDIR:-/tmp}"/update-all.* ]] && rm -rf "$old"
      tmux kill-window -t "${target}update-all-review" 2>/dev/null
      # war er das einzige Fenster, ist die Session jetzt weg → eigene Session anlegen
      if [[ -n $target ]] && ! tmux has-session -t "${target%:}" 2>/dev/null; then sess=update-all; target=""; tgt=(); fi
    fi
  fi

  # Lock belegt (Lauf aus einer anderen Session oder SSH-Sitzung, --plain, cron)? Dann gar
  # kein Fenster bauen. Bis 3.3.2 entstand eines, dessen Runner sofort aufgab — die Meldung
  # verschwand mit dem Pane, der Aufruf endete mit 0. Der Runner ist das Pane selbst
  # (exec zsh), seine PID also die pane_pid: daran findet sich sein Fenster.
  local holder hp
  if [[ $1 == run ]] && (( ! DRY_RUN )) && holder=$(lock_holder); then
    echo "${YELLOW}⚠${NC}  update-all läuft bereits (PID $holder, seit $(sed -n 2p "$LOCKFILE" 2>/dev/null)) — dieser Aufruf macht nichts"
    hp=$(tmux list-panes -a -F "#{pane_pid}	#{pane_id}	#{session_name}" 2>/dev/null | awk -F'\t' -v p="$holder" '$1 == p { print $2 "\t" $3; exit }')
    if [[ -n $hp ]]; then
      echo "   springe hin: tmux-Session ${hp#*	}"
      tmux select-window -t "${hp%%	*}" 2>/dev/null; tmux select-pane -t "${hp%%	*}" 2>/dev/null
      if [[ -n $TMUX ]]; then tmux switch-client -t "=${hp#*	}" 2>/dev/null; else tmux attach -t "=${hp#*	}"; fi
    else
      echo "   ohne Ansicht (--plain oder cron) — mitlesen: tail -f ${LOGFILE/#$HOME/~}"
    fi
    exit 2
  fi

  RUNDIR=$(mktemp -d "${TMPDIR:-/tmp}/update-all.XXXXXX")
  local logcmd statuscmd actcmd win pane_run pane_status
  if [[ $1 == review ]]; then
    [[ -f "$LOGDIR/last/state" ]] || { echo "Kein abgeschlossener Lauf unter $LOGDIR/last"; rm -rf "$RUNDIR"; exit 1; }
    rm -rf "$RUNDIR"; cp -R "$LOGDIR/last" "$RUNDIR"; : > "$RUNDIR/review"
    logcmd="exec zsh '$SELF' --_pane-log '$RUNDIR'"
  else
    : > "$RUNDIR/args"
    (( $# > 1 )) && print -rl -- "${(@)argv[2,-1]}" > "$RUNDIR/args"
    logcmd="exec zsh '$SELF' --_runner '$RUNDIR'"
  fi
  statuscmd="exec zsh '$SELF' --_status '$RUNDIR'"
  actcmd="exec zsh '$SELF' --_actions '$RUNDIR'"

  if [[ -n $sess ]]; then
    tmux new-session -d -s "$sess" -n "$wname" -x "$(tput cols)" -y "$(tput lines)" -c "$HOME" "$logcmd" || { echo "tmux konnte nicht starten — nutze --plain"; rm -rf "$RUNDIR"; exit 1; }
    pane_run=$(tmux list-panes -t "=$sess" -F '#{pane_id}' | head -1)
  else
    pane_run=$(tmux new-window "${tgt[@]}" -P -F '#{pane_id}' -n "$wname" -c "$HOME" "$logcmd")
    [[ -n $pane_run ]] || { echo "tmux konnte kein Fenster öffnen — nutze --plain"; rm -rf "$RUNDIR"; exit 1; }
  fi
  win=$(tmux display-message -p -t "$pane_run" '#{window_id}')
  print -rl -- "$win" "$sess" > "$RUNDIR/tmux"
  tmux set-option -t "$win" -w @rundir "$RUNDIR" 2>/dev/null   # für den Nachfolger, der dieses Fenster abräumt
  tmux set-option -t "$win" -w pane-border-status top 2>/dev/null
  tmux set-option -t "$win" -w pane-border-format ' #{pane_title} ' 2>/dev/null
  # ── Layout nach Platz ──────────────────────────────────────────
  # Das feste 40-Spalten-Status-Pane ließ auf einem iPhone im Querformat (ca. 80×20)
  # 39 Spalten fürs Log übrig — unbrauchbar. Darum: Breite und Höhe messen und die
  # Panes danach bemessen. prefs layout=auto|wide|compact übersteuert (auto = Standard).
  #   ab 140 Spalten   Status 40   wie bisher
  #   100–139          Status 34
  #    88–99           Status 28   (iPad-Fenster)
  #   unter 88         kein Status-Pane — der Fortschritt steht im Pane-Rand (Titel)
  #                    und in jeder Abschnitts-Kopfzeile des Logs
  # Höhe: ab 30 Zeilen Aktionen 32 %, ab 22 Zeilen 7 Zeilen, darunter erst nach dem Lauf
  # (das Aktionen-Pane wird dann weggelassen; die Aktionen stehen im Fazit und in --review).
  local lay cols rows sw ah sl
  lay=$(grep -s '^layout=' "$CONFDIR/prefs" | cut -d= -f2-); lay=${lay:-auto}
  # Von außerhalb in eine BESTEHENDE Session (Arbeitssession, prefs tmux_session): das neue Fenster hat
  # deren Größe, nicht die des Terminals, das gleich anhängt. Bis 3.3.2 wurde für 200×50
  # gebaut und dann am iPhone (80×20) gezeigt — Status-Pane 1 Spalte, Aktionen 1 Zeile.
  # Darum das Fenster vor dem Teilen auf das Terminal bringen (minus Statuszeile).
  if [[ -z $sess && -z $TMUX && $tc == <-> && $tr == <-> ]]; then
    sl=$(tmux show-options -gqv status 2>/dev/null)
    case $sl in off) sl=0 ;; <->) ;; *) sl=1 ;; esac
    tmux resize-window -t "$win" -x "$tc" -y "$(( tr - sl ))" 2>/dev/null
  fi
  cols=$(tmux display-message -p -t "$pane_run" '#{window_width}' 2>/dev/null); cols=${cols:-$(tput cols)}
  rows=$(tmux display-message -p -t "$pane_run" '#{window_height}' 2>/dev/null); rows=${rows:-$(tput lines)}
  case $lay in
    wide)    sw=40; ah=32% ;;
    compact) sw=0;  ah=0 ;;
    *) if   (( cols >= 140 )); then sw=40
       elif (( cols >= 100 )); then sw=34
       elif (( cols >= 88 ));  then sw=28
       else                         sw=0; fi
       if   (( rows >= 30 )); then ah=32%
       elif (( rows >= 22 )); then ah=7
       else                        ah=0; fi ;;
  esac
  # Im Rückblick ist die Aktionsliste der Zweck des Fensters — die gibt es immer
  [[ $1 == review && $ah == 0 ]] && ah=7
  (( sw )) && pane_status=$(tmux split-window -t "$pane_run" -h -b -l $sw -P -F '#{pane_id}' "$statuscmd")
  [[ $ah == 0 ]] || tmux split-window -t "$pane_run" -v -l $ah "$actcmd"
  # Der Runner setzt den Pane-Titel (settitle: „update-all · 7/12 · Homebrew") — im
  # Kompaktlayout ist der Rand die einzige Daueranzeige, also sichtbar lassen.
  print -r -- "$sw	$ah	$cols	$rows" > "$RUNDIR/layout"
  tmux select-pane -t "$pane_run"
  # resize-window hat das Fenster auf feste Größe gestellt (window-size manual). Erst wenn
  # unser Client hängt, wieder freigeben — dann folgt es ihm, und die Pane-Maße bleiben;
  # sofort freigegeben, würde es auf einen anderen angehängten Client springen und zurück.
  if [[ -z $sess && -z $TMUX && $tc == <-> ]]; then
    ( sleep 3; tmux set-option -w -u -t "$win" window-size 2>/dev/null ) &>/dev/null &!
  fi
  if [[ -n $sess ]]; then exec tmux attach -t "=$sess"
  elif [[ -z $TMUX ]]; then exec tmux attach -t "${target%:}"; fi
}

# tmuxinator-Projekt: 'tmuxinator start update-all' öffnet eine Session, in der
# das Skript sein Drei-Pane-Fenster anlegt; das Startfenster schließt sich danach.
write_tmuxinator() {
  local dir="$HOME/.config/tmuxinator" f="$HOME/.config/tmuxinator/update-all.yml"
  mkdir -p "$dir"
  cat > "$f" <<EOF
# update-all.sh als tmuxinator-Projekt — geschrieben von update-all.sh --tmuxinator
# Start: tmuxinator start update-all   (Fenster "update-all" mit Status | Log ; Aktionen)
# Das Skript legt sein Fenster in dieser Session an; das Startfenster schließt sich.
name: update-all
root: ~
windows:
  - start: $SELF -y; exit
EOF
  echo "geschrieben: ${f/#$HOME/~}"
  echo "Start: tmuxinator start update-all   (Alias-Idee: alias uut='tmuxinator start update-all')"
}

# ── Status-Pane ──────────────────────────────────────────────────
pane_status() {
  printf '\e[?25l'; trap 'printf "\e[?25h\e[0m"; exit 0' EXIT INT TERM
  printf '\e]2;Status\a'
  local -a spin; spin=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏); local tick=0 key frame line cols rows
  local -a steps; local w bar fill empty _e="" pct el name dur icon col hb hb_ts hb_line
  # add: Zeile anhängen — bei Überlänge ohne Farbcodes kürzen; \e[K löscht Reste
  local nl=0
  add() { local s=$1; if (( $(vlen "$s") > w )); then s="${s//$ESC\[[0-9;]#[mK]/}"; s="${s[1,$w]}"; fi; frame+="$s"$'\e[K\n'; (( nl+=1 )); }
  hr_() { add "${DIM}${(l:$w::─:)_e}${NC}"; }
  # Schalter-Hilfe: ein Schalter je Zeile mit Erklärung (Spalte 13 + ≤ 25 Zeichen
  # passen in die 40 Spalten des Panes); gezeigt wird, was in die Höhe passt.
  local -a help; help=(
    "-g"            "Self-Updater nachziehen"
    "-y"            "Rückfragen: ja (TeX mit)"
    "-m"            "Ollama-Modelle neu ziehen"
    "--apps"        "MacUpdater-Apps heben"
    "--docker"      "Floating-Images ziehen"
    "--askpass"     "Passwort einmal (SSH)"
    "--notify URL"  "Fazit per ntfy"
    "--no-macos"    "ohne macOS-Update"
    "--only/--skip" "Abschnitte wählen (--list)"
    "--check"       "nur anzeigen, nichts tun"
    "--plain"       "Ausgabe ohne TUI"
    "--review"      "letzten Lauf öffnen"
    "--history"     "Verlauf der Läufe"
    "--dry-run"     "alles simulieren"
    "--tmuxinator"  "Projektdatei schreiben"
    "--selftest"    "Ausgabe-Layer testen"
  )
  while true; do
    # RUNDIR weg = der Runner hat aufgegeben (Lock belegt) oder jemand hat abgeräumt —
    # dann gehen, statt als Geister-Pane ewig auf eine state-Datei zu warten
    load_state "$RUNDIR" || { [[ -d $RUNDIR ]] || exit 0; sleep 0.5; continue; }
    cols=$(tput cols); rows=$(tput lines); w=$(( cols - 2 ))
    frame=""; nl=0
    (( tick+=1 ))
    el=$(( ${ST[end]:-$EPOCHSECONDS} - ${ST[start]:-$EPOCHSECONDS} ))
    add "${BOLD}${CYAN}◆ update-all${NC} ${DIM}v${ST[version]:-?}${NC} · ${ST[host]}"
    add "${DIM}${ST[os]%% \(*} · ${ST[start_h]} · ⏱ $(fmt_dur $el)${NC}"
    [[ -n ${ST[mode]} ]] && add "${DIM}Modus: ${ST[mode]}${NC}"
    hr_
    local total=${ST[total]:-1} step=${ST[step]:-0} done_n=0
    steps=("${(@f)$([[ -f "$RUNDIR/steps" ]] && cat "$RUNDIR/steps")}")
    for line in "${steps[@]}"; do [[ ${${(s:	:)line}[3]} == (ok|fail|skip) ]] && (( done_n+=1 )); done
    pct=$(( total ? done_n * 100 / total : 0 ))
    local bw=$(( w - 12 )); fill=$(( bw * done_n / (total ? total : 1) )); empty=$(( bw - fill ))
    # Balkenfarbe = Zustand: läuft (cyan) · fertig mit Fehlern (rot) · mit Warnungen (gelb) · sauber (grün)
    local bcol=$CYAN
    if [[ ${ST[phase]} == done ]]; then
      if   (( ${ST[aborted]:-0} || ${ST[errors]:-0} > 0 )); then bcol=$RED
      elif (( ${ST[warnings]:-0} > 0 ));                     then bcol=$YELLOW
      else                                                        bcol=$GREEN; fi
    fi
    bar="${bcol}${(l:$fill::█:)_e}${DIM}${(l:$empty::░:)_e}${NC}"
    add "$bar ${(l:3:)pct} %"
    if [[ ${ST[phase]} == done ]]; then
      if (( ${ST[aborted]:-0} )); then add "${RED}${BOLD}✗ Abgebrochen${NC}"
      elif (( ${ST[errors]:-0} > 0 )); then add "${RED}${BOLD}✗ Fertig mit ${ST[errors]} Fehler(n)${NC}"
      else add "${GREEN}${BOLD}✓ Fertig${NC} ${DIM}in $(fmt_dur ${ST[elapsed]:-0})${NC}"; fi
    else
      add "${MAGENTA}${spin[tick % 10 + 1]}${NC} ${BOLD}${ST[section]}${NC} ${DIM}$(fmt_dur $(( EPOCHSECONDS - ${ST[section_t0]:-$EPOCHSECONDS} )))${NC}"
      local eta_; eta_=$(fmt_eta "$(eta_left)"); [[ -n $eta_ ]] && add "  ${DIM}$eta_${NC}"
      [[ -n ${ST[cmd]} ]] && add "  ${DIM}▶ ${ST[cmd]}${NC}"
    fi
    hr_
    for line in "${steps[@]}"; do
      local -a f; f=("${(@s:	:)line}")
      name=${f[2]}; dur=""
      # Feld 6 = Warnungen des Abschnitts (ab 3.3.0; ältere steps-Dateien haben es nicht):
      # ein grünes Häkchen mit gelbem Rand heißt „durchgelaufen, aber da war was"
      case ${f[3]} in
        ok)      if (( ${f[6]:-0} > 0 )); then icon="${YELLOW}✓${NC}"; else icon="${GREEN}✓${NC}"; fi
                 dur=$(fmt_dur ${f[4]}); (( ${f[6]:-0} > 0 )) && dur="$dur ${YELLOW}⚠${f[6]}${NC}" ;;
        fail)    icon="${RED}✗${NC}"; dur="$(fmt_dur ${f[4]}) ${RED}${f[5]}!${NC}" ;;
        skip)    icon="${DIM}◦${NC}"; name="${DIM}$name${NC}" ;;
        running) icon="${MAGENTA}▶${NC}"; name="${BOLD}$name${NC}"; dur="${MAGENTA}${spin[tick % 10 + 1]}${NC}" ;;
        *)       icon="${DIM}○${NC}"; name="${DIM}$name${NC}" ;;
      esac
      local nm=$(( w - 12 )); local plain=${f[2]}
      [[ ${#plain} -gt $nm ]] && { plain="${plain[1,$(( nm - 1 ))]}…"; name=${name//${f[2]}/$plain}; }
      local dl=$(vlen "$dur"); local nml=$(vlen "$name"); local pad=$(( w - 3 - nml - dl ))   # nicht 'nl': das ist der Zeilenzähler von add()
      (( pad < 1 )) && pad=1
      add "$icon $name${(l:$pad:: :)_e}$dur"
    done
    hr_
    # KPIs: im schmalen Pane (iPad/iPhone) ohne Label-Spalte, nur Symbole — sonst bleibt
    # vom Wert nichts übrig. kv() setzt Label nur, wenn Platz ist.
    local narrow=0; (( w < 32 )) && narrow=1
    kv() { if (( narrow )); then add "$2"; else add "${(r:10:)1}$2"; fi }
    local ec=${ST[errors]:-0} wc=${ST[warnings]:-0} ac=${ST[actions]:-0} ch=${ST[changes]:-0}
    (( narrow )) || add "${BOLD}KPIs${NC}"
    kv "Pakete"   "brew ${ST[pkg_brew]:-0} · $( (( narrow )) && print -n MAS || print -n 'App Store') ${ST[pkg_mas]:-0}"
    # Zahlen färben: 0 bleibt blass, alles andere springt ins Auge
    local ecs="$ec" wcs="$wc" acs="$ac" chs="$ch"
    (( ec )) && ecs="${RED}${BOLD}$ec${NC}" || ecs="${DIM}0${NC}"
    (( wc )) && wcs="${YELLOW}$wc${NC}"     || wcs="${DIM}0${NC}"
    (( ac )) && acs="${CYAN}$ac${NC}"       || acs="${DIM}0${NC}"
    (( ch )) && chs="${GREEN}$ch${NC}"      || chs="${DIM}0${NC}"
    if (( narrow )); then
      kv "" "✗ $ecs  ⚠ $wcs  · $acs  ↑ $chs"
    else
      kv "Fehler"  "$ecs · Warnungen $wcs · Aktionen $acs"
      kv "Änderung" "$chs aktualisiert"
    fi
    if [[ -n ${ST[security]} ]]; then
      local sec=${ST[security]%% · XProtect*}   # kompakt: "FV ✓ FW ✓ GK ✓ SIP ✓"
      sec=${sec//FileVault/FV}; sec=${sec//Firewall/FW}; sec=${sec//Gatekeeper/GK}; sec=${sec// · / }
      [[ $sec == *✗* ]] && sec="${YELLOW}$sec${NC}" || sec="${GREEN}$sec${NC}"
      kv "Sicherh." "$sec"
      [[ ${ST[security]} == *XProtect* ]] && (( ! narrow )) && add "          XProtect${ST[security]##*XProtect}"
    fi
    [[ -n ${ST[disk]} ]] && kv "Speicher" "${ST[disk]#Freier Speicher: }"
    [[ -n ${ST[caches]} ]] && kv "Caches" "${ST[caches]} GB"
    [[ -n ${ST[backup]} ]] && kv "Backup" "${ST[backup]}$( (( narrow )) || print -n ' (Time Machine)')"
    [[ -n ${ST[sudo]} ]] && kv "Admin" "${ST[sudo]}"
    [[ -n ${ST[net]} ]] && kv "Netz" "${ST[net]}"
    (( ${ST[reboot]:-0} )) && add "${YELLOW}${BOLD}⚠ Neustart erforderlich${NC}"
    if [[ ${ST[phase]} != done && -f "$RUNDIR/heartbeat" ]]; then
      hb=$(<"$RUNDIR/heartbeat"); hb_ts=${hb%%	*}; hb_line=${hb#*	}
      local age=$(( EPOCHSECONDS - hb_ts ))
      hr_
      # Hänger remote melden — einmal pro Lauf. Per SSH sieht niemand dieses Pane, und der
      # Runner selbst kann nicht melden, dass er hängt. Braucht notify=URL in prefs (ein
      # --notify-Flag kennt nur der Runner), und im Dry-Run schweigen wir.
      if (( age > 300 )) && [[ ! -f "$RUNDIR/hang-notified" && ${ST[mode]} != *dry-run* ]]; then
        : > "$RUNDIR/hang-notified"
        notify_push "⏳ update-all hängt? (${ST[host]})" "Seit $(fmt_dur $age) keine Ausgabe · Abschnitt: ${ST[section]} · ${ST[cmd]}" high hourglass
      fi
      if (( age > 180 )); then add "${YELLOW}⚠ Seit $(fmt_dur $age) keine Ausgabe — hängt?${NC}"
      else add "${DIM}└ letzte Ausgabe (vor ${age}s):${NC}"; fi
      add "  ${DIM}${hb_line[1,$(( w - 2 ))]}${NC}"
    fi
    local room=$(( rows - nl - 4 ))   # Zeilen, die für die Hilfe bleiben (Trenner + Fußzeile abgezogen)
    if (( room >= 4 )); then           # Hilfe nur, wenn Platz ist — so viele Schalter, wie passen
      hr_; add "${BOLD}Schalter${NC} ${DIM}update-all.sh …${NC}"
      local hi shown=0; for (( hi=1; hi <= ${#help} && shown < room - 1; hi+=2 )); do
        add " ${BOLD}${(r:13:)help[hi]}${NC}${DIM}${help[hi+1]}${NC}"; (( shown+=1 ))
      done
      (( shown * 2 < ${#help} )) && add " ${DIM}… alle: -h${NC}"
    fi
    hr_
    if [[ -f "$RUNDIR/final" || -f "$RUNDIR/review" ]]; then add "${BOLD}q${NC} ${DIM}schließt die Ansicht (alle Panes)${NC}"
    elif [[ ${ST[phase]} == done ]]; then add "${DIM}schließt ab …${NC}"
    else add "${DIM}läuft … Abbruch: ^C im Log-Pane${NC}"; fi
    printf '\e[H%s\e[J' "$frame"
    # q schließt erst alles, wenn der Runner $RUNDIR/final geschrieben hat (Verlauf, Kopie
    # nach last/, ntfy sind dann durch) — währenddessen würde es den Lauf abschießen.
    # Marker dafür FRISCH prüfen: ST stammt von vor dem (bis zu 1 s blockierenden) read.
    if read -t 1 -k1 -s key 2>/dev/null && [[ $key == q ]] && [[ -f "$RUNDIR/final" || -f "$RUNDIR/review" ]]; then tui_close; break; fi
  done
}

# ── Log-Pane (nur --review) ───────────────────────────────────────
pane_log() {
  printf '\e]2;Log des letzten Laufs (q schließt alles)\a'
  less -R +G "$RUNDIR/run.log"
  tui_close
}

# ── Aktionen-Pane ────────────────────────────────────────────────
action_list() {   # Zeilen "id<TAB>icon titel" — ohne erledigte, ohne bekannte (außer im Rückblick)
  local line aid sfx; local -a f
  [[ -f "$RUNDIR/actions" ]] || return 0
  while IFS= read -r line; do
    f=("${(@s:	:)line}"); aid=${f[1]}; sfx=""
    grep -qx "$aid" "$CONFDIR/acks" 2>/dev/null && continue
    if grep -qx "$aid" "$RUNDIR/known" 2>/dev/null; then
      [[ -f "$RUNDIR/review" ]] || continue
      sfx=" (unverändert)"
    fi
    case ${f[2]} in err) icon="✗" ;; warn) icon="⚠" ;; *) icon="·" ;; esac
    print -r -- "$aid	$icon ${f[4]}$sfx"
  done < "$RUNDIR/actions"
}
action_fix() {
  local line; line=$(grep "^$ACTION_ID	" "$RUNDIR/actions"); local -a f; f=("${(@s:	:)line}")
  [[ -n ${f[5]} ]] || { echo "Kein Fix-Befehl hinterlegt."; read -k1 -s; return 0; }
  echo "${BOLD}▶ ${f[5]}${NC}"; echo
  zsh -lc "${f[5]}"; local rc=$?
  echo; (( rc == 0 )) && echo "${GREEN}✓ Exit 0${NC}" || echo "${RED}✗ Exit $rc${NC}"
  echo "${DIM}Taste: a = als erledigt markieren · andere = zurück${NC}"
  local k; read -k1 -s k; [[ $k == a ]] && { mkdir -p "$CONFDIR"; print -r -- "$ACTION_ID" >> "$CONFDIR/acks"; }
}
pane_actions() {
  printf '\e]2;Aktionen\a'; local key frame line cols w n _e=""
  trap 'printf "\e[?25h\e[0m"; exit 0' EXIT INT TERM
  while true; do
    [[ -d $RUNDIR ]] || exit 0   # wie im Status-Pane: ohne Zustand kein Pane
    load_state "$RUNDIR"
    [[ -f "$RUNDIR/final" || -f "$RUNDIR/review" ]] && break   # erst nach dem kompletten Abschluss in den fzf-Modus
    cols=$(tput cols); w=$(( cols - 2 )); frame=""
    local -a items; items=("${(@f)$(action_list)}"); n=${#items}; [[ -z ${items[1]} ]] && n=0
    frame+="${BOLD}Aktionen${NC} ${DIM}($n) — sammeln sich während des Laufs${NC}"$'\e[K\n'
    frame+="${DIM}${(l:$w::─:)_e}${NC}"$'\e[K\n'
    for line in "${items[@]}"; do [[ -n $line ]] && frame+="${${line#*	}[1,$w]}"$'\e[K\n'; done
    printf '\e[?25l\e[H%s\e[J' "$frame"
    read -t 1 -k1 -s key 2>/dev/null
  done
  printf '\e[?25h'
  while true; do
    local -a items; items=("${(@f)$(action_list)}")
    if [[ -z ${items[1]} ]]; then
      printf '\e[H\e[J%s\n%s\n' "${GREEN}${BOLD}✓ Keine offenen Aktionen${NC}" "${DIM}q schließt die Ansicht${NC}"
      read -k1 -s key; [[ $key == q ]] && { tui_close; exit 0; }; continue
    fi
    if ! has fzf; then   # ohne fzf: statische Liste, q schließt
      printf '\e[H\e[J'; print -rl -- "${(@)items#*	}"; echo "${DIM}(fzf fehlt — 'brew install fzf' für Details/Fix/erledigt) · q schließt die Ansicht${NC}"
      read -k1 -s key; [[ $key == q ]] && { tui_close; exit 0; }; continue
    fi
    # --no-mouse: sonst fängt fzf die Maus ab und tmux kann im Pane nichts markieren/kopieren
    action_list | fzf --no-mouse --delimiter='\t' --with-nth=2.. --ansi --reverse --no-info \
      --header="Enter Details · ^X Fix ausführen · ^A erledigt · ^R Liste neu · q schließt die Ansicht" \
      --preview="cat '$RUNDIR/actions.d/'{1}'.txt'" --preview-window=down:55%:wrap \
      --bind="enter:execute(cat '$RUNDIR/actions.d/'{1}'.txt' | less -R)" \
      --bind="ctrl-x:execute(zsh '$SELF' --_action-fix '$RUNDIR' {1})+reload(zsh '$SELF' --_action-list '$RUNDIR')" \
      --bind="ctrl-a:execute-silent(zsh '$SELF' --_action-ack '$RUNDIR' {1})+reload(zsh '$SELF' --_action-list '$RUNDIR')" \
      --bind="ctrl-r:reload(zsh '$SELF' --_action-list '$RUNDIR')" --bind='q:abort'
    tui_close; exit 0   # q/Esc in fzf → ganze Ansicht zu
  done
}

# ═════════════════════════════════════════════════════════════════
# --history / --list
# ═════════════════════════════════════════════════════════════════
show_history() {
  [[ -f "$LOGDIR/history.tsv" ]] || { echo "Noch kein Verlauf ($LOGDIR/history.tsv)."; exit 0; }
  local -a rows; rows=("${(@f)$(tail -n +2 "$LOGDIR/history.tsv" | tail -20)}")
  local line max=1 d; local -a f durs
  for line in "${rows[@]}"; do f=("${(@s:	:)line}"); durs+=(${f[2]}); (( f[2] > max )) && max=${f[2]}; done
  local sp="▁▂▃▄▅▆▇█" spark=""
  for d in "${durs[@]}"; do spark+=${sp[$(( d * 7 / max + 1 ))]}; done
  echo "\n${BOLD}  Letzte ${#rows} Läufe${NC}   ${DIM}Dauer-Trend:${NC} $spark"
  echo "  ${DIM}Start             Dauer   ok/fehl/skip  Fehler  Aktionen  brew  mas   Speicher            Modus${NC}"
  for line in "${rows[@]}"; do
    f=("${(@s:	:)line}"); local col=$GREEN; (( f[6] > 0 )) && col=$RED
    printf "  %-17s %6s   %2s/%2s/%2s      ${col}%3s${NC}      %3s     %3s  %3s   %-19s %s\n" \
      "${f[1]}" "$(fmt_dur ${f[2]})" "${f[3]}" "${f[4]}" "${f[5]}" "${f[6]}" "${f[7]}" "${f[8]}" "${f[9]}" "${f[10]}" "${f[12]}"
  done
  echo
}

# Selbsttest des Ausgabe-Layers — nach Edits an run/stream/fail/scan/box laufen lassen
selftest() {
  RUNDIR=$(mktemp -d "${TMPDIR:-/tmp}/update-all-selftest.XXXXXX"); mkdir -p "$RUNDIR/out"; : > "$RUNDIR/actions"
  SEC_NAME[test]="Selbsttest"; SEC_ORDER=(test); S_ID=(test); S_NAME=(Selbsttest); S_STATUS=(pending); S_DUR=(0); S_ERRS=(0); S_WARN=(0)
  st phase running; st total 1; st_flush
  section test
  run true
  run sh -c 'echo "zeile eins"; printf "ohne newline am ende"'
  run sh -c 'echo "==> Caveats"; echo "  bitte PATH ergänzen"; echo "==> Summary"; echo "6 vulnerabilities (5 high, 1 critical)"'
  run sh -c 'echo "Error: kaputt"; exit 3'
  run_t 1 sleep 5; local trc=$?
  _close_section
  local failed=0 got
  got=$(<"$RUNDIR/out/2.txt"); [[ $got == $'zeile eins\nohne newline am ende' ]] || { echo "  ✗ stream: letzte Zeile ohne \\n verloren"; failed=1; }
  (( trc == 142 )) || { echo "  ✗ run_t: Timeout lieferte rc=$trc statt 142"; failed=1; }
  (( ERRORS == 2 )) || { echo "  ✗ fail: ERRORS=$ERRORS statt 2"; failed=1; }
  [[ ${S_STATUS[1]} == fail ]] || { echo "  ✗ section: Status ${S_STATUS[1]} statt fail"; failed=1; }
  grep -q 'Caveats von' "$RUNDIR/actions" || { echo "  ✗ scan: Caveats nicht erkannt"; failed=1; }
  grep -q 'npm audit: 6 vulnerabilities' "$RUNDIR/actions" || { echo "  ✗ scan: vulnerabilities nicht erkannt"; failed=1; }
  grep -q 'Fehlgeschlagen: sh -c' "$RUNDIR/actions" || { echo "  ✗ fail: keine Aktion angelegt"; failed=1; }
  [[ -f "$RUNDIR/heartbeat" ]] || { echo "  ✗ stream: kein Heartbeat"; failed=1; }
  box "$CYAN" "Box-Test" "${GREEN}farbig${NC} und länger als die erste Zeile"
  # Umbruch: keine Zeile breiter als das Terminal, kein Wort verloren
  local bx bl bwmax=0 bn
  bx=$(BOX_COLS=30 box "$CYAN" "kurz" "${GREEN}Umbruch-Test${NC} mit einer Zeile, die über dreissig Spalten hinausgeht" "Wort-ohne-Leerzeichen-das-allein-zu-lang-ist")
  for bl in "${(@f)bx}"; do bn=$(vlen "$bl"); (( bn > bwmax )) && bwmax=$bn; done
  (( bwmax <= 30 )) || { echo "  ✗ box: Zeile $bwmax Zellen breit bei 30 Spalten"; failed=1; }
  [[ ${${bx//$ESC\[[0-9;]#[mK]/}//[$'\n'│ ]/} == *Umbruch-Testmit*dreissigSpaltenhinausgeht*Wort-ohne-Leerzeichen-das-allein-zu-lang-ist* ]] \
    || { echo "  ✗ box: Umbruch hat Text verloren"; failed=1; }
  # Log-Rotation: 43 Logs, 40 bleiben — die drei ältesten müssen weg (bis 3.3.3 blieben
  # bei mehr als einem Überzähligen alle stehen)
  local rd_="$RUNDIR/rot" k_; mkdir -p "$rd_"
  for (( k_=1; k_<=43; k_++ )); do touch -t "$(printf '2026010100%02d' $k_)" "$rd_/l$k_.log"; done
  rotate_logs "$rd_" 40 2>/dev/null
  local -a left_; left_=("$rd_"/*.log(N))
  (( ${#left_} == 40 )) && [[ ! -e $rd_/l1.log && ! -e $rd_/l3.log && -e $rd_/l4.log ]] \
    || { echo "  ✗ rotate_logs: ${#left_} statt 40 Logs, oder die falschen gelöscht"; failed=1; }
  # su_parse: Updates mit Neustart (later) von solchen ohne (now) trennen, Größe in GB
  local su_; su_=$(print -r -- 'Software Update Tool

Finding available software
Software Update found the following new or updated software:
* Label: macOS Tahoe 26.1-25B78
	Title: macOS Tahoe 26.1, Version: 26.1, Size: 7354880KiB, Recommended: YES, Action: restart, 
* Label: Safari26.1TahoeAuto-26.1
	Title: Safari, Version: 26.1, Size: 230712KiB, Recommended: YES, ' | su_parse)
  [[ $su_ == $'later\tmacOS Tahoe 26.1-25B78\tmacOS Tahoe 26.1\t26.1\t7.0 GB\nnow\tSafari26.1TahoeAuto-26.1\tSafari\t26.1\t0.2 GB' ]] \
    || { echo "  ✗ su_parse: ${(q)su_}"; failed=1; }
  # Bekannte Hinweise: dieselbe Info wie im letzten Lauf → known (zählt nicht, fehlt in der
  # Liste); dieselbe Warnung bleibt offen; eine neue Info auch
  local LOGDIR="$RUNDIR/lg" kid_ an_=$ACTIONS_N; mkdir -p "$LOGDIR/last"
  kid_=$(print -rn -- "Selbsttest|Dauer-Info" | md5 -q)
  { print -r -- "$kid_	info	Selbsttest	Dauer-Info	"
    print -r -- "$(print -rn -- "Selbsttest|Dauer-Warnung" | md5 -q)	warn	Selbsttest	Dauer-Warnung	"; } > "$LOGDIR/last/actions"
  action info Selbsttest "Dauer-Info"; action warn Selbsttest "Dauer-Warnung"; action info Selbsttest "Neue Info"
  [[ $(<"$RUNDIR/known") == $kid_ ]] && (( ACTIONS_N == an_ + 2 )) \
    || { echo "  ✗ known: $(<"$RUNDIR/known") · neu gezählt $(( ACTIONS_N - an_ )) statt 2"; failed=1; }
  [[ $(action_list) != *Dauer-Info* && $(action_list) == *Dauer-Warnung* ]] \
    || { echo "  ✗ action_list: bekannte Info sichtbar oder Warnung verschluckt"; failed=1; }
  # adopt_ignored: Cask-Name exakt, Bundle-ID per Muster, Fremdes bleibt Vorschlag
  local ai_="parallels,com.example.*,org.sample.*"
  adopt_ignored "$ai_" parallels "com.parallels.desktop.console" \
    && adopt_ignored "$ai_" fooapp com.example.fooapp \
    && adopt_ignored "$ai_" barapp org.sample.barapp \
    && ! adopt_ignored "$ai_" obsidian md.obsidian \
    && ! adopt_ignored "$ai_" example "" \
    || { echo "  ✗ adopt_ignored: Muster greifen falsch"; failed=1; }
  # scan_output: bekannte brew-Meldungen (hdiutil, Sammelzeile) → keine Aktion; npm-Deprecation → Aktion
  local sf_="$RUNDIR/dep.txt"
  print -rl -- "hdiutil: WARNING: 'hdiutil attach -nobrowse -readonly ...' is deprecated. Please use 'diskutil image attach --mountOptions nobrowse --readOnly ...' instead." \
    "==> 1 Deprecated or disabled package" "blu-ray-player-pro (disabled)" > "$sf_"
  scan_output "$sf_" "brew upgrade" >/dev/null
  print -r -- "npm warn deprecated inflight@1.0.6: This module is not supported" > "$sf_"
  scan_output "$sf_" "npm install" >/dev/null
  ! grep -q 'Deprecation-Hinweise (brew upgrade)' "$RUNDIR/actions" && grep -q 'Deprecation-Hinweise (npm install)' "$RUNDIR/actions" \
    || { echo "  ✗ scan_output: bekannte brew-Meldung wurde Aktion oder npm-Hinweis ging verloren"; failed=1; }
  # eta_left: laufender Abschnitt abzüglich seiner Zeit + offene voll, fertige zählen nicht
  local ed_="$RUNDIR/eta" t0s_=${ST[section_t0]:-}; mkdir -p "$ed_"
  print -rl -- $'macos\tmacOS\tok\t6\t0\t0' $'brew\tHomebrew\tok\t198\t0\t0' $'texlive\tTeX\tok\t78\t0\t0' > "$ed_/prev-steps"
  print -rl -- $'macos\tmacOS\tok\t5\t0\t0' $'brew\tHomebrew\trunning\t0\t0\t0' $'texlive\tTeX\tpending\t0\t0\t0' > "$ed_/steps"
  ST[section_t0]=$(( EPOCHSECONDS - 50 ))
  [[ $(eta_left "$ed_") == 226 && $(fmt_eta 226) == "noch ca. 4 min" && $(fmt_eta 30) == "noch < 1 min" && -z $(fmt_eta 0) ]] \
    || { echo "  ✗ eta_left/fmt_eta: $(eta_left "$ed_") · $(fmt_eta 226)"; failed=1; }
  # … und keine Schätzung, wenn einem offenen Abschnitt der Vergleichswert fehlt (Teillauf davor)
  print -rl -- $'macos\tmacOS\tok\t6\t0\t0' > "$ed_/prev-steps"
  [[ -z $(eta_left "$ed_") ]] || { echo "  ✗ eta_left schätzt trotz fehlender Vergleichswerte: $(eta_left "$ed_")"; failed=1; }
  ST[section_t0]=$t0s_
  # journal_summary: Zahlen je Quelle, Einzelzeilen ohne TeX zuerst, Rest gezählt; eine Zeile
  # ohne Quelle (mit Backticks) landet unter „andere“ und wird nicht ausgeführt
  local jf_="$RUNDIR/journal-test" js_
  print -rl -- "brew: a 1 → 2" "tex: x 1 → 2" "brew: b 1 → 2" "npm: c 1 → 2" "tex: y 1 → 2" \
    '`echo AUSGEFUEHRT` ohne Doppelpunkt' "brew: d 1 → 2" > "$jf_"
  js_=$(journal_summary "$jf_" 4)
  [[ $js_ == $'brew 3 · tex 2 · andere 1 · npm 1\nbrew: a 1 → 2\nbrew: b 1 → 2\nnpm: c 1 → 2\n`echo AUSGEFUEHRT` ohne Doppelpunkt\n… und 3 weitere' ]] \
    || { echo "  ✗ journal_summary: ${(q)js_}"; failed=1; }
  js_=$(journal_block "$jf_" 7)
  [[ $js_ == *"Aktualisiert (7):"*"brew 3 · tex 2"* && $js_ == *"↑ tex: y 1 → 2" && $js_ != *weitere* ]] \
    || { echo "  ✗ journal_block: ${(q)js_}"; failed=1; }
  # resume_ids: Abbruch-Notiz (neuer als last/) → alles nicht Fertige; sonst Fehlschläge aus last/
  local rl_="$RUNDIR/resume"; mkdir -p "$rl_/last"
  print -rl -- $'macos\tmacOS\tok\t5\t0\t0' $'brew\tHomebrew\tfail\t9\t1\t0' $'mas\tMAS\tok\t1\t0\t0' > "$rl_/last/steps"
  [[ $(resume_ids "$rl_") == brew ]] || { echo "  ✗ resume_ids (letzter Lauf): $(resume_ids "$rl_")"; failed=1; }
  sleep 1; print -rl -- $'macos\tmacOS\tok\t5\t0\t0' $'brew\tHomebrew\trunning\t0\t0\t0' $'node\tNode\tpending\t0\t0\t0' $'apps\tRadar\tskip\t0\t0\t0' > "$rl_/resume-steps"
  [[ $(resume_ids "$rl_") == brew,node ]] || { echo "  ✗ resume_ids (Abbruch): $(resume_ids "$rl_")"; failed=1; }
  # Netz-Wiederholung: erst „Could not resolve host“, dann Erfolg → kein Fehler; ohne Netzmuster kein zweiter Versuch
  local e0_=$ERRORS nm_="$RUNDIR/netmark" rd0_=$RETRY_DELAY; RETRY_DELAY=0
  run sh -c "if [ -f '$nm_' ]; then echo zweiter Versuch ok; else touch '$nm_'; echo 'curl: (6) Could not resolve host: example.invalid'; exit 6; fi" >/dev/null
  (( $? == 0 && ERRORS == e0_ )) || { echo "  ✗ Netz-Wiederholung: rc/Fehler falsch (ERRORS $ERRORS statt $e0_)"; failed=1; }
  [[ -z ${RUN_RETRIED:-} ]] || { echo "  ✗ Netz-Wiederholung: RUN_RETRIED bleibt nach dem Versuch gesetzt"; failed=1; }
  rm -f "$nm_"
  run sh -c "touch '$nm_'; echo 'Error: kaputt'; exit 4" >/dev/null; undo_last_fail
  [[ -f $nm_ ]] && (( ERRORS == e0_ )) || { echo "  ✗ Netz-Wiederholung: ohne Netzfehler falsch behandelt"; failed=1; }
  RETRY_DELAY=$rd0_
  # docker_gb: Größen aus docker system df
  [[ $(print -r -- $'Images\t9.78GB (45%)' | docker_gb) == 9.8 && $(print -r -- $'Build Cache\t7.668GB' | docker_gb) == 7.7 \
     && $(print -r -- $'x\t512MB (2%)' | docker_gb) == 0.5 && $(print -r -- $'x\t0B (0%)' | docker_gb) == 0.0 ]] \
    || { echo "  ✗ docker_gb rechnet falsch"; failed=1; }
  # app_broken: gesundes Paket nein, ohne Info.plist ja, ohne Programm ja (leeres Gerüst)
  local ab_="$RUNDIR/apps"; mkdir -p "$ab_/Gut.app/Contents/MacOS" "$ab_/OhnePlist.app/Contents/MacOS" "$ab_/OhneProgramm.app/Contents/MacOS"
  : > "$ab_/Gut.app/Contents/Info.plist"; : > "$ab_/Gut.app/Contents/MacOS/Gut"
  : > "$ab_/OhnePlist.app/Contents/MacOS/OhnePlist"; : > "$ab_/OhneProgramm.app/Contents/Info.plist"
  ! app_broken "$ab_/Gut.app" >/dev/null && [[ $(app_broken "$ab_/OhnePlist.app") == "Info.plist fehlt" ]] \
    && [[ $(app_broken "$ab_/OhneProgramm.app") == "kein Programm in Contents/MacOS" ]] \
    || { echo "  ✗ app_broken erkennt Pakete falsch"; failed=1; }
  # mau_redundant: nur wenn ALLE Office-Apps einen Cask haben; ohne Office-Apps nein
  local mr_ok=1 mr_hp=$HOMEBREW_PREFIX; local -a mr_apps; mr_apps=("${OFFICE_APPS[@]}")
  HOMEBREW_PREFIX="$RUNDIR/hb"; mkdir -p "$HOMEBREW_PREFIX/Caskroom/microsoft-word"
  OFFICE_APPS=("/Applications/Microsoft Word.app"); mau_redundant || mr_ok=0
  OFFICE_APPS+=("/Applications/Microsoft Excel.app"); mau_redundant && mr_ok=0
  OFFICE_APPS=(); mau_redundant && mr_ok=0
  HOMEBREW_PREFIX=$mr_hp; OFFICE_APPS=("${mr_apps[@]}")
  (( mr_ok )) || { echo "  ✗ mau_redundant: MAU würde für manuell installierte Office-Apps stillgelegt"; failed=1; }
  # tm_latest: jüngstes Datum über zwei Ziele (das zweite ist neuer), UTC → Epoch
  local tp_="$RUNDIR/tm.plist"
  print -r -- '<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>Destinations</key><array>
<dict><key>SnapshotDates</key><array><date>2026-10-27T17:16:01Z</date><date>2026-10-29T10:03:08Z</date></array></dict>
<dict><key>SnapshotDates</key><array><date>2026-10-30T18:17:39Z</date></array></dict>
</array></dict></plist>' > "$tp_"
  [[ $(tm_latest "$tp_") == 1793384259 ]] || { echo "  ✗ tm_latest: $(tm_latest "$tp_") statt 1793384259"; failed=1; }
  vercmp 12.6 12.5.5; (( $? == 1 )) || { echo "  ✗ vercmp 12.6 > 12.5.5"; failed=1; }
  vercmp 1.12.4.0,2607 1.12.8.0,2609; (( $? == 2 )) || { echo "  ✗ vercmp mit Komma-Suffix"; failed=1; }
  (( $(vlen "${RED}abc${NC}") == 3 )) || { echo "  ✗ vlen"; failed=1; }
  echo; (( failed )) && echo "  ${RED}✗ Selbsttest fehlgeschlagen${NC}" || echo "  ${GREEN}✓ Selbsttest bestanden${NC} ${DIM}(2 erwartete Fehlschläge oben: Exit 3 und Timeout)${NC}"
  rm -rf "$RUNDIR"; exit $failed
}

show_list() {
  build_registry
  echo "\n${BOLD}  Abschnitte auf diesem Mac${NC} ${DIM}(--only/--skip mit diesen IDs)${NC}"
  local id; for id in "${SEC_ORDER[@]}"; do printf "  %-10s %s\n" "$id" "${SEC_NAME[$id]}"; done
  (( ${#MISSING} )) && echo "  ${DIM}nicht installiert: ${(j:, :)MISSING}${NC}"
  echo "  ${DIM}opt-in: ollama (-m) · docker (--docker)${NC}\n"
}

# ═════════════════════════════════════════════════════════════════
# Dispatcher
# ═════════════════════════════════════════════════════════════════
case $INTERNAL in
  runner)      runner 1 ;;
  status)      pane_status ;;
  actions)     pane_actions ;;
  pane-log)    pane_log ;;
  action-list) action_list ;;
  action-fix)  action_fix ;;
  action-ack)  mkdir -p "$CONFDIR"; print -r -- "$ACTION_ID" >> "$CONFDIR/acks" ;;
  "")
    case $MODE in
      history)  show_history ;;
      list)     show_list ;;
      selftest) selftest ;;
      tmuxinator) write_tmuxinator ;;
      review)  has tmux || { echo "--review braucht tmux"; exit 1; }; tui_launch review ;;
      run)
        if (( RESUME )) && [[ -z $(resume_ids) ]]; then
          echo "Nichts nachzuholen — der letzte Lauf ist vollständig und ohne Fehlschlag durchgelaufen."; exit 0
        fi
        if (( PLAIN )) || (( ! HAS_TTY )) || ! has tmux; then runner 0
        else tui_launch run "$@"; fi ;;
    esac ;;
esac
