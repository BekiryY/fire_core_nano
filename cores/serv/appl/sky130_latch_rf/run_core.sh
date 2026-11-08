#!/usr/bin/env bash
# ============================================================
#  run_core.sh -- LibreLane Classic flow for SERV with the latch register file (sky130A / sky130_fd_sc_hd), in WSL.
#
#  USAGE   ./run_core.sh <tag> [librelane options]
#          DETACH=1 ./run_core.sh k1          (detached; log $RUNS_ROOT/<tag>.log, last line DONE_EXIT <rc>)
#          UTIL=55 DETACH=1 ./run_core.sh k2  (another core utilization, %; default config.yaml's)
#  Run dir $RUNS_ROOT/<tag> (default ~/eda/projects/serv_sky130).
# ============================================================
set -u -o pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
qargs() { [ $# -gt 0 ] && printf '%q ' "$@"; }
if [ $# -lt 1 ]; then sed -n 3,9p "${BASH_SOURCE[0]}"; exit 2; fi
if command -v cygpath >/dev/null 2>&1 && command -v wsl.exe >/dev/null 2>&1; then
  WSELF="$(wsl.exe -e wslpath -u "$(cygpath -w "$HERE/run_core.sh")" | tr -d '\r')"
  exec wsl.exe -e bash -lc "DETACH='${DETACH:-}' UTIL='${UTIL:-}' bash '$WSELF' $(qargs "$@")"
fi
TAG="$1"; shift
LIBRELANE_NIX="${LIBRELANE_NIX:-$HOME/eda/librelane}"
PDK_ROOT="${PDK_ROOT:-$HOME/.ciel}"
RUNS_ROOT="${RUNS_ROOT:-$HOME/eda/projects/serv_sky130}"
RUN_DIR="$RUNS_ROOT/$TAG"; LOG="$RUNS_ROOT/$TAG.log"
if [ -n "$(ls -A "$RUN_DIR" 2>/dev/null)" ]; then
  case " $* " in *" --from "*|*" -F "*) ;; *) echo "[!] $RUN_DIR exists: new tag or --from"; exit 2;; esac
fi
mkdir -p "$RUN_DIR"
[ -n "${UTIL:-}" ] && set -- -c "FP_CORE_UTIL=$UTIL" "$@"
JOB="$RUNS_ROOT/$TAG.job.sh"
cat > "$JOB" <<EOF
#!/usr/bin/env bash
cd '$HERE' || exit 1
nix-shell '$LIBRELANE_NIX' --run "librelane --flow Classic --pdk sky130A --pdk-root '$PDK_ROOT' --design-dir '$HERE' --force-run-dir '$RUN_DIR' --hide-progress-bar $(qargs "$@") '$HERE/config.yaml'" >> '$LOG' 2>&1
echo "DONE_EXIT \$?" >> '$LOG'
EOF
chmod +x "$JOB"
echo "[i] run dir $RUN_DIR"; echo "[i] log     $LOG"
if [ -n "${DETACH:-}" ]; then
  setsid nohup bash "$JOB" >/dev/null 2>&1 < /dev/null &
  disown
  sleep 2; pgrep -f "$JOB" >/dev/null && echo "[i] detached (pid $(pgrep -f "$JOB" | head -1))"
else
  bash "$JOB"; tail -1 "$LOG"
fi
