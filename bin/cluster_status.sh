cluster_status() {
    local divider
    divider=$(printf '%.0s-' {1..96})

    # --- Node Table ---
    echo -e "\n${divider}"
    printf "%-20s %10s %10s %8s %9s %8s %7s  %-16s\n" \
        "NODE" "TOTAL_MEM" "FREE_MEM" "CPU_TOT" "CPU_ALLOC" "CPU_IDLE" "CPU_OFF" "PARTITION"
    echo "${divider}"

    sinfo -N -o "%N %m %e %C %P" --noheader \
        | awk -F'[ /]' '{
            node      = $1
            total_mem = $2
            free_mem  = $3
            allocated = $4
            idle      = $5
            offline   = $6
            total_cpu = $7
            part      = $8

            if (!(node in seen)) {
                seen[node] = 1
                order[++n] = node
                tmem[node] = total_mem
                fmem[node] = free_mem
                tcpu[node] = total_cpu
                alloc[node] = allocated
                idl[node]  = idle
                off[node]  = offline
                parts[node] = part
            } else if (part != "" && index("," parts[node] ",", "," part ",") == 0) {
                parts[node] = parts[node] "," part
            }
        }
        END {
            for (i = 1; i <= n; i++) {
                node = order[i]
                printf "%-20s %6.1f GB  %6.1f GB  %7s %9s %8s %7s  %-16s\n",
                    node,
                    tmem[node] / 1024,
                    fmem[node] / 1024,
                    tcpu[node],
                    alloc[node],
                    idl[node],
                    off[node],
                    parts[node]
            }
        }'

    echo "${divider}"
}
