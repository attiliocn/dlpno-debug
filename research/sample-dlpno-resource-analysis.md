# Análise de recursos dos outputs DLPNO de amostra

## Escopo

Análise dos dois outputs em `sample-dlpno/`, com foco nos recursos
computacionais efetivamente solicitados e observados:

- `sample-dlpno/bis_int_tbpButTrans_3.out`
- `sample-dlpno/ts-exchg-2_f3_17.out`

Os dois cálculos foram executados com ORCA **5.0.4** dentro do contêiner
`orca_5_0_4_linux_x86-64_shared_openmpi411`, portanto os números servem como
referência empírica para o job novo, mas não substituem medições com ORCA 6.1.1.

Nenhum arquivo de job ou input foi alterado por esta análise. A capacidade do
cluster e a premissa de um scratch por node estão em
`research/cloudufscar-resources.md`.

## Resumo comparativo

| Item | `bis_int_tbpButTrans_3` | `ts-exchg-2_f3_17` |
|---|---|---|
| Método | `DLPNO-CCSD(T1)` | `DLPNO-CCSD(T1)` |
| Precisão PNO | `NormalPNO` | `TightPNO` |
| Base | `def2-QZVPP` | `def2-QZVPP` |
| Auxiliar de correlação | `def2-QZVPP/C` | `def2-TZVPP/C` |
| SCF | `TightSCF RIJCOSX` | `TightSCF RIJCOSX` |
| Auxiliar de Coulomb | `def2/J` | `def2/J` |
| Processos ORCA | 8 MPI | 8 MPI |
| `%maxcore` | 24.000 MB | 24.000 MB |
| Átomos | 52 | 53 |
| Funções de base | 2.313 | 2.397 |
| Elétrons | 200 | 212 |
| Elétrons correlacionados | 148 | 156 |
| Core congelado | 52 elétrons | 56 elétrons |
| Iterações SCF | 25 | 26 |
| Pico de memória no GTOINT | 302,9 MB | 278,9 MB |
| Pico de memória no SCF | 735,4 MB | 765,6 MB |
| Pico de memória no MDCI | 24.562,6 MB | 26.371,3 MB |
| Armazenamento de PNO | disco | disco |
| RI integrals em memória | não | não |
| Tempo SCF | 3.997,4 s (66,6 min) | 1.414,0 s (23,6 min) |
| Tempo MDCI | 150.302,9 s (41,8 h) | 199.652,1 s (55,5 h) |
| Tempo total (`TOTAL RUN TIME`) | 154.343,6 s (42,9 h) | 201.083,2 s (55,9 h) |
| Tempo total formatado | 1 d 18 h 52 min | 2 d 7 h 51 min |
| Fração do MDCI no total | 97,4% | 99,3% |
| Energia final | -1163,250070800 Eh | -1255,369797041 Eh |

Os dois cálculos terminaram normalmente:

```text
****ORCA TERMINATED NORMALLY****
```

## 1. Configuração de execução

Trechos relevantes dos outputs:

- Diretório de execução em `/scratch/...`, coerente com a recomendação de
  scratch local do manual.
- Contêiner: `/opt/chemsoft/orca_5_0_4_linux_x86-64_shared_openmpi411/orca`.
- Input com `! pal8` e `%maxcore 24000`.
- O output confirma:

```text
Program running with 8 parallel MPI-processes
```

- O `MaxCore` configurado é reportado como:

```text
Maximum memory for working arrays ... 24000 MB
```

- O cálculo usa `Shared parallel matrices` e OpenBLAS `SINGLE_THREADED`.
- Não há indicação de uso de memória compartilhada para as integrais do DLPNO:
  `Keep RI integrals in memory ... off`.

## 2. Tamanho do sistema e espaço de orbitais

| Métrica | `bis_int_tbpButTrans_3` | `ts-exchg-2_f3_17` |
|---|---:|---:|
| Átomos | 52 | 53 |
| Funções de base / AO | 2.313 | 2.397 |
| Elétrons | 200 | 212 |
| Elétrons correlacionados | 148 | 156 |
| Core químico congelado | 52 elétrons | 56 elétrons |
| Orbitais internos | 26–99 (74 MOs) | 28–105 (78 MOs) |
| Orbitais virtuais | 100–2312 (2.213 MOs) | 106–2396 (2.291 MOs) |
| Pares de shells primitivos | 615.565 | 666.532 |

Os sistemas são próximos em tamanho, mas o `ts-exchg` tem base efetiva de
correlação menor (`def2-TZVPP/C`) e precisão PNO mais apertada (`TightPNO`).
Ainda assim, foi o cálculo mais caro, principalmente pela correção de triples.

## 3. Recursos e memória observados

### 3.1 Picos por módulo

| Módulo | `bis` | `ts` |
|---|---:|---:|
| GTOINT | 302,9 MB | 278,9 MB |
| SCF | 735,4 MB | 765,6 MB |
| MDCI | 24.562,6 MB | 26.371,3 MB |

O pico do MDCI ficou **acima** do `%maxcore 24000`:

- `bis`: 24.562,6 MB, cerca de **+2,3%** sobre 24.000 MB;
- `ts`: 26.371,3 MB, cerca de **+9,9%** sobre 24.000 MB.

Isso é consistente com o manual, que avisa que o ORCA pode ultrapassar o
`MaxCore` durante a execução. O valor reportado é um pico de memória de
trabalho, não deve ser interpretado automaticamente como consumo total do nó.

### 3.2 Armazenamento em disco

Ambos os cálculos usam:

```text
PNO-Integral Storage ... ON DISK
Keep RI integrals in memory ... off
In-Core Storage of quantities:
   Amplitudes+Sigma Vector ... NO
   J+K operators ... NO
   DIIS vectors ... NO
   3-external integrals ... NO
   4-external integrals ... NO
```

Além disso:

```text
Data storage in matrix containers ... UNCOMPRESSED
Data type for integral storage ... DOUBLE
```

Ou seja, o DLPNO dependeu de armazenamento em disco para as integrais de PNO e
não manteve as principais quantidades em memória. Isso reforça a necessidade de
scratch local com espaço e I/O adequados.

## 4. Tempos por etapa

### 4.1 Visão geral

| Etapa | `bis` | `ts` |
|---|---:|---:|
| Cálculo de integrais GTO | 37,1 s | 13,7 s |
| Iterações SCF | 3.997,4 s (66,6 min) | 1.414,0 s (23,6 min) |
| Módulo MDCI | 150.302,9 s (41,8 h) | 199.652,1 s (55,5 h) |
| Total (`TOTAL RUN TIME`) | 154.343,6 s (42,9 h) | 201.083,2 s (55,9 h) |

Distribuição percentual reportada pelo ORCA:

| Etapa | `bis` | `ts` |
|---|---:|---:|
| GTO integral | 0,0% | 0,0% |
| SCF | 2,6% | 0,7% |
| MDCI | 97,4% | 99,3% |

O MDCI domina praticamente todo o custo. O SCF, embora use `RIJCOSX`, é uma
fração pequena do tempo nesses sistemas.

### 4.2 Breakdown do MDCI

| Etapa do MDCI | `bis` | `ts` |
|---|---:|---:|
| Localização dos MOs ocupados | 25,0 s | 24,1 s |
| Formação da matriz de Fock | 303,2 s | 108,1 s |
| Overlap/Fock/MKN globais | 18,5 s | 8,2 s |
| Integrais de overlap diferencial | 30,4 s | 12,6 s |
| Organização dos mapas | 1,3 s | 0,6 s |
| Geração de integrais RI 3-índices | 2.435,8 s | 580,8 s |
| Transformação RI-PNO | 34.244,7 s (22,8%) | 20.479,5 s (10,3%) |
| Guess inicial | 3.155,2 s (2,1%) | 5.464,7 s (2,7%) |
| Solver DIIS | 3,5 s | 216,8 s |
| Construção do vetor sigma | 6.948,1 s (4,6%) | 18.084,7 s (9,1%) |
| Correção (T) total | 102.902,8 s (68,5%) | 154.841,1 s (77,6%) |
| Pico de memória do MDCI | 24.562,6 MB | 26.371,3 MB |

Observação: o output também mostra `Total PNO integral transformation time`
de 9.912,1 s (`bis`) e 6.110,0 s (`ts`). Esse número tem escopo diferente da
linha `RI-PNO integral transformation` do bloco de timings do MDCI e não deve
ser somado a ela.

### 4.3 Correção de triples

| Parcela | `bis` | `ts` |
|---|---:|---:|
| Tempo T0 | 63.786,7 s | 106.821,6 s |
| Tempo iterativo (T) | 36.484,8 s | 47.408,5 s |
| Tempo total (T) | 102.884,8 s | 154.841,1 s |
| Geração de integrais 3-índices | 48.795,4 s | 65.336,1 s |
| Geração de TNOs | 4.452,1 s | 15.682,8 s |
| Integrais TNO | 49.545,4 s | 65.859,0 s |
| Fração do MDCI | 68,5% | 77,6% |

A correção de triples é a maior parcela do custo nos dois casos. No `ts`, ela
chega a 77,6% do MDCI. O `ts` também tem muito mais triples:

| Item | `bis` | `ts` |
|---|---:|---:|
| Triples a calcular | 12.977 | 40.785 |
| Pares strong/weak | 2.499 / 10.478 | 2.667 / 38.118 |
| Triples com 0 weak pairs | 6.759 | 23.306 |
| Triples com 1 weak pair | 6.218 | 17.479 |

## 5. Footprint de PNO e amplitudes

| Métrica | `bis` | `ts` |
|---|---:|---:|
| Total de PNOs | 37.167 | 71.718 |
| Média de PNOs por par | 39 | 40 |
| Máximo de PNOs por par | 106 | 156 |
| Pares com >96 PNOs | 9 | 191 |
| Amplitudes PNO a otimizar | 1.951.677 | 5.034.288 |
| Amplitudes não-PNO | 4.593.732.122 | 9.221.932.517 |
| Amplitudes regulares sem truncamento | 13.590.198.975 | 16.171.186.161 |
| Iterações CCSD | 13 | 15 |

O `ts` tem quase o dobro de PNOs totais, 50% mais PNOs no pior par e cerca de
2,6× mais amplitudes PNO. Isso ajuda a explicar o maior custo do MDCI e o maior
pico de memória.

## 6. Leitura dos resultados

1. **O MDCI é o recurso dominante.** Nos dois casos ele responde por 97–99% do
   tempo total. Ajustes de SCF ou de integral GTO têm impacto pequeno no tempo
   final.
2. **A correção de triples domina o MDCI.** Ela consome 68,5% (`bis`) e 77,6%
   (`ts`) do tempo do módulo. O `TightPNO` do `ts` está associado a mais
   triples e mais tempo.
3. **O DLPNO usou disco.** `PNO-Integral Storage ... ON DISK` e
   `Keep RI integrals in memory ... off` significam que o scratch precisa de
   espaço e I/O adequados. O manual alerta que o I/O do DLPNO pode ser um
   gargalo.
4. **O pico de memória do MDCI ficou próximo ou acima do `MaxCore`.** O caso
   `ts` ultrapassou 24 GB em cerca de 10%. Isso justifica manter margem entre
   `MaxCore × nprocs` e a memória total solicitada ao Slurm.
5. **Os dois cálculos usaram 8 processos MPI.** Eles não validam diretamente a
   configuração atual de 4 processos do `jobfile`; servem como referência de
   tempo e memória para uma execução com `pal8`.
6. **A versão é ORCA 5.0.4.** O job novo usa ORCA 6.1.1; diferenças de
   implementação, thresholds default e eficiência podem alterar tempos e
   memória.

## 7. Comparação com o job atual do repositório

Configuração atual:

- `jobfile/cjobs_6631.sh`: `--ntasks=4`, `--mem=80000`, `--time=720:00:00`.
- `jobfile/int-1-HH.inp`: `%maxcore 20000`, `%pal nprocs 4`,
  `DLPNO-CCSD(T1)`, `TightPNO`, `def2-tzvpp`, `def2-tzvpp/C`, `def2/J`.

Comparação:

| Item | Amostras | Job atual |
|---|---|---|
| Processos | 8 | 4 |
| `%maxcore` | 24.000 MB | 20.000 MB |
| Memória Slurm | não disponível no output | 80.000 MB |
| Precisão PNO | `NormalPNO` e `TightPNO` | `TightPNO` |
| Base | `def2-QZVPP` | `def2-TZVPP` |
| Átomos | 52–53 | 49 |
| Tempo total | 42,9–55,9 h | walltime 720 h |

O walltime de 720 h é bastante folgado em relação às amostras. Entretanto, a
configuração atual não é uma reprodução das amostras: usa 4 processos em vez de
8, `MaxCore` diferente, base menor e o mesmo `TightPNO` do caso mais caro. Os
números das amostras devem ser usados como ordem de grandeza, não como
previsão direta.

## 8. Referências nos outputs

`bis_int_tbpButTrans_3.out`:

| Informação | Linhas |
|---|---|
| Cabeçalho, usuário e scratch | 1–6 |
| `%maxcore 24000` | 193 |
| 8 processos MPI | 683, 776 |
| Átomos e funções de base | 716–717 |
| Memória GTOINT | 772 |
| Memória SCF | 5734 |
| PNO em disco | 5769 |
| Memória de trabalho / in-core | 5789–5800 |
| PNOs totais e máximos | 6380–6401 |
| RI integrals fora de memória | 6407 |
| Amplitudes PNO | 6440–6442 |
| Triples | 6495–6608 |
| Memória máxima do MDCI | 6653 |
| Timings finais | 6718–6723 |

`ts-exchg-2_f3_17.out`:

| Informação | Linhas |
|---|---|
| Cabeçalho, usuário e scratch | 1–6 |
| `%maxcore 24000` | 193 |
| 8 processos MPI | 691, 784 |
| Átomos e funções de base | 724–725 |
| Memória GTOINT | 780 |
| Memória SCF | 5899 |
| PNO em disco | 5934 |
| Memória de trabalho / in-core | 5954–5965 |
| PNOs totais e máximos | 6581–6603 |
| RI integrals fora de memória | 6609 |
| Amplitudes PNO | 6642–6644 |
| Triples | 6699–6818 |
| Memória máxima do MDCI | 6863 |
| Timings finais | 6928–6933 |
