# AGENTS.md

## Objetivo do projeto

Ajustar o `jobfile` deste repositório às novas diretrizes de uso do Cluster UFSCar
e garantir que o cálculo DLPNO (ORCA) continue funcionando corretamente.

Em outras palavras:

1. Revisar e editar `jobfile/cjobs_6631.sh`, `jobfile/cjobs_joblist.csv` e
   `jobfile/int-1-HH.inp` conforme necessário.
2. Adequar o fluxo de trabalho às regras descritas em `docs/andre-email.txt`,
   especialmente:
   - não usar subpastas de `/home` como área de trabalho durante a execução;
   - executar o cálculo em `/scratch` ou `/tmp`;
   - ao final, enviar resultados preferencialmente para a nuvem via `rclone`;
   - se for inevitável gravar no `/home`, empacotar toda a pasta de resultados
     em um único arquivo `.tar.gz` com `tar cvzf`;
   - remover os arquivos temporários de `/scratch` ao final do job.
3. Preservar/validar a configuração científica do cálculo DLPNO:
   - método `DLPNO-CCSD(T1)`;
   - `TightPNO`, `TightSCF`, `RIJCOSX`;
   - bases e auxiliares definidas no `.inp` (`def2-tzvpp`, `def2-tzvpp/C`,
     `def2/J`);
   - paralelismo e memória coerentes com os recursos solicitados ao Slurm.
4. Confirmar o funcionamento do cálculo, verificando a terminação normal do ORCA
   (`****ORCA TERMINATED NORMALLY****`) e a ausência de erros no `stderr.log`.

## Conteúdo do repositório

- `jobfile/cjobs_6631.sh` — script original preservado como referência;
  documentado em `jobfile/README.md`.
- `jobfile/cjobs_joblist.csv` — CSV original preservado como referência.
- `jobfile/slurm-dlpno/slurm-dlpno.sh` — cópia de trabalho editável; já difere
  do original (ver seção de diferenças no `jobfile/README.md`).
- `jobfile/slurm-dlpno/slurm-dlpno.csv` — CSV de trabalho consumido por
  `slurm-dlpno.sh`.
- `jobfile/slurm-dlpno/prepare-job.sh` — configura o CSV, o `localDir` e a
  numeração da `--array`; mantém `--job-name dlpno` e
  `--output=dlpno_%J.stdout`.
- `jobfile/slurm-dlpno/water1.inp` e `water2.inp` — inputs de exemplo para um
  lote de teste com duas tasks.
- `jobfile/README.md` — documentação do fluxo, variáveis, recursos e pontos de
  atenção do script original `cjobs_6631.sh`. A cópia de trabalho está em
  `jobfile/slurm-dlpno/`.
- `jobfile/int-1-HH.inp` — entrada ORCA do cálculo DLPNO em questão.
- `sample-dlpno/` — dois exemplos de saída ORCA que terminaram normalmente
  (`bis_int_tbpButTrans_3.out` e `ts-exchg-2_f3_17.out`), úteis como referência
  de configuração, desempenho e formato dos resultados.
- `docs/orca_manual_6_1_1.pdf` — manual do ORCA 6.1.1.
- `docs/andre-email.txt` — comunicado da administração do Cluster UFSCar com as
  novas diretrizes de armazenamento e transferência de resultados.
- `docs/cloudufscar-resources.txt` — snapshot de recursos do CloudUFSCar.
- `research/orca-dlpno-resources.md` — notas sobre recursos computacionais para
  DLPNO/NormalPNO, com referências ao manual ORCA 6.1.1.
- `research/sample-dlpno-resource-analysis.md` — análise de tempo, memória,
  disco e paralelismo dos dois cálculos de referência em `sample-dlpno/`.
- `research/cloudufscar-resources.md` — capacidade dos nodes, premissa de um
  scratch por node e execução em node único.

## Situação atual

- Nenhuma alteração funcional foi feita no `jobfile` ou nos arquivos de entrada.
  Esta etapa apenas documenta o objetivo e o estado inicial do projeto.
- O script atual ainda copia a pasta de resultados diretamente para o `/home`
  com `cp -r "$exeDir"/*/ "$localDir"`, o que conflita com a nova diretriz de
  compactação/transferência.
- O script usa contêiner `orca-611_2025-12-16_19-01-10_orca611.sif` (ORCA 6.1.1),
  enquanto os exemplos em `sample-dlpno/` foram gerados com ORCA 5.0.4.
- Os exemplos de saída indicam cálculo concluído com sucesso; servem de
  referência para comparar a configuração e os tempos de execução após o ajuste.

## Ambiente Python

- Se precisar executar Python, usar o ambiente default do mamba (atualmente
  `base`, em `/home/attilio/opt/miniforge3`), por exemplo:
  `mamba run -n base python ...`.
- Não criar `.venv` nem ambientes conda/mamba específicos sem necessidade.

## Recursos para DLPNO com NormalPNO (manual ORCA 6.1.1)

- Para DLPNO-CCSD(T), `NormalPNO` é o ajuste default e usa
  `TCutPairs=1e-4`, `TCutDO=1e-2`, `TCutPNO=3.33e-7` e `TCutMKN=1e-3`,
  com tratamento MP2 semicanônico dos pares (mais barato que `TightPNO`).
- `%maxcore` é por processo, em MB. O manual recomenda pelo menos 8 GB por
  core para coupled cluster e `maxcore * nprocs <= 0.75 * RAM disponível`.
  Com 4 processos e 80 GB de `--mem`, o limite coerente é
  `maxcore <= 15000 MB` (15 GB/core).
- `%pal nprocs` deve coincidir com `--ntasks` do Slurm. O manual indica que
  coupled cluster escala bem até pelo menos 8 processos; 16 pode valer a pena.
- DLPNO exige base auxiliar de correlação (ex.: `def2-tzvpp/C`); `RIJCOSX`
  também requer `def2/J`.
- DLPNO pode demandar bastante I/O de disco; executar em scratch local (não
  NFS), manter um diretório por job e removê-lo ao final. Em nó único,
  `%mdci StorageType Shared` tenta manter integrais em memória compartilhada,
  com fallback para disco.

## Diretrizes para futuras alterações

- Não alterar parâmetros científicos do cálculo sem justificativa e sem
  registrar em `HISTORY.md`.
- Manter `HISTORY.md` atualizado a cada mudança ou decisão relevante.
- Validar o script com `bash -n` antes de submetê-lo ao Slurm.
- Verificar se o caminho do contêiner, os recursos (`--ntasks`, `--mem`,
  `%maxcore`, `%pal`) e as variáveis de paralelismo (`MKL_NUM_THREADS`,
  `OMP_NUM_THREADS`) permanecem consistentes.
- Não deixar resultados apenas no Cluster; seguir a opção de transferência
  definida pela administração.
- O Slurm do CloudUFSCar tem um scratch por node e o job será single-node;
  todos os ranks compartilham o mesmo scratch. Manter `--nodes=1`, usar um
  diretório exclusivo por job e não assumir scratch privado por rank.
- Editar o script de trabalho `jobfile/slurm-dlpno/slurm-dlpno.sh` e o CSV
  `jobfile/slurm-dlpno/slurm-dlpno.csv`. Não modificar `cjobs_6631.sh` nem
  `cjobs_joblist.csv`: eles são os originais preservados para referência e
  documentação.
- Não fixar `#SBATCH --partition` na cópia de trabalho; informar a partition
  desejada no comando de submissão (`sbatch --partition=<partition> ...`).
- Na finalização normal, arquivar a pasta de resultados em
  `$localDir/<inputname>_${SLURM_JOB_ID}.tar.gz` com `tar cvzf`; `inputname`
  é o nome do input sem `.inp`. Não copiar resultados soltos para `/home`.
  Em falha, usar o sufixo `_failed` e manter o scratch se o arquivamento não
  funcionar.
- Não reintroduzir sincronização de containers nem `rclone` na cópia de
  trabalho. O container do ORCA deve permanecer com caminho fixo e ser
  verificado antes da execução.
- Manter `localDir="__LOCAL_DIR__"` e `#SBATCH --array=ARRAY` no script
  versionado; o `prepare-job.sh` substitui os placeholders pelos valores
  calculados.
- No HPC, criar uma pasta de trabalho, colocar nela os inputs e os scripts,
  executar `./prepare-job.sh <input> [input ...]` a partir dessa pasta e
  submeter com `sbatch --partition=<partition> slurm-dlpno.sh` no mesmo
  diretório.
- Não usar caminho completo do jobfile nos comandos de preparação/submissão;
  operar sempre no diretório atual (`$PWD`), que também será o `localDir`.
