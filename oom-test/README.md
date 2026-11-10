# Teste de falha por OOM

Este diretório contém um kit para reproduzir uma falha por falta de memória
(OOM) no fluxo do `slurm-dlpno.sh`, sem executar o ORCA real.

O teste usa uma cópia de trabalho em `work/` e um `singularity` falso que
tenta alocar 4 GiB. O cgroup do Slurm deve matar o processo.

## Arquivos

- `fake-singularity` — executável falso que aloca memória via Python.
- `fixtures/` — cópia de fallback dos scripts e do input, usada quando este
  diretório é copiado sozinho para o HPC, sem o restante do repositório.
- `setup-oom-test.sh` — cria `work/`, copia os scripts de produção (ou os
  fixtures), ajusta `ctPath` para um SIF vazio e executa o `prepare-job.sh`.
- `submit-oom-test.sh` — submete o job com `--mem` baixo e o `PATH` apontando
  para o `singularity` falso.
- `work/` — área descartável criada pelo setup; não versionada.

## Uso no HPC

```bash
./setup-oom-test.sh
./submit-oom-test.sh <partition>
```

O padrão é:

```text
--mem=1G
--time=00:10:00
```

Para mudar:

```bash
./submit-oom-test.sh <partition> 2G 00:20:00
```

O valor de `--mem` precisa ser menor que a memória que o
`fake-singularity` tenta alocar. Por padrão, 1 GiB de limite contra 4 GiB de
alocação.

Para alterar a alocação do fake:

```bash
OOM_ALLOC_GB=8 ./submit-oom-test.sh <partition> 2G
```

## O que esperar

- O job deve terminar com estado `OUT_OF_MEMORY`.
- O exit code deve ser `137` ou `0:9`.
- O stdout final do Slurm deve existir como `work/water1_<jobid>.stdout`.
- Se o shell sobreviver ao OOM, deve ser criado
  `work/water1_<jobid>_failed.tar.gz`.
- Se o OOM matar o job inteiro com `SIGKILL`, o `trap` do script não roda:
  o scratch pode permanecer e o archive `_failed` pode não existir.

Verificação:

```bash
sacct -j <jobid> --format=JobID,JobName,State,ExitCode,ReqMem,MaxRSS,Elapsed,NodeList
seff <jobid>
ls -lh work
tar tzf work/water1_<jobid>_failed.tar.gz
```

## Limitações

- O teste não valida o consumo real do ORCA; ele valida o comportamento do
  script quando o processo é morto por OOM.
- O `ctPath` é substituído por um arquivo vazio na cópia de teste; o
  `singularity` falso ignora o conteúdo.
- É necessário `python3` no nó de execução.
- Execute apenas em uma partição Slurm, nunca no nó de login.
