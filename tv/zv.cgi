#!/bin/sh
# Bridge HTTP -> zv.sh (da usare con busybox httpd, porta 8081)
# Richiamo: http://127.0.0.1:8081/cgi-bin/zv.cgi?token=XXXX&cmd=apps+list
ZV=/mtd_rwcommon/zeshinv
TOKEN="$(cat $ZV/token 2>/dev/null)"

echo "Content-Type: text/plain; charset=utf-8"
echo "Access-Control-Allow-Origin: *"
echo ""

get() { echo "$QUERY_STRING" | tr '&' '\n' | grep "^$1=" | head -n1 | cut -d= -f2-; }
t=$(get token)
[ -n "$TOKEN" ] && [ "$t" = "$TOKEN" ] || { echo "ERRORE: token non valido"; exit 0; }

# cmd con "+" come separatore; solo caratteri sicuri
c=$(get cmd | tr '+' ' ')
echo "$c" | grep -Eq '^[A-Za-z0-9._ -]{1,120}$' || { echo "ERRORE: comando non valido"; exit 0; }
set -- $c
case "$1" in
  status|freeram|diag|wifi|ping|scan|apps|theme|store) sh $ZV/zv.sh "$@" 2>&1;;
  *) echo "ERRORE: comando non consentito";;
esac
