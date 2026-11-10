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
     em um único arquivo `.tar.zst` com `tar -I "zstd ..."`;
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

- `jobfile/cjobs_6631.sh` — script de submissão Slurm e execução do ORCA em
  contêiner Singularity.
- `jobfile/cjobs_joblist.csv` — lista de jobs; atualmente aponta para
  `int-1-HH.inp`.
- `jobfile/int-1-HH.inp` — entrada ORCA do cálculo DLPNO em questão.
- `sample-dlpno/` — dois exemplos de saída ORCA que terminaram normalmente
  (`bis_int_tbpButTrans_3.out` e `ts-exchg-2_f3_17.out`), úteis como referência
  de configuração, desempenho e formato dos resultados.
- `docs/orca_manual_6_1_1.pdf` — manual do ORCA 6.1.1.
- `docs/andre-email.txt` — comunicado da administração do Cluster UFSCar com as
  novas diretrizes de armazenamento e transferência de resultados.

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
