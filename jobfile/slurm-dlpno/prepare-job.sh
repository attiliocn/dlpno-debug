#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
JOBFILE="$SCRIPT_DIR/slurm-dlpno.sh"
CSV="$SCRIPT_DIR/slurm-dlpno.csv"

local_dir="$PWD"
local_dir_q="$(printf '%q' "$local_dir")"
local_dir_escaped="$(printf '%s' "$local_dir_q" | sed 's/[\\&|]/\\&/g')"

usage() {
    cat <<EOF
Uso: $(basename "$0") <job-name>

Lê automaticamente todos os arquivos *.inp do diretório atual,
em ordem natural, e atualiza $JOBFILE e $CSV.

Atualiza:
  - localDir com o diretório atual
  - #SBATCH --job-name <job-name>
  - #SBATCH --output=slurm-%A_%a.stdout (renomeado para <input>_<jobid>.stdout)
  - #SBATCH --array=1-<quantidade de .inp>

Exemplo:
  $(basename "$0") test4
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

[[ $# -eq 1 ]] || {
    echo "ERRO: informe exatamente um job name." >&2
    usage >&2
    exit 1
}

job_name="$1"
[[ "$job_name" =~ ^[A-Za-z0-9._-]+$ ]] || die "nome do job inválido: $job_name"
output_pattern="slurm-%A_%a.stdout"

# Collect *.inp files from the current directory.
shopt -s nullglob
input_files=("$PWD"/*.inp)
shopt -u nullglob

inputs=()
for input_path in "${input_files[@]}"; do
    [[ -f "$input_path" ]] || continue
    input_name="${input_path##*/}"
    [[ "$input_name" =~ ^[A-Za-z0-9._-]+$ ]] || die "nome de input inválido: $input_name"
    inputs+=("$input_name")
done

[[ "${#inputs[@]}" -gt 0 ]] || die "nenhum arquivo .inp encontrado em $PWD"

# Sort in natural order (file2 before file10).
mapfile -t sorted_inputs < <(printf '%s\n' "${inputs[@]}" | LC_ALL=C sort -V)
inputs=("${sorted_inputs[@]}")

[[ -f "$JOBFILE" ]] || die "script não encontrado: $JOBFILE"
[[ -f "$CSV" ]] || die "CSV não encontrado: $CSV"
grep -q '^#SBATCH --job-name[[:space:]]' "$JOBFILE" || die "diretiva --job-name não encontrada em $JOBFILE"
grep -q '^#SBATCH --output=' "$JOBFILE" || die "diretiva --output não encontrada em $JOBFILE"
grep -q '^#SBATCH --array=' "$JOBFILE" || die "diretiva --array não encontrada em $JOBFILE"
grep -q '^localDir=' "$JOBFILE" || die "variável localDir não encontrada em $JOBFILE"

tmp_csv="$(mktemp "${CSV}.XXXXXX")"
trap 'rm -f "$tmp_csv"' EXIT

for i in "${!inputs[@]}"; do
    printf '%d,%s\n' "$((i + 1))" "${inputs[$i]}" >> "$tmp_csv"
done

if [[ -e "$CSV" ]]; then
    chmod --reference="$CSV" "$tmp_csv" 2>/dev/null || true
fi
mv "$tmp_csv" "$CSV"
trap - EXIT

array_end="${#inputs[@]}"

sed -i -E \
    -e "s|^localDir=.*|localDir=${local_dir_escaped}|" \
    -e "s|^#SBATCH --job-name[[:space:]].*|#SBATCH --job-name ${job_name}|" \
    -e "s|^#SBATCH --output=.*|#SBATCH --output=${output_pattern}|" \
    -e "s|^#SBATCH --array=.*|#SBATCH --array=1-${array_end}|" \
    "$JOBFILE"

echo "Atualizado: $JOBFILE"
echo "  localDir ${local_dir}"
echo "  --job-name ${job_name}"
echo "  --output=${output_pattern}"
echo "  --array=1-${array_end}"
echo "Atualizado: $CSV"
sed 's/^/  /' "$CSV"
