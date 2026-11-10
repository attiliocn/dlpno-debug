# HISTORY.md

Memória do projeto: registro cronológico de decisões, mudanças e estado dos
arquivos.

## 2026-11-10 — Documentação inicial do objetivo

- Criado `AGENTS.md` documentando o objetivo do projeto: ajustar o `jobfile`
  para as novas diretrizes do Cluster UFSCar e garantir o funcionamento do
  cálculo DLPNO no ORCA.
- Registrado o conteúdo do repositório:
  - `jobfile/cjobs_6631.sh`, `jobfile/cjobs_joblist.csv`,
    `jobfile/int-1-HH.inp`;
  - `sample-dlpno/bis_int_tbpButTrans_3.out` e
    `sample-dlpno/ts-exchg-2_f3_17.out`;
  - `docs/orca_manual_6_1_1.pdf` e `docs/andre-email.txt`.
- Verificado que os dois exemplos em `sample-dlpno/` terminaram normalmente
  (`****ORCA TERMINATED NORMALLY****`), com tempos totais de aproximadamente
  1 dia 18 h 52 min e 2 dias 7 h 51 min.
- Identificado que o script atual ainda copia resultados diretamente para o
  `/home` com `cp -r`, em desacordo com a nova diretriz de compactação em
  `.tar.zst` ou envio via `rclone`.
- Nenhuma alteração foi feita no `jobfile`, no `.inp` ou nos demais arquivos
  funcionais. O projeto permanece no estado inicial, apenas documentado.

## 2026-11-10 — Ambiente Python e recursos DLPNO

- Registrado em `AGENTS.md` que Python deve ser executado no ambiente default
  do mamba (atualmente `base`, em `/home/attilio/opt/miniforge3`), sem criar
  ambientes ad hoc.
- Revisado o manual ORCA 6.1.1 (§1.7.5, §2.1.3, §2.5 e §3.10.10) e registradas
  as referências de recursos para DLPNO com `NormalPNO`: thresholds default,
  `MaxCore` por processo, regra de 75% da RAM, recomendação de pelo menos
  8 GB/core, paralelismo e uso de scratch local.
- Criado `research/orca-dlpno-resources.md` com a pesquisa detalhada sobre
  recursos do ORCA para DLPNO/NormalPNO, incluindo tabelas de thresholds,
  dimensionamento de memória, paralelismo, disco/scratch, tempos de referência
  e implicações para o `jobfile` atual.
- Atualizado `AGENTS.md` para incluir o novo documento em `research/`.

## 2026-11-10 — Análise de recursos dos outputs de amostra

- Criado `research/sample-dlpno-resource-analysis.md` com a análise dos dois
  outputs em `sample-dlpno/`.
- Verificado que ambos usaram ORCA 5.0.4, `! pal8` e `%maxcore 24000`; o pico
  de memória do MDCI foi de 24.562,6 MB e 26.371,3 MB, acima do `MaxCore`
  configurado.
- Registrados os tempos, o breakdown do MDCI e da correção de triples, o uso de
  PNO em disco, os totais de PNO/amplitudes e a comparação com o job atual.
- Nenhuma alteração funcional foi feita no `jobfile` ou nos inputs.

## 2026-11-10 — Recursos do CloudUFSCar e scratch por node

- Criado `research/cloudufscar-resources.md` com a capacidade observada em
  `docs/cloudufscar-resources.txt`.
- Documentado que o Slurm do ambiente usa um scratch por node e que o job será
  executado em node único (`--nodes=1`), com todos os ranks MPI compartilhando
  o mesmo diretório de scratch.
- Registradas as implicações para diretório exclusivo por job, `%pal`/`--ntasks`,
  memória, `StorageType Shared`, I/O de disco e transferência final.
- Atualizados `AGENTS.md` e os documentos de pesquisa com referências cruzadas.

## 2026-11-10 — README do script de submissão

- Criado `jobfile/README.md` documentando `jobfile/cjobs_6631.sh`: recursos
  Slurm, variáveis, sincronização do contêiner, seleção do input, execução do
  ORCA, logs, limpeza do scratch e pré-requisitos.
- Registrados os pontos de atenção atuais: `localDir` fixo, cópia para `/home`
  em desacordo com a diretriz do cluster, ausência de verificação do status do
  ORCA, risco na limpeza do scratch, inconsistência `%maxcore`/`--mem` e
  possível oversubscription de threads.
- Adicionado `jobfile/README.md` à lista de conteúdos do `AGENTS.md`.

## 2026-11-10 — Original preservado e cópia de trabalho

- Definido que `jobfile/cjobs_6631.sh` e `jobfile/cjobs_joblist.csv` são os
  originais preservados e documentados; eles não devem ser editados.
- Criados `jobfile/slurm-dlpno.sh` e `jobfile/slurm-dlpno.csv` como cópias de
  trabalho. No momento da criação, são idênticos aos originais (`diff` vazio).
- As próximas alterações funcionais serão feitas em `slurm-dlpno.sh` e
  `slurm-dlpno.csv`.
- `jobfile/README.md` continua documentando o original `cjobs_6631.sh`; foi
  adicionada uma nota indicando qual é a cópia de trabalho.
- `AGENTS.md` foi atualizado com a regra de não editar os arquivos originais.

## 2026-11-10 — Opção de partition no script de trabalho

- Adicionada a diretiva `#SBATCH --partition=cpu` em
  `jobfile/slurm-dlpno.sh`, com comentário para ajuste ao nome real da
  partição do CloudUFSCar.
- O script original `jobfile/cjobs_6631.sh` permaneceu inalterado.
- `jobfile/README.md` foi atualizado para registrar a diferença entre o
  original e a cópia de trabalho.
- `bash -n jobfile/slurm-dlpno.sh` executado com sucesso.

## 2026-11-10 — Arquivamento dos resultados em tar.zst

- Alterada a cópia de trabalho `jobfile/slurm-dlpno.sh` para arquivar os
  resultados em `$localDir/job_${SLURM_JOB_ID}.tar.zst` ao final de uma
  execução normal, seguindo a recomendação de `docs/andre-email.txt`.
- Em terminação anormal, o arquivo gerado é
  `$localDir/job_${SLURM_JOB_ID}_failed.tar.zst`; se o `tar` falhar, o scratch
  é mantido para inspeção e o script termina com erro.
- A detecção de sucesso passou a verificar o status de `wait` e a presença de
  `****ORCA TERMINATED NORMALLY****` no output.
- `localDir` foi alterado para `/home/$USER/run/slurm-dlpno`; o script copia e
  lê `slurm-dlpno.sh`/`slurm-dlpno.csv`.
- A partition atual da cópia de trabalho é `slow`; `jobfile/README.md` foi
  atualizado com uma seção de diferenças em relação ao original.
- `bash -n jobfile/slurm-dlpno.sh` executado com sucesso.

## 2026-11-10 — Remoção da sincronização de containers

- Removidas de `jobfile/slurm-dlpno.sh` as funções de lock e sincronização de
  containers: `acquire_lock`, `release_lock`, `attempt_acquire_lock`,
  `create_directory_with_group_ownership` e `fetch_containers_from_drive`.
- Removidas as variáveis associadas: `g16GID`, `scrDir`, `usrScrDir`,
  `ctDirRemote`, `ctDirLocal` e `ct`.
- O container do ORCA permanece em caminho fixo:
  `/scratch/$USER/containers/orca-611_2025-12-16_19-01-10_orca611.sif`.
- Adicionada verificação `[[ -f "$ctPath" ]]`; se o container não existir, o
  script aborta antes de criar o diretório do job.
- `jobfile/README.md` e `AGENTS.md` foram atualizados; `bash -n` passou.

## 2026-11-10 — Remoção de variáveis não usadas

- Removidas de `jobfile/slurm-dlpno.sh` as variáveis `allocCPU`, `allocRAM` e
  `numjobs`, que não eram utilizadas na lógica do script.
- O laço único passou de `for job_number in 0` para `for _ in 0`, eliminando a
  variável de índice sem uso.
- `jobfile/README.md` foi atualizado para registrar a remoção.
- `bash -n jobfile/slurm-dlpno.sh` executado com sucesso.

## 2026-11-10 — Aumento da verbosidade do runtime

- Adicionados echos de progresso em `jobfile/slurm-dlpno.sh`: contexto do job
  Slurm, horário, host, diretórios, verificação do container, cópia de arquivos,
  input selecionado, criação do job, variáveis de threads, PID/status do ORCA,
  marcador de terminação, arquivamento e limpeza.
- Os echos são enviados ao stdout do job, portanto aparecem no log do Slurm e
  não no `<basename>.out` do ORCA.
- `jobfile/README.md` foi atualizado na seção de diferenças da cópia de trabalho.
- `bash -n jobfile/slurm-dlpno.sh` executado com sucesso.

## 2026-11-10 — Script de preparação de job

- Criado `jobfile/prepare-job.sh` para configurar a cópia de trabalho a partir
  de um nome de job e de uma lista opcional de inputs.
- O script preenche `slurm-dlpno.csv`, atualiza `--job-name`, ajusta
  `--output=<job-name>_%J.stdout` e define `--array=1-<nº de inputs>`.
- Sem inputs explícitos, usa `<job-name>.inp`; com múltiplos inputs, gera uma
  linha por input e ajusta a array para `1-N`.
- O script valida nomes e verifica a existência dos inputs no diretório de
  `jobfile/`; os arquivos originais permanecem intactos.
- Testado em diretório temporário com um e com múltiplos inputs; `bash -n`
  passou.

## 2026-11-10 — Reorganização da cópia de trabalho

- Movidos os arquivos editáveis para `jobfile/slurm-dlpno/`:
  `slurm-dlpno.sh`, `slurm-dlpno.csv` e `prepare-job.sh`.
- O script `prepare-job.sh` passou a procurar os inputs no próprio diretório ou
  no diretório pai (`jobfile/`), permitindo configurar jobs com os inputs
  existentes ao lado dos scripts originais.
- `AGENTS.md` e `jobfile/README.md` foram atualizados com os novos caminhos.
- `bash -n` passou em `prepare-job.sh` e `slurm-dlpno.sh`; o fluxo de
  configuração com um e com múltiplos inputs foi testado em diretório
  temporário.

## 2026-11-10 — Lote de exemplo com inputs de água

- Adicionados `jobfile/slurm-dlpno/water1.inp` e `water2.inp` como inputs de
  exemplo para testar a configuração de múltiplos jobs.
- A cópia de trabalho foi configurada com `prepare-job.sh` para o lote
  `water-dlpno`, com `--output=water-dlpno_%J.stdout` e `--array=1-2`.
- O CSV `slurm-dlpno.csv` passou a apontar para `water1.inp` e `water2.inp`.
- `AGENTS.md` e `jobfile/README.md` foram atualizados para registrar os inputs
  de exemplo e o estado atual da configuração.

## 2026-11-10 — localDir automático no prepare-job

- `prepare-job.sh` passou a atualizar também `localDir` em
  `slurm-dlpno.sh` com o caminho absoluto do diretório atual (`$PWD`).
- O caminho é convertido para uma forma shell-safe antes de ser gravado no
  script, suportando espaços e caracteres especiais.
- O script agora exige ser executado a partir do diretório que contém
  `slurm-dlpno.sh` e `slurm-dlpno.csv`, garantindo que o `localDir` gravado
  seja utilizável na execução.
- `AGENTS.md` e `jobfile/README.md` foram atualizados com a nova regra.
- Testado em diretório temporário, incluindo caminho com espaços; `bash -n`
  passou.

## 2026-11-10 — Compactação com tar cvzf

- Alterado o passo de compactação de `slurm-dlpno.sh` para usar
  `tar cvzf`, gerando arquivos `.tar.gz` em vez de `.tar.zst`.
- Os nomes dos arquivos passaram a ser `job_<id>.tar.gz` e
  `job_<id>_failed.tar.gz`.
- `AGENTS.md` e `jobfile/README.md` foram atualizados para refletir a mudança;
  a recomendação original do email usava zstd.
- `bash -n` e um teste de criação/listagem de `.tar.gz` passaram.

## 2026-11-10 — Nome do arquivo inclui o input

- O arquivo de resultados passou a ser nomeado com o input antes do job ID:
  `<inputname>_${SLURM_JOB_ID}.tar.gz`, onde `<inputname>` é o nome do input
  sem a extensão `.inp`.
- Em falha, o nome é `<inputname>_${SLURM_JOB_ID}_failed.tar.gz`.
- Exemplo: `water1.inp` + job `12345` gera `water1_12345.tar.gz`.
- `AGENTS.md` e `jobfile/README.md` foram atualizados.

## 2026-11-10 — Remoção do laço único

- Removido o `for _ in 0; do ... done` de `slurm-dlpno.sh`, que executava
  apenas uma iteração.
- O corpo do laço foi convertido em fluxo procedural, com a indentação
  ajustada e sem o `cd` final de retorno ao diretório de execução.
- Mensagens passaram de “Running jobs”/“All jobs processed” para
  “Running job”/“Job processed”.
- `jobfile/README.md` foi atualizado; `bash -n` passou.

## 2026-11-10 — Comentários e placeholder de localDir

- Adicionados comentários de seção e de etapas em `slurm-dlpno.sh` para
  documentar o fluxo: scheduler, funções, estado do runtime, contexto Slurm,
  caminhos, staging, seleção do input, execução do ORCA, validação e status.
- `localDir` passou a usar o placeholder `__LOCAL_DIR__`, que é substituído
  pelo `prepare-job.sh`.
- Adicionada verificação para abortar caso o placeholder não tenha sido
  substituído.
- Criado bloco visual `PATHS - USER-EDITABLE` destacando que o usuário pode
  alterar os caminhos do container (`ctPath`) e do scratch (`exeDir`).
- `AGENTS.md` e `jobfile/README.md` foram atualizados; `bash -n` passou.

## 2026-11-10 — README curto no topo e partition no sbatch

- Adicionado um bloco curto de instruções no topo de `slurm-dlpno.sh`:
  execução do `prepare-job.sh`, submissão com `sbatch --partition=<partition>`
  e ajuste opcional dos caminhos de container/scratch.
- A partition deixou de ser definida no jobfile; deve ser informada no comando
  de submissão.
- Atualizados `AGENTS.md` e `jobfile/README.md`.
- `bash -n` executado com sucesso.

## 2026-11-10 — Fluxo genérico de pasta no HPC

- Atualizado o README curto no topo de `slurm-dlpno.sh` para o fluxo: criar
  uma pasta no HPC, colocar inputs e scripts nela, executar
  `./prepare-job.sh` e submeter a partir da mesma pasta.
- Removidos caminhos específicos como `cd jobfile/slurm-dlpno` e o caminho
  completo do jobfile nos comandos de submissão; os comandos usam `$PWD`.
- A partition continua sendo informada no `sbatch`, não no script.
- `AGENTS.md` e `jobfile/README.md` foram atualizados.
- `bash -n` executado com sucesso.

## 2026-11-10 — Job name e logfile padrão dlpno

- `slurm-dlpno.sh` passou a usar `#SBATCH --job-name dlpno` e
  `#SBATCH --output=dlpno_%J.stdout`.
- `prepare-job.sh` deixou de usar o primeiro argumento como nome do job; agora
  recebe apenas uma lista de inputs (`<input> [input ...]`).
- O prepare passou a fixar/garantir `--job-name dlpno` e
  `--output=dlpno_%J.stdout` a cada execução, além de atualizar CSV, `localDir`
  e `--array`.
- `AGENTS.md` e `jobfile/README.md` foram atualizados.
- Testado com um e com múltiplos inputs; `bash -n` passou.

## 2026-11-10 — Placeholder ARRAY na diretiva do Slurm

- A cópia de trabalho passou a usar `#SBATCH --array=ARRAY` como placeholder.
- O `prepare-job.sh` substitui `ARRAY` por `1-N`, onde `N` é o número de inputs
  do CSV.
- O CSV padrão pode ficar vazio até a execução do prepare.
- `AGENTS.md` e `jobfile/README.md` foram atualizados.
- Testado em diretório temporário; `bash -n` passou.

## 2026-11-10 — Comentários e separadores no jobfile

- Aumentada a verbosidade dos comentários em `slurm-dlpno.sh`.
- Adicionados separadores e seções numeradas para inspeção: diretivas Slurm,
  funções, estado do runtime, contexto Slurm, paths, staging, seleção do input,
  execução do ORCA, validação e status final.
- Documentados os blocos de cleanup, CSV, arquivamento, staging, PID/status e
  caminhos editáveis.
- Nenhuma mudança de comportamento.
- `bash -n` e um teste de `prepare-job.sh` com o placeholder `ARRAY` passaram.

## 2026-11-10 — Compatibilidade do prepare-job com rótulo inicial

- `prepare-job.sh` voltou a aceitar o uso antigo `./prepare-job.sh <label> *.inp`:
  se o primeiro argumento não for um arquivo `.inp` existente e houver mais
  inputs, ele é ignorado com aviso, pois o job name é fixo em `dlpno`.
- A mensagem de input não encontrado agora orienta a usar apenas arquivos
  `.inp` e informa que o job name é fixo.
- Testado com `./prepare-job.sh test4 *.inp`; o CSV e `--array=1-N` foram
  gerados corretamente.
- `jobfile/README.md` foi atualizado; `bash -n` passou.

## 2026-11-10 — Correção: job name é opcional, não fixo

- Corrigida a interpretação: `dlpno` é o job name padrão, não um valor fixo.
- `prepare-job.sh` agora aceita `[job-name] [input ...]`:
  - primeiro argumento sem `.inp` é o job name;
  - sem job name explícito, usa `dlpno`;
  - sem inputs após o job name, usa `<job-name>.inp`.
- O logfile acompanha o job name: `<job-name>_%J.stdout`.
- Corrigido o caso `./prepare-job.sh test4 *.inp`, que agora configura o job
  `test4` em vez de tratar `test4` como input.
- `AGENTS.md` e `jobfile/README.md` foram atualizados.
- Testes com job name explícito, padrão e input derivado; `bash -n` passou.

## 2026-11-10 — prepare-job simplificado com descoberta automática

- `prepare-job.sh` agora recebe somente `<job-name>`.
- O script descobre automaticamente todos os `*.inp` do diretório atual e os
  ordena naturalmente com `sort -V` (`input2` antes de `input10`).
- O job name é obrigatório; o logfile é `<job-name>_%J.stdout`.
- O CSV, `localDir`, `--array=1-N` e o nome do job são atualizados em uma única
  execução.
- `AGENTS.md`, `jobfile/README.md` e o comentário do jobfile foram atualizados.
- Testado com ordem natural e com diretório sem `.inp`; `bash -n` passou.

## 2026-11-10 — Log do Slurm renomeado por input

- Revertida a alteração dos nomes de stdout/stderr do ORCA; voltaram a
  `<basename>.out` e `stderr.log`.
- `#SBATCH --output` passou a usar o nome temporário `slurm-%A_%a.stdout`.
- Após selecionar o input, o script renomeia esse arquivo para
  `<input>_<SLURM_JOB_ID>.stdout`.
- O `prepare-job.sh` mantém `#SBATCH --output=slurm-%A_%a.stdout`; o nome final
  depende do input e é resolvido em tempo de execução.
- `AGENTS.md` e `jobfile/README.md` foram atualizados.

## 2026-11-10 — Kit de teste de falha por OOM

- Criado `oom-test/` com um `fake-singularity` que aloca memória para
  disparar o OOM killer do cgroup do Slurm.
- `setup-oom-test.sh` monta uma cópia descartável em `oom-test/work/`, ajusta
  `ctPath` para um SIF vazio e executa o `prepare-job.sh`.
- `submit-oom-test.sh` submete com `--mem` baixo e exporta um `PATH` que
  resolve o `singularity` falso.
- O teste usa `water1.inp` e valida o fluxo de falha, o stdout renomeado e o
  archive `_failed`, quando o shell sobrevive ao OOM.
- `AGENTS.md` foi atualizado com a referência ao kit; `bash -n` passou.

## 2026-11-10 — Corrige setup do teste OOM fora do repositório

- O `setup-oom-test.sh` falhava quando `oom-test/` era copiado sozinho para o
  HPC, pois procurava `../jobfile/slurm-dlpno/`.
- Adicionado `oom-test/fixtures/` com cópias de `slurm-dlpno.sh`,
  `prepare-job.sh`, `slurm-dlpno.csv` e `water1.inp`.
- O setup agora usa os arquivos de produção quando o repositório está
  presente e cai para os fixtures quando só o diretório de teste foi copiado.
- Testado com uma cópia isolada de `oom-test/`; o setup, o `prepare-job.sh` e
  a geração de `work/` funcionaram.

## 2026-11-10 — Remove arquivos `*.tmp` do archive de falha

- `clean_job` agora remove todos os arquivos `*.tmp` do diretório do job
  antes de criar o archive, quando `job_success != 1`.
- A remoção usa `find "$jobDir" -type f -name '*.tmp'`, portanto alcança
  subdiretórios e cobre `<basename>.tmp`, `<basename>.en.tmp` e
  `<basename>.SHARKINP.tmp` (nomes confirmados nos exemplos de
  `sample-dlpno/`).
- O log registra o tamanho total liberado e a lista de arquivos removidos.
- Justificativa: os `*.tmp` são scratch de integrais/PNO e podem chegar a
  dezenas de GB; sem o cálculo completo eles não servem para nada e tornavam o
  archive `_failed` inútil na prática.
- Em sucesso o arquivamento continua integral, sem remoção de `*.tmp`.
- Testado com um `singularity` falso em `/tmp`: falha (`exit 137`, sem marcador)
  gerou `water1_9101_failed.tar.gz` sem os `*.tmp` (7 MB liberados) e manteve
  `.out`, `stderr.log`, `.gbw` e o input; sucesso gerou o archive completo.
- `jobfile/slurm-dlpno/slurm-dlpno.sh`, `jobfile/README.md` e a cópia
  `oom-test/fixtures/slurm-dlpno.sh` foram atualizados; `bash -n` passou.
