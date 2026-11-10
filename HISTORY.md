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
