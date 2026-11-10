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
# ============================================================================

# ============================================================================
# 1. SLURM DIRECTIVES
# ============================================================================
# dlpno is the template default; prepare-job.sh sets the job name.
# Slurm output starts as slurm-%A_%a.stdout; after the input is selected it is
# renamed to <input>_<jobid>.stdout. Partition is chosen at submission time.
# ARRAY is a placeholder replaced by prepare-job.sh.
#SBATCH --job-name dlpno
#SBATCH --output=slurm-%A_%a.stdout

# Resource request: one node, four MPI ranks, 80 GB, up to 720 hours.
#SBATCH --nodes=1
#SBATCH --ntasks=4
#SBATCH --mem=80000
#SBATCH --time=720:00:00

# Slurm array and early cleanup signal.
#SBATCH --array=ARRAY
#SBATCH --signal=B:TERM@60

# ============================================================================
# 2. FUNCTIONS
# ============================================================================

# ----------------------------------------------------------------------------
# clean_job
# Archive the job output (success or failure) and remove the per-job scratch.
# Called on normal exit and on termination signals; safe to call more than once.
# On failure the ORCA temporary files (*.tmp) are discarded before compressing.
# ----------------------------------------------------------------------------
function clean_job() {
    # Avoid running cleanup twice, e.g. when a signal is followed by EXIT.
    if [[ "$cleanup_done" -eq 1 ]]; then
        return
    fi
    cleanup_done=1

    echo "LOG: Cleanup started (job_success=$job_success, job_status=$job_status)."

    # Nothing to archive if scratch was never created.
    if [[ ! -d "$exeDir" ]]; then
        echo "LOG: Scratch directory does not exist."
        echo "LOG: Cleanup finished."
        return
    fi

    # Archive only when a job output directory exists.
    if [[ -n "$jobDir" && -d "$jobDir" ]]; then
        local job_id="${SLURM_JOB_ID:-unknown}"
        local archive

        # Name the archive after the input and job ID for easy identification.
        if [[ "$job_success" -eq 1 ]]; then
            archive="$localDir/${basename}_${job_id}.tar.gz"
        else
            archive="$localDir/${basename}_${job_id}_failed.tar.gz"
        fi

        # A failed run leaves ORCA temporary files (*.tmp, integral and
        # PNO/OI-processing scratch) that are useless without a complete run
        # and can be tens of GB. Drop them so the _failed archive stays small.
        if [[ "$job_success" -ne 1 ]]; then
            local tmp_list tmp_size
            tmp_list=$(find "$jobDir" -type f -name '*.tmp')
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
        if tar cvzf "$archive" -C "$exeDir" "$basename/"; then
            echo "LOG: Successfully archived outputs: $archive ($(du -h "$archive" | cut -f1))"
        else
            echo "LOG: ERROR: failed to create archive; keeping scratch: $exeDir" >&2
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
# slurm_output: temporary Slurm output file, renamed after input selection.
job_success=0
job_status=1
cleanup_done=0
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

# 5.1 Fail fast if prepare-job.sh was not run.
if [[ "$localDir" == "__LOCAL_DIR__" ]]; then
    echo "LOG: localDir placeholder was not replaced; run prepare-job.sh first." >&2
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
mkdir -p "$exeDir"

# Keep the runner and job list beside the input in scratch.
echo "LOG: Copying script and CSV to execution directory."
cp "$localDir"/slurm-dlpno.sh "$localDir"/slurm-dlpno.csv "$exeDir"
echo "LOG: Script and CSV copied."

echo "LOG: Running job"
cd "$exeDir"

# ============================================================================
# 7. SELECT INPUT AND CREATE JOB DIRECTORY
# ============================================================================
# The array task ID selects the CSV row; column 2 is the input filename.
echo "LOG: Reading job list for array task ID ${SLURM_ARRAY_TASK_ID:-unset}."
job=$(get_csv_element slurm-dlpno.csv "$SLURM_ARRAY_TASK_ID" 2)
echo "LOG: Selected input: $job"

# Strip the .inp extension to build the per-job directory and archive name.
basename="$(echo $job | rev | cut -f 2- -d '.' | rev)"
jobDir="$exeDir"/"$basename"
echo "LOG: Creating job directory: $jobDir"
mkdir "$jobDir"

# Stage the selected input in the job directory.
echo "LOG: Copying input to job directory."
cp "$localDir"/"$job" "$jobDir"
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
# Enter the job directory and set thread/stack limits.
echo "LOG: Changing to job directory: $jobDir"
cd "$jobDir"
echo "LOG: Setting thread and stack limits."
export MKL_NUM_THREADS=4
export OMP_NUM_THREADS=4
export OMP_STACKSIZE=4G
ulimit -s unlimited
echo "LOG: MKL_NUM_THREADS=$MKL_NUM_THREADS OMP_NUM_THREADS=$OMP_NUM_THREADS OMP_STACKSIZE=$OMP_STACKSIZE"

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
