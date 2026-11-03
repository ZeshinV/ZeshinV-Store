#!/bin/sh
# ZeshinV - strato di controllo per Samsung serie E (Orsay), busybox sh
# Uso: zv.sh <comando> [args]
# Installare in: /mtd_rwcommon/zeshinv/zv.sh  (chmod 755)

ZV_HOME="${ZV_HOME:-/mtd_rwcommon/zeshinv}"
CATALOG_URL="${CATALOG_URL:-https://zeshinv.github.io/zeshinv-store/catalog.txt}"
# Cartelle da verificare con "zv.sh scan" sul TUO firmware:
USER_APPS_DIR="${USER_APPS_DIR:-/mtd_rwcommon/widgets/user}"
NATIVE_APPS_DIR="${NATIVE_APPS_DIR:-/mtd_rwcommon/widgets/normal}"
DISABLED_DIR="$ZV_HOME/disabled"
BACKUP_DIR="$ZV_HOME/backup"
mkdir -p "$ZV_HOME" "$DISABLED_DIR" "$BACKUP_DIR" "$ZV_HOME/tmp" 2>/dev/null

safe_id() { echo "$1" | grep -Eq '^[A-Za-z0-9._-]{1,64}$'; }

cmd_status() {
  echo "== MEMORIA =="
  grep -E 'MemTotal|MemFree|Buffers|^Cached' /proc/meminfo
  echo "== CPU load =="; cat /proc/loadavg
  echo "== UPTIME =="; uptime
  echo "== SPAZIO =="; df 2>/dev/null
  echo "== RAM realmente disponibile (free+buffers+cached) =="
  awk '/^MemTotal/{t=$2} /^MemFree/{f=$2} /^Buffers/{b=$2} /^Cached/{c=$2} END{printf "%d MB su %d MB\n",(f+b+c)/1024,t/1024}' /proc/meminfo
  echo "== TOP processi per RAM (RSS, kB) =="
  for p in /proc/[0-9]*; do
    r=$(grep -m1 VmRSS "$p/status" 2>/dev/null | tr -s ' \t' ' ' | cut -d' ' -f2)
    [ -n "$r" ] && echo "$r $(basename "$p") $(tr '\0' ' ' < "$p/cmdline" 2>/dev/null | cut -c1-45)"
  done | sort -n -r | head -n 12
}

cmd_freeram() {
  sync
  echo 3 > /proc/sys/vm/drop_caches 2>/dev/null && echo "Cache liberata" || echo "drop_caches non disponibile"
  grep -E 'MemFree|^Cached' /proc/meminfo
}

# ---------- DIAGNOSTICA ----------
cmd_diag_wifi() {
  score=0; notes=""
  echo "== Interfacce di rete =="
  cat /proc/net/dev
  echo; echo "== Wireless (/proc/net/wireless) =="
  if [ -s /proc/net/wireless ] && [ "$(wc -l < /proc/net/wireless)" -gt 2 ]; then
    cat /proc/net/wireless
  else
    echo "NESSUNA interfaccia wireless registrata"; score=$((score+3))
    notes="$notes\n- Nessuna interfaccia wireless attiva (driver non caricato o scheda non rilevata)"
  fi
  echo; echo "== iwconfig =="; (iwconfig 2>&1 || echo "iwconfig assente") | head -n 30
  echo; echo "== Moduli kernel =="; lsmod 2>/dev/null
  echo; echo "== USB (la scheda wifi Samsung e' spesso USB interna) =="
  cat /proc/bus/usb/devices 2>/dev/null | grep -E 'Vendor|Product|Manufacturer|Driver' || ls /sys/bus/usb/devices 2>/dev/null
  echo; echo "== Errori nel log kernel =="
  errs=$(dmesg 2>/dev/null | grep -iE 'wlan|wifi|wl[0-9]|rtl|ath|rt2|rt3|mt76|usb' | grep -iE 'fail|error|timeout|reset|disconnect|unable|no such' | tail -n 15)
  [ -n "$errs" ] && { echo "$errs"; score=$((score+2)); notes="$notes\n- Errori wifi/USB nel log kernel"; } || echo "nessuno"
  echo; echo "== Errori pacchetti per interfaccia =="
  awk -F'[: ]+' 'NR>2 && ($1 ~ /wl|ra|eth|wlan/ || $2 ~ /wl|ra|eth|wlan/){print}' /proc/net/dev
  for q in $(awk 'NR>2{gsub(":"," ");print $1, $4, $12}' /proc/net/dev | awk '$1 !~ /^lo/ && ($2>100 || $3>100){print $1}'); do
    score=$((score+1)); notes="$notes\n- Molti errori RX/TX su $q"
  done
  echo; echo "== VERDETTO (euristico, non una certezza) =="
  if [ $score -ge 4 ]; then echo "ALTA probabilita' di problema scheda/driver wifi"
  elif [ $score -ge 2 ]; then echo "MEDIA probabilita': possibile driver/antenna/alimentazione USB"
  else echo "Nessun guasto evidente via software (prova anche segnale/router/canale)"; fi
  printf "$notes\n"
}

cmd_diag_all() {
  echo "== SISTEMA =="; uname -a; cat /proc/version 2>/dev/null
  echo; echo "== CPU =="; cat /proc/cpuinfo 2>/dev/null
  echo; echo "== MEMORIA =="; cat /proc/meminfo | head -n 8
  echo; echo "== PARTIZIONI MTD (flash) =="; cat /proc/mtd 2>/dev/null
  echo; echo "== MONTAGGI =="; mount
  echo; echo "== SPAZIO =="; df 2>/dev/null
  echo; echo "== TEMPERATURE (se esposte) =="
  for f in /sys/class/thermal/thermal_zone*/temp /sys/devices/virtual/thermal/thermal_zone*/temp; do
    [ -f "$f" ] && echo "$f: $(cat $f)"
  done 2>/dev/null
  echo; echo "== ERRORI KERNEL RECENTI =="
  dmesg 2>/dev/null | grep -iE 'error|fail|oops|panic|bad block|ecc|i/o error|segfault' | tail -n 25
  echo; echo "== USB =="; cat /proc/bus/usb/devices 2>/dev/null | grep -E 'Product|Manufacturer' 
  echo; echo "== WIFI =="; cmd_diag_wifi
}

cmd_ping() { ping -c 4 "${1:-8.8.8.8}" 2>&1; }

# ---------- APP NATIVE ----------
cmd_scan() {
  echo "== Cartelle widget candidate (cerco config.xml) =="
  find /mtd_rwcommon /mtd_down /mtd_exe /mtd_ram /dtv 2>/dev/null -maxdepth 5 -name config.xml 2>/dev/null | sed 's|/config.xml||' | head -n 80
  echo; echo "Imposta USER_APPS_DIR / NATIVE_APPS_DIR in zv.conf se diversi da quelli di default."
}

app_name() {
  c="$1/config.xml"; [ -f "$c" ] || { echo "?"; return; }
  n=$(sed -n 's:.*<widgetname>\(.*\)</widgetname>.*:\1:p' "$c" | head -n1)
  [ -n "$n" ] || n=$(sed -n 's:.*<cp>\(.*\)</cp>.*:\1:p' "$c" | head -n1)
  [ -n "$n" ] || n=$(sed -n 's:.*<description>\(.*\)</description>.*:\1:p' "$c" | head -n1)
  echo "${n:-?}" | tr ' ' '_'
}

# Formato: STATO ID KB NOME   (STATO: ATTIVA = disattivabile, PROTETTA, OFF)
cmd_apps_list() {
  ALLOW="$ZV_HOME/disable.allow"
  echo "== NATIVE ($NATIVE_APPS_DIR) =="
  for d in "$NATIVE_APPS_DIR"/*/; do
    [ -d "$d" ] || continue
    id=$(basename "$d"); kb=$(du -sk "$d" 2>/dev/null | cut -f1)
    if [ -f "$ALLOW" ] && grep -qx "$id" "$ALLOW"; then st=ATTIVA; else st=PROTETTA; fi
    echo "$st $id ${kb}KB $(app_name "${d%/}")"
  done
  echo "== DISATTIVATE =="
  for d in "$DISABLED_DIR"/*/; do [ -d "$d" ] && echo "OFF $(basename "$d") - $(app_name "${d%/}")"; done
}

cmd_apps_disable() {
  safe_id "$1" || { echo "ID non valido"; return 1; }
  [ -d "$NATIVE_APPS_DIR/$1" ] || { echo "App non trovata"; return 1; }
  # protezione: SOLO gli ID scritti in disable.allow sono disattivabili (vuoto di default)
  grep -qx "$1" "$ZV_HOME/disable.allow" 2>/dev/null || { echo "Protetta: aggiungi l'ID a $ZV_HOME/disable.allow solo dopo averlo verificato"; return 1; }
  mv "$NATIVE_APPS_DIR/$1" "$DISABLED_DIR/$1" && echo "Disattivata: $1 (riavvia la TV)"
}

cmd_apps_enable() {
  safe_id "$1" || { echo "ID non valido"; return 1; }
  [ -d "$DISABLED_DIR/$1" ] || { echo "Non e' tra le disattivate"; return 1; }
  mv "$DISABLED_DIR/$1" "$NATIVE_APPS_DIR/$1" && echo "Riattivata: $1 (riavvia la TV)"
}

# ---------- TEMA ----------
# Un tema = cartella $ZV_HOME/themes/<nome>/ con un file "manifest": una riga per file,
#   <percorso_originale_sulla_TV>|<file_sostitutivo_nella_cartella_del_tema>
# Si usa "mount --bind": NON modifica le partizioni, al riavvio tutto torna originale
# (a meno che tu non attivi "theme persist").
MOUNTED="$ZV_HOME/mounted.list"

cmd_theme_scan() {
  for d in /mtd_exe /mtd_appext /mtd_rocommon /mtd_rwcommon; do
    echo "== $d =="; mount | grep " $d " | head -n 1
    echo "file grafici/css/js (primi 60):"
    find "$d" -maxdepth 6 \( -name '*.png' -o -name '*.jpg' -o -name '*.css' \) 2>/dev/null | head -n 60
  done
}
cmd_theme_list() { ls "$ZV_HOME/themes" 2>/dev/null || echo "(nessun tema installato)"; }
theme_target_ok() {
  case "$1" in *..*) return 1;; esac
  for r in /mtd_exe /mtd_appext /mtd_rocommon /mtd_rwcommon $ZV_THEME_ROOTS; do
    case "$1" in "$r"/*) return 0;; esac
  done
  return 1
}
theme_pair_ok() { # $1 target  $2 sorgente: entrambi cartelle oppure entrambi file
  if [ -d "$1" ]; then [ -d "$2" ]; return; fi
  [ -f "$1" ] && [ -f "$2" ]
}
# Controllo in sola lettura: verifica che originali e file del tema esistano
cmd_theme_check() {
  safe_id "$1" || { echo "ID non valido"; return 1; }
  T="$ZV_HOME/themes/$1"; [ -f "$T/manifest" ] || { echo "Tema non trovato in $T"; return 1; }
  ok=0; bad=0
  while IFS='|' read -r target src; do
    [ -z "$target" ] && continue
    if theme_target_ok "$target" && theme_pair_ok "$target" "$T/$src"; then ok=$((ok+1)); else bad=$((bad+1)); echo "PROBLEMA: $target <- $src"; fi
  done < "$T/manifest"
  echo "OK: $ok  Problemi: $bad"
  [ "$bad" -eq 0 ]
}
cmd_theme_apply() {
  safe_id "$1" || { echo "ID non valido"; return 1; }
  T="$ZV_HOME/themes/$1"; [ -f "$T/manifest" ] || { echo "Tema non trovato"; return 1; }
  done_n=0
  while IFS='|' read -r target src; do
    [ -z "$target" ] && continue
    theme_target_ok "$target" || { echo "Percorso rifiutato: $target"; continue; }
    case "$src" in */*|"") echo "Sorgente non valida: $src"; continue;; esac
    [ -e "$target" ] || { echo "Originale non trovato: $target"; continue; }
    [ -e "$T/$src" ] || { echo "Tema mancante: $src"; continue; }
    if [ -d "$target" ] && [ ! -d "$T/$src" ]; then echo "Tipo diverso: $target"; continue; fi
    if [ -f "$target" ] && [ ! -f "$T/$src" ]; then echo "Tipo diverso: $target"; continue; fi
    grep -qx "$target" "$MOUNTED" 2>/dev/null && { echo "Gia' sostituito: $target"; continue; }
    mount --bind "$T/$src" "$target" && echo "$target" >> "$MOUNTED" && done_n=$((done_n+1))
  done < "$T/manifest"
  echo "Cartelle/file sostituiti: $done_n (temporaneo, riavvia la TV per annullare)"
}
cmd_theme_restore() {
  [ -f "$MOUNTED" ] || { echo "Nessun tema attivo"; return 0; }
  while read -r target; do
    [ -n "$target" ] && umount "$target" 2>/dev/null && echo "Ripristinato $target"
  done < "$MOUNTED"
  rm -f "$MOUNTED"
}
cmd_theme_persist() {
  safe_id "$1" || { echo "ID non valido"; return 1; }
  [ -f "$ZV_HOME/themes/$1/manifest" ] || { echo "Tema non trovato"; return 1; }
  echo "$1" > "$ZV_HOME/theme.active" && echo "Il tema '$1' verra' applicato a ogni avvio (provalo prima senza persist!)"
}
cmd_theme_unpersist() { rm -f "$ZV_HOME/theme.active" && echo "Tema automatico disattivato"; }

# ---------- STORE ----------
cmd_store_list() {
  wget -q -O - "$CATALOG_URL" 2>/dev/null || echo "ERRORE: catalogo non raggiungibile"
}
cmd_store_install() {
  safe_id "$1" || { echo "ID non valido"; return 1; }
  line=$(wget -q -O - "$CATALOG_URL" | grep "^$1|") || true
  [ -n "$line" ] || { echo "App non nel catalogo"; return 1; }
  url=$(echo "$line" | cut -d'|' -f4); md5=$(echo "$line" | cut -d'|' -f5)
  case "$url" in https://*|http://*) ;; *) echo "URL non valido"; return 1;; esac
  f="$ZV_HOME/tmp/$1.zip"
  wget -q -O "$f" "$url" || { echo "Download fallito"; return 1; }
  got=$(md5sum "$f" | cut -d' ' -f1)
  [ "$got" = "$md5" ] || { echo "MD5 non corrisponde, annullato"; rm -f "$f"; return 1; }
  mkdir -p "$USER_APPS_DIR/$1" && unzip -o -q "$f" -d "$USER_APPS_DIR/$1" && echo "Installata: $1 (riavvia Smart Hub)"
  rm -f "$f"
}
cmd_store_remove() {
  safe_id "$1" || { echo "ID non valido"; return 1; }
  [ -d "$USER_APPS_DIR/$1" ] && rm -rf "$USER_APPS_DIR/${1:?}" && echo "Rimossa: $1"
}

[ -f "$ZV_HOME/zv.conf" ] && . "$ZV_HOME/zv.conf"

case "$1" in
  status) cmd_status;;
  freeram) cmd_freeram;;
  diag) cmd_diag_all;;
  wifi) cmd_diag_wifi;;
  ping) cmd_ping "$2";;
  scan) cmd_scan;;
  apps) case "$2" in list) cmd_apps_list;; disable) cmd_apps_disable "$3";; enable) cmd_apps_enable "$3";; *) echo "apps list|disable|enable <id>";; esac;;
  theme) case "$2" in check) cmd_theme_check "$3";; scan) cmd_theme_scan;; list) cmd_theme_list;; apply) cmd_theme_apply "$3";; restore) cmd_theme_restore;; persist) cmd_theme_persist "$3";; unpersist) cmd_theme_unpersist;; *) echo "theme scan|list|check <n>|apply <n>|restore|persist <n>|unpersist";; esac;;
  store) case "$2" in list) cmd_store_list;; install) cmd_store_install "$3";; remove) cmd_store_remove "$3";; *) echo "store list|install|remove <id>";; esac;;
  *) echo "ZeshinV: status freeram diag wifi ping scan apps theme store";;
esac
