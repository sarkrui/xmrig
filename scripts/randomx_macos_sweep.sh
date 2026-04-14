#!/bin/bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/randomx_macos_sweep.sh [options]

Sequentially benchmark RandomX on macOS and print a compact table that is easy
to compare across Apple Silicon machines.

Options:
  --bin PATH         Path to xmrig binary (default: ./build/xmrig)
  --bench SIZE       Benchmark size passed to --bench (default: 1M)
  --duration SEC     Seconds to let each run warm up before stopping it (default: 20)
  --threads LIST     Comma-separated thread counts, for example 6,8,10,12
  --keep-logs DIR    Keep per-run logs in DIR instead of deleting them
  -h, --help         Show this help
EOF
}


BIN="./build/xmrig"
BENCH_SIZE="1M"
DURATION=20
THREADS_LIST=""
KEEP_LOGS_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bin)
            BIN="$2"
            shift 2
            ;;
        --bench)
            BENCH_SIZE="$2"
            shift 2
            ;;
        --duration)
            DURATION="$2"
            shift 2
            ;;
        --threads)
            THREADS_LIST="${2//,/ }"
            shift 2
            ;;
        --keep-logs)
            KEEP_LOGS_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ ! -x "$BIN" ]]; then
    echo "xmrig binary not found or not executable: $BIN" >&2
    exit 1
fi

if [[ -n "$KEEP_LOGS_DIR" ]]; then
    mkdir -p "$KEEP_LOGS_DIR"
fi

if [[ -z "$THREADS_LIST" ]]; then
    LOGICAL_CPUS="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 0)"
    if [[ "$LOGICAL_CPUS" -le 0 ]]; then
        echo "Failed to detect logical CPU count. Pass --threads explicitly." >&2
        exit 1
    fi

    THREADS_LIST=""
    STEP=2
    if [[ "$LOGICAL_CPUS" -le 8 ]]; then
        STEP=1
    fi

    i="$STEP"
    while [[ "$i" -le "$LOGICAL_CPUS" ]]; do
        THREADS_LIST="$THREADS_LIST $i"
        i=$((i + STEP))
    done

    case " $THREADS_LIST " in
        *" $LOGICAL_CPUS "*) ;;
        *) THREADS_LIST="$THREADS_LIST $LOGICAL_CPUS" ;;
    esac
fi

echo "Benchmark binary : $BIN"
echo "Benchmark size   : $BENCH_SIZE"
echo "Run duration     : ${DURATION}s"
echo "Thread sweep     :$THREADS_LIST"
echo

printf "%-8s %-12s %-12s %-12s %s\n" "target" "actual" "10s_H/s" "dataset_ms" "log"

for target_threads in $THREADS_LIST; do
    log_file="$(mktemp -t xmrig-rx-sweep.XXXXXX.log)"

    "$BIN" --bench="$BENCH_SIZE" --no-color --print-time=1 --log-file="$log_file" -t "$target_threads" >/dev/null 2>&1 &
    pid=$!

    sleep "$DURATION"

    kill -TERM "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true

    actual_threads="$(sed -n 's/.*use profile .* (\([0-9][0-9]*\) threads).*/\1/p' "$log_file" | tail -n 1)"
    speed_10s="$(sed -n 's/.*speed 10s\/60s\/15m \([0-9.][0-9.]*\).*/\1/p' "$log_file" | tail -n 1)"
    dataset_ms="$(sed -n 's/.*dataset ready (\([0-9][0-9]*\) ms).*/\1/p' "$log_file" | tail -n 1)"

    [[ -n "$actual_threads" ]] || actual_threads="n/a"
    [[ -n "$speed_10s" ]] || speed_10s="n/a"
    [[ -n "$dataset_ms" ]] || dataset_ms="n/a"

    if [[ -n "$KEEP_LOGS_DIR" ]]; then
        final_log="$KEEP_LOGS_DIR/randomx_t${target_threads}.log"
        mv "$log_file" "$final_log"
    else
        final_log="$log_file"
    fi

    printf "%-8s %-12s %-12s %-12s %s\n" "$target_threads" "$actual_threads" "$speed_10s" "$dataset_ms" "$final_log"

    if [[ -z "$KEEP_LOGS_DIR" ]]; then
        rm -f "$final_log"
    fi
done
