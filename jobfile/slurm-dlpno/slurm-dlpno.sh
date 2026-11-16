#!/bin/bash

# ============================================================================
# ORCA DLPNO Slurm job - one input per array task
#
# 1. On the HPC, create a working folder and put the inputs there.
# 2. Keep this script, the CSV, prepare-job.sh, and inputs in that folder.
# 3. From that folder, prepare the job (reads *.inp automatically):
#      ./prepare-job.sh <job-name>
# 4. Submit from the same folder, choosing the partition at submission:
#      sbatch --partition=<partition> slurm-dlpno.sh
# 5. Adjust the container and scratch paths in the PATHS block below if needed.
#
# NOTE: Tested on CloudUFSCar and Curie. On a different HPC cluster, verify the
# Singularity container and scratch paths in section 5 (PATHS - USER-EDITABLE).

# ============================================================================

# ============================================================================
# 1. SLURM DIRECTIVES
# ============================================================================
# Placeholders below are replaced by ./prepare-job.sh <job-name>; this template
# is intentionally invalid for sbatch until prepare-job.sh is executed.
# Slurm output starts as slurm-%A_%a.stdout; after the input is selected it is
# renamed to <input>_<jobid>.stdout. Partition is chosen at submission time.

# Resource placeholders (populated by prepare-job.sh from *.inp):
#   - --ntasks: read from %pal nprocs / ! palN (must match across all *.inp)
#   - --mem: 100% surplus above nprocs * %maxcore (minimum 75% recommended)
#   - --time: 168:00:00 (7 days default)

#SBATCH --job-name PLACEHOLDER_JOB_NAME
#SBATCH --output=PLACEHOLDER_OUTPUT
#SBATCH --nodes=1
#SBATCH --ntasks=PLACEHOLDER_NTASKS
#SBATCH --mem=PLACEHOLDER_MEM
#SBATCH --time=PLACEHOLDER_TIME
#SBATCH --array=ARRAY
#SBATCH --signal=B:TERM@60

# ============================================================================
# 2. FUNCTIONS
# ============================================================================

# ----------------------------------------------------------------------------
# shutdown_orca
# Stop the container process (and therefore ORCA) before archiving.
# On a signaled kill the shell trap fires while ORCA is still running; without
# this the archive would read files being written and ORCA would recreate the
# temporary files deleted by clean_job. No-op if the process already exited.
# ----------------------------------------------------------------------------
function shutdown_orca() {
    [[ -n "$orca_pid" ]] || return
    kill -0 "$orca_pid" 2>/dev/null || return

    local i
    echo "LOG: Stopping ORCA process $orca_pid (signals were received)."
    kill -TERM "$orca_pid" 2>/dev/null

    # Give ORCA up to 30 s to write its own restart information and exit.
    for ((i = 0; i < 30; i++)); do
        kill -0 "$orca_pid" 2>/dev/null || break
        sleep 1
    done

    if kill -0 "$orca_pid" 2>/dev/null; then
        echo "LOG: ORCA still alive after 30s; sending KILL." >&2
        kill -KILL "$orca_pid" 2>/dev/null
        sleep 1
    else
        echo "LOG: ORCA process stopped."
    fi

    wait "$orca_pid" 2>/dev/null
    return 0
}

# ----------------------------------------------------------------------------
# clean_job
# Archive the job output (success or failure) and remove the per-job scratch.
# Called on normal exit and on termination signals; safe to call more than once.
# On failure the ORCA temporary files (*.tmp, *.tmp.*, *.PAUX.tmp, *.PINP0.tmp,
# *.bas*) are discarded before compressing.
# ----------------------------------------------------------------------------
function clean_job() {
    # Avoid running cleanup twice, e.g. when a signal is followed by EXIT.
    if [[ "$cleanup_done" -eq 1 ]]; then
        return
    fi
    cleanup_done=1

    echo "LOG: Cleanup started (job_success=$job_success, job_status=$job_status)."

    # Make sure ORCA is not writing anymore before touching the job directory.
    shutdown_orca

    # Nothing to archive if scratch was never created.
    if [[ ! -d "$exeDir" ]]; then
        echo "LOG: Scratch directory does not exist."
        echo "LOG: Cleanup finished."
        return
    fi

    # Archive only when a valid per-job output directory exists.
    # Guard against an empty or slash-containing basename expanding to "/".
    if [[ -n "$basename" && "$basename" != */* && "$jobDir" == "$exeDir/$basename" && -d "$jobDir" ]]; then
        local job_id="${SLURM_JOB_ID:-unknown}"
        local archive

        # Name the archive after the input and job ID for easy identification.
        if [[ "$job_success" -eq 1 ]]; then
            archive="$localDir/${basename}_${job_id}.tar.gz"
        else
            archive="$localDir/${basename}_${job_id}_failed.tar.gz"
        fi

        # A failed run leaves ORCA temporary files that are useless without a
        # complete run and can be tens of GB: the integral files (*.tmp in
        # ORCA 5, *.bas, *.bas0, *.bas1, ... in ORCA 6), PAUX/PINP0 workspaces,
        # their suffixed variants and the correlation densities. Drop them so
        # the _failed archive stays small.
        if [[ "$job_success" -ne 1 ]]; then
            local tmp_list tmp_size
            tmp_list=$(find "$jobDir" -type f \( \
                -name '*.tmp' -o \
                -name '*.tmp.*' -o \
                -name '*.PAUX.tmp' -o \
                -name '*.PINP0.tmp' -o \
                -name '*.bas' -o \
                -name '*.bas[0-9]*' -o \
                -name '*.densities' \))
            if [[ -n "$tmp_list" ]]; then
                tmp_size=$(echo "$tmp_list" | xargs -d '\n' du -ch 2>/dev/null | tail -1 | cut -f1)
                echo "LOG: Removing ORCA temporary files before archiving ($tmp_size):"
                echo "$tmp_list" | sed 's/^/LOG:   /'
                echo "$tmp_list" | xargs -d '\n' rm -f
            else
                echo "LOG: No ORCA temporary files to remove."
            fi
        fi

        echo "LOG: Archiving job directory: $jobDir"
        echo "LOG: Creating output archive: $archive"
        mkdir -p "$localDir"

        # Keep scratch if archiving fails, so results are not lost.
        # GNU tar exit codes: 0 = ok, 1 = "some files differ" (a file changed
        # or vanished while being read), 2 = fatal error. Only 0 and 1 are
        # acceptable here; --warning=no-file-changed just silences the
        # corresponding message, it does not change the exit status.
        tar cvzf "$archive" --warning=no-file-changed -C "$exeDir" "$basename"
        tar_status=$?
        if [[ "$tar_status" -le 1 ]]; then
            echo "LOG: Successfully archived outputs: $archive ($(du -h "$archive" | cut -f1))"
        else
            echo "LOG: ERROR: failed to create archive (tar status $tar_status); keeping scratch: $exeDir" >&2
            # Do not leave a truncated archive that looks like a valid result.
            rm -f "$archive"
            exit 1
        fi
    else
        echo "LOG: No job output directory found; nothing to archive."
    fi

    # Cleanup only reaches this point after a successful archive or if there
    # was no output directory to preserve.
    echo "LOG: Removing scratch directory: $exeDir"
    rm -vrf "$exeDir"
    echo "LOG: Scratch directory removed."
    echo "LOG: Cleanup finished."
}

# ----------------------------------------------------------------------------
# get_csv_element
# Return column $3 from a 1-based row of the job-list CSV.
# The CSV has no header: row 1 is the first job.
# ----------------------------------------------------------------------------
function get_csv_element() {
    local csv_file=$1
    local row=$2
    local column=$3

    sed "${row}q;d" $csv_file | awk -F ',' -v col="$column" '{print $col}'
}

# ============================================================================
# 3. RUNTIME STATE AND SIGNAL HANDLING
# ============================================================================
# job_success: 1 only after ORCA exits cleanly and reports normal termination.
# job_status: ORCA/singularity process exit status.
# cleanup_done: prevents duplicate cleanup.
# jobDir/basename: filled during execution and reused by clean_job.
# orca_pid: PID of the container process, stopped by clean_job if still alive.
# slurm_output: temporary Slurm output file, renamed after input selection.
job_success=0
job_status=1
cleanup_done=0
orca_pid=""
jobDir=""
basename=""
submit_dir="${SLURM_SUBMIT_DIR:-$PWD}"
slurm_output="$submit_dir/slurm-${SLURM_ARRAY_JOB_ID:-${SLURM_JOB_ID:-unknown}}_${SLURM_ARRAY_TASK_ID:-0}.stdout"

# Run cleanup on normal exit and on termination signals.
trap clean_job EXIT
trap 'job_success=0; job_status=1; clean_job; exit 1' HUP INT TERM

# ============================================================================
# 4. SLURM CONTEXT
# ============================================================================
# Log allocation details to simplify troubleshooting.
echo "LOG: ============================================================"
echo "LOG: Starting slurm-dlpno.sh"
echo "LOG: Start time: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "LOG: Host: $(hostname)"
echo "LOG: User: $USER"
echo "LOG: Job ID: ${SLURM_JOB_ID:-unset}"
echo "LOG: Array task ID: ${SLURM_ARRAY_TASK_ID:-unset}"
echo "LOG: Partition: ${SLURM_JOB_PARTITION:-unset}"
echo "LOG: Nodes: ${SLURM_JOB_NUM_NODES:-unset}"
echo "LOG: Tasks: ${SLURM_NTASKS:-unset}"
echo "LOG: CPUs per task: ${SLURM_CPUS_PER_TASK:-unset}"
echo "LOG: Memory per node: ${SLURM_MEM_PER_NODE:-unset} MB"
echo "LOG: ============================================================"

# ============================================================================
# 5. PATHS - USER-EDITABLE
# ============================================================================
# Change the container and scratch paths below if your environment differs.
# localDir: archive destination; replaced by prepare-job.sh with $PWD.
# exeDir: per-job scratch directory.
# ctPath: hardcoded ORCA container path.
localDir="__LOCAL_DIR__"

exeDir="/scratch/$USER/jobs/$SLURM_JOB_ID"
ctPath="/scratch/$USER/containers/orca-611_2025-12-16_19-01-10_orca611.sif"

# 5.1 Fail fast if prepare-job.sh was not run (or script was copied from another dir).
if [[ "$localDir" == "__LOCAL_DIR__" ]]; then
    echo "LOG: localDir placeholder was not replaced; run prepare-job.sh first." >&2
    exit 1
fi

if [[ ! -d "$localDir" || ! -f "$localDir/slurm-dlpno.csv" || ! -f "$localDir/slurm-dlpno.sh" ]]; then
    echo "LOG: Missing working directory or job files in localDir ($localDir); run ./prepare-job.sh first." >&2
    exit 1
fi

if [[ -n "${SLURM_SUBMIT_DIR:-}" && "$(realpath -m "$localDir")" != "$(realpath -m "$SLURM_SUBMIT_DIR")" ]]; then
    echo "LOG: localDir ($localDir) does not match submit directory ($SLURM_SUBMIT_DIR); run ./prepare-job.sh in the submit directory." >&2
    exit 1
fi

echo "LOG: localDir: $localDir"
echo "LOG: exeDir: $exeDir"
echo "LOG: ORCA container: $ctPath"
echo "LOG: Checking ORCA container."

# 5.2 Fail fast if the hardcoded SIF is unavailable.
if [[ ! -f "$ctPath" ]]; then
    echo "LOG: ORCA container not found: $ctPath" >&2
    exit 1
fi

echo "LOG: ORCA container found."

# ============================================================================
# 6. STAGE JOB FILES IN SCRATCH
# ============================================================================
# Copy the runner and CSV so execution does not depend on /home.
echo "LOG: Creating execution directory: $exeDir"
mkdir -p "$exeDir" || { echo "LOG: ERROR: failed to create $exeDir." >&2; exit 1; }

# Keep the runner and job list beside the input in scratch.
echo "LOG: Copying script and CSV to execution directory."
if ! cp "$localDir"/slurm-dlpno.sh "$localDir"/slurm-dlpno.csv "$exeDir"; then
    echo "LOG: ERROR: failed to copy script/CSV from $localDir to $exeDir." >&2
    exit 1
fi
echo "LOG: Script and CSV copied."

echo "LOG: Running job"
cd "$exeDir" || { echo "LOG: ERROR: failed to enter $exeDir." >&2; exit 1; }

# ============================================================================
# 7. SELECT INPUT AND CREATE JOB DIRECTORY
# ============================================================================
# The array task ID selects the CSV row; column 2 is the input filename.
echo "LOG: Reading job list for array task ID ${SLURM_ARRAY_TASK_ID:-unset}."
job=$(get_csv_element slurm-dlpno.csv "$SLURM_ARRAY_TASK_ID" 2)
echo "LOG: Selected input: $job"

# Strip the .inp extension to build the per-job directory and archive name.
basename="$(echo "$job" | rev | cut -f 2- -d '.' | rev)"
if [[ -z "$job" || -z "$basename" || "$basename" == */* || ! -f "$localDir/$job" ]]; then
    echo "LOG: ERROR: invalid or missing input '$job' in $localDir (array task ${SLURM_ARRAY_TASK_ID:-unset})." >&2
    exit 1
fi

jobDir="$exeDir"/"$basename"
echo "LOG: Creating job directory: $jobDir"
mkdir "$jobDir" || { echo "LOG: ERROR: failed to create $jobDir." >&2; exit 1; }

# Stage the selected input in the job directory.
echo "LOG: Copying input to job directory."
if ! cp "$localDir"/"$job" "$jobDir"; then
    echo "LOG: ERROR: failed to copy $job from $localDir to $jobDir." >&2
    exit 1
fi
echo "LOG: Input copied."

echo LOG: Current job: "$job"
echo LOG: Job basename: "$basename"
echo LOG: Running at: "$jobDir"
echo LOG: Hostname: $(hostname)
echo LOG: Singularity container path: "$ctPath"

# Slurm cannot use the input name in --output, so rename its temporary file.
job_id="${SLURM_JOB_ID:-unknown}"
slurm_output_final="$localDir/${basename}_${job_id}.stdout"
if [[ -f "$slurm_output" ]]; then
    if mv "$slurm_output" "$slurm_output_final"; then
        echo "LOG: Slurm output renamed: $slurm_output_final"
    else
        echo "LOG: WARNING: could not rename Slurm output: $slurm_output" >&2
    fi
else
    echo "LOG: WARNING: Slurm output not found: $slurm_output" >&2
fi

# ============================================================================
# 8. RUN ORCA IN THE CONTAINER
# ============================================================================
# Enter the job directory and set single-thread limits (ORCA uses MPI + SINGLE_THREADED OpenBLAS).
echo "LOG: Changing to job directory: $jobDir"
cd "$jobDir"
echo "LOG: Setting thread and stack limits."
export MKL_NUM_THREADS=1
export OMP_NUM_THREADS=1
ulimit -s unlimited
echo "LOG: MKL_NUM_THREADS=$MKL_NUM_THREADS OMP_NUM_THREADS=$OMP_NUM_THREADS"

# Run one ORCA job in the container; capture stdout and stderr separately.
# The process is backgrounded so its PID and exit status can be tracked.
echo "LOG: Launching ORCA container."
echo "LOG: ORCA stdout: $jobDir/$basename.out"
echo "LOG: ORCA stderr: $jobDir/stderr.log"
singularity run \
--bind="$PWD":"$PWD" \
"$ctPath" \
"$PWD" \
"$job" 1> "$basename".out 2> stderr.log &
orca_pid=$!
echo "LOG: ORCA process started with PID $orca_pid."

# Wait for completion and capture the ORCA/singularity exit status.
wait "$orca_pid"
job_status=$?
echo "LOG: ORCA process finished with status $job_status."

# ============================================================================
# 9. VALIDATE ORCA TERMINATION
# ============================================================================
# Require both a clean process exit and ORCA's normal termination marker.
echo "LOG: Checking ORCA normal termination marker."
if [[ "$job_status" -eq 0 ]] && grep -q 'ORCA TERMINATED NORMALLY' "$jobDir/$basename.out"; then
    job_success=1
    echo "LOG: ORCA terminated normally."
else
    job_success=0
    [[ "$job_status" -eq 0 ]] && job_status=1
    echo "LOG: ORCA did not terminate normally (status=$job_status)."
fi

echo "LOG: Job processed."
echo "LOG: End time: $(date '+%Y-%m-%d %H:%M:%S %Z')"

# ============================================================================
# 10. EXIT STATUS
# ============================================================================
# Propagate the job result to Slurm.
if [[ "$job_success" -eq 1 ]]; then
    echo "LOG: Job completed successfully."
    exit 0
fi

echo "LOG: Job did not complete normally."
exit 1
