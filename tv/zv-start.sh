#!/bin/sh
# Avvia il bridge HTTP. Richiamalo dallo script di autostart di SamyGo/exeDSP.
ZV=/mtd_rwcommon/zeshinv
mkdir -p $ZV/www/cgi-bin
cp $ZV/zv.cgi $ZV/www/cgi-bin/zv.cgi && chmod 755 $ZV/www/cgi-bin/zv.cgi $ZV/zv.sh
[ -f $ZV/token ] || (head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' > $ZV/token)
# Se "httpd" non esiste in busybox, vedi README (alternativa: nc loop)
busybox httpd -p 8081 -h $ZV/www 2>/dev/null || httpd -p 8081 -h $ZV/www
echo "ZeshinV bridge su :8081 - token: $(cat $ZV/token)"
[ -f $ZV/theme.active ] && sh $ZV/zv.sh theme apply "$(cat $ZV/theme.active)"
