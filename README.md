# DLPNO-CCSD(T1) Slurm Diagnostics & Jobfile (CloudUFSCar)

This repository diagnoses failing **ORCA 6.1.1 `DLPNO-CCSD(T1)`** calculations on the **CloudUFSCar** HPC cluster, establishes proper memory/CPU sizing guidelines, and provides a production-ready **Slurm submission workflow** compliant with the cluster's local-scratch and archiving policies.

---

## Purpose

1. **Diagnose calculation failures:** Identify why large `DLPNO-CCSD(T1) TightPNO` jobs crash during the `MDCI` module (e.g., Slurm cgroup OOM kills vs. `/scratch` disk usage).
2. **Define proper resource sizing:** Align ORCA's `%pal nprocs` and `%maxcore` parameters with Slurm's `--ntasks` and `--mem` directives, accounting for both per-rank non-`%maxcore` overhead and `IBatch` scaling with `nprocs × %maxcore`.
3. **Provide a reliable Slurm jobfile:** Deliver an automated, fault-tolerant submission script (`slurm-dlpno.sh`) that runs exclusively on node-local `/scratch`, verifies normal ORCA termination, strips multi-gigabyte temporary files on failure, packages outputs as `.tar.gz`, and cleans up `/scratch`.

---

## Problem & Manual Baseline

The target job (`int-1-HH.inp`) is a 51-atom `DLPNO-CCSD(T1) TightPNO` calculation (292 total electrons, 214 correlated / 107 internal MOs, 1,377 `def2-TZVPP` basis functions, 3,324 `def2-TZVPP/C` auxiliary functions) running in ORCA 6.1.1 under CloudUFSCar's node-local `/scratch` workflow. During the `MDCI` `Pair Pair Term precalculation` stage, jobs were killed by the Slurm cgroup OOM killer even after adding standard memory headroom.

**ORCA 6.1.1 Manual Expectations (§1.7.5, §2.1.3, §2.5):**
- **`%maxcore` is per MPI process (MB):** It bounds only the dominant working arrays; actual `MDCI` memory can exceed `%maxcore`. The manual recommends **≥ 8,000 MB/core** for coupled cluster and $\text{nprocs} \times \text{\%maxcore} \le 0.75 \times \text{available RAM}$.
- **Parallelism & Scratch:** `%pal nprocs` must match Slurm `--ntasks` on a single node (`--nodes=1`), scaling well around 8 processes (up to 16) while sharing node-local `/scratch` for large 3-index integral files.
- **CloudUFSCar Regular Nodes (`c1`–`c18`):** **40 CPUs** and **386,700 MB RAM** (~9,667 MB/CPU).

As shown below, the manual's 25% headroom rule proved insufficient for `int-1-HH` at `nprocs=8` with `%maxcore 16000`.

---

## Key Diagnostic Findings

- **Why a `+30%` Slurm RAM surplus still failed (`test1_after-diagnose`, `Job 1152147`):**
  - In [`test0_rafa`](tests/test0_rafa/README.md) (`Job 1152088`: `nprocs=4`, `%maxcore 20000`, `--mem=80000` → `0%` surplus, `20,000 MB/rank`), ORCA split `Pair Pair Term precalculation` into **15 batches**, completed `IBatch 1..7`, and OOM'd in `IBatch 8`.
  - In [`test1_after-diagnose`](tests/test1_after-diagnose/README.md) (`Job 1152147`: `nprocs=8`, `%maxcore 16000`, `--mem=166000` → `+29.7%` surplus, `20,750 MB/rank`), doubling `nprocs` raised `nprocs × %maxcore` from `80,000` to `128,000 MB` (+60%), causing ORCA to group the same 107 internal orbitals into **10 larger batches** (~50% more orbitals per batch). With total RAM per rank barely changed (`20,750` vs. `20,000 MB/rank`), only `4,750 MB/rank` remained for non-`%maxcore` MDCI/SHARK/MPI overhead across 8 ranks, triggering 2 Slurm `oom_kill` events immediately in **`IBatch 1 (of 10)`**.
  - `slurm-dlpno.sh` also exported `MKL_NUM_THREADS=4`, `OMP_NUM_THREADS=4`, and `OMP_STACKSIZE=4G` (unnecessary for MPI ORCA with `SINGLE_THREADED` OpenBLAS; set to `1` / remove).
- **Disk (`/scratch`) vs. RAM:** The `47.7 GB` (`VABPAO`) reported before the crash is **3-index integral data written to `/scratch` disk** (~74–75 GB total temporary files), not a minimum RAM floor.
- **Recommended CloudUFSCar profiles (`386,700 MB` RAM / 40 CPUs per node):**

| Profile | `--ntasks` / `%pal nprocs` | `#SBATCH --mem` (MB) | `%maxcore` (MB) | `nprocs × %maxcore` | Surplus | Notes |
|---|---:|---:|---:|---:|---:|---|
| **Multi-User Throughput (Recommended)** | `4` | `128000` | `16000` | `64000` | `+100%` | `16,000 MB/rank` headroom; ~33% of node RAM, best queue & array throughput |
| **Half-Node (8 cores, low `MaxCore`)** | `8` | `160000`–`190000` | `10000`–`12000` | `80000`–`96000` | `+98–100%` | Smaller `IBatch`es + 8-core speed; fits 2 jobs/node |
| **Single-Job Priority (8 cores, `16 GB/core`)** | `8` | `192000`–`224000` | `16000` | `128000` | `+50–75%` | Uses 50–58% of node RAM; less multi-user friendly |

---

## Quick Start (Submitting a Job)

> **Important:** **ALWAYS copy from the updated template in [`jobfile/slurm-dlpno/`](jobfile/slurm-dlpno/)** for every new calculation directory. **Never** reuse an already-prepared `slurm-dlpno.sh` from a previous run folder (its hardcoded `localDir` will point to the old folder; see [`tests/test2_chaos-error/README.md`](tests/test2_chaos-error/README.md)).

1. Copy the fresh template files from [`jobfile/slurm-dlpno/`](jobfile/slurm-dlpno/) (`slurm-dlpno.sh`, `slurm-dlpno.csv`, and `prepare-job.sh`) into your new working directory on the cluster alongside your `.inp` files.
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
- [`tests/test0_rafa/`](tests/test0_rafa/) — Post-mortem analysis of the initial OOM failure (`Job 1152088`, [`tests/test0_rafa/README.md`](tests/test0_rafa/README.md)).
- [`tests/test1_after-diagnose/`](tests/test1_after-diagnose/) — Diagnosis of the `+30%` surplus OOM failure (`Job 1152147`, `dlpno-test2`) and 4-core multi-user sizing ([`tests/test1_after-diagnose/README.md`](tests/test1_after-diagnose/README.md)).
- [`tests/test2_chaos-error/`](tests/test2_chaos-error/) — Post-mortem of the catastrophic `Job 1152215` failure where an invalid `localDir` left `basename` empty and caused `clean_job` to `tar` `/` ([`tests/test2_chaos-error/README.md`](tests/test2_chaos-error/README.md)).
- [`research/`](research/) — Technical notes on ORCA 6.1.1 DLPNO resource requirements, CloudUFSCar node specs, and benchmark analysis of reference outputs.
- [`sample-dlpno/`](sample-dlpno/) — Reference ORCA `DLPNO-CCSD(T1)` outputs that completed normally.
- [`docs/`](docs/) — Cluster storage guidelines (`andre-email.txt`), node snapshot (`cloudufscar-resources.txt`), and ORCA 6.1.1 manual.
- [`HISTORY.md`](HISTORY.md) — Chronological log of repository changes and design decisions.
