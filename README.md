# DLPNO-CCSD(T1) Slurm Diagnostics & Jobfile

This repository diagnoses failing **ORCA 6.1.1 `DLPNO-CCSD(T1)`** calculations on Slurm HPC clusters, establishes proper memory/CPU sizing guidelines, and provides a production-ready **Slurm submission workflow** compliant with node-local `/scratch` and archiving policies.

---

## Purpose

1. **Diagnose calculation failures:** Identify why large `DLPNO-CCSD(T1) TightPNO` jobs crash during the `MDCI` module (e.g., Slurm cgroup OOM kills vs. `/scratch` disk usage).
2. **Define proper resource sizing:** Align ORCA's `%pal nprocs` and `%maxcore` parameters with Slurm's `--ntasks` and `--mem` directives, accounting for both per-rank non-`%maxcore` overhead and `IBatch` scaling with `nprocs × %maxcore`.
3. **Provide a reliable Slurm jobfile:** Deliver an automated, fault-tolerant submission script (`slurm-dlpno.sh`) that runs exclusively on node-local `/scratch`, verifies normal ORCA termination, strips multi-gigabyte temporary files on failure, packages outputs as `.tar.gz`, and cleans up `/scratch`.

---

## Problem & Manual Baseline

The target job (`int-1-HH.inp`) is a 51-atom `DLPNO-CCSD(T1) TightPNO` calculation (292 total electrons, 214 correlated / 107 internal MOs, 1,377 `def2-TZVPP` basis functions, 3,324 `def2-TZVPP/C` auxiliary functions) running in ORCA 6.1.1 under a node-local `/scratch` Slurm workflow. During the `MDCI` `Pair Pair Term precalculation` stage, jobs were killed by the Slurm cgroup OOM killer even after adding standard memory headroom.

**ORCA 6.1.1 Manual Expectations (§1.7.5, §2.1.3, §2.5):**
- **`%maxcore` is per MPI process (MB):** It bounds only the dominant working arrays; actual `MDCI` memory can exceed `%maxcore`. The manual recommends **≥ 8,000 MB/core** for coupled cluster and $\text{nprocs} \times \text{\%maxcore} \le 0.75 \times \text{available RAM}$.
- **Parallelism & Scratch:** `%pal nprocs` must match Slurm `--ntasks` on a single node (`--nodes=1`), scaling well around 8 processes (up to 16) while sharing node-local `/scratch` for large 3-index integral files.

As shown below, the manual's 25% headroom rule proved insufficient for `int-1-HH` at `nprocs=8` with `%maxcore 16000`.

---

## Problems Found & Solutions (From Tests)

- **OOM with `0%` surplus ([`test0_rafa`](tests/test0_rafa/README.md), `Job 1152088`):** `4` ranks × `%maxcore 20000` under `--mem=80000` (`TightPNO`) crashed in `IBatch 8 (of 15)` of `Pair Pair Term precalculation`. Note that the `47.7 GB` (`VABPAO`) printed beforehand is **disk I/O to `/scratch`**, not RAM. → **Solution:** always budget Slurm `--mem` well above `nprocs × %maxcore`.
- **OOM with `+29.7%` surplus at 8 ranks ([`test1_after-diagnose`](tests/test1_after-diagnose/README.md), `Job 1152147`):** `8` ranks × `%maxcore 16000` under `--mem=166000` (`TightPNO`) reduced `Pair Pair Term` from `15` to `10` batches (~50% more orbitals/batch) while leaving only `4,750 MB/rank` above `%maxcore`, causing immediate OOM in `IBatch 1`; the script also exported `MKL_NUM_THREADS=4`, `OMP_NUM_THREADS=4`, and `OMP_STACKSIZE=4G`. → **Solution:** pin `MKL_NUM_THREADS=1` and `OMP_NUM_THREADS=1`, drop `OMP_STACKSIZE=4G`, and increase RAM surplus.
- **Catastrophic `tar /` on invalid `localDir` ([`test2_chaos-error`](tests/test2_chaos-error/README.md), `Job 1152215`):** reusing a script with a stale/nonexistent `localDir` left `basename` empty, causing `clean_job` to archive `/`. → **Solution:** added fail-fast checks on `localDir`, `$SLURM_SUBMIT_DIR`, `job`/`basename`, and `jobDir` in `slurm-dlpno.sh`; always copy fresh from [`jobfile/slurm-dlpno/`](jobfile/slurm-dlpno/).
- **Validated run with `+100%` surplus ([`testA1`](tests/testA1/README.md), `Job 90036`):** `4` ranks × `%maxcore 16000` under `--mem=128000` (`NormalPNO`, `def2-TZVPP`) completed normally in `4h 39m 32s` (`ORCA MDCI` peak `16,602 MB/rank`, Slurm `MaxRSS` `65.60 GiB` / `52.5%` of `125 GiB`).
- **OOM with `+50%` surplus in `TightPNO` + `def2-QZVPP` ([`testA2`](tests/testA2/README.md), `Job 91772`):** `8` ranks × `%maxcore 16000` under `--mem=192000` (`187.50 GiB`) completed SCF, LMP2, `VABPAO` (`312.2 GB` on disk), `Pair Pair Term` (`26` batches), `RI-PNO`, and CCSD, but was OOM-killed after `25h 42m 37s` inside `(T)` (`49,811` triples) at `MaxRSS = 191.96 GiB` (`+53.57%` over the `125 GiB` base). → **Solution:** use **`+100%` surplus** (`--mem=256G` for `8 × 16000`, or reduce `%maxcore` to `12000` under `--mem=192G`); `+60%` is too close to the kill point (`T0` had not finished).

---

## Cost Comparison: `NormalPNO`/`def2-TZVPP` vs. `TightPNO`/`def2-QZVPP` (4-Core Normalized)

Comparing [`testA1`](tests/testA1/README.md) (`4` cores, completed) and [`testA2`](tests/testA2/README.md) (`8` cores normalized to `4` cores via `×2` assuming ideal linear scaling, killed in `(T)`):

| Stage / Metric | `testA1` (`NormalPNO`, TZ, 4c) | `testA2` (norm. 4c, `TightPNO`, QZ) | Ratio (`A2 / A1`) |
|---|---:|---:|---:|
| **AOs / Aux (`/C`) / Triples** | `1,377` / `3,324` / `13,351` | `2,583` / `6,171` / `49,811` | **1.88×** / **1.86×** / **3.73×** |
| **`LeanSCF`** | `0.13 h` (`481.9 s`) | `0.49 h` (`1,772.0 s`) | **3.7×** |
| **`Initial Guess` (`MP2` vs `LMP2`)** | `0.06 h` (`198.6 s`) | `4.11 h` (`14,800.2 s`) | **74.5×** |
| **`VABPAO`** | `0.05 h` (`194.2 s`) | `0.68 h` (`2,441.2 s`) | **12.6×** |
| **`Pair Pair Term`** | `0.26 h` (`5` batches) | `14.59 h` (`26` batches) | **56.3×** |
| **`RI-PNO` transformation** | `0.13 h` (`1` batch) | `7.62 h` (`4` batches) | **56.9×** |
| **CCSD iterations (`11` iters)** | `0.68 h` (`~2,450 s`) | `8.09 h` (`29,135.6 s`) | **11.9×** |
| **Triples `(T)`** | `3.11 h` (complete) | `> 6.95 h` (killed in `T0`) | *(incomplete)* |
| **Total (end vs. OOM)** | **`4.66 h`** (`18.6 core-h`) | **`> 51.42 h`** (`> 205.7 core-h`) | **> 11.0×** |
| **`MaxRSS` (`sacct`) / `VABPAO` disk** | `65.60 GiB` / `41.9 GB` | `191.96 GiB` (OOM) / `312.2 GB` | **>= 2.93×** / **7.46×** |

---

## Final Recommendations

- **`%maxcore`:** minimum **8 GB (`8000 MB`)** per core (ORCA manual baseline); **16 GB (`16000 MB`)** per core recommended.
- **Slurm `--mem` surplus:** **minimum +75%** above `nprocs × %maxcore`; **+100% strongly recommended** (e.g., `4 × 16000` → `--mem=128G`; `8 × 16000` → `--mem=256G`).
- **Slurm memory units (`--mem`):** without a suffix, Slurm treats `--mem` as **MiB** ($1024^2$ bytes), so `--mem=128000` allocates $128{,}000 \div 1024 = \mathbf{125\text{ GiB}}$ (`ReqMem=125G` in `sacct`). Use the `G` suffix (e.g., `--mem=128G`) to request exact GiB.
- **Cores (`%pal nprocs` / `--ntasks`, `--nodes=1`):** **4 cores** for `NormalPNO`; **8 to 16 cores** for `TightPNO`.
- **Simultaneous jobs per node (`/scratch` `1.1–5.5 TB`):** `NormalPNO` (`~75–90 GB` disk/job) is **RAM-limited** (e.g., 2–3 concurrent jobs on a regular node); `TightPNO` + `def2-QZVPP` (`~550–600 GB` disk/job, `224G–256G` RAM) should run **at most 1 job at a time per node** to avoid `/scratch` exhaustion and I/O contention.

| `n_cores` | `%maxcore` | Base (`n_cores × %maxcore`) | Slurm `--mem` (+75% min.) | Slurm `--mem` (+100% rec.) | Typical use |
|---:|---:|---:|---:|---:|---|
| `4` | `8000` (8 GB) | `32 GB` | `56G` | `64G` | `NormalPNO` (min. `%maxcore`) |
| `4` | `16000` (16 GB) | `64 GB` | `112G` | `128G` | `NormalPNO` (recommended) |
| `8` | `8000` (8 GB) | `64 GB` | `112G` | `128G` | `TightPNO` (min. `%maxcore`) |
| `8` | `16000` (16 GB) | `128 GB` | `224G` | `256G` | `TightPNO` (recommended) |
| `16` | `8000` (8 GB) | `128 GB` | `224G` | `256G` | `TightPNO` (16c, min. `%maxcore`) |
| `16` | `16000` (16 GB) | `256 GB` | `448G`\* | `512G`\* | `TightPNO` (high-mem node only) |

\*Exceeds CloudUFSCar regular node RAM (`~377.6 GiB`).

---

## HPC

- **CloudUFSCar:** regular compute nodes (`c1`–`c9`, `c12`–`c18`) with **40 CPUs** and **386,700 MB RAM** (~377.6 GiB; ~9,667 MB/CPU) per node, node-local `/scratch` shared across all MPI ranks (`--nodes=1`), and `.tar.gz` / `rclone` archiving policy (see [`docs/cloudufscar-resources.txt`](docs/cloudufscar-resources.txt) and [`research/cloudufscar-resources.md`](research/cloudufscar-resources.md)).

---

## Quick Start (Submitting a Job)

> **Important:** **ALWAYS copy from the updated template in [`jobfile/slurm-dlpno/`](jobfile/slurm-dlpno/)** for every new calculation directory. **Never** reuse an already-prepared `slurm-dlpno.sh` from a previous run folder (its hardcoded `localDir` will point to the old folder; see [`tests/test2_chaos-error/README.md`](tests/test2_chaos-error/README.md)).

1. **Create and enter a dedicated working directory on the HPC** and place your `*.inp` files there (all inputs in the same folder must use the same core count):
   ```bash
   mkdir -p ~/run/<my-job-dir> && cd ~/run/<my-job-dir>
   ```
2. **Download or copy the fresh template files** (`slurm-dlpno.sh`, `slurm-dlpno.csv`, and `prepare-job.sh`) into this working directory. Either copy them from [`jobfile/slurm-dlpno/`](jobfile/slurm-dlpno/) or **choose one of the two options below**:

   **Option A — Using `curl`:**
   ```bash
   BASE="https://raw.githubusercontent.com/attiliocn/dlpno-debug/main/jobfile/slurm-dlpno"
   curl -fsSLO "$BASE/slurm-dlpno.sh" -fsSLO "$BASE/slurm-dlpno.csv" -fsSLO "$BASE/prepare-job.sh" && chmod +x prepare-job.sh
   ```

   **Option B — Using `wget`:**
   ```bash
   BASE="https://raw.githubusercontent.com/attiliocn/dlpno-debug/main/jobfile/slurm-dlpno"
   wget -q "$BASE/slurm-dlpno.sh" "$BASE/slurm-dlpno.csv" "$BASE/prepare-job.sh" && chmod +x prepare-job.sh
   ```
3. **Prepare the job** from inside the working directory (replace `<job-name>` with a short identifier, e.g., `dlpno_run1`). This scans all `*.inp` files in natural sort order and populates `slurm-dlpno.csv`, `localDir`, `--job-name`, `--output`, `--ntasks`, `--mem` (100% surplus), `--time=168:00:00` (7 days), and `--array`:
   ```bash
   ./prepare-job.sh <job-name>
   ```
4. **Submit the job** from the same directory, replacing `<partition>` with your cluster's Slurm partition (e.g., `normal`, `slow`, or `cpu`):
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
- [`tests/testA1/`](tests/testA1/) — Successful validation run (`Job 90036`, `NormalPNO`, `def2-TZVPP`, `4` ranks, `+100%` surplus) with ORCA memory and `sacct MaxRSS` analysis ([`tests/testA1/README.md`](tests/testA1/README.md)).
- [`tests/testA2/`](tests/testA2/) — Post-mortem of the `+50%` surplus OOM failure (`Job 91772`, `TightPNO`, `def2-QZVPP`, `8` ranks) during `(T)` ([`tests/testA2/README.md`](tests/testA2/README.md)).
- [`research/`](research/) — Technical notes on ORCA 6.1.1 DLPNO resource requirements, HPC node specs, and benchmark analysis of reference outputs.
- [`sample-dlpno/`](sample-dlpno/) — Reference ORCA `DLPNO-CCSD(T1)` outputs that completed normally.
- [`docs/`](docs/) — Cluster storage guidelines (`andre-email.txt`) and node snapshot (`cloudufscar-resources.txt`).
- [`HISTORY.md`](HISTORY.md) — Chronological log of repository changes and design decisions.
