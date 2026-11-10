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
