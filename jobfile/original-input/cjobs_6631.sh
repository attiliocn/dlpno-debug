#!/bin/bash

#############  SCHEDULER  ##############

#SBATCH --job-name 6631
#SBATCH --output=cjobs_log_%x_%J.stdout
#SBATCH --nodes=1
#SBATCH --ntasks=4
#SBATCH --mem=80000
#SBATCH --time=720:00:00
#SBATCH --array=1-1
#SBATCH --signal=B:TERM@60

#############  FUNCTIONS  ##############

function clean_job() {
    echo "LOG: Received signal. The trap has been activated."
    if [[ -d "$exeDir" ]]; then
        echo "LOG: Copying outputs to local directory."
        cp -r "$exeDir"/*/ "$localDir"
        echo "LOG: Successfully copied outputs."
        echo "LOG: Removing scratch directory."
        rm -vrf "$exeDir"
        echo "LOG: Scratch directory removed."
        echo "LOG: Job completed."
    else
        echo "LOG: Scratch directory does not exist."
    fi
    exit
}
function acquire_lock() {
    local lock_name=$1
    local lock_location=$2
    local lock_file="$lock_location/$lock_name"

    exec 3>"$lock_file"
    if flock -n -e 3; then
        echo "LOG: Successfully acquired lock for $lock_name at $lock_location."
        return 0
    else
        return 1
    fi
}
function release_lock() {
    local lock_name=$1
    local lock_location=$2
    local lock_file="$lock_location"/"$lock_name"
    
    exec 3>&-
    rm "$lock_file"
    echo "LOG: The lock for $lock_name at $lock_location has been released."
}
function attempt_acquire_lock() {
    local lock_name=$1
    local lock_location=$2
    local max_wait_time=$3
    local wait_time=0
    
    while ! acquire_lock "$lock_name" "$lock_location"; do
        echo "LOG: Waiting for the lock to be released..."
        sleep 5
        wait_time=$((wait_time + 5))
        if [ "$wait_time" -gt "$max_wait_time" ]; then
            echo "LOG: Maximum wait time exceeded. Exiting..."
            exit 1
        fi
    done
}
function create_directory_with_group_ownership() {
    directory=$1
    gid=$2
    parent_directory=$(dirname "$directory")

    # Check if the directory exists
    if [ ! -d "$directory" ]; then
        # Create the directory
        mkdir -p "$directory"

        # Change the group ownership by GID
        chown -R :"$gid" "$parent_directory"
        chmod -R 770 "$directory"

        echo "LOG: Directory created: $directory"
        echo "LOG: Group ownership set to GID: $gid"
        echo "LOG: Permissions set to rwx for owner and group, and none for others."
    else
        echo "LOG: Directory already exists: $directory"
        directory_owner=$(stat -c "%U" "$parent_directory")

        if [ "$USER" = "$directory_owner" ]; then
            echo "LOG: The user $USER is the owner of the directory $parent_directory. Applying standard permission settings"

            # Change the group ownership by GID
            chown -R :"$gid" "$parent_directory"
            chmod -R 770 "$directory"
        else
            echo "LOG: The user $USER is not the owner of the directory $parent_directory. There is nothing to do"
            return
        fi
    fi
}
function fetch_containers_from_drive() {
    container_cloud_dir="$1"
    container_local_dir="$2"
    container_local_dir_parent=$(dirname "$container_local_dir")

    synced_file="$container_local_dir_parent/last_sync.lock"

    # Check if the synced file exists and is older than 1 week
    if [ -e "$synced_file" ]; then
        file_age=$(($(date +%s) - $(stat -c %Y "$synced_file")))

        if [ "$file_age" -lt 604800 ]; then
            echo "LOG: The last sync was done $file_age seconds ago. Actions will not be performed."
            return
        fi
    fi

    if ! command -v rclone &>/dev/null; then
        echo "LOG: The rclone command is unavailable. No synchronization will be performed."
        return
    fi
    echo "LOG: Updating containers directory using rclone"
    rclone sync -v "$container_cloud_dir" "$container_local_dir"

    touch "$synced_file"
    echo "LOG: Updated last_sync.lock file"
}
function get_csv_element() {
    local csv_file=$1
    local row=$2
    local column=$3

    sed "${row}q;d" $csv_file | awk -F ',' -v col="$column" '{print $col}'
}

############  JOB RUNTIME  #############

# trap signals if the job is either done or interrupted
trap clean_job EXIT HUP INT TERM ERR

# allocation details
allocCPU=4
allocRAM=20000
g16GID=2111

# relevant directories
localDir="/home/u831869/run/slurm-dlpno"
scrDir="/scratch"
usrScrDir="/scratch/"$USER""
exeDir="/scratch/"$USER"/jobs/$SLURM_JOB_ID"
ctDirRemote="sintcatmol:containers"
ctDirLocal="/scratch/"$USER"/containers"
ct="orca-611_2025-12-16_19-01-10_orca611.sif"
ctPath="/scratch/"$USER"/containers"/orca-611_2025-12-16_19-01-10_orca611.sif

# update containers
echo "LOG: Requesting lock for synchronization using rclone."
attempt_acquire_lock "$USER"_sync.lock "$scrDir" 3600
create_directory_with_group_ownership "$ctDirLocal" "$g16GID"
fetch_containers_from_drive "$ctDirRemote" "$ctDirLocal"
release_lock "$USER"_sync.lock "$scrDir"

# job execution
echo "LOG: Creating execution directory"
mkdir -p "$exeDir"
cp "$localDir"/cjobs_*.sh "$localDir"/cjobs_joblist.csv "$exeDir"

numjobs=1
echo "LOG: Running jobs"
# NOTICE: This is not a massive job.
#         The for loop will run only once.
for job_number in 0; do
    cd $exeDir
    job=$(get_csv_element cjobs_joblist.csv "$SLURM_ARRAY_TASK_ID" 2)
    basename="$(echo $job | rev | cut -f 2- -d '.' | rev)"
    jobDir="$exeDir"/"$basename"
    mkdir "$jobDir"
    cp "$localDir"/"$job" "$jobDir"

    echo LOG: Current job: "$job"
    echo LOG: Job basename: "$basename"
    echo LOG: Running at: "$jobDir"
    echo LOG: Hostname: $(hostname)
    echo LOG: Singularity container path: "$ctPath"

    cd "$jobDir"
    # <-- orca execution routine
    export MKL_NUM_THREADS=4
    export OMP_NUM_THREADS=4
    export OMP_STACKSIZE=4G
    ulimit -s unlimited

    singularity run \
    --bind="$PWD":"$PWD" \
    "$ctPath" \
    "$PWD" \
    "$job" 1> "$basename".out 2> stderr.log &
    wait
    # end of orca execution routine -->
    cd "$exeDir"
done

exit