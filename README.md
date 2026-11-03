# ZeshinV - Store e strumenti per Samsung UE46ES6200

Tre parti:
- `tv/`     script shell che girano **sulla TV** (fanno il lavoro vero)
- `widget/` app Orsay (interfaccia a schermo, telecomando)
- catalog.txt / catalog.json  catalogo (gia' pubblicato su GitHub Pages: https://zeshinv.github.io/zeshinv-store/)

Il widget non puo' eseguire nulla sul sistema: parla via HTTP locale (porta 8081) con `zv.cgi`, che richiama `zv.sh`.

## Installazione
1. **GitHub Pages**: crea il repo `zeshinv-store`, abilita Pages, carica `catalog.txt`, `catalog.json` e gli zip delle app in `apps/`. Gli URL sono gia' impostati su zeshinv.
   L'MD5 di ogni zip: `md5sum app.zip`. Senza MD5 corretto l'installazione viene annullata.
2. **FTP -> TV**: copia `tv/zv.sh`, `tv/zv.cgi`, `tv/zv-start.sh` in `/mtd_rwcommon/zeshinv/` (o altra cartella scrivibile e persistente sul tuo firmware).
3. **Telnet**: `chmod 755 /mtd_rwcommon/zeshinv/*.sh`, poi `sh /mtd_rwcommon/zeshinv/zv-start.sh`. Stampa il token: incollalo in `widget/js/main.js` (`CFG.token`).
4. Aggiungi `zv-start.sh` all'autostart di SamyGo/exeDSP per averlo a ogni accensione.
5. **Widget**: aggiungi icone in `widget/images/` (`icon_106.png`, `icon_115.png`, `icon_95.png`, `icon_85.png`), installa come app utente (modalita' sviluppatore, IP del server) o copia la cartella nella directory widget utente.

## Prova subito da telnet (senza widget)
```
sh /mtd_rwcommon/zeshinv/zv.sh wifi
sh /mtd_rwcommon/zeshinv/zv.sh diag
sh /mtd_rwcommon/zeshinv/zv.sh scan
```
**Comincia da `wifi` e `scan`**: mandami l'output e adatto lo script al tuo firmware.

## Cose NON verificate (dipendono dal tuo firmware)
- `busybox httpd` puo' non esistere. Se manca, serve un'alternativa (loop con `nc`) o un httpd compilato per ARM: dimmelo.
- Percorsi `USER_APPS_DIR` e `NATIVE_APPS_DIR` sono ipotesi: usa `zv.sh scan` e correggili in `zv.conf`.
- **Tema**: non esiste un tema ufficiale modificabile. Lo script gestisce backup/applicazione/ripristino di file sostitutivi (cartella `themes/<nome>/` con `manifest`), ma i file Smart Hub da alleggerire vanno individuati sul tuo firmware. Subito utile: `freeram`.
- **Diagnostica wifi**: il verdetto e' euristico (log kernel, interfacce, errori). Non puo' confermare un guasto fisico; se risulta alto, la scheda wifi/modulo USB interno e' il sospettato principale. Prova anche un adattatore USB/LAN cavo.
- Le app native disattivate vengono **spostate**, non cancellate (reversibile). Le app di sistema (Settings, Hub, Source, Network, Support) sono protette.
- Il widget e' accessibile a chiunque sulla tua LAN senza il token: tienilo segreto.
- Rischio: modificare file di sistema puo' mandare in loop la TV. Fai sempre backup della flash prima.
