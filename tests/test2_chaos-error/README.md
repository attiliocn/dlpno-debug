# Diagnóstico do Teste `test2_chaos-error` (Job `1152215` — Arquivamento Acidental de `/`)

Este documento registra, de forma autossuficiente (sem depender do log bruto de 100 MB do Slurm, que foi descartado), o erro catastrófico ocorrido no job `1152215` (nó `c16`, `2026-11-12` das `14:22:46` às `19:22`) e as falhas estruturais identificadas em [`jobfile-chaos-error/slurm-dlpno.sh`](jobfile-chaos-error/slurm-dlpno.sh).

---

## 1. Resumo do Incidente

O job foi submetido a partir de `/home/u831869/run/TESTS-DLPNO/test2_after-diagnose`, mas **`./prepare-job.sh` não foi executado nessa pasta antes do `sbatch`** (o script [`slurm-dlpno.sh`](jobfile-chaos-error/slurm-dlpno.sh#L226) foi copiado já preparado de outra execução e ainda continha um `localDir` desatualizado de outro diretório inexistente):

```bash
localDir=/home/u831869/run/slurm-dlpno/testes-dlpno/slurm-dlpno
```

Por não validar a existência de `$localDir`, dos arquivos copiados nem de `$job`/`$basename`, o script continuou executando após sucessivos erros de `cp` e `sed`, deixou `basename=""` vazio e, na rotina `clean_job`, acabou chamando:

```bash
tar cvzf "$archive" --warning=no-file-changed -C "$exeDir" "$basename/"
```

Como `basename` estava vazio, `"$basename/"` expandiu literalmente para **`"/"`** (o diretório raiz do nó `c16`). O `tar` ignorou o `-C "$exeDir"` por causa do caminho absoluto `/` e passou **~5 horas** tentando compactar todo o sistema de arquivos do nó `c16` (gerando 100 MB / 1.168.040 linhas de log) para `/home/u831869/run/slurm-dlpno/testes-dlpno/slurm-dlpno/_1152215_failed.tar.gz`, até abortar com `tar status 2` por erros de `Permission denied` em arquivos protegidos do sistema (ex.: `/xcatpost/mypostscript`).

---

## 2. Cadeia Completa de Falhas no Script

1. **Validação insuficiente de `localDir` (linha 232):**
   - O bloco `5.1` verifica apenas `[[ "$localDir" == "__LOCAL_DIR__" ]]`, mas não verifica se o diretório `$localDir` realmente existe nem se contém `slurm-dlpno.csv` e `slurm-dlpno.sh`.
2. **Ausência de `set -e` ou checagem de retorno em etapas críticas:**
   - `cp "$localDir"/slurm-dlpno.sh "$localDir"/slurm-dlpno.csv "$exeDir"` (linha 259) falhou com `No such file or directory`, mas o script prosseguiu.
3. **`get_csv_element` retornou string vazia (linhas 270–275):**
   - `sed` falhou ao ler `slurm-dlpno.csv` inexistente, deixando `job=""` e `basename=""`.
   - Com isso, `jobDir="$exeDir"/"$basename"` virou `/scratch/u831869/jobs/1152215/` (que já existia do `mkdir -p "$exeDir"`), fazendo `mkdir "$jobDir"` falhar (`File exists`) e a condição `[[ -n "$jobDir" && -d "$jobDir" ]]` do `clean_job` (linha 99) ser **verdadeira**.
4. **Execução do container com argumento vazio (linhas 321–325):**
   - O `singularity run` recebeu `"$job"` vazio (`""`), falhou imediatamente com `status=1` (`job_success=0`) e acionou `clean_job`.
5. **Expansão de `"$basename/"` para `"/"` no `tar` (linha 144):**
   - `clean_job` executou `mkdir -p "$localDir"` (recriando a pasta antiga vazia no `/home`) e chamou `tar cvzf ... -C "$exeDir" "/"`, tentando arquivar a raiz `/` do nó de computação em vez da pasta do job.
   - O `tar` só parou após ~5 horas porque atingiu arquivos do sistema sem permissão de leitura (`tar status 2`), preservando `/scratch/u831869/jobs/1152215` ao final.

---

## 3. Correções Necessárias no `slurm-dlpno.sh` de Produção

Para tornar esse tipo de falha impossível:

1. **Validar `localDir` e os arquivos de entrada antes de qualquer ação:**
   - Verificar `[[ -d "$localDir" ]]`, `[[ -f "$localDir/slurm-dlpno.csv" ]]` e `[[ -f "$localDir/slurm-dlpno.sh" ]]`, abortando imediatamente (`exit 1`) se qualquer um faltar.
2. **Validar `cp`, `job`, `basename` e `jobDir`:**
   - Checar o código de saída dos `cp` de staging (`|| exit 1`).
   - Exigir `[[ -n "$job" && -n "$basename" ]]` e `[[ -f "$localDir/$job" ]]` antes de criar `jobDir` ou lançar o ORCA.
3. **Proteger o `clean_job` contra `basename` vazio ou absoluto:**
   - Exigir `[[ -n "$basename" && "$basename" != */* && -d "$exeDir/$basename" ]]` antes de remover temporários ou chamar `tar`.
   - Evitar a barra final ou validar explicitamente o caminho relativo passado ao `tar -C "$exeDir" "$basename"`.
