#!/bin/bash

INTERVAL=${INTERVAL:-5}
LOG_FILE="system-state.log"

while true; do
    {
        echo "==================== STARE SISTEM ===================="
        echo "Data si ora: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Host: $(hostname)"

        if [ -f /etc/os-release ]; then
            . /etc/os-release
            echo "Sistem de operare: $NAME $VERSION"
        else
            echo "Sistem de operare: $(uname -s) $(uname -r)"
        fi

        echo "Timp de functionare: $(uptime -p)"
        
        echo "CPU utilizat: $(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4 "%"}')"

        echo "Memorie utilizata: $(free -h | awk 'NR==2{printf "%s / Total: %s (%.2f%%)", $3, $2, $3/$2*100}')"
        
        echo "Procese active: $(ps aux | wc -l)"

        echo "Utilizare disc: $(df -h | awk '$NF=="/"{printf "%s folosit din %s (%s)", $3, $2, $5}')"
        

        echo "Top 5 procese dupa CPU:"
        ps -eo pid,comm,%cpu --sort=-%cpu | head -n 6 | awk 'NR==1 {print "  "$0} NR>1 {print "  "$0}'

        echo "Top 5 procese dupa memorie:"
        ps -eo pid,comm,%mem --sort=-%mem | head -n 6 | awk 'NR==1 {print "  "$0} NR>1 {print "  "$0}'

    } > "$LOG_FILE"

    sleep "$INTERVAL"
done
