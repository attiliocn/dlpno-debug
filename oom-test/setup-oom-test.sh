#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
WORK="$SCRIPT_DIR/work"
FAKE_SRC="$SCRIPT_DIR/fake-singularity"

# Prefer the production files when running inside the repository. When this
# directory is copied alone to the HPC, use the bundled fixtures instead.
if [[ -f "$REPO_DIR/jobfile/slurm-dlpno/slurm-dlpno.sh" ]]; then
    SOURCE_DIR="$REPO_DIR/jobfile/slurm-dlpno"
else
    SOURCE_DIR="$SCRIPT_DIR/fixtures"
fi

die() {
    echo "ERRO: $*" >&2
    exit 1
}

echo "Fonte dos arquivos do job: $SOURCE_DIR"
if [[ ! -f "$SOURCE_DIR/slurm-dlpno.sh" ]]; then
    die "arquivos da cópia de trabalho não encontrados em $SOURCE_DIR"
fi
[[ -f "$SOURCE_DIR/prepare-job.sh" ]] || die "prepare-job.sh não encontrado: $SOURCE_DIR/prepare-job.sh"
[[ -f "$SOURCE_DIR/slurm-dlpno.csv" ]] || die "CSV não encontrado: $SOURCE_DIR/slurm-dlpno.csv"
[[ -f "$SOURCE_DIR/water1.inp" ]] || die "input de teste não encontrado: $SOURCE_DIR/water1.inp"
[[ -f "$FAKE_SRC" ]] || die "fake-singularity não encontrado: $FAKE_SRC"

# The work directory is disposable; keep the guard to avoid deleting anything else.
[[ "$WORK" == "$SCRIPT_DIR/work" ]] || die "diretório de trabalho inesperado: $WORK"
rm -rf "$WORK"

mkdir -p "$WORK/test-bin"
cp "$SOURCE_DIR/slurm-dlpno.sh" "$WORK/slurm-dlpno.sh"
cp "$SOURCE_DIR/slurm-dlpno.csv" "$WORK/slurm-dlpno.csv"
chmod +x "$WORK/slurm-dlpno.sh"
cp "$SOURCE_DIR/prepare-job.sh" "$WORK/prepare-job.sh"
cp "$SOURCE_DIR/water1.inp" "$WORK/water1.inp"
cp "$FAKE_SRC" "$WORK/test-bin/singularity"
chmod +x "$WORK/prepare-job.sh" "$WORK/test-bin/singularity"

# The fake runner ignores the container, but slurm-dlpno.sh checks that the
# configured path exists. Use a dummy file instead of the real SIF.
: > "$WORK/dummy.sif"
sed -i "s|^ctPath=.*|ctPath=\"$WORK/dummy.sif\"|" "$WORK/slurm-dlpno.sh"

(
    cd "$WORK"
    ./prepare-job.sh oomtest
)

cat <<EOF

Teste preparado em:
  $WORK

Para submeter:
  $SCRIPT_DIR/submit-oom-test.sh <partition>

O teste usa --mem=1G e um fake singularity que tenta alocar 4 GiB.
EOF
