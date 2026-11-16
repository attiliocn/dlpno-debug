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
Usage: $(basename "$0") <job-name>

Automatically discovers all *.inp files in the current directory in natural
sort order and updates $JOBFILE and $CSV.

Updates:
  - localDir to the current directory
  - #SBATCH --job-name <job-name>
  - #SBATCH --output=slurm-%A_%a.stdout (renamed to <input>_<jobid>.stdout)
  - #SBATCH --ntasks=<n_cores> (read from *.inp; fails if inputs differ)
  - #SBATCH --mem=<mem>G (100% surplus: 2 x n_cores x %maxcore)
  - #SBATCH --time=168:00:00 (7-day default)
  - #SBATCH --array=1-<number of .inp files>

Example:
  $(basename "$0") test4
EOF
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

if [[ ! -f "$PWD/slurm-dlpno.sh" || ! -f "$PWD/slurm-dlpno.csv" ]]; then
    die "run from the directory containing slurm-dlpno.sh and slurm-dlpno.csv"
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
    echo "ERROR: provide exactly one job name." >&2
    usage >&2
    exit 1
}

job_name="$1"
[[ "$job_name" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid job name: $job_name"
output_pattern="slurm-%A_%a.stdout"

# Collect *.inp files from the current directory.
shopt -s nullglob
input_files=("$PWD"/*.inp)
shopt -u nullglob

inputs=()
for input_path in "${input_files[@]}"; do
    [[ -f "$input_path" ]] || continue
    input_name="${input_path##*/}"
    [[ "$input_name" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid input filename: $input_name"
    inputs+=("$input_name")
done

[[ "${#inputs[@]}" -gt 0 ]] || die "no .inp files found in $PWD"

# Sort in natural order (file2 before file10).
mapfile -t sorted_inputs < <(printf '%s\n' "${inputs[@]}" | LC_ALL=C sort -V)
inputs=("${sorted_inputs[@]}")

# Extract nprocs (from %pal ... nprocs N or ! palN) and %maxcore N from an ORCA .inp file.
parse_orca_resources() {
    awk '
    BEGIN { IGNORECASE = 1; in_pal = 0; nprocs = ""; maxcore = "" }
    {
        sub(/#.*/, "", $0)
        line = $0
        if (line ~ /^[[:space:]]*$/) next

        if (line ~ /^[[:space:]]*!/) {
            if (match(line, /(^|[[:space:]])pal([0-9]+)([[:space:]]|$)/, m)) {
                nprocs = m[2]
            }
        }
        if (line ~ /^[[:space:]]*%pal([[:space:]]|$)/) {
            in_pal = 1
        }
        if (in_pal) {
            if (match(line, /nprocs[[:space:]]+([0-9]+)/, m)) {
                nprocs = m[1]
            }
            if (line ~ /(^|[[:space:]])end([[:space:]]|$)/ && line !~ /^[[:space:]]*%pal[[:space:]]*$/) {
                in_pal = 0
            } else if (line ~ /^[[:space:]]*end([[:space:]]|$)/) {
                in_pal = 0
            }
        }
        if (match(line, /^[[:space:]]*%maxcore[[:space:]]+([0-9]+)/, m)) {
            maxcore = m[1]
        }
    }
    END { printf "%s %s\n", nprocs, maxcore }
    ' "$1"
}

n_cores=""
max_maxcore=0
for input_name in "${inputs[@]}"; do
    read -r file_cores file_maxcore < <(parse_orca_resources "$PWD/$input_name")
    [[ "${file_cores:-}" =~ ^[1-9][0-9]*$ ]] || die "could not detect n_cores (%pal nprocs or ! palN) in $input_name"
    [[ "${file_maxcore:-}" =~ ^[1-9][0-9]*$ ]] || die "could not detect %maxcore in $input_name"
    if [[ "$file_maxcore" -eq 8000 ]]; then
        echo "WARNING: $input_name uses %maxcore 8000 MB; 16000 MB (16 GB) is recommended." >&2
    elif [[ "$file_maxcore" -gt 16000 ]]; then
        echo "WARNING: $input_name uses %maxcore ${file_maxcore} MB (> 16000 MB); 16000 MB (16 GB) is recommended." >&2
    elif [[ "$file_maxcore" -lt 16000 ]]; then
        echo "WARNING: $input_name had %maxcore ${file_maxcore} MB (< 16000 MB); updated to %maxcore 16000 in input." >&2
        sed -i -E 's|^([[:space:]]*)%maxcore[[:space:]]+[0-9]+|\1%maxcore 16000|I' "$PWD/$input_name"
        file_maxcore=16000
    fi

    if [[ -z "$n_cores" ]]; then
        n_cores="$file_cores"
    elif [[ "$file_cores" -ne "$n_cores" ]]; then
        die "inputs with different core counts are not allowed: $input_name has $file_cores cores (expected $n_cores)"
    fi

    if [[ "$max_maxcore" -gt 0 && "$file_maxcore" -ne "$max_maxcore" ]]; then
        echo "WARNING: $input_name uses %maxcore $file_maxcore MB (another input uses $max_maxcore MB); using the largest value for --mem." >&2
    fi
    if [[ "$file_maxcore" -gt "$max_maxcore" ]]; then
        max_maxcore="$file_maxcore"
    fi
done

# Default Slurm limits: 7 days walltime and 100% RAM surplus above n_cores * %maxcore.
default_time="168:00:00"
mem_gb=$(( (2 * n_cores * max_maxcore + 999) / 1000 ))

[[ -f "$JOBFILE" ]] || die "script not found: $JOBFILE"
[[ -f "$CSV" ]] || die "CSV not found: $CSV"
grep -q '^#SBATCH --job-name[[:space:]]' "$JOBFILE" || die "--job-name directive not found in $JOBFILE"
grep -q '^#SBATCH --output=' "$JOBFILE" || die "--output directive not found in $JOBFILE"
grep -q '^#SBATCH --ntasks=' "$JOBFILE" || die "--ntasks directive not found in $JOBFILE"
grep -q '^#SBATCH --mem=' "$JOBFILE" || die "--mem directive not found in $JOBFILE"
grep -q '^#SBATCH --time=' "$JOBFILE" || die "--time directive not found in $JOBFILE"
grep -q '^#SBATCH --array=' "$JOBFILE" || die "--array directive not found in $JOBFILE"
grep -q '^localDir=' "$JOBFILE" || die "localDir variable not found in $JOBFILE"

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
    -e "s|^#SBATCH --ntasks=.*|#SBATCH --ntasks=${n_cores}|" \
    -e "s|^#SBATCH --mem=.*|#SBATCH --mem=${mem_gb}G|" \
    -e "s|^#SBATCH --time=.*|#SBATCH --time=${default_time}|" \
    -e "s|^#SBATCH --array=.*|#SBATCH --array=1-${array_end}|" \
    "$JOBFILE"

echo "Updated: $JOBFILE"
echo "  localDir ${local_dir}"
echo "  --job-name ${job_name}"
echo "  --output=${output_pattern}"
echo "  --ntasks=${n_cores}"
echo "  --mem=${mem_gb}G (100% surplus over ${n_cores} x ${max_maxcore} MB)"
echo "  --time=${default_time}"
echo "  --array=1-${array_end}"
echo "Updated: $CSV"
sed 's/^/  /' "$CSV"
