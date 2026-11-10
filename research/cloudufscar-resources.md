# Recursos do CloudUFSCar e premissas de execução

## Fonte

Snapshot de recursos do cluster em `docs/cloudufscar-resources.txt`, com saída
no formato do comando `sinfo`.

Premissas adicionais confirmadas para este projeto:

- o Slurm do ambiente é configurado com **um scratch por node**;
- o script de submissão usará **um único node**;
- todos os processos MPI do ORCA devem, portanto, compartilhar o mesmo
  diretório de scratch do node.

Este documento não altera o `jobfile`. Ele registra a capacidade observada do
cluster e as consequências dessas premissas para o cálculo DLPNO.

## Capacidade observada

Interpretação das colunas do snapshot:

- `CPUS(A/I/O/T)` = CPUs alocadas / idle / outras / total;
- `MEMORY` e `FREE_MEM` estão em MB;
- `GRES` lista recursos genéricos, como GPUs;
- o snapshot é pontual e pode não representar a disponibilidade futura.

| Node(s) | CPUs totais | Memória (MB) | Memória aproximada | GRES | Estado no snapshot |
|---|---:|---:|---:|---|---|
| c1–c9, c12–c15, c17–c18 | 40 | 386.700 | ~377,6 GiB | nenhum | allocated |
| c16 | 40 | 386.700 | ~377,6 GiB | nenhum | mixed (38 alocadas, 2 idle) |
| c11 | 40 | 322.100 | ~314,6 GiB | 2 GPUs Turing | down |
| c23 | 96 | 2.064.140 | ~1,97 TiB | nenhum | allocated |

Observações:

- A maior parte dos nodes regulares tem **40 CPUs** e cerca de **386,7 GB**
  de memória.
- O node `c23` tem **96 CPUs** e cerca de **2,06 TB** de memória.
- O node `c11` tem duas GPUs Turing, mas estava **down** no snapshot.
- Não há indicação de GPUs disponíveis nos demais nodes.
- No momento do snapshot, quase todos os nodes estavam alocados; a
  disponibilidade real deve ser consultada antes da submissão.

## Consequências do scratch único por node

### 1. Um diretório compartilhado, não um scratch por rank

Com um scratch por node, todos os processos ORCA do job enxergam o mesmo
diretório. Isso é compatível com o caso que o manual do ORCA chama de
“working on a common directory”, desde que todos os processos estejam no mesmo
node.

Implicações:

- o diretório de execução deve ser único por job;
- não usar o mesmo caminho para jobs simultâneos no mesmo node;
- o `jobfile` atual já usa um diretório específico por job:

```text
/scratch/$USER/jobs/$SLURM_JOB_ID
```

- esse padrão evita colisão entre jobs que eventualmente compartilhem o mesmo
  node e o mesmo filesystem de scratch.

### 2. Single node no Slurm

O script deve manter:

```bash
#SBATCH --nodes=1
```

Consequências:

- todos os ranks MPI ficam no mesmo node;
- `%pal nprocs` deve caber nos CPUs alocados nesse node;
- `--ntasks` deve corresponder ao número de processos MPI do ORCA;
- não é necessário configurar `machinefile`/`nodefile` para múltiplos nodes;
- não se deve planejar um `%pal` que dependa de recursos de outros nodes.

### 3. Memória compartilhada do ORCA

O manual do ORCA permite tentar manter integrais em memória compartilhada com:

```text
%mdci
  StorageType Shared
end
```

Essa opção só funciona se todos os processos estiverem no mesmo node. Com a
premissa de single node, ela é tecnicamente compatível. Entretanto:

- só deve ser usada se houver RAM suficiente;
- se a memória não bastar, o ORCA volta para disco;
- o `MaxCore` e o `--mem` do Slurm continuam precisando ser dimensionados
  corretamente;
- o caso atual dos samples usou PNO em disco e `Keep RI integrals in memory`
  desligado, portanto não há evidência de que `StorageType Shared` seja
  necessário para o job atual.

### 4. I/O de disco

Como o DLPNO pode usar disco intensivamente, o scratch único por node precisa
comportar:

- arquivos temporários do ORCA;
- integrais de PNO;
- arquivos de restart e saída;
- resultados que serão posteriormente compactados ou enviados para a nuvem.

O `jobfile` atual executa em `/scratch` e depois copia resultados para `/home`
com `cp -r`. Essa última parte conflita com a diretriz do cluster e deve ser
substituída por `rclone` ou por um pacote `.tar.zst`.

## Dimensionamento para o job atual

Configuração atual do script/input:

- `--nodes=1`;
- `--ntasks=4`;
- `--mem=80000` MB;
- `%pal nprocs 4`;
- `%maxcore 20000` MB.

Capacidade dos nodes regulares:

- 40 CPUs e ~386,7 GB por node;
- o job de 4 ranks e 80 GB cabe com folga no node;
- o `--mem` do Slurm, entretanto, reserva 80 GB para o job; a regra do ORCA
  continua sendo `MaxCore × nprocs ≤ 0,75 × memória disponível para o job`.

Com 4 ranks e 80 GB reservados:

```text
%maxcore ≤ 15000 MB
```

para respeitar a regra de 75%. Alternativamente, aumentar `--mem` para cerca
de 107 GB mantendo `%maxcore 20000`.

Se o job for ampliado para 8 ranks no mesmo node:

- `--ntasks=8` e `%pal nprocs 8` devem ser ajustados juntos;
- com 80 GB de `--mem`, `%maxcore` deve cair para cerca de 7.500 MB;
- com 160 GB de `--mem`, `%maxcore` pode ficar em cerca de 15.000 MB;
- um node regular de 40 CPUs/386,7 GB comporta 8 ranks, mas a memória
  reservada precisa ser coerente.

O node `c23` (96 CPUs, ~2 TB) também é single-node e poderia hospedar jobs
maiores, mas a escolha de node não altera a regra de um scratch por node nem a
necessidade de um diretório exclusivo por job.

## Checklist para o script de submissão

- [ ] manter `--nodes=1`;
- [ ] garantir que `--ntasks` e `%pal nprocs` sejam iguais;
- [ ] garantir `%maxcore × nprocs ≤ 0,75 × --mem`;
- [ ] usar um diretório exclusivo em `/scratch/$USER/jobs/$SLURM_JOB_ID`;
- [ ] não compartilhar o diretório de scratch com outro job;
- [ ] executar o ORCA no scratch local, não em `/home`;
- [ ] ao final, enviar resultados via `rclone` ou compactar em `.tar.zst`;
- [ ] remover o diretório de scratch ao final;
- [ ] não assumir múltiplos nodes nem scratch privado por rank;
- [ ] se usar `%mdci StorageType Shared`, confirmar RAM suficiente e single node.

## Relação com os outros documentos

- `research/orca-dlpno-resources.md` — regras do manual ORCA para memória,
  paralelismo, disco e DLPNO/NormalPNO.
- `research/sample-dlpno-resource-analysis.md` — tempos e memória observados
  nos dois outputs de referência.
- `docs/andre-email.txt` — diretriz do cluster para transferência de resultados
  e limpeza do scratch.
- `docs/cloudufscar-resources.txt` — snapshot bruto de recursos usado aqui.
