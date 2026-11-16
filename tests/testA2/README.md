# Diagnóstico do Teste `testA2` (Job `91772`)

Este documento registra a configuração, as decisões de base auxiliar e o diagnóstico da falha por **Out of Memory (OOM)** do job `91772` (`int-1-HH.inp`, `TightPNO`, `def2-qzvpp`, `nprocs 8`, `+50%` de surplus).

---

## 1. Arquivos do Teste

- [`inputs/`](inputs/) — arquivos preparados para submissão (`int-1-HH.inp`, `slurm-dlpno.sh`, `slurm-dlpno.csv`, `prepare-job.sh`).
- [`outputs/sacct.txt`](outputs/sacct.txt) — saída do `sacct -j 91772` com `MaxRSS` real e estado `FAILED`.
- [`outputs/int-1-HH_91772.stdout`](outputs/int-1-HH_91772.stdout) — log do Slurm e do `slurm-dlpno.sh`.
- [`outputs/slurm-dlpno.sh`](outputs/slurm-dlpno.sh) — script Slurm efetivamente submetido (`#SBATCH --job-name testA2`, `--ntasks=8`, `--mem=192000`, `--time=48:00:00`).
- [`outputs/int-1-HH/int-1-HH.inp`](outputs/int-1-HH/int-1-HH.inp) — entrada ORCA (`TightPNO`, `def2-qzvpp`, `def2-qzvpp/C`, `def2/J`, `%maxcore 16000`, `%pal nprocs 8`).
- [`outputs/int-1-HH/int-1-HH.out`](outputs/int-1-HH/int-1-HH.out) — saída do ORCA 6.1.1 interrompida na etapa `(T)` do módulo `MDCI`.
- [`outputs/int-1-HH/stderr.log`](outputs/int-1-HH/stderr.log) — saída de erro do `mpirun`/`orca_mdci_mpi`.

---

## 2. O que aconteceu no Job `91772`

- **Job / Nó:** `91772` (array task `1`), nó `mcurie01`, partição `cpu` ([`int-1-HH_91772.stdout`](outputs/int-1-HH_91772.stdout#L4-L12)).
- **Janela de execução:** `2026-11-15 10:19:13 -03` até `2026-11-16 12:01:50 -03` (**~25h 42min**).
- **Causa da falha:** **OOM** no cgroup do Slurm:
  - [`outputs/sacct.txt`](outputs/sacct.txt#L3-L5): `ReqMem = 187.50G` (`192.000 MiB`), `91772_1.batch` atingiu **`MaxRSS = 201.289.608 K` = `196.571,88 MiB` (`191,96 GiB`)**, ou **`24.571,49 MiB/rank`**, estado `FAILED`.
  - [`outputs/int-1-HH/stderr.log`](outputs/int-1-HH/stderr.log#L6-L9): `mpirun noticed that process rank 4 with PID 319777 on node mcurie01 exited on signal 9 (Killed).`
- **Ponto exato da parada ([`outputs/int-1-HH/int-1-HH.out`](outputs/int-1-HH/int-1-HH.out#L4671-L4889)):**
  - Concluiu normalmente todas as etapas anteriores: `LeanSCF` (`886,0 s`, `601,7 MB`), `LMP2` iterativo (`7.400,1 s`, `2.222` pares), `VABPAO` (`1.220,6 s`, `312.153,5 MB` em disco), `Pair Pair Term` (`26.261,7 s`, `26` lotes `IBatch`), `RI-PNO` (`13.722,3 s`, `all 3-external` = `141.172 MB`, `4-external` = `30.687 MB`, `pair overlap` = `30.553 MB`) e **CCSD iterativo** (`11` iterações, `E(TOT) = -2440.184587382 Eh`).
  - Foi morto após ~3h 29min dentro de **`DLPNO BASED TRIPLES CORRECTION` (`49.811` triplos)**, após 3 blocos de progresso (`3.228,8 s`, `3.342,9 s`, `5.942,1 s`), antes de concluir o `T0`.
- **Limpeza do `slurm-dlpno.sh`:** detectou a ausência de `ORCA TERMINATED NORMALLY`, removeu os temporários de `/scratch`, gerou `int-1-HH_91772_failed.tar.gz` (`99M`, preservando `.gbw` e `.loc`) e apagou `/scratch/attilio.chiavegatti/jobs/91772` ([`int-1-HH_91772.stdout`](outputs/int-1-HH_91772.stdout#L43-L1998)).

---

## 3. Análise de RAM: Por que `+50%` de surplus falhou

| Parâmetro / Métrica | Valor no `testA2` (`91772`) | Comparação com [`testA1`](../testA1/README.md) (`90036`) |
|---|---|---|
| **Método / bases** | `TightPNO`, `def2-qzvpp` + `def2-qzvpp/C` (`2.583` AOs, `6.171` Aux) | `NormalPNO`, `def2-tzvpp` (`1.377` AOs, `3.324` Aux) |
| **`%pal nprocs` / `--ntasks`** | `8` | `4` |
| **`%maxcore`** | `16.000 MB` | `16.000 MB` |
| **Base declarada (`nprocs × %maxcore`)** | `128.000 MiB` (`125,00 GiB`) | `64.000 MiB` (`62,50 GiB`) |
| **Slurm `--mem` (`ReqMem`)** | `192000` (`187,50 GiB`, `+50%` surplus, `24.000 MiB/rank`) | `128000` (`125,00 GiB`, `+100%` surplus, `32.000 MiB/rank`) |
| **Folga acima de `%maxcore`** | `8.000 MiB/rank` (`64.000 MiB` no nó) | `16.000 MiB/rank` (`64.000 MiB` no nó) |
| **`MaxRSS` observado (`sacct`)** | **`196.571,88 MiB` (`191,96 GiB`, `24.571,49 MiB/rank`)** | `67.177,84 MiB` (`65,60 GiB`, `16.794,46 MiB/rank`) |
| **Surplus real no momento do `MaxRSS`** | **`+53,57%`** (estourou o limite em `~4,46 GiB` e foi morto) | `+4,97%` (concluiu normalmente) |

### Interpretação do surplus mínimo

- **`+53,57%` (`191,96 GiB`) não é o pico final do cálculo**, mas apenas o limite onde o processo foi morto ainda durante o `T0` da etapa `(T)`.
- **`+60%` de surplus (`--mem=200G`):** adicionaria apenas `~8 GiB` (`~1 GiB/rank`) acima do ponto de morte — arriscado caso o `(T)` cresça nas iterações seguintes.
- **Faixas recomendadas para concluir com segurança:**
  - **Manter `nprocs 8` + `%maxcore 16000`:** usar **`+100%` de surplus (`--mem=256G`)**, ou testar **`+75%` (`--mem=220G`–`224G`)** como faixa intermediária.
  - **Manter `--mem=192G` com `nprocs 8`:** reduzir **`%maxcore`** para **`12000`** (`96.000 MB` de base → `+100%` de surplus, `12.000 MB/rank` de folga).

---

## 4. Bases Auxiliares (ORCA)

1. **`def2-qzvpp/C` é necessária com `def2-qzvpp`:** métodos DLPNO exigem a auxiliar `/C` pareada com a base orbital (`AuxC`), e `RIJCOSX` exige `def2/J` (`AuxJ`), ambas corretamente especificadas em [`inputs/int-1-HH.inp`](inputs/int-1-HH.inp#L1).
2. **Não usar `def2-qzvpp/C` com base orbital `def2-tzvpp`:** com base triplo-zeta deve-se manter `def2-tzvpp/C`, pois `def2-qzvpp/C` não traz ganho prático de precisão e aumenta o custo de tempo, `/scratch` e memória.

---

## 5. Possibilidade de Reinício (Restart)

- **MDCI (`CCSD` e `(T)`):** **não** pode ser retomado do ponto de parada — todos os temporários do MDCI (`*.tmp`, integrais `VABPAO`, `all 3-external`, amplitudes) foram removidos pelo `clean_job` para proteger `/home`, e a etapa `(T)` não retoma do meio do loop de triplos.
- **SCF:** o `int-1-HH.gbw` foi preservado em `int-1-HH_91772_failed.tar.gz` e pode ser reaproveitado via `! MORead` + `%moinp "int-1-HH.gbw"`, economizando os `~15 min` do `LeanSCF` (`886 s`) em uma nova submissão com mais memória.
