#!/bin/bash
# Минимальный граф «юнит -> файлы» только из готовых команд, своих парсеров нет:
#   systemctl show   что запускает юнит и откуда берёт переменные
#   ldd              какие библиотеки подгрузит бинарник
#   dpkg -S, -V      чей файл и совпал ли он с пакетом
#   file             тип файла
#   dot              картинка
# Запуск: ./graph_min.sh ssh.service tailscale-guard.service | dot -Tpng -o files_min.png
declare -A seen verify

origin() {  # ставит ORG и COL по происхождению файла $1
  local p=$1 pkg
  pkg=$(dpkg -S "$p" 2>/dev/null | grep -v '^diversion' | head -1 | cut -d: -f1)
  [ -z "$pkg" ] && pkg=$(dpkg -S "${p#/usr}" 2>/dev/null | grep -v '^diversion' | head -1 | cut -d: -f1)
  if [ -z "$pkg" ]; then ORG="ничей"; COL="#f4b6b6"; return; fi
  [ -v "verify[$pkg]" ] || verify[$pkg]=$(dpkg -V "$pkg" 2>/dev/null)
  if awk -v a="$p" -v b="${p#/usr}" '$NF==a || $NF==b {f=1} END {exit !f}' <<<"${verify[$pkg]}"
  then ORG="пакет $pkg, изменён"; COL="#f6e3a1"
  else ORG="пакет $pkg, совпал"; COL="#bfe3bf"; fi
}

leaf() {  # печатает узел файла $1 с подписью $2 (по умолчанию путь)
  [ -v "seen[$1]" ] && return 1; seen[$1]=1
  origin "$1"
  echo "  \"$1\" [label=\"${2:-$1}\\n$ORG\", fillcolor=\"$COL\"];"
}

expand() {  # узел файла $1 и то, что готовые команды знают о нём дальше
  local p lib kind; p=$(realpath -m "$1")
  leaf "$p" || return
  kind=$(file -b "$p")
  case $kind in
    ELF*)
      while read -r lib; do
        lib=$(realpath -m "$lib"); leaf "$lib"
        echo "  \"$p\" -> \"$lib\" [label=\"ldd\"];"
      done < <(ldd "$p" | awk '$2=="=>" && $3 ~ /^\// {print $3} $1 ~ /^\// {print $1}') ;;
    *script*)
      echo "  \"stop:$p\" [label=\"дальше не разобрано:\\nнужен парсер для\\n${kind%%,*}\", shape=note, style=dashed];"
      echo "  \"$p\" -> \"stop:$p\" [style=dashed];" ;;
  esac
}

echo 'digraph autostart {'
echo '  rankdir=LR; nodesep=0.12; ranksep=1.2;'
echo '  graph [fontname="DejaVu Sans", fontsize=11, labelloc=b, label="зелёный: файл из пакета, dpkg -V расхождений не показал;  жёлтый: из пакета, но изменён;  красный: не принадлежит ни одному пакету"];'
echo '  node [shape=box, style=filled, fontname="DejaVu Sans", fontsize=10, fillcolor=white];'
echo '  edge [fontname="DejaVu Sans", fontsize=9];'
for unit in "$@"; do
  frag=$(systemctl show -p FragmentPath --value "$unit")
  leaf "$frag" "$unit\\n$frag"
  for prop in ExecStartPre ExecStart ExecStartPost; do
    for path in $(systemctl show -p "$prop" "$unit" | grep -o 'path=[^ ]*' | cut -d= -f2 | sort -u); do
      expand "$path"
      echo "  \"$frag\" -> \"$(realpath -m "$path")\" [label=\"$prop\"];"
    done
  done
  for env in $(systemctl show -p EnvironmentFiles --value "$unit" | grep -o '^/[^ ]*'); do
    expand "$env"
    echo "  \"$frag\" -> \"$(realpath -m "$env")\" [label=\"EnvironmentFile\"];"
  done
done
echo '}'
