#!/bin/bash

#############  SCHEDULER  ##############

#SBATCH --job-name 6631
#SBATCH --output=log.stdout
#SBATCH --nodes=1
#SBATCH --ntasks=4
#SBATCH --mem=80000
#SBATCH --time=720:00:00
#SBATCH --array=1-1
#SBATCH --signal=B:TERM@60

#SBATCH --partition=slow

#############  FUNCTIONS  ##############

function clean_job() {
    if [[ "$cleanup_done" -eq 1 ]]; then
        return
    fi
    cleanup_done=1

    echo "LOG: Cleanup started (job_success=$job_success, job_status=$job_status)."

    if [[ ! -d "$exeDir" ]]; then
        echo "LOG: Scratch directory does not exist."
        echo "LOG: Cleanup finished."
        return
    fi

    if [[ -n "$jobDir" && -d "$jobDir" ]]; then
        local job_id="${SLURM_JOB_ID:-unknown}"
        local archive
        if [[ "$job_success" -eq 1 ]]; then
            archive="$localDir/job_${job_id}.tar.zst"
        else
            archive="$localDir/job_${job_id}_failed.tar.zst"
        fi

        echo "LOG: Archiving job directory: $jobDir"
        echo "LOG: Creating output archive: $archive"
        mkdir -p "$localDir"
        if tar -I "zstd -T${SLURM_CPUS_PER_TASK:-2} -1" \
            -cf "$archive" -C "$exeDir" "$basename/"; then
            echo "LOG: Successfully archived outputs: $archive ($(du -h "$archive" | cut -f1))"
        else
            echo "LOG: ERROR: failed to create archive; keeping scratch: $exeDir" >&2
            exit 1
        fi
    else
        echo "LOG: No job output directory found; nothing to archive."
    fi

    echo "LOG: Removing scratch directory: $exeDir"
    rm -vrf "$exeDir"
    echo "LOG: Scratch directory removed."
    echo "LOG: Cleanup finished."
}
function get_csv_element() {
    local csv_file=$1
    local row=$2
    local column=$3

    sed "${row}q;d" $csv_file | awk -F ',' -v col="$column" '{print $col}'
}

############  JOB RUNTIME  #############

# trap signals if the job is either done or interrupted
job_success=0
job_status=1
cleanup_done=0
jobDir=""
basename=""
trap clean_job EXIT
trap 'job_success=0; job_status=1; clean_job; exit 1' HUP INT TERM

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

# relevant directories
localDir="/home/$USER/run/slurm-dlpno"
exeDir="/scratch/"$USER"/jobs/$SLURM_JOB_ID"
ctPath="/scratch/$USER/containers/orca-611_2025-12-16_19-01-10_orca611.sif"

echo "LOG: localDir: $localDir"
echo "LOG: exeDir: $exeDir"
echo "LOG: ORCA container: $ctPath"
echo "LOG: Checking ORCA container."

if [[ ! -f "$ctPath" ]]; then
    echo "LOG: ORCA container not found: $ctPath" >&2
    exit 1
fi

echo "LOG: ORCA container found."

# job execution
echo "LOG: Creating execution directory: $exeDir"
mkdir -p "$exeDir"
echo "LOG: Copying script and CSV to execution directory."
cp "$localDir"/slurm-dlpno.sh "$localDir"/slurm-dlpno.csv "$exeDir"
echo "LOG: Script and CSV copied."

echo "LOG: Running jobs"
# NOTICE: This is not a massive job.
#         The for loop will run only once.
for _ in 0; do
    cd $exeDir
    echo "LOG: Reading job list for array task ID ${SLURM_ARRAY_TASK_ID:-unset}."
    job=$(get_csv_element slurm-dlpno.csv "$SLURM_ARRAY_TASK_ID" 2)
    echo "LOG: Selected input: $job"
    basename="$(echo $job | rev | cut -f 2- -d '.' | rev)"
    jobDir="$exeDir"/"$basename"
    echo "LOG: Creating job directory: $jobDir"
    mkdir "$jobDir"
    echo "LOG: Copying input to job directory."
    cp "$localDir"/"$job" "$jobDir"
    echo "LOG: Input copied."

    echo LOG: Current job: "$job"
    echo LOG: Job basename: "$basename"
    echo LOG: Running at: "$jobDir"
    echo LOG: Hostname: $(hostname)
    echo LOG: Singularity container path: "$ctPath"

    echo "LOG: Changing to job directory: $jobDir"
    cd "$jobDir"
    # <-- orca execution routine
    echo "LOG: Setting thread and stack limits."
    export MKL_NUM_THREADS=4
    export OMP_NUM_THREADS=4
    export OMP_STACKSIZE=4G
    ulimit -s unlimited
    echo "LOG: MKL_NUM_THREADS=$MKL_NUM_THREADS OMP_NUM_THREADS=$OMP_NUM_THREADS OMP_STACKSIZE=$OMP_STACKSIZE"

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
    wait "$orca_pid"
    job_status=$?
    echo "LOG: ORCA process finished with status $job_status."
    echo "LOG: Checking ORCA normal termination marker."
    if [[ "$job_status" -eq 0 ]] && grep -q 'ORCA TERMINATED NORMALLY' "$jobDir/$basename.out"; then
        job_success=1
        echo "LOG: ORCA terminated normally."
    else
        job_success=0
        [[ "$job_status" -eq 0 ]] && job_status=1
        echo "LOG: ORCA did not terminate normally (status=$job_status)."
    fi
    # end of orca execution routine -->
    echo "LOG: Returning to execution directory: $exeDir"
    cd "$exeDir"
done

echo "LOG: All jobs processed."
echo "LOG: End time: $(date '+%Y-%m-%d %H:%M:%S %Z')"

if [[ "$job_success" -eq 1 ]]; then
    echo "LOG: Job completed successfully."
    exit 0
fi

echo "LOG: Job did not complete normally."
exit 1