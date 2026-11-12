# DLPNO-CCSD(T1) Slurm Diagnostics & Jobfile (CloudUFSCar)

This repository diagnoses failing **ORCA 6.1.1 `DLPNO-CCSD(T1)`** calculations on the **CloudUFSCar** HPC cluster, establishes proper memory/CPU sizing guidelines, and provides a production-ready **Slurm submission workflow** compliant with the cluster's local-scratch and archiving policies.

---

## Purpose

1. **Diagnose calculation failures:** Identify why large `DLPNO-CCSD(T1) TightPNO` jobs crash during the `MDCI` module (e.g., Slurm cgroup OOM kills vs. `/scratch` disk usage).
2. **Define proper resource sizing:** Align ORCA's `%pal nprocs` and `%maxcore` parameters with Slurm's `--ntasks` and `--mem` directives following the $\text{nprocs} \times \text{MaxCore} \le 0.75 \times \text{RAM}$ safety margin.
3. **Provide a reliable Slurm jobfile:** Deliver an automated, fault-tolerant submission script (`slurm-dlpno.sh`) that runs exclusively on node-local `/scratch`, verifies normal ORCA termination, strips multi-gigabyte temporary files on failure, packages outputs as `.tar.gz`, and cleans up `/scratch`.

---

## Key Diagnostic Findings

- **Root cause of `int-1-HH` failure (`Job 1152088`):** Setting `%pal nprocs 4` and `%maxcore 20000` inside a `#SBATCH --mem=80000` allocation left **0% memory headroom** ($4 \times 20\,000\text{ MB} = 80\,000\text{ MB}$). Because ORCA's `MDCI` module allocates 5–15% additional memory outside `%maxcore`, the job triggered the Slurm cgroup OOM killer (`SIGKILL` on MPI rank 3 during `Pair Pair Term precalculation`, `IBatch 8 of 15`).
- **Disk (`/scratch`) vs. RAM:** The `47.7 GB` (`VABPAO`) reported before the crash is **3-index integral data written to `/scratch` disk** (~75 GB total temporary files), not a minimum RAM floor.
- **Recommended CloudUFSCar profiles (`386,700 MB` RAM / 40 CPUs per node):**

| Profile | `--ntasks` / `%pal nprocs` | `#SBATCH --mem` (MB) | `%maxcore` (MB) | `nprocs × %maxcore` | Notes |
|---|---:|---:|---:|---:|---|
| **Balanced (Sweet Spot)** | `8` | `160000` | `15000` | `120000` (75.0%) | Fits 2 jobs/node; low `IBatch` count & strong MPI scaling |
| **Half-Node RAM (8 cores)** | `8` | `190000` | `17500` | `140000` (73.7%) | Fits 2 jobs/node; maximizes memory per rank |
| **Half-Node CPU (16 cores)** | `16` | `190000` | `8500` | `136000` (71.6%) | Fits 2 jobs/node; higher CPU count, more disk batches |
| **High Performance (1 job)** | `16` | `260000` | `12000` | `192000` (73.8%) | Fastest single-job turnaround |

---

## Quick Start (Submitting a Job)

1. Copy the contents of [`jobfile/slurm-dlpno/`](jobfile/slurm-dlpno/) (`slurm-dlpno.sh`, `slurm-dlpno.csv`, and `prepare-job.sh`) into your working directory on the cluster alongside your `.inp` files.
2. Run the preparation script from that directory to auto-detect all `*.inp` files (in natural sort order) and configure `slurm-dlpno.csv`, `localDir`, `--job-name`, and `--array`:
   ```bash
   ./prepare-job.sh <job-name>
   ```
3. Submit the job specifying the target Slurm partition:
   ```bash
   sbatch --partition=<partition> slurm-dlpno.sh
   ```

### Output Artifacts

- **Slurm log:** Renamed at runtime to `<inputname>_<JOBID>.stdout`.
- **Normal completion (`****ORCA TERMINATED NORMALLY****`):** Full calculation directory archived to `<inputname>_<JOBID>.tar.gz`.
- **Failed / OOM / interrupted run:** Temporary integral files (`*.tmp*`, `*.bas*`, `*.densities`) are purged first, and the remaining diagnostic files (`.out`, `stderr.log`, `.gbw`, `.loc`, `.inp`) are archived to `<inputname>_<JOBID>_failed.tar.gz`.

---

## Repository Structure

- [`jobfile/slurm-dlpno/`](jobfile/slurm-dlpno/) — Production Slurm script (`slurm-dlpno.sh`), helper script (`prepare-job.sh`), CSV manifest, and sample inputs (`water1.inp`, `water2.inp`).
- [`jobfile/`](jobfile/) — Legacy reference script (`cjobs_6631.sh`), target input (`int-1-HH.inp`), and detailed workflow documentation ([`jobfile/README.md`](jobfile/README.md)).
- [`tests/test0_rafa/`](tests/test0_rafa/) — Post-mortem analysis and resource sizing for the failed `int-1-HH` calculation ([`tests/test0_rafa/README.md`](tests/test0_rafa/README.md)).
- [`research/`](research/) — Technical notes on ORCA 6.1.1 DLPNO resource requirements, CloudUFSCar node specs, and benchmark analysis of reference outputs.
- [`sample-dlpno/`](sample-dlpno/) — Reference ORCA `DLPNO-CCSD(T1)` outputs that completed normally.
- [`oom-test/`](oom-test/) — Self-contained test harness using a mock Singularity binary to simulate Slurm OOM kills and verify cleanup/archiving behavior.
- [`docs/`](docs/) — Cluster storage guidelines (`andre-email.txt`), node snapshot (`cloudufscar-resources.txt`), and ORCA 6.1.1 manual.
- [`HISTORY.md`](HISTORY.md) — Chronological log of repository changes and design decisions.
