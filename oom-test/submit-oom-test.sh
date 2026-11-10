#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORK="$SCRIPT_DIR/work"

usage() {
    cat <<EOF
Uso: $(basename "$0") <partition> [mem] [time]

Exemplo:
  $(basename "$0") <partition> 1G 00:10:00
EOF
}

die() {
    echo "ERRO: $*" >&2
    exit 1
}

[[ $# -ge 1 ]] || {
    usage >&2
    exit 1
}

partition="$1"
mem="${2:-1G}"
run_time="${3:-00:10:00}"

[[ -f "$WORK/slurm-dlpno.sh" ]] || die "execute ./setup-oom-test.sh primeiro"
[[ -f "$WORK/slurm-dlpno.csv" ]] || die "CSV não encontrado em $WORK"
[[ -x "$WORK/test-bin/singularity" ]] || die "fake singularity não encontrado em $WORK/test-bin"
[[ -f "$WORK/dummy.sif" ]] || die "dummy.sif não encontrado em $WORK"
command -v sbatch >/dev/null 2>&1 || die "sbatch não encontrado"

if grep -q '^#SBATCH --array=ARRAY' "$WORK/slurm-dlpno.sh"; then
    die "job ainda não preparado; execute ./setup-oom-test.sh"
fi

# Put the fake singularity first in PATH and export that PATH to the job.
export PATH="$WORK/test-bin:$PATH"
cd "$WORK"

sbatch \
    --partition="$partition" \
    --mem="$mem" \
    --time="$run_time" \
    --export="ALL,PATH=$PATH" \
    slurm-dlpno.sh
