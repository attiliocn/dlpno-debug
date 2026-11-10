#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
JOBFILE="$SCRIPT_DIR/slurm-dlpno.sh"
CSV="$SCRIPT_DIR/slurm-dlpno.csv"
JOB_NAME="dlpno"
OUTPUT_PATTERN="${JOB_NAME}_%J.stdout"
local_dir="$PWD"
local_dir_q="$(printf '%q' "$local_dir")"
local_dir_escaped="$(printf '%s' "$local_dir_q" | sed 's/[\\&|]/\\&/g')"

usage() {
    cat <<EOF
Uso: $(basename "$0") <input> [input ...]

Preenche $CSV e atualiza $JOBFILE:
  - localDir com o diretório atual
  - #SBATCH --job-name (fixo: ${JOB_NAME})
  - #SBATCH --output (fixo: ${OUTPUT_PATTERN})
  - #SBATCH --array

O localDir do script será atualizado para o diretório atual.
Execute este script a partir do diretório que contém slurm-dlpno.sh e
slurm-dlpno.csv.

Os inputs devem existir no diretório deste script ou no diretório pai.

Exemplos:
  $(basename "$0") int-1-HH
  $(basename "$0") water1 water2
EOF
}

die() {
    echo "ERRO: $*" >&2
    exit 1
}

if [[ ! -f "$PWD/slurm-dlpno.sh" || ! -f "$PWD/slurm-dlpno.csv" ]]; then
    die "execute a partir do diretório que contém slurm-dlpno.sh e slurm-dlpno.csv"
fi

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    "")
        usage >&2
        exit 1
        ;;
esac

inputs=("$@")

normalized_inputs=()
for raw_input in "${inputs[@]}"; do
    [[ "$raw_input" != */* ]] || die "o input deve ser um nome de arquivo, sem diretório: $raw_input"

    input="${raw_input%.inp}.inp"
    [[ "$input" =~ ^[A-Za-z0-9._-]+$ ]] || die "nome de input inválido: $input"
    if [[ -f "$SCRIPT_DIR/$input" ]]; then
        :
    elif [[ -f "$SCRIPT_DIR/../$input" ]]; then
        :
    else
        die "input não encontrado: $SCRIPT_DIR/$input ou $SCRIPT_DIR/../$input"
    fi

    normalized_inputs+=("$input")
done

[[ -f "$JOBFILE" ]] || die "script não encontrado: $JOBFILE"
[[ -f "$CSV" ]] || die "CSV não encontrado: $CSV"
grep -q '^#SBATCH --job-name[[:space:]]' "$JOBFILE" || die "diretiva --job-name não encontrada em $JOBFILE"
grep -q '^#SBATCH --output=' "$JOBFILE" || die "diretiva --output não encontrada em $JOBFILE"
grep -q '^#SBATCH --array=' "$JOBFILE" || die "diretiva --array não encontrada em $JOBFILE"
grep -q '^localDir=' "$JOBFILE" || die "variável localDir não encontrada em $JOBFILE"

tmp_csv="$(mktemp "${CSV}.XXXXXX")"
trap 'rm -f "$tmp_csv"' EXIT

for i in "${!normalized_inputs[@]}"; do
    printf '%d,%s\n' "$((i + 1))" "${normalized_inputs[$i]}" >> "$tmp_csv"
done

if [[ -e "$CSV" ]]; then
    chmod --reference="$CSV" "$tmp_csv" 2>/dev/null || true
fi
mv "$tmp_csv" "$CSV"
trap - EXIT

array_end="${#normalized_inputs[@]}"

sed -i -E \
    -e "s|^localDir=.*|localDir=${local_dir_escaped}|" \
    -e "s|^#SBATCH --job-name[[:space:]].*|#SBATCH --job-name ${JOB_NAME}|" \
    -e "s|^#SBATCH --output=.*|#SBATCH --output=${OUTPUT_PATTERN}|" \
    -e "s|^#SBATCH --array=.*|#SBATCH --array=1-${array_end}|" \
    "$JOBFILE"

echo "Atualizado: $JOBFILE"
echo "  localDir ${local_dir}"
echo "  --job-name ${JOB_NAME}"
echo "  --output=${OUTPUT_PATTERN}"
echo "  --array=1-${array_end}"
echo "Atualizado: $CSV"
sed 's/^/  /' "$CSV"
