#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
JOBFILE="$SCRIPT_DIR/slurm-dlpno.sh"
CSV="$SCRIPT_DIR/slurm-dlpno.csv"

usage() {
    cat <<EOF
Uso: $(basename "$0") <job-name> [input ...]

Preenche $CSV e atualiza as diretivas de $JOBFILE:
  - #SBATCH --job-name
  - #SBATCH --output
  - #SBATCH --array

Se nenhum input for informado, usa <job-name>.inp.
Os inputs devem existir no diretório deste script ou no diretório pai.

Exemplos:
  $(basename "$0") int-1-HH
  $(basename "$0") lote-01 int-1-HH.inp outro-job.inp
EOF
}

die() {
    echo "ERRO: $*" >&2
    exit 1
}

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

job_name="${1%.inp}"
shift
inputs=("$@")

[[ -n "$job_name" ]] || die "nome do job vazio"
[[ "$job_name" =~ ^[A-Za-z0-9._-]+$ ]] || die "nome do job inválido: $job_name"

if [[ ${#inputs[@]} -eq 0 ]]; then
    inputs=("$job_name")
fi

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
    -e "s|^#SBATCH --job-name[[:space:]].*|#SBATCH --job-name ${job_name}|" \
    -e "s|^#SBATCH --output=.*|#SBATCH --output=${job_name}_%J.stdout|" \
    -e "s|^#SBATCH --array=.*|#SBATCH --array=1-${array_end}|" \
    "$JOBFILE"

echo "Atualizado: $JOBFILE"
echo "  --job-name ${job_name}"
echo "  --output=${job_name}_%J.stdout"
echo "  --array=1-${array_end}"
echo "Atualizado: $CSV"
sed 's/^/  /' "$CSV"
