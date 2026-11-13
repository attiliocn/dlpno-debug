# Diagnóstico do Teste `test1_after-diagnose` (`dlpno-test2`, Job `1152147`)

Este documento registra a análise da falha do job `1152147` (`dlpno-test2` em `int-1-HH.inp`), executado após o diagnóstico inicial do [`test0_rafa`](../test0_rafa/README.md), e a decisão de dimensionamento para o próximo teste em ambiente multiusuário.

---

## 1. Arquivos do Teste

- [`int-1-HH_1152147.stdout`](int-1-HH_1152147.stdout) — log do Slurm e do `slurm-dlpno.sh`.
- [`int-1-HH.inp`](int-1-HH.inp) — entrada ORCA (`%maxcore 16000`, `%pal nprocs 8`).
- [`slurm-dlpno.sh`](slurm-dlpno.sh) — script Slurm submetido (`#SBATCH --job-name dlpno-test2`, `--ntasks=8`, `--mem=166000`).
- [`int-1-HH/int-1-HH.out`](int-1-HH/int-1-HH.out) — saída do ORCA 6.1.1 interrompida no módulo MDCI.
- [`int-1-HH/stderr.log`](int-1-HH/stderr.log) — saída de erro do `mpirun`/`orca_mdci_mpi`.

---

## 2. O que aconteceu no Job `1152147`

O cálculo rodou no nó `c23` (partição `normal`) de `11:58:45` até `13:39:25` de `2026-11-12` (~1h 40min) e foi encerrado por **Out of Memory (OOM)** no cgroup do Slurm (`166000 MB`):

1. **Evidência nos logs:**
   - [`int-1-HH_1152147.stdout`](int-1-HH_1152147.stdout#L166):
     ```text
     [2026-11-12T13:39:35.621] error: Detected 2 oom_kill events in StepId=1152147.batch. Some of the step tasks have been OOM Killed.
     ```
   - [`int-1-HH/stderr.log`](int-1-HH/stderr.log#L6-L9):
     ```text
     mpirun noticed that process rank 3 with PID 386690 on node c23 exited on signal 9 (Killed).
     ```
2. **Ponto exato da parada ([`int-1-HH/int-1-HH.out`](int-1-HH/int-1-HH.out#L3780-L3823)):**
   - `LeanSCF` (`858.5 s`), localização, `LMP2` iterativo (`3503.6 s`), `IJV` (`54.7 s`) e `VABPAO` (`332.9 s`, `47699.659 MB` em disco) concluíram normalmente.
   - O job foi morto imediatamente ao entrar no **`IBatch 1 (of 10)`** da etapa `Pair Pair Term precalculation with RI-(ij|mn) and (im|jn) transformation ON THE FLY`.
3. **Limpeza do `slurm-dlpno.sh`:**
   - O script detectou a ausência de `ORCA TERMINATED NORMALLY`, removeu `74G` de temporários em `/scratch`, gerou `int-1-HH_1152147_failed.tar.gz` (`28M`) e apagou `/scratch/u831869/jobs/1152147`.

---

## 3. Por que `+30%` de surplus (`166000 MB`) ainda deu OOM

| Parâmetro / Métrica | `test0_rafa` (`1152088`) | `test1_after-diagnose` (`1152147`) |
|---|---:|---:|
| Processos MPI (`nprocs` / `--ntasks`) | `4` | `8` |
| `%maxcore` | `20.000 MB` | `16.000 MB` |
| Base `nprocs × %maxcore` | `80.000 MB` | `128.000 MB` (**+60%**) |
| Slurm `--mem` | `80.000 MB` (`0%` surplus) | `166.000 MB` (`+29,7%` surplus) |
| **RAM total por rank (`--mem / nprocs`)** | **`20.000 MB/rank`** | **`20.750 MB/rank`** |
| **Lotes no `Pair Pair Term`** | **`15` lotes** (~7,1 MOs/lote) | **`10` lotes** (~10,7 MOs/lote) |
| **Onde falhou** | Sobreviveu `IBatch 1..7`, OOM no `IBatch 8` | OOM imediato no **`IBatch 1`** |

Em resumo:

1. **Dobrar `nprocs` aumentou o tamanho dos lotes (`IBatch`):**
   Mesmo baixando `%maxcore` de `20000` para `16000`, o produto `nprocs × %maxcore` subiu de `80.000 MB` para `128.000 MB`. Com isso, o ORCA reduziu de **15** para **10 lotes** na etapa `Pair Pair Term` — colocando **~50% mais orbitais internos por lote**.
2. **A RAM total por processo praticamente não mudou (`20.000` → `20.750 MB/rank`):**
   Sobraram apenas **`4.750 MB/rank`** de folga acima do `%maxcore` (`38.000 MB / 8`). Como o `%maxcore` regula apenas as áreas de trabalho principais do MDCI, os gastos extras por rank (mapas replicados, buffers de `VABPAO`/`PNOJK`/SHARK, intermediários de transformação do lote e buffers MPI entre 8 ranks) somados aos lotes 50% maiores ultrapassaram os `20.750 MB/rank` logo no `IBatch 1`.
   - Além disso, `slurm-dlpno.sh` ainda exportava `MKL_NUM_THREADS=4`, `OMP_NUM_THREADS=4` e `OMP_STACKSIZE=4G` para 8 ranks MPI (embora o OpenBLAS do ORCA seja `SINGLE_THREADED`).

---

## 4. Decisão para o próximo teste (ambiente multiusuário)

Nos nós regulares do CloudUFSCar (`386.700 MB` de RAM e 40 CPUs), alocar `>= 192–224 GB` (50%–58% da RAM do nó) ou toda a memória do nó para rodar com 8 cores e `%maxcore 16000` reduz o espaço para outros usuários e prejudica a fila.

Para priorizar **melhor throughput na fila** e **estabilidade contra OOM**, a configuração escolhida é **voltar para 4 cores mantendo `%maxcore 16000` e aplicando 100% de surplus (o dobro da base)**:

- **Input (`int-1-HH.inp`):**
  - `%pal nprocs 4`
  - `%maxcore 16000` (base `4 × 16.000 = 64.000 MB`)
- **Slurm (`slurm-dlpno.sh`):**
  - `#SBATCH --ntasks=4`
  - `#SBATCH --mem=128000` (**+100% de surplus**: `64.000 MB` de folga total = `16.000 MB/rank` livres fora do `%maxcore`; ~33% da RAM de um nó regular)
  - Remover `OMP_STACKSIZE=4G` e definir `MKL_NUM_THREADS=1` e `OMP_NUM_THREADS=1` (ou remover os exports).

### Referência: alternativas com 8 cores (caso seja necessário acelerar um job específico)

- **8 cores em meio nó (~100% surplus):** `nprocs 8` + `%maxcore 10000` + `--mem=160000` (ou `%maxcore 12000` + `--mem=190000`).
- **8 cores mantendo `%maxcore 16000`:** exigiria `--mem=192000` (`+50%`, `8.000 MB/rank` de folga) a `--mem=224000` (`+75%`, `12.000 MB/rank` de folga).
