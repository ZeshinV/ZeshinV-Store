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
  echo "== TOP processi per RAM =="
  ps 2>/dev/null | sort -k3 -n -r 2>/dev/null | head -n 12
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

cmd_apps_list() {
  echo "== NATIVE ($NATIVE_APPS_DIR) =="
  for d in "$NATIVE_APPS_DIR"/*/; do [ -d "$d" ] && echo "ATTIVA  $(basename "$d")  $(du -sk "$d" 2>/dev/null | cut -f1)KB"; done
  echo "== DISATTIVATE =="
  for d in "$DISABLED_DIR"/*/; do [ -d "$d" ] && echo "OFF     $(basename "$d")"; done
}

cmd_apps_disable() {
  safe_id "$1" || { echo "ID non valido"; return 1; }
  [ -d "$NATIVE_APPS_DIR/$1" ] || { echo "App non trovata"; return 1; }
  # protezione: app critiche mai disattivabili
  case "$1" in *[Ss]ettings*|*[Hh]ub*|*[Ss]ource*|*[Nn]etwork*|*[Ss]upport*) echo "App di sistema protetta, rifiutato"; return 1;; esac
  mv "$NATIVE_APPS_DIR/$1" "$DISABLED_DIR/$1" && echo "Disattivata: $1 (riavvia la TV)"
}

cmd_apps_enable() {
  safe_id "$1" || { echo "ID non valido"; return 1; }
  [ -d "$DISABLED_DIR/$1" ] || { echo "Non e' tra le disattivate"; return 1; }
  mv "$DISABLED_DIR/$1" "$NATIVE_APPS_DIR/$1" && echo "Riattivata: $1 (riavvia la TV)"
}

# ---------- TEMA ----------
# Un tema = cartella in $ZV_HOME/themes/<nome>/ con file "manifest" (una riga: percorso_assoluto_target)
# e gli stessi file con nome flat. apply fa backup, restore ripristina.
cmd_theme_list() { ls "$ZV_HOME/themes" 2>/dev/null || echo "(nessun tema installato)"; }
cmd_theme_apply() {
  safe_id "$1" || { echo "ID non valido"; return 1; }
  T="$ZV_HOME/themes/$1"; [ -f "$T/manifest" ] || { echo "Tema non trovato"; return 1; }
  while read -r target; do
    [ -z "$target" ] && continue
    case "$target" in /mtd_rwcommon/*|/mtd_down/*|/mtd_exe/*) ;; *) echo "Percorso rifiutato: $target"; return 1;; esac
    b="$BACKUP_DIR/$(echo "$target" | tr '/' '_')"
    [ -f "$b" ] || cp "$target" "$b"
    cp "$T/$(basename "$target")" "$target" && echo "OK $target"
  done < "$T/manifest"
  echo "Tema applicato (riavvia la TV)"
}
cmd_theme_restore() {
  for b in "$BACKUP_DIR"/*; do
    [ -f "$b" ] || continue
    target=$(basename "$b" | tr '_' '/')
    cp "$b" "$target" && echo "Ripristinato $target"
  done
}

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
  theme) case "$2" in list) cmd_theme_list;; apply) cmd_theme_apply "$3";; restore) cmd_theme_restore;; *) echo "theme list|apply <n>|restore";; esac;;
  store) case "$2" in list) cmd_store_list;; install) cmd_store_install "$3";; remove) cmd_store_remove "$3";; *) echo "store list|install|remove <id>";; esac;;
  *) echo "ZeshinV: status freeram diag wifi ping scan apps theme store";;
esac
