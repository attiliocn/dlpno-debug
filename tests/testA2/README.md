# Planejamento do Teste `testA2`

Este documento registra a configuração, as decisões de base auxiliar e os pontos de atenção levantados antes da submissão do teste `testA2` em `int-1-HH.inp`.

---

## 1. Arquivos do Teste

- [`inputs/int-1-HH.inp`](inputs/int-1-HH.inp) — entrada ORCA (`TightPNO`, `def2-qzvpp`, `def2-qzvpp/C`, `def2/J`, `%maxcore 16000`, `%pal nprocs 8`).

---

## 2. Configuração e Objetivo (`+50%` de surplus)

| Parâmetro | Valor planejado (`testA2`) | Comparação com [`testA1`](../testA1/README.md) |
|---|---|---|
| **Método / truncamento** | `DLPNO-CCSD(T1) TightPNO TightSCF RIJCOSX` | `testA1` usou `NormalPNO` |
| **Base orbital / auxiliares** | `def2-qzvpp` + `def2-qzvpp/C` + `def2/J` | `testA1` usou `def2-tzvpp` + `def2-tzvpp/C` |
| **`%pal nprocs` / `--ntasks`** | `8` | `testA1` usou `4` |
| **`%maxcore`** | `16.000 MB` | Igual ao `testA1` |
| **Base declarada (`nprocs × %maxcore`)** | **`128.000 MB`** | `testA1`: `64.000 MB` |
| **Surplus / `--mem` alvo no Slurm** | **`+50%` → `--mem=192000`** (`24.000 MB/rank`) | `testA1`: `+100%` (`--mem=128000`, `MaxRSS` real `65,60 GiB`) |
| **Folga acima de `%maxcore`** | `8.000 MB/rank` (`64.000 MB` no nó) | `testA1`: `16.000 MB/rank` |

O objetivo do `testA2` é verificar se **`+50%` de surplus (`--mem=192000`)** sustenta o cálculo sem OOM com `nprocs 8` e `%maxcore 16000` em `TightPNO` com base quádrupla-zeta.

---

## 3. Bases Auxiliares (ORCA)

1. **`def2-qzvpp/C` é necessária com `def2-qzvpp`:**
   - Métodos DLPNO exigem a aproximação RI na correlação (`AuxC`), usando a base `/C` pareada com a base orbital (`def2-qzvpp` → `def2-qzvpp/C`).
   - Com `RIJCOSX` no SCF, também é necessária a base auxiliar de Coulomb (`AuxJ`) `def2/J`, já presente na linha 1 de [`inputs/int-1-HH.inp`](inputs/int-1-HH.inp#L1).
2. **Não usar `def2-qzvpp/C` com base orbital `def2-tzvpp`:**
   - Se a base orbital for triplo-zeta (`def2-tzvpp`), deve-se manter `def2-tzvpp/C`.
   - Trocar para `def2-qzvpp/C` mantendo `def2-tzvpp` **não** melhora de forma relevante a precisão (o erro de ajuste RI de `def2-tzvpp/C` já é desprezível frente ao erro da base orbital TZ e do DLPNO), mas aumenta o número de funções auxiliares ($N_{\text{aux}}$), elevando tempo de execução, I/O em `/scratch` e pressão de memória por lote.

---

## 4. Riscos e Recomendações Operacionais

- **Salto de carga em relação aos testes anteriores:**
  - O `testA1` validou `MaxRSS` baixo (`+4,97%` sobre a base), porém em **`NormalPNO` + `def2-tzvpp` + `nprocs 4`**.
  - No [`test1_after-diagnose`](../test1_after-diagnose/README.md) (`TightPNO` + `def2-tzvpp` + `nprocs 8` + `%maxcore 16000`), `--mem=166000` (`+29,7%` de surplus, `4.750 MB/rank` de folga) sofreu **OOM imediato no `IBatch 1`**.
  - Em `testA2`, `--mem=192000` dobra aproximadamente essa folga por rank (`8.000 MB/rank`), mas a combinação **`TightPNO` + `def2-qzvpp`** aumenta de forma expressiva o número de AOs, PAOs e funções auxiliares — mantendo risco moderado de OOM caso os buffers fora do `%maxcore` cresçam com a base QZVPP.
- **Checklist para submissão e pós-execução:**
  - Garantir no `slurm-dlpno.sh` do `testA2`: `#SBATCH --ntasks=8` e `#SBATCH --mem=192000`.
  - Ajustar `#SBATCH --time` prevendo tempo bem superior às `4h 40min` do `testA1` (`NormalPNO` + `def2-tzvpp`).
  - Ao final do job, registrar o `MaxRSS` real com `sacct -j <JOBID> --format=JobID,MaxRSS,ReqMem,AllocCPUS,State` em `data/usage-ram.txt` (como feito no `testA1`).
