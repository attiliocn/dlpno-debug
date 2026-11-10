# `cjobs_6631.sh`

> **Nota de versionamento:** este README documenta o script **original**
> `cjobs_6631.sh`. A cópia de trabalho é `slurm-dlpno.sh`, acompanhada de
> `slurm-dlpno.csv`. Os arquivos `cjobs_6631.sh` e `cjobs_joblist.csv`
> permanecem preservados como referência. A cópia de trabalho já difere do
> original; as diferenças estão na seção
> [Diferenças da cópia de trabalho](#diferenças-da-cópia-de-trabalho).

## Visão geral

`cjobs_6631.sh` é o script de submissão Slurm usado para executar um cálculo
DLPNO com ORCA 6.1.1 em um contêiner Singularity no CloudUFSCar.

O script:

1. sincroniza o contêiner do ORCA a partir de um remote `rclone`;
2. cria um diretório de execução exclusivo em `/scratch`;
3. lê o nome do input em `cjobs_joblist.csv`;
4. copia o input para o diretório do job;
5. executa o ORCA dentro do contêiner;
6. ao final, copia a pasta de resultados para `localDir` e remove o scratch.

O fluxo foi escrito para **um job por array task** e, na configuração atual, para
**um único job** (`--array=1-1` e um único registro no CSV).

## Arquivos e layout esperado

O script assume que `localDir` contém:

```text
$localDir/
  cjobs_6631.sh
  cjobs_joblist.csv
  int-1-HH.inp
```

O CSV não tem cabeçalho e usa o formato:

```csv
1,int-1-HH.inp
```

- coluna 1: índice/linha do job;
- coluna 2: nome do arquivo de entrada ORCA.

O script copia `cjobs_*.sh`, `cjobs_joblist.csv` e o input para o scratch; ele
**não lê o input diretamente do diretório de submissão**.

## Recursos solicitados ao Slurm

| Diretiva | Valor atual | Observação |
|---|---|---|
| `--job-name` | `6631` | Nome exibido no Slurm e usado em `%x` |
| `--output` | `cjobs_log_%x_%J.stdout` | Log do Slurm no diretório de submissão |
| `--nodes` | `1` | Execução em node único |
| `--ntasks` | `4` | Deve coincidir com `%pal nprocs` |
| `--mem` | `80000` MB | Memória total reservada para o job |
| `--time` | `720:00:00` | 720 horas de walltime |
| `--array` | `1-1` | Uma única task |
| `--signal` | `B:TERM@60` | Envia `SIGTERM` 60 s antes do fim do walltime |

O script também declara:

```bash
allocCPU=4
allocRAM=20000
```

Esses valores são apenas informativos/legados; quem realmente define os
recursos é o cabeçalho `#SBATCH` e, no caso do ORCA, `%pal` e `%maxcore` no
arquivo `.inp`. Na cópia de trabalho, `allocCPU`, `allocRAM` e `numjobs` foram
removidos por não serem usados.

## Variáveis de configuração

| Variável | Valor atual | Função |
|---|---|---|
| `g16GID` | `2111` | GID usado no diretório de contêineres |
| `localDir` | `/home/u831869/run/slurm-dlpno` | Diretório local com script, CSV e inputs |
| `scrDir` | `/scratch` | Base do lock de sincronização |
| `usrScrDir` | `/scratch/$USER` | Definida, mas não usada |
| `exeDir` | `/scratch/$USER/jobs/$SLURM_JOB_ID` | Diretório de execução do job |
| `ctDirRemote` | `sintcatmol:containers` | Remote `rclone` dos contêineres |
| `ctDirLocal` | `/scratch/$USER/containers` | Cópia local dos contêineres |
| `ct` | `orca-611_...sif` | Definida, mas não usada diretamente |
| `ctPath` | `/scratch/$USER/containers/orca-611_...sif` | Caminho efetivo do contêiner |

> Esta tabela descreve o script original. Na cópia de trabalho, `g16GID`,
> `scrDir`, `usrScrDir`, `ctDirRemote`, `ctDirLocal`, `ct`, `allocCPU`,
> `allocRAM` e `numjobs` foram removidos; ver a seção de diferenças.

Atenção: `localDir` está com um caminho de usuário fixo
(`/home/u831869/run/slurm-dlpno`). Ele precisa ser ajustado para o usuário e o
diretório reais antes da submissão.

## Fluxo de execução

### 1. Trap de limpeza

```bash
trap clean_job EXIT HUP INT TERM ERR
```

A função `clean_job` é chamada em saída normal e em sinais. Ela:

- copia os subdiretórios de `$exeDir` para `$localDir`;
- remove `$exeDir` com `rm -vrf`.

Não há verificação explícita do status do `cp` antes do `rm`; uma falha de
cópia pode levar à remoção do scratch mesmo assim.

### 2. Sincronização do contêiner

O script:

1. adquire um lock em `/scratch/${USER}_sync.lock`;
2. espera até 3.600 s se o lock estiver ocupado;
3. cria/ajusta `/scratch/$USER/containers` com o GID `2111`;
4. executa `rclone sync` do remote `sintcatmol:containers`;
5. grava `/scratch/$USER/last_sync.lock`;
6. libera o lock.

A sincronização é feita no máximo uma vez por semana, controlada pela idade de
`last_sync.lock`:

```text
604800 segundos = 7 dias
```

Se `rclone` não estiver disponível, a sincronização é ignorada; o script segue
com o contêiner já existente em `ctPath`.

Atenção: `create_directory_with_group_ownership` pode aplicar
`chown -R :2111 /scratch/$USER` quando o diretório de contêineres ainda não
existe. Isso altera o grupo de todo o conteúdo do usuário em `/scratch`.

### 3. Criação do diretório do job

```bash
exeDir="/scratch/$USER/jobs/$SLURM_JOB_ID"
mkdir -p "$exeDir"
```

O script copia para `$exeDir`:

```text
cjobs_*.sh
cjobs_joblist.csv
```

O diretório é único por `SLURM_JOB_ID`. Com um scratch por node e execução em
node único, todos os ranks MPI compartilham esse mesmo diretório.

### 4. Seleção do input

O input é obtido com:

```bash
job=$(get_csv_element cjobs_joblist.csv "$SLURM_ARRAY_TASK_ID" 2)
```

Para a linha 1 do CSV, o resultado é `int-1-HH.inp`.

O basename é calculado removendo a extensão:

```text
int-1-HH.inp -> int-1-HH
```

Em seguida, o script cria `$exeDir/int-1-HH`, copia o input para lá e entra
nesse diretório.

### 5. Execução do ORCA

Variáveis de execução:

```bash
export MKL_NUM_THREADS=4
export OMP_NUM_THREADS=4
export OMP_STACKSIZE=4G
ulimit -s unlimited
```

Comando:

```bash
singularity run \
  --bind="$PWD":"$PWD" \
  "$ctPath" \
  "$PWD" \
  "$job" 1> "$basename".out 2> stderr.log &
wait
```

O contêiner recebe:

- `$PWD`: diretório de trabalho do job;
- `$job`: nome do input ORCA.

O stdout do ORCA vai para `$basename.out`; o stderr vai para `stderr.log`.

### 6. Finalização

Após o `wait`, o script volta para `$exeDir`. O trap de `EXIT` executa a limpeza
e copia a pasta do job para `localDir`.

## Relação com o input ORCA

O input atual em `int-1-HH.inp` usa:

```text
! DLPNO-CCSD(T1) TightPNO TightSCF RIJCOSX def2-tzvpp def2-tzvpp/C def2/J
%maxcore 20000
%pal nprocs 4
```

Portanto:

- `--ntasks=4` deve coincidir com `%pal nprocs 4`;
- `%maxcore 20000` é por processo;
- com 4 processos, o teto teórico é `20000 × 4 = 80000 MB`, exatamente o
  `--mem=80000` solicitado;
- o manual do ORCA recomenda `MaxCore × nprocs ≤ 0,75 × RAM disponível`, o que
  sugeriria `%maxcore 15000` para 80 GB, ou aumentar `--mem` para cerca de
  107 GB;
- `MKL_NUM_THREADS=4` e `OMP_NUM_THREADS=4` com 4 processos MPI podem causar
  oversubscription; validar com o ambiente do cluster.

## Saídas e logs

- Log do Slurm: `cjobs_log_6631_<JOBID>.stdout`, no diretório de submissão.
- Saída do ORCA: `<basename>.out`, dentro de `$exeDir/<basename>/`.
- Erros do ORCA/contêiner: `stderr.log`, dentro do diretório do job.
- Resultados copiados para `$localDir` pelo trap de limpeza.

## Pré-requisitos

- Slurm com `sbatch`, `squeue` etc.
- `bash`, `flock`, `sed`, `awk`, `cp`, `rm`.
- `rclone` configurado com o remote `sintcatmol` (ou ajuste de
  `ctDirRemote`).
- Singularity disponível no path; se o ambiente usar apenas Apptainer, ajustar
  o comando.
- Acesso de escrita a `/scratch/$USER`.
- Grupo/GID `2111` disponível para o usuário, ou ajuste de `g16GID`.
- Contêiner ORCA 6.1.1 presente em `ctPath` ou sincronizável via `rclone`.
- `localDir` com o script, o CSV e o input.

## Submissão

Depois de ajustar `localDir`, o nome do job, o contêiner e os caminhos:

```bash
sbatch jobfile/cjobs_6631.sh
squeue -u "$USER"
```

O log do Slurm pode ser acompanhado com:

```bash
tail -f cjobs_log_6631_<JOBID>.stdout
```

## Pontos de atenção do script original

1. **Transferência para `/home`:** a limpeza usa `cp -r` para `localDir`, que
   atualmente aponta para `/home/...`. Isso conflita com a diretriz do cluster
   de enviar resultados via `rclone` ou compactar em `.tar.zst`.
2. **Status de saída:** o resultado de `wait`/`singularity` não é verificado
   explicitamente; o script pode terminar sem propagar uma falha do ORCA.
3. **Limpeza agressiva:** o trap roda em `EXIT` e remove `$exeDir`; não há
   confirmação de que a cópia dos resultados foi bem-sucedida.
4. **Caminho fixo de usuário:** `localDir` contém `/home/u831869/...`; ajustar
   para o usuário real.
5. **Recursos:** `--mem=80000`, `%maxcore 20000` e 4 processos não respeitam a
   margem de 75% recomendada pelo manual do ORCA.
6. **Threads:** `MKL_NUM_THREADS=4`/`OMP_NUM_THREADS=4` com 4 ranks MPI pode
   oversubscribe as 4 CPUs.
7. **Multi-node:** o script é single-node e pressupõe um scratch por node;
   não deve ser adaptado para múltiplos nodes sem revisar o compartilhamento de
   scratch e o paralelismo.
8. **Variáveis não usadas:** `allocCPU`, `allocRAM`, `usrScrDir`, `ct`,
   `numjobs` e `job_number` não participam da lógica principal.

## Diferenças da cópia de trabalho

A cópia de trabalho preserva o fluxo geral do original, mas já recebeu as
seguintes alterações:

| Item | Original | Cópia de trabalho |
|---|---|---|
| Partition | ausente | `#SBATCH --partition=slow` |
| Sincronização do contêiner | `rclone` + lock + GID | removida; container fixo em `ctPath` |
| Variáveis não usadas | `allocCPU`, `allocRAM`, `numjobs` | removidas; loop usa `_` |
| `localDir` | `/home/u831869/run/slurm-dlpno` | `/home/$USER/run/slurm-dlpno` |
| Script copiado para o scratch | `cjobs_*.sh` | `slurm-dlpno.sh` |
| CSV usado | `cjobs_joblist.csv` | `slurm-dlpno.csv` |
| Finalização | `cp -r` para `localDir` | arquivo `.tar.zst` em `localDir` |
| Limpeza | sempre remove o scratch | remove apenas após arquivar com sucesso |
| Status do ORCA | não verificado | verifica `wait` e `ORCA TERMINATED NORMALLY` |
| Verbosidade | echos esparsos | echos de contexto, caminhos, PID, status, arquivo e limpeza |

Detalhes:

- Em terminação normal, o arquivo gerado é:

```text
$localDir/job_${SLURM_JOB_ID}.tar.zst
```

- Em terminação anormal, o arquivo gerado é:

```text
$localDir/job_${SLURM_JOB_ID}_failed.tar.zst
```

- O comando de arquivamento segue a recomendação de `docs/andre-email.txt`:

```bash
tar -I "zstd -T${SLURM_CPUS_PER_TASK:-2} -1" \
    -cf "$archive" -C "$exeDir" "$basename/"
```

- Se o `tar` falhar, o scratch é mantido para inspeção e o script termina com
  status de erro.
- A cópia de trabalho exige `zstd` e `tar` disponíveis no ambiente.
- O container do ORCA não é mais sincronizado. Ele deve existir previamente em:

```text
/scratch/$USER/containers/orca-611_2025-12-16_19-01-10_orca611.sif
```

- O script verifica a existência do container com `-f` e aborta se ele não
  estiver disponível.
- Não são necessários `rclone`, `flock`, `chown` ou `chmod` para a cópia de
  trabalho.
- `allocCPU`, `allocRAM` e `numjobs` foram removidos; o laço único usa
  `for _ in 0`, sem variável de índice não utilizada.
- A cópia de trabalho emite echos de progresso no stdout do Slurm: contexto do
  job, diretórios, cópia de arquivos, input selecionado, PID e status do ORCA,
  marcador de terminação, arquivamento e limpeza. Esses echos não vão para o
  `<basename>.out` do ORCA.
- `localDir` deve conter `slurm-dlpno.sh`, `slurm-dlpno.csv` e o input.
- A submissão da cópia de trabalho é feita com:

```bash
sbatch jobfile/slurm-dlpno.sh
```

O restante deste README continua descrevendo o comportamento do script
original `cjobs_6631.sh`.

## Referências internas

- `research/cloudufscar-resources.md` — capacidade dos nodes, scratch por node e
  premissa de node único.
- `research/orca-dlpno-resources.md` — regras de memória, paralelismo e disco do
  ORCA para DLPNO/NormalPNO.
- `research/sample-dlpno-resource-analysis.md` — tempos e memória observados
  nos outputs de referência.
- `docs/andre-email.txt` — diretriz de transferência de resultados e limpeza do
  scratch.
