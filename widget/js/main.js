/* ZeshinV - widget Orsay (JS ES5, nessuna libreria) */
var ZV = (function () {
  var CFG = {
    bridge: "http://127.0.0.1:8081/cgi-bin/zv.cgi",
    token: "",   // incolla qui il contenuto di /mtd_rwcommon/zeshinv/token
    catalog: "https://zeshinv.github.io/zeshinv-store/catalog.json"
  };
  var KEY = { LEFT: 4, RIGHT: 5, UP: 29460, DOWN: 29461, ENTER: 29443, RETURN: 88 };
  var SECTIONS = ["Store", "Sistema", "App native", "Diagnostica"];
  var tab = 0, sel = 0, items = [], busy = false;
  var $ = function (id) { return document.getElementById(id); };

  function demoReply(cmd) {
    if (cmd.indexOf("wifi") === 0) return "== Wireless ==\nNESSUNA interfaccia wireless registrata\n\n== VERDETTO ==\nALTA probabilita' di problema scheda wifi";
    if (cmd.indexOf("apps list") === 0) return "== NATIVE ==\nATTIVA 111477000562 13704KB TIMVISION\nPROTETTA 20121000004 10968KB Web_Browser\nATTIVA 111299000190 2352KB La_Gazzetta_dello_Sport\n== DISATTIVATE ==";
    if (cmd.indexOf("status") === 0) return "== MEMORIA ==\nMemTotal: 509076 kB\nMemFree: 28068 kB\nMemFree: 28068 kB\n== CPU load ==\n1.38 1.23 0.99";
    return "OK";
  }
  function xhr(url, cb) {
    if (DEMO && url.indexOf("catalog") >= 0) { cb('{"apps":[{"id":"a","name":"App di prova","version":"1.0","desc":"Esempio"},{"id":"b","name":"Lettore video","version":"2.1","desc":"x"},{"id":"c","name":"Meteo","version":"0.9","desc":"x"}]}'); return; }
    var r = new XMLHttpRequest();
    r.onreadystatechange = function () {
      if (r.readyState === 4) cb(r.status === 200 || r.status === 0 ? r.responseText : "ERRORE HTTP " + r.status);
    };
    r.open("GET", url, true);
    r.send();
  }
  var DEMO = (typeof location !== "undefined" && /[?&]demo/.test(location.search || ""));
  function bridge(cmd, cb) {
    if (DEMO) { cb(demoReply(cmd)); return; }
    xhr(CFG.bridge + "?token=" + CFG.token + "&cmd=" + encodeURIComponent(cmd).replace(/%20/g, "+"), cb);
  }
  function out(t) { $("out").innerHTML = String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").substring(0, 4500); }

  function drawTabs() {
    var h = "";
    for (var i = 0; i < SECTIONS.length; i++) h += '<span class="tab' + (i === tab ? " on" : "") + '">' + SECTIONS[i] + "</span>";
    $("tabs").innerHTML = h;
  }
  function drawList() {
    var h = "", start = Math.max(0, sel - 4);
    for (var i = start; i < items.length && i < start + 9; i++) {
      h += '<div class="item' + (i === sel ? " sel" : "") + '">' + items[i].label +
           (items[i].sub ? '<span class="sub">' + items[i].sub + "</span>" : "") + "</div>";
    }
    $("list").innerHTML = h || '<div class="item">(vuoto)</div>';
  }
  function setItems(a) { items = a; sel = 0; drawList(); }

  function loadTab() {
    drawTabs(); out(""); sel = 0;
    if (tab === 0) {
      setItems([{ label: "Carico catalogo...", act: null }]);
      xhr(CFG.catalog, function (t) {
        try {
          var c = JSON.parse(t), a = [];
          for (var i = 0; i < c.apps.length; i++) {
            (function (app) {
              a.push({ label: app.name, sub: "v" + app.version, act: function () {
                out(app.desc + "\n\nInstallo...");
                bridge("store install " + app.id, out);
              } });
            })(c.apps[i]);
          }
          setItems(a);
        } catch (e) { setItems([{ label: "Catalogo non leggibile", act: null }]); out(t); }
      });
    } else if (tab === 1) {
      setItems([
        { label: "Stato memoria/CPU", act: function () { bridge("status", out); } },
        { label: "Libera RAM (cache)", act: function () { bridge("freeram", out); } },
        { label: "Elenco temi", act: function () { bridge("theme list", out); } },
        { label: "Applica tema 'lite'", act: function () { bridge("theme apply lite", out); } },
        { label: "Ripristina tema originale", act: function () { bridge("theme restore", out); } },
        { label: "Cerca cartelle app (scan)", act: function () { bridge("scan", out); } }
      ]);
    } else if (tab === 2) {
      setItems([{ label: "Carico...", act: null }]);
      bridge("apps list", function (t) {
        var lines = t.split("\n"), a = [];
        for (var i = 0; i < lines.length; i++) {
          var m = lines[i].match(/^(ATTIVA|PROTETTA|OFF)\s+(\S+)\s+\S+\s*(.*)$/);
          if (m) (function (state, id, name) {
            var label = (name && name !== "-" ? name.replace(/^- /, "") : "?") + " (" + id + ")";
            if (state === "PROTETTA") { a.push({ label: label, sub: "[protetta]", act: function () { out("Protetta: non disattivabile da qui."); } }); return; }
            a.push({ label: label, sub: state === "OFF" ? "[off] OK=riattiva" : "[attiva] OK=disattiva",
              act: function () { bridge("apps " + (state === "OFF" ? "enable " : "disable ") + id, function (r) { out(r); loadTab(); }); } });
          })(m[1], m[2], m[3]);
        }
        setItems(a); out(a.length ? "Le modifiche richiedono riavvio TV.\nSono reversibili." : t);
      });
    } else {
      setItems([
        { label: "Diagnostica WiFi", act: function () { out("Analisi..."); bridge("wifi", out); } },
        { label: "Diagnostica completa", act: function () { out("Analisi..."); bridge("diag", out); } },
        { label: "Ping 8.8.8.8", act: function () { out("Ping..."); bridge("ping 8.8.8.8", out); } },
        { label: "Ping 1.1.1.1", act: function () { bridge("ping 1.1.1.1", out); } }
      ]);
    }
  }

  function onKey(code) {
    if (code === KEY.LEFT || code === 37) { tab = (tab + SECTIONS.length - 1) % SECTIONS.length; loadTab(); }
    else if (code === KEY.RIGHT || code === 39) { tab = (tab + 1) % SECTIONS.length; loadTab(); }
    else if (code === KEY.UP || code === 38) { if (sel > 0) sel--; drawList(); }
    else if (code === KEY.DOWN || code === 40) { if (sel < items.length - 1) sel++; drawList(); }
    else if (code === KEY.ENTER || code === 13) { if (items[sel] && items[sel].act) items[sel].act(); }
    else if (code === KEY.RETURN || code === 8) {
      try { new Common.API.Widget().blockNavigation(event); new Common.API.Widget().sendReturnEvent(); } catch (e) {}
    }
  }

  return {
    init: function () {
      if (!CFG.token && !DEMO) out("Configura il token in js/main.js (vedi README).");
      document.onkeydown = function (e) { e = e || window.event; onKey(e.keyCode); };
      try { new Common.API.Widget().sendReadyEvent(); } catch (e) {} // assente nel browser desktop (test)
      loadTab();
      setInterval(function () {
        if (CFG.token || DEMO) bridge("status", function (t) {
          var m = t.match(/MemFree:\s+(\d+)/);
          if (m) $("mem").innerHTML = "RAM libera " + Math.round(m[1] / 1024) + " MB";
        });
      }, 15000);
    }
  };
})();
