# Recursos computacionais para DLPNO no ORCA 6.1.1

## Escopo

Nota de pesquisa sobre os recursos necessários para executar cálculos DLPNO,
com foco em `NormalPNO`, baseada no manual oficial em
`docs/orca_manual_6_1_1.pdf`.

As referências de página abaixo são as **páginas impressas** do manual, que
podem diferir do índice do PDF.

Este documento não altera o `jobfile` nem o input científico. As implicações
para o job atual estão reunidas na última seção. A capacidade do cluster e a
premissa de um scratch por node estão em
`research/cloudufscar-resources.md`.

## Resumo executivo

- `NormalPNO` é o ajuste de precisão padrão do DLPNO-CCSD(T). Para o método
  atual (`DLPNO-CCSD(T1)`), os thresholds são:
  `TCutPairs=1e-4`, `TCutDO=1e-2`, `TCutPNO=3.33e-7` e `TCutMKN=1e-3`.
- `NormalPNO` usa o tratamento MP2 semicanônico dos pares; `TightPNO` usa o
  tratamento iterativo completo e tende a ser mais caro.
- `%maxcore` é **por processo**, em MB. O manual recomenda pelo menos 8 GB por
  core para coupled cluster e a regra
  `MaxCore × nprocs ≤ 0,75 × RAM disponível`.
- O módulo MDCI, que contém DLPNO, é paralelizado. O número de processos é
  definido no input (`%pal`/`PALn`) e deve coincidir com os recursos do Slurm.
- Coupled cluster costuma escalar bem até pelo menos 8 processos; testar 16
  pode valer a pena.
- DLPNO exige base auxiliar de correlação, como `def2-tzvpp/C`. Com
  `RIJCOSX`, também é necessária a auxiliar de Coulomb, como `def2/J`.
- DLPNO pode gerar bastante I/O de disco. O manual recomenda scratch local
  (não NFS) e, em nó único, permite tentar manter integrais em memória
  compartilhada com `%mdci StorageType Shared`.
- O manual não fornece uma fórmula fechada de RAM ou disco por átomo/base.
  Ele fornece regras de memória, orientação de paralelismo e exemplos de tempo.

## 1. NormalPNO: precisão e custo

### 1.1 DLPNO-CCSD(T)

Manual, seção **3.10.10 — Local correlation (DLPNO)**, Tabela 3.40, p. 317.

| Ajuste | TCutPairs | TCutDO | TCutPNO | TCutMKN | Tratamento MP2 dos pares |
|---|---:|---:|---:|---:|---|
| LoosePNO | `1e-3` | `2e-2` | `1e-6` | `1e-3` | semicanônico |
| **NormalPNO** | **`1e-4`** | **`1e-2`** | **`3.33e-7`** | **`1e-3`** | **semicanônico** |
| TightPNO | `1e-5` | `5e-3` | `1e-7` | `1e-3` | LMP2 iterativo completo |

Pontos relevantes:

- `NormalPNO` corresponde ao default e não precisa ser escrito no input.
- É indicado para termoquímica geral.
- `TightPNO` é mais preciso e mais caro, pois ativa o tratamento iterativo
  completo no “guess” de MP2.
- `LoosePNO` é mais rápido e menos preciso.
- O manual recomenda ajustar a precisão com `LoosePNO`/`NormalPNO`/`TightPNO`
  em vez de alterar manualmente os thresholds.
- O método `DLPNO-CCSD(T1)`, usado no input atual, calcula a correção de
  triples de forma iterativa. Isso é diferente do `DLPNO-CCSD(T)`
  semicanônico e pode ter custo adicional; o manual não fornece um fator
  numérico específico para essa diferença.

### 1.2 DLPNO-MP2: não confundir os thresholds

Manual, seção **3.9.10 — Local MP2 calculations (DLPNO-MP2)**, Tabela 3.33,
p. 266.

| Ajuste | TCutDO | TCutPNO RHF | TCutPNO UHF |
|---|---:|---:|---:|
| LoosePNO | `2e-2` | `1e-7` | `1e-8` |
| NormalPNO | `1e-2` | `1e-8` | `1e-9` |
| TightPNO | `5e-3` | `1e-9` | `1e-10` |

Os thresholds de `NormalPNO` para DLPNO-MP2 são diferentes dos usados em
DLPNO-CCSD(T). Para o job atual, que é `DLPNO-CCSD(T1)`, vale a Tabela 3.40.

## 2. Memória

### 2.1 Regra do MaxCore

Manual, seção **1.7.5 — Out of Memory**, p. 14, e seção
**2.1.3 — Global Memory Use**, p. 23.

- `%maxcore` é especificado em MB.
- O valor é o máximo de memória de trabalho **por processo**, não o total do
  job.
- O default é 4 GB por core.
- Para coupled cluster e métodos semelhantes, o manual recomenda **pelo menos
  8 GB por core**.
- Regra de segurança:

```text
MaxCore × nprocs ≤ 0,75 × RAM disponível
```

- O manual também recomenda que o valor não ultrapasse 75–80% da memória
  física.
- O ORCA pode ultrapassar o `MaxCore` durante a execução, pois ele controla
  principalmente as áreas de trabalho dominantes.
- Se a estimativa de memória ficar entre 1× e 2× o `MaxCore`, o ORCA emite
  aviso e continua; se ficar acima de 2×, pode abortar.
- Memória grande não é obrigatória para DLPNO, mas acelera a transformação
  inicial de integrais.

### 2.2 Exemplos de dimensionamento

Para a regra de 75%, com `--mem` em MB no Slurm:

| Processos | `--mem` | `%maxcore` máximo aproximado |
|---:|---:|---:|
| 4 | 80 GB | 15.000 MB |
| 4 | 107 GB | 20.000 MB |
| 8 | 80 GB | 7.500 MB |
| 8 | 160 GB | 15.000 MB |

Esses valores são limites superiores; deixar margem para o sistema operacional,
para o contêiner e para eventuais picos do ORCA é recomendável.

### 2.3 Memória compartilhada

Manual, seção **3.10.10**, p. 319.

Para sistemas maiores ou thresholds mais apertados, o I/O de disco pode ficar
crítico. Se houver RAM suficiente, o ORCA pode tentar manter integrais muito
usadas em memória compartilhada:

```text
%mdci
  StorageType Shared
end
```

Condições e comportamento:

- só funciona se todos os processos estiverem no mesmo nó;
- se a memória não for suficiente, o ORCA volta para armazenamento em disco;
- não substitui o dimensionamento correto de `%maxcore` e da memória do job.

## 3. CPU e paralelismo

### 3.1 Módulos paralelos

Manual, seção **2.5 — Parallel and Multi-Process Runs**, pp. 39–44.

- O módulo MDCI, incluindo métodos canônicos e DLPNO, é paralelizado.
- O driver do ORCA deve ser chamado serialmente; **não iniciar o driver com
  `mpirun`**.
- O paralelismo é solicitado no input:

```text
! PAL4
```

ou

```text
%pal
  nprocs 4
end
```

- O ORCA inicia os módulos paralelos automaticamente.
- O manual indica que coupled cluster normalmente escala bem até pelo menos
  8 processos, e que provavelmente vale a pena testar 16.
- O número de processos do ORCA deve coincidir com os recursos alocados pelo
  Slurm (`--ntasks`).

### 3.2 Threads

O manual exemplifica um wrapper com `MKL_NUM_THREADS=1` comentado. Não há uma
recomendação explícita para usar 4 threads OpenMP por processo MPI em um job
DLPNO.

Atenção: com 4 processos MPI e `MKL_NUM_THREADS=4`/`OMP_NUM_THREADS=4`, o job
pode criar até 16 threads sobre 4 CPUs, causando oversubscription. Validar
esse ponto antes de aumentar o paralelismo.

## 4. Disco e scratch

### 4.1 Scratch local

Manual, seção **2.5.2 — Hints on the Use of Parallel ORCA**, pp. 40–44.

Recomendações:

- rodar o ORCA em scratch local, não em diretório montado via NFS;
- criar um diretório novo para cada execução;
- copiar a entrada para o scratch;
- executar o cálculo;
- salvar os resultados;
- remover o diretório de scratch ao final.

O `jobfile` atual já usa `/scratch/$USER/jobs/$SLURM_JOB_ID`, o que está
alinhado com essa recomendação.

### 4.2 I/O do DLPNO

Manual, seção **3.10.10**, p. 319.

- Para sistemas maiores e thresholds mais apertados, o I/O de disco do DLPNO
  pode se tornar desafiador.
- O manual sugere `StorageType Shared` quando há RAM suficiente e todos os
  processos estão no mesmo nó.
- Caso contrário, o cálculo pode manter integrais em disco.

O manual não fornece um tamanho fixo de disco por átomo ou por base. O consumo
depende do sistema, da base, dos thresholds, do número de PNOs e do modo de
armazenamento. O acompanhamento deve ser feito pela saída do ORCA e pelo uso
real do scratch.

### 4.3 MaxDisk não é um limite geral do DLPNO

Manual, seção **2.14 — Integral Handling**, pp. 145–147.

- `MaxDisk` no bloco `%scf` controla o espaço para arquivos de integrais de
  dois elétrons do SCF.
- O manual alerta que o espaço real usado por todos os arquivos temporários
  pode ser bem maior que `MaxDisk`.
- Portanto, `MaxDisk` não deve ser tratado como limite de disco do cálculo
  DLPNO completo.

## 5. Tempo e escalabilidade

Manual, seção **3.10.10**, pp. 305–321.

- DLPNO-CCSD(T) é linear-scaling.
- A correção de triples adiciona cerca de 10–20% ao tempo do DLPNO-CCSD para
  sistemas grandes.
- A versão open-shell é aproximadamente 2× mais cara que a closed-shell.
- Sistemas com mais de dez SOMOs podem aumentar drasticamente o custo; se os
  SOMOs estiverem distribuídos por todo o esqueleto molecular, a truncagem por
  domínios pode perder eficiência.
- O manual cita que DLPNO-CCSD já foi aplicado a sistemas com mais de 1000
  átomos e mais de 20.000 funções de base.

Exemplos de tempo citados no manual:

| Sistema | Método/configuração | Recursos | Tempo |
|---|---|---|---:|
| [NiFe] hidrogenase, 180 átomos | `def2-TZVPP`, `NormalPNO` | 4 cores Xeon E5-2670 | ~45 h |
| OEC, 238 átomos, 13 SOMOs | `def2-TZVPP`, `NormalPNO` | 4 cores Xeon E5-2670 | ~44 h |
| Crambin, >650 átomos | `def2-TZVP`, DLPNO-CCSD(T) | 4 CPUs | ~2 semanas |

Os tempos são exemplos ilustrativos e dependem fortemente do sistema, da base,
do número de processos e do hardware.

## 6. Bases auxiliares e SCF

- DLPNO exige a aproximação RI e, portanto, uma base auxiliar de correlação.
- Exemplo: `def2-tzvpp/C` para o cálculo DLPNO com base `def2-tzvpp`.
- `RIJCOSX` também exige uma auxiliar de Coulomb; no input atual, `def2/J`.
- O input atual já contém:

```text
def2-tzvpp def2-tzvpp/C def2/J
```

- `TightSCF` é coerente com a recomendação de convergência do SCF; o manual
  também observa que a tolerância da localização de orbitais é acoplada à
  tolerância do gradiente SCF por padrão.
- DLPNO funciona com `RIJCOSX`, `RI-JK` e bases ANO.

## 7. Implicações para este repositório

### 7.1 Estado atual

- `jobfile/cjobs_6631.sh`:
  - `--nodes=1`
  - `--ntasks=4`
  - `--mem=80000` MB
  - `--time=720:00:00`
  - `%maxcore 20000` no input
  - `%pal nprocs 4`
  - `MKL_NUM_THREADS=4` e `OMP_NUM_THREADS=4`
- `jobfile/int-1-HH.inp`:
  - `DLPNO-CCSD(T1)`
  - `TightPNO`
  - `TightSCF`
  - `RIJCOSX`
  - `def2-tzvpp def2-tzvpp/C def2/J`

### 7.2 Pontos de atenção

1. **Memória:** `20000 MB × 4 = 80000 MB`, ou seja, 100% do `--mem=80000`.
   Pela regra de 75%, o limite seria `%maxcore 15000`. Alternativamente,
   solicitar cerca de 107 GB de `--mem` para manter 20 GB por processo.
2. **NormalPNO versus TightPNO:** o input atual usa `TightPNO`, não
   `NormalPNO`. Se o objetivo for `NormalPNO`, o keyword deve ser alterado e o
   custo esperado é menor que o de `TightPNO`.
3. **Paralelismo:** 4 processos é coerente com `--ntasks=4`, mas o manual
   sugere que coupled cluster escala bem até 8–16 processos. Aumentar exige
   reajustar `--ntasks`, `%pal`, `%maxcore` e `--mem`.
4. **Threads:** `MKL_NUM_THREADS=4` e `OMP_NUM_THREADS=4` com 4 processos MPI
   podem causar oversubscription. Validar com o ambiente do cluster.
5. **Disco:** o job atual usa scratch, mas a transferência final para `/home`
   ainda é feita com `cp -r`, o que conflita com a diretriz do cluster. O
   resultado deve ser enviado via `rclone` ou empacotado em `.tar.zst`.
6. **Amostras:** os arquivos em `sample-dlpno/` foram gerados com ORCA 5.0.4,
   com `pal8` e `%maxcore 24000`, e mostram pico de memória do MDCI em torno
   de 24,6–26,4 GB. Servem como referência empírica, não como regra do manual
   nem como garantia para o job novo.

## 8. Referências do manual

| Seção | Página impressa | Assunto |
|---|---:|---|
| 1.7.5 — Out of Memory | 14 | `MaxCore`, OOM, aviso e aborto |
| 2.1.3 — Global Memory Use | 23 | `%maxcore` por processo, default, 8 GB/core |
| 2.5 — Parallel and Multi-Process Runs | 39–44 | `PAL`, `%pal`, MPI, scaling, scratch |
| 2.14 — Integral Handling | 145–147 | `MaxDisk`, arquivos temporários, integrais |
| 3.9.10 — Local MP2 (DLPNO-MP2) | 263–266 | thresholds de NormalPNO para DLPNO-MP2 |
| 3.10.10 — Local correlation (DLPNO) | 305–321 | DLPNO, NormalPNO, memória, disco, tempo |
| Tabela 3.40 | 317 | thresholds de DLPNO-CCSD(T) |
| Tabela 3.33 | 266 | thresholds de DLPNO-MP2 |
