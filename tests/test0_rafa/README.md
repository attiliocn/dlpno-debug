# Diagnóstico do Teste `test0_rafa` — Falha por OOM no Cálculo `int-1-HH` (Job `1152088`)

Este documento registra o diagnóstico completo da falha do job `1152088` (`int-1-HH.inp`), a análise de consumo de memória RAM e disco (`/scratch`) no módulo MDCI do ORCA 6.1.1 e o dimensionamento ótimo de recursos para os nós do CloudUFSCar.

---

## 1. Arquivos do Teste

- [`int-1-HH-FAILED/int-1-HH_1152088.stdout`](int-1-HH-FAILED/int-1-HH_1152088.stdout) — log do Slurm e das etapas do script `slurm-dlpno.sh`.
- [`int-1-HH-FAILED/int-1-HH_1152088_failed.tar.gz`](int-1-HH-FAILED/int-1-HH_1152088_failed.tar.gz) — pacote compactado (28 MB) gerado automaticamente na falha após limpeza dos temporários.
- [`int-1-HH-FAILED/int-1-HH/int-1-HH.inp`](int-1-HH-FAILED/int-1-HH/int-1-HH.inp) — arquivo de entrada submetido.
- [`int-1-HH-FAILED/int-1-HH/int-1-HH.out`](int-1-HH-FAILED/int-1-HH/int-1-HH.out) — saída principal do ORCA 6.1.1 interrompida no módulo MDCI.
- [`int-1-HH-FAILED/int-1-HH/stderr.log`](int-1-HH-FAILED/int-1-HH/stderr.log) — saída de erro do `mpirun`/`orca_mdci_mpi`.

---

## 2. Diagnóstico da Falha (`Job 1152088`)

A falha foi causada por **Out of Memory (OOM)** no limite de memória do cgroup do Slurm (`80000 MB`), após **4h 13min** de execução (`16:30:30` às `20:43:44` de `2026-11-11`) no nó `c7` (partição `slow`).

### 2.1 Evidências nos Logs e no Output do ORCA

1. **Log do Slurm (`int-1-HH_1152088.stdout`, linha 150):**
   O Slurm confirma o acionamento do OOM killer na alocação do job:
   ```text
   [2026-11-11T20:43:47.315] error: Detected 1 oom_kill event in StepId=1152088.batch. Some of the step tasks have been OOM Killed.
   ```

2. **Stderr do Container/MPI (`stderr.log`, linhas 6–9):**
   O `mpirun` reporta que o rank 3 do `orca_mdci_mpi` foi morto com `SIGKILL` (`signal 9`):
   ```text
   mpirun noticed that process rank 3 with PID 807951 on node c7 exited on signal 9 (Killed).
   [file orca_tools/qcmsg.cpp, line 394]:
     .... aborting the run
   ```

3. **Cronologia e ponto exato da parada no ORCA (`int-1-HH.out`):**
   - **LeanSCF:** convergiu normalmente em 23m 32s (`1412.4 s`), com pico de memória de apenas `255.9 MB` (linha 3044).
   - **Property Integrals:** concluído em `1.2 s`, pico de `208.8 MB` (linha 3090).
   - **Módulo `MDCI` (iniciado na linha 3100 com 4 processos MPI e `MaxCore = 20000 MB`):**
     - Localização Foster-Boys dos orbitais de valência (MOs 39–145) e de caroço (MOs 0–38): convergiu normalmente.
     - Operador de Fock closed-shell: `299.9 s` (`Reference energy = -2432.008063115 Eh`).
     - Prescreening de pares: `0.018 s` (1 de 5.778 pares descartado).
     - 1ª transformação `LOCAL RI TRANSFORMATION (IAVPAO)` (crude MP2): `111.1 s` (`3736.6 MB`).
     - 1º `INITIAL GUESS AND PNO GENERATION` (MP2 semilocal): `1242.5 s` (2.201 pares CCSD mantidos, 1.667 pares MP2 para `(T)`, 1.909 descartados).
     - 2ª transformação `LOCAL RI TRANSFORMATION (IAVPAO)` (fine MP2): `107.6 s` (`3502.5 MB`).
     - 2º `INITIAL GUESS AND PNO GENERATION` (`full local MP2` — LMP2 iterativo completo exigido pelo `TightPNO`): convergiu em 10 iterações em `4990.5 s` (~83 min, linhas 3719–3754).
     - Transformação `LOCAL RI TRANSFORMATION (IJV)`: `77.4 s` (`226.7 MB`).
     - Transformação `LOCAL RI TRANSFORMATION (VABPAO)`: concluída em `559.9 s`, gerando **`47699.659 MB` (~47,7 GB)** de integrais em disco (linha 3808).
     - Etapa **`Pair Pair Term precalculation with RI-(ij|mn) and (im|jn) transformation ON THE FLY`** (dividida em 15 lotes, linhas 3812–3829):
       - `IBatch 1` a `IBatch 7`: concluídos (entre `621.2 s` e `1113.4 s` por lote).
       - **`IBatch 8 (of 15)`**: o consumo agregado de RAM dos 4 processos MPI ultrapassou os `80000 MB` do cgroup e o rank 3 recebeu `SIGKILL`.

---

## 3. Análise do Input (`int-1-HH.inp`) vs. Recursos Solicitados

| Parâmetro | Valor em `int-1-HH` | Amostras de referência (`sample-dlpno/`) | Impacto |
|---|---|---|---|
| **Átomos / Elétrons totais** | 51 átomos / **292 $e^-$** (15 átomos de F) | 52–53 átomos / 200–212 $e^-$ | Mais elétrons devido aos 3 anéis $-\text{C}_6\text{F}_5$ |
| **Elétrons correlacionados** | **214 $e^-$ (107 MOs internos)** | 148–156 $e^-$ (74–78 MOs internos) | **+37% a +45% mais orbitais internos correlacionados** |
| **Pares totais / Pares CCSD (`TightPNO`)** | **5.778 totais / 2.201 CCSD** | 2.764–3.081 totais / 938–1.757 CCSD | Mais pares ativos no pré-cálculo de pares |
| **Funções de base / AuxC** | 1.377 (`def2-TZVPP`) / 3.324 (`def2-TZVPP/C`) | 2.313–2.397 (`def2-QZVPP`) / 3.024–5.318 | Base orbital menor, porém mais pares ocupados |
| **Processos MPI (`%pal` / `--ntasks`)** | `4` | `8` | Metade dos processos MPI das amostras |
| **`%maxcore`** | `20000` MB / rank | `24000` MB / rank | No `ts-exchg` (`TightPNO`), o MDCI usou `26371 MB` (**+9,9% acima do `%maxcore`**) |
| **Memória Slurm (`--mem`)** | `80000` MB (`20000 × 4 = 100%`) | — | **Zero margem** acima de `MaxCore × nprocs` |

### Por que ocorreu o estouro de memória

- O input define `%maxcore 20000` e `%pal nprocs 4`, totalizando $20\,000 \times 4 = 80\,000\text{ MB}$ — exatamente **100% do `#SBATCH --mem=80000`**.
- Conforme documentado no manual do ORCA 6.1.1 (§1.7.5 e §2.1.3), `%maxcore` regula apenas as áreas de trabalho dominantes por processo MPI; o consumo real por rank no MDCI frequentemente supera `%maxcore` em **5% a 15%** (além do overhead de binários, matrizes compartilhadas MPI, buffers SHARK/I/O e container). Por isso o manual recomenda:
  $$\text{MaxCore} \times \text{nprocs} \le 0{,}75 \times \text{RAM disponível}$$
- Adicionalmente, o script exportou `MKL_NUM_THREADS=4`, `OMP_NUM_THREADS=4` e `OMP_STACKSIZE=4G`, o que é desnecessário para os processos MPI do ORCA (cujo OpenBLAS interno já roda `SINGLE_THREADED`) e pode reservar memória extra caso alguma rotina crie threads OpenMP.

---

## 4. Comportamento do Script `slurm-dlpno.sh` na Falha

O fluxo de tratamento de erro do `slurm-dlpno.sh` funcionou exatamente como projetado:

1. **Captura de falha silenciosa do container:** O `singularity run` retornou exit code `0` mesmo após o aborto do ORCA (`LOG: ORCA process finished with status 0.`, linha 41), mas a verificação do marcador `ORCA TERMINATED NORMALLY` (linhas 42–43) detectou a terminação anormal e marcou `job_success=0`.
2. **Descarte dos temporários no scratch:** Antes de compactar, `clean_job` removeu **75 GB** de arquivos temporários (`*.tmp`, `*.tmp.*`, `*.bas0`–`*.bas5`, `*.densities`, linhas 48–120).
3. **Empacotamento enxuto e limpeza:** O arquivo final `int-1-HH_1152088_failed.tar.gz` ficou com apenas **28 MB** (linha 133), preservando `int-1-HH.out`, `stderr.log`, `int-1-HH.gbw` e `int-1-HH.loc`, e o diretório `/scratch/u831869/jobs/1152088` foi removido em seguida (linhas 134–149).

---

## 5. Disco (`/scratch`) vs. Memória RAM: O que são os 47,7 GB do `VABPAO`?

Os **47,7 GB (`47699.659 MB`)** impressos na etapa `LOCAL RI TRANSFORMATION (VABPAO)` (`int-1-HH.out`, linha 3808) referem-se ao **volume de dados gravado em disco (`/scratch`)**, e **não** a um piso de memória RAM:

- **O que são os 47,7 GB:** tamanho total dos arquivos de integrais de 3 índices semi-transformadas `int-1-HH.VABPAO.tmp.0` a `.3` gravados no `/scratch` (que compõem a maior parte dos **75 GB** de arquivos temporários apagados pelo `clean_job`).
- **Comparação com os cálculos de referência (`sample-dlpno/`):**
  - Em `bis_int_tbpButTrans_3.out` (linha 6359), o `VABPAO` gerou **`199944.384 MB` (~200 GB)** em disco, mas o pico de memória RAM de todo o módulo MDCI foi de **`24562.6 MB`** por processo (linha 6653).
  - Em `ts-exchg-2_f3_17.out` (linha 6554), o `VABPAO` gerou **`132558.641 MB` (~132,6 GB)** em disco, mas o pico de memória RAM do MDCI foi de **`26371.3 MB`** por processo (linha 6863).

Portanto, os **47,7 GB são um requisito mínimo de espaço em `/scratch` (disco)** para essa molécula/base/thresholds, mas **não de RAM**.

---

## 6. Piso de RAM, Regra dos 75% e Vantagens de `%maxcore > 8000`

### 6.1 Piso de RAM vs. Folga de 25% no Slurm

- **Piso algorítmico de RAM:** O ORCA divide o cálculo em lotes (`IBatch`), mas no limite precisa manter na memória ao menos 1 orbital interno (ou 1 par/tripla) por lote, além dos mapas de domínios e matrizes PAO/PNO. O manual recomenda **pelo menos `8000 MB` por core** para Coupled Cluster. Se o mínimo de 1 lote ficar entre $1\times$ e $2\times$ o `%maxcore`, o ORCA emite aviso e ultrapassa o `%maxcore`; se passar de $2\times$, ele aborta.
- **Folga no `int-1-HH`:** Com `%maxcore 20000`, os 107 orbitais internos foram divididos em apenas **15 lotes (`IBatch 1 of 15`)** (~7 orbitais por lote), ou seja, bem acima do piso algorítmico.
- **Por que a regra dos 75% no Slurm é decisiva:** O ORCA **não enxerga o `#SBATCH --mem` do Slurm**; ele dimensiona os lotes para usar 100% de `nprocs × %maxcore` nos vetores principais e aloca mais ~5–15% por fora. Assim, para evitar OOM, é fundamental garantir:
  $$\text{Slurm }\texttt{--mem} \ge \frac{\text{nprocs} \times \texttt{\%maxcore}}{0{,}75} \approx 1{,}33 \times (\text{nprocs} \times \texttt{\%maxcore})$$

### 6.2 Vantagens de manter `%maxcore` acima de `8000` MB (15.000 a 20.000 MB)

Aumentar `%maxcore` não altera a energia final, mas reduz drasticamente o I/O de disco e o tempo de execução em quatro frentes:

1. **Menos lotes (`IBatch`) no `Pair Pair Term`:** Com `%maxcore 20000`, o ORCA precisou de 15 lotes (~11–18 min por lote). Com `%maxcore 8000`, precisaria de ~35–40 lotes, relendo/recalculando dezenas de GB de integrais do `/scratch` a cada lote e adicionando várias horas ao cálculo.
2. **Passe único na transformação `RI-PNO`:** Nas amostras com `%maxcore 24000`, a geração das integrais PNO de 2 a 4 índices rodou em lote único (`Ibatch: 1 (of 1)`). Com `%maxcore` baixo, essa etapa também é fatiada em múltiplos passes de disco.
3. **Aceleração da etapa dominante de Triples `(T1)`:** A correção iterativa `(T1)` consome **70% a 78% do tempo total** do cálculo DLPNO-CCSD(T1). Maior `%maxcore` mantém mais triplas $(i,j,k)$ e integrais TNO em memória por lote, reduzindo o gargalo de I/O na fase mais longa do job.
4. **Previsibilidade do pico de memória:** Com `TightPNO`, pares com domínios grandes (>100 PNOs) podem fazer um lote pequeno estourar `8000 MB`. Com `15000`–`20000 MB`, os lotes acomodam esses pares sem ultrapassar o teto planejado.

---

## 7. Dimensionamento de Recursos no CloudUFSCar (40, 20, 16, 8 e 4 Cores)

Nos nós regulares do CloudUFSCar (`c1`–`c18`), cada nó possui **40 CPUs** e **`386700 MB` (~386,7 GB) de RAM**, resultando em **~9.667 MB de RAM física por CPU**.

### 7.1 Limite de Eficiência de Escala de CPUs no ORCA

- O módulo MDCI/DLPNO **escala muito bem até 8 processos MPI, continua ganhando velocidade até 16 processos, e perde eficiência rapidamente acima de 16 processos (20 ou 40 cores)** devido a:
  1. **Contenção de I/O no `/scratch`:** 20 ou 40 processos lendo/escrevendo concorrentemente nos mesmos arquivos de dezenas de GB no disco local.
  2. **Queda do `%maxcore` por processo:** como a RAM do nó é fixa (`386700 MB`), usar 40 cores força `%maxcore <= 7000 MB` (abaixo dos `8000 MB` recomendados pelo manual), multiplicando os lotes de disco (`IBatch`).
  3. **Desbalanceamento de domínios PNO:** pares e triplas têm tamanhos heterogêneos, aumentando o tempo ocioso em barreiras MPI com muitos ranks.
- **Faixa ideal ("sweet spot"):** **8 a 16 cores**.

### 7.2 Tabela Comparativa: 40, 20, 16, 8 e 4 Cores

Aplicando a regra segura $\texttt{nprocs} \times \texttt{\%maxcore} \le 0{,}75 \times \texttt{--mem}$:

| Cores (`--ntasks` e `%pal nprocs`) | Perfil / Cenário no Nó (`386700 MB`) | `#SBATCH --mem` (MB) | `%maxcore` (MB) | Soma `nprocs × %maxcore` | Folga Slurm (`--mem` − Soma) | Avaliação para DLPNO `TightPNO` |
|---:|---|---:|---:|---:|---:|---|
| **40** | **Node completo** (40 CPUs + toda a RAM) | `380000` | `7000` | `280000` (73,7%) | `100000` MB | **Ruim.** `%maxcore` fica abaixo de 8 GB e 40 ranks saturam o I/O do `/scratch`. |
| **20** | **Meio node estrito** (50% CPU + 50% RAM) | `190000` | `7000` | `140000` (73,7%) | `50000` MB | **Subótimo.** 20 ranks têm ganho marginal sobre 16 e o `%maxcore` cai para 7 GB. |
| **20** | **Meio node em CPU + 60% da RAM** | `220000` | `8000` | `160000` (72,7%) | `60000` MB | **Aceitável**, atinge o piso de 8 GB/core, mas 16 cores com a mesma RAM é mais rápido. |
| **16** | **Meio node** (cabem **2 jobs/node**) | `190000` | `8500`–`9000` | `136000`–`144000` | `46000`–`54000` MB | **Bom.** Permite rodar 2 jobs de 16 cores no mesmo nó respeitando 386 GB. |
| **16** | **Alta performance** (1 job rápido) | `260000` | `12000` | `192000` (73,8%) | `68000` MB | **Excelente (Mais rápido).** Máxima escala de CPU do ORCA com lotes grandes em RAM. |
| **16** | **Node completo dedicado a 1 job** | `350000` | `16000` | `256000` (73,1%) | `94000` MB | **Excelente** se o nó inteiro estiver disponível para um único job urgente. |
| **8** | **Proporcional** (cabem **4 jobs/node**) | `95000` | `8500` | `68000` (71,6%) | `27000` MB | **Econômico**, seguro contra OOM, mas faz mais lotes de disco. |
| **8** | **Meio node de RAM** (cabem **2 jobs/node**) | **`190000`** | **`17500`** | `140000` (73,7%) | `50000` MB | **Ideal para "Meio Node".** Muito `%maxcore` por rank, poucos lotes `IBatch` e 8 CPUs eficientes. |
| **8** | **Equilibrado** (cabem **2 jobs/node**) | **`160000`** | **`15000`** | `120000` (75,0%) | `40000` MB | **Ponto doce geral.** Ótimo tempo de execução e fácil alocação no Slurm. |
| **4** | **Atual corrigido (RAM mantida)** | `80000` | `15000` | `60000` (75,0%) | `20000` MB | **Seguro**, entra fácil na fila, porém tempo total ~1,8× maior que 8 cores. |
| **4** | **Atual corrigido (`%maxcore` mantido)** | `110000` | `20000` | `80000` (72,7%) | `30000` MB | **Seguro**, mantém os 15 lotes do `int-1-HH`, mas limitado a 4 CPUs. |

### 7.3 Recomendações por Cenário

1. **Cenário "Meio Node" (Orçamento de até 20 CPUs e ~190.000 MB de RAM — permite 2 jobs por nó):**
   - **Priorizando memória por processo e eficiência (Recomendado — 8 cores):**
     - `#SBATCH --ntasks=8` e `%pal nprocs 8`
     - `#SBATCH --mem=160000` (com `%maxcore 15000`) **ou** `#SBATCH --mem=190000` (com `%maxcore 17500`)
   - **Priorizando número de CPUs (16 cores):**
     - `#SBATCH --ntasks=16` e `%pal nprocs 16`
     - `#SBATCH --mem=190000` e `%maxcore 8500` (ou `9000`)
2. **Cenário "Node Completo" (Orçamento de 1 nó inteiro = 40 CPUs e ~380.000 MB de RAM):**
   - **Para 1 único job urgente:** usar **16 cores** (`#SBATCH --ntasks=16`, `%pal nprocs 16`, `#SBATCH --mem=350000`, `%maxcore 16000`), evitando usar 40 ranks que derrubariam o `%maxcore` para 7 GB e saturariam o `/scratch`.
   - **Para lote (`--array`) com múltiplos inputs:** dividir o nó em **2 tasks simultâneas de 8 ou 16 cores** (Cenário "Meio Node").
