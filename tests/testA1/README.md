# Análise do Teste `testA1` (Job `90036`)

Este documento registra a execução bem-sucedida do teste `testA1` em `int-1-HH.inp`, analisa o consumo de memória RAM reportado pelo ORCA 6.1.1 e confronta o uso observado com os recursos configurados no input do ORCA e no script do Slurm.

---

## 1. Arquivos do Teste

- [`inputs/`](inputs/) — arquivos preparados para submissão (`int-1-HH.inp`, `slurm-dlpno.sh`, `slurm-dlpno.csv`, `prepare-job.sh`).
- [`data/usage-ram.txt`](data/usage-ram.txt) — saída do `sacct -j 90036` com o pico real de RSS (`MaxRSS`) registrado pelo Slurm.
- [`outputs/int-1-HH_90036.stdout`](outputs/int-1-HH_90036.stdout) — log do Slurm e do `slurm-dlpno.sh`.
- [`outputs/slurm-dlpno.sh`](outputs/slurm-dlpno.sh) — script Slurm efetivamente submetido (`#SBATCH --job-name testA1`, `--ntasks=4`, `--mem=128000`, `--time=10:00:00`).
- [`outputs/int-1-HH/int-1-HH.inp`](outputs/int-1-HH/int-1-HH.inp) — entrada ORCA (`%maxcore 16000`, `%pal nprocs 4`).
- [`outputs/int-1-HH/int-1-HH.out`](outputs/int-1-HH/int-1-HH.out) — saída completa do ORCA 6.1.1.
- [`outputs/int-1-HH/stderr.log`](outputs/int-1-HH/stderr.log) — saída de erro (`0 bytes`, sem erros).

---

## 2. Resumo da Execução

- **Job / Nó:** `90036` (array task `1`), nó `mcurie01`, partição `cpu` ([`int-1-HH_90036.stdout`](outputs/int-1-HH_90036.stdout#L4-L12)).
- **Janela de execução:** `2026-11-14 16:31:14 -03` até `21:10:46 -03` (~4h 39min 32s de wall-clock; `TOTAL RUN TIME: 0 days 4 hours 39 minutes 31 seconds 707 msec` em [`int-1-HH.out`](outputs/int-1-HH/int-1-HH.out#L4311)).
- **Status:** saída `0` da singularity/ORCA, marcador `****ORCA TERMINATED NORMALLY****` presente ([`int-1-HH.out`](outputs/int-1-HH/int-1-HH.out#L4310)), `stderr.log` vazio.
- **Energia final:** `-2439.858304931843 Eh` ([`int-1-HH.out`](outputs/int-1-HH/int-1-HH.out#L4075)).
- **Empacotamento e limpeza:** arquivo `int-1-HH_90036.tar.gz` (`57M`) gerado e diretório `/scratch/attilio.chiavegatti/jobs/90036` removido ao final ([`int-1-HH_90036.stdout`](outputs/int-1-HH_90036.stdout#L60-L75)).

---

## 3. Recursos Estabelecidos vs. Uso Observado de RAM

### 3.1. Configuração estabelecida (INP e Slurm)

| Camada | Parâmetro | Valor configurado | Observação |
|---|---|---:|---|
| **ORCA INP** | Método / bases | `DLPNO-CCSD(T1) NormalPNO TightSCF RIJCOSX def2-tzvpp def2-tzvpp/C def2/J` | Preservar parâmetros científicos |
| **ORCA INP** | `%pal nprocs` | `4` | 4 ranks MPI |
| **ORCA INP** | `%maxcore` | `16.000 MB` | Por processo MPI (arrays de trabalho) |
| **ORCA INP** | Base declarada (`nprocs × %maxcore`) | **`64.000 MB`** | `16.000 MB/rank` |
| **Slurm** | `--nodes` / `--ntasks` | `1` / `4` | Coincide com `%pal nprocs 4` |
| **Slurm** | `--mem` | **`128.000 MB`** | **`32.000 MB/rank`** (**+100% de surplus** sobre a base) |
| **Slurm** | `--time` | `10:00:00` | Utilizou ~46,6% do limite (`4h 39m 32s`) |
| **Ambiente** | `MKL_NUM_THREADS` / `OMP_NUM_THREADS` | `1` / `1` | `ulimit -s unlimited`, sem `OMP_STACKSIZE=4G` |

### 3.2. Pico de memória reportado pelo ORCA por módulo

O ORCA reporta `Maximum memory used throughout the entire <MODULO>-calculation` (valor por processo MPI rastreado internamente):

| Módulo | Pico reportado (por rank) | Referência no `int-1-HH.out` |
|---|---:|---|
| `STARTUP` | `170,2 MB` | [L883](outputs/int-1-HH/int-1-HH.out#L883) |
| `GUESS` | `163,1 MB` | [L996](outputs/int-1-HH/int-1-HH.out#L996) |
| `LEANSCF` | `255,9 MB` | [L3044](outputs/int-1-HH/int-1-HH.out#L3044) |
| `PROPINT` | `208,8 MB` | [L3090](outputs/int-1-HH/int-1-HH.out#L3090) |
| **`MDCI`** | **`16.602,0 MB`** | [L4072](outputs/int-1-HH/int-1-HH.out#L4072) |
| `PROP` | `175,6 MB` | [L4176](outputs/int-1-HH/int-1-HH.out#L4176) |

### 3.3. Confronto entre uso observado e orçamento de RAM

1. **O módulo MDCI excedeu `%maxcore` em `+602,0 MB/rank` (`+3,76%`):**
   - `%maxcore 16000` limita apenas os arrays de trabalho principais do MDCI (`Maximum memory for working arrays ... 16000 MB`, [L3147](outputs/int-1-HH/int-1-HH.out#L3147)).
   - Estruturas estáticas/replicadas, mapas esparsos, buffers de integrais/SHARK e buffers auxiliares elevam o pico rastreado pelo ORCA para **`16.602,0 MB/rank`**.
   - Multiplicado pelos 4 ranks MPI, apenas o pico rastreado pelo ORCA soma **`66.408,0 MB`** (já acima dos `64.000 MB` de `nprocs × %maxcore`), sem contar o overhead de processo/MPI/Singularity não contabilizado pelo tracker interno do ORCA.

2. **Pico real no Slurm (`sacct MaxRSS`) e margem em relação ao `--mem=128000` (`125 GiB`):**
   - O registro de [`data/usage-ram.txt`](data/usage-ram.txt) mostra `MaxRSS = 68.790.108 K` no step `90036_1.batch` (e `932 K` no `90036_1.extern`), com `ReqMem = 125G` (`128.000 MiB`):
     - **`MaxRSS` do batch:** `68.790.108 KiB` = **`67.177,84 MiB`** (**`65,60 GiB`**, ou `70.441,07 MB` decimais) ≈ **`16.794,46 MiB/rank`**.
     - **Overhead fora do tracker do ORCA (MPI/contêiner/sistema):** apenas `~769,8 MiB` no nó (`~192,5 MiB/rank`) acima dos `66.408,0 MB` reportados pelo MDCI.
     - **Utilização da memória alocada:** **`52,48%`** dos `128.000 MiB` (`125 GiB`), deixando **`60.822,16 MiB`** (`59,40 GiB`) livres no nó.
     - **Surplus mínimo observado sobre `4 × 16.000 MiB = 64.000 MiB`:** **`+4,97%`** em base binária (`67.177,84 / 64.000 - 1`; ou `+10,06%` se comparado em MB decimais). Com margem de segurança operacional, `+20%` a `+33%` (`--mem=77000` a `86000` MiB) já cobriria este cálculo em `NormalPNO` com 4 ranks, mantendo `+50%` a `+100%` como faixa conservadora.

3. **Por que essa configuração resolveu os OOMs anteriores (`test0_rafa` e `test1_after-diagnose`):**
   - Em [`test0_rafa`](../test0_rafa/README.md) (`nprocs 4`, `%maxcore 20000`, `--mem=80000`, `20.000 MB/rank`, `0%` surplus) e [`test1_after-diagnose`](../test1_after-diagnose/README.md) (`nprocs 8`, `%maxcore 16000`, `--mem=166000`, `20.750 MB/rank`, `+29,7%` surplus), a folga real acima de `%maxcore` (`0` e `4.750 MB/rank`, respectivamente) não comportava o overhead do MDCI somado ao RSS de MPI/processo.
   - Reduzir `%maxcore` para `16.000 MB` com `nprocs 4` e aplicar **100% de surplus** (`--mem=128000`) manteve o armazenamento *in-core* desligado (`In-Core Storage of quantities: NO`, `Keep RI integrals in memory: off`, [L3150-L3155](outputs/int-1-HH/int-1-HH.out#L3150-L3155), [L3828](outputs/int-1-HH/int-1-HH.out#L3828)), fez o `Pair Pair Term` rodar em `5` lotes (`IBatch 1..5`, `932,782 s`, [L3786-L3791](outputs/int-1-HH/int-1-HH.out#L3786-L3791)) e manteve a execução estável até o fim.

---

## 4. Uso Complementar de Disco (`/scratch`) e Tempo

- **Principais arquivos reportados em disco durante o MDCI:**
  - `VABPAO`: `41.853,668 MB` ([L3776](outputs/int-1-HH/int-1-HH.out#L3776))
  - `all 3-external`: `18.747 MB` ([L3838](outputs/int-1-HH/int-1-HH.out#L3838))
  - `pair overlap`: `5.693 MB` ([L3842](outputs/int-1-HH/int-1-HH.out#L3842))
  - `4-external`: `2.714 MB` ([L3836](outputs/int-1-HH/int-1-HH.out#L3836))
  - `3-external`: `422 MB` ([L3835](outputs/int-1-HH/int-1-HH.out#L3835)), `1-external`: `67 MB` ([L3839](outputs/int-1-HH/int-1-HH.out#L3839)), `IKJL`: `4 MB` ([L3837](outputs/int-1-HH/int-1-HH.out#L3837))
- **Distribuição de tempo ([L4304-L4309](outputs/int-1-HH/int-1-HH.out#L4304-L4309)):**
  - `MDCI module`: `16.274,249 s` (`97,0%`, sendo `11.198,593 s` apenas na correção `(T)` — `68,8%` do MDCI)
  - `SCF iterations`: `486,212 s` (`2,9%`)
  - `Startup` + `Property`: `10,818 s` (`0,1%`)

---

## 5. Conclusão

A configuração **`%pal nprocs 4` + `%maxcore 16000` + `#SBATCH --ntasks=4` + `#SBATCH --mem=128000`** (`+100%` de surplus) validou-se na prática para `int-1-HH.inp`: o cálculo concluiu sem erros em ~4h 40min, com pico reportado pelo ORCA de **`16.602,0 MB/rank`** (`66.408,0 MB` nos 4 ranks), deixando ampla margem dentro dos `128.000 MB` solicitados ao Slurm.
