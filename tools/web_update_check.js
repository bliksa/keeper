// Injected into build/web/index.html by tools/export_web.sh (BUILD_SHA is replaced).
// Checks version.json (written next to the page at export: the build and its
// recent commits) on load, every minute and when the tab comes back. A newer
// build: a chime and a card "New version" with, in a few words, what is new since
// this page's build. On the boot / title screens the page then reloads by itself
// after a few seconds (once per new build); during play or in developer mode
// (unsaved edits) it waits for the Reload button. The game reports its state and
// language in window.keeperState / window.keeperLang (main.gd _report_state).
(function () {
  var BUILD = "BUILD_SHA";
  var told = false;
  var T = {
    sk: { title: "Nová verzia", news: "Čo je nové:", reload: "Obnoviť", all: "Všetky zmeny", soon: "Obnovím o %d s…", more: "…a ďalšie (%d)" },
    en: { title: "New version", news: "What's new:", reload: "Reload", all: "All changes", soon: "Reloading in %d s…", more: "…and %d more" },
    pt: { title: "Nova versão", news: "O que há de novo:", reload: "Recarregar", all: "Todas as alterações", soon: "A recarregar em %d s…", more: "…e mais %d" }
  };
  function tr() {
    var l = (window.keeperLang || navigator.language || "en").slice(0, 2).toLowerCase();
    return T[l] || T.en;
  }
  function chime() {
    try {
      var A = window.AudioContext || window.webkitAudioContext;
      var ctx = new A();
      [[988, 0], [1319, 0.12]].forEach(function (n) {
        var o = ctx.createOscillator(), g = ctx.createGain();
        o.type = "sine"; o.frequency.value = n[0];
        g.gain.setValueAtTime(0.0001, ctx.currentTime + n[1]);
        g.gain.exponentialRampToValueAtTime(0.25, ctx.currentTime + n[1] + 0.02);
        g.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + n[1] + 0.6);
        o.connect(g); g.connect(ctx.destination);
        o.start(ctx.currentTime + n[1]); o.stop(ctx.currentTime + n[1] + 0.65);
      });
    } catch (e) {}
  }
  // The commits newer than this page's build (the list is newest first).
  function news(v) {
    var out = [];
    var list = v.changes || [];
    for (var i = 0; i < list.length; i++) {
      if (list[i].sha === BUILD) break;
      out.push(list[i].s);
    }
    return out;
  }
  function esc(s) { return String(s).replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]; }); }
  function card(v, auto) {
    var t = tr();
    var items = news(v);
    var d = document.createElement("div");
    d.id = "kc-update";
    d.style.cssText = "position:fixed;left:50%;top:12px;transform:translateX(-50%);z-index:20;max-width:min(560px,92vw);background:#f0eee9;color:#0f3d34;" +
      "font:500 13px KeeperComfortaa,sans-serif;padding:12px 14px 12px 18px;border-radius:18px;box-shadow:0 4px 18px rgba(0,0,0,.35)";
    var html = "<div style='display:flex;gap:12px;align-items:center'><b style='font-size:15px;flex:1'>" + esc(t.title) +
      " <span style='color:#64748b;font-weight:500'>(" + esc(v.sha) + ")</span></b></div>";
    if (items.length) {
      html += "<div style='margin-top:6px;color:#334155'>" + esc(t.news) + "</div><ul style='margin:4px 0 0 18px;padding:0;line-height:1.45'>";
      items.slice(0, 4).forEach(function (s) { html += "<li>" + esc(s) + "</li>"; });
      if (items.length > 4) html += "<li style='list-style:none;color:#64748b'>" + esc(t.more.replace("%d", items.length - 4)) + "</li>";
      html += "</ul>";
    }
    html += "<div style='display:flex;gap:10px;align-items:center;margin-top:10px'><a href='changelog.html' target='_blank' style='color:#16a34a'>" + esc(t.all) + "</a><span id='kc-soon' style='flex:1;color:#64748b;text-align:right'></span></div>";
    d.innerHTML = html;
    var row = d.lastChild;
    var b = document.createElement("button");
    b.textContent = t.reload;
    b.style.cssText = "font:700 13px KeeperComfortaa,sans-serif;background:#16a34a;color:#fff;border:0;border-radius:12px;padding:7px 14px;cursor:pointer";
    b.onclick = function () { location.reload(); };
    var x = document.createElement("button");
    x.textContent = "×";
    x.style.cssText = "font:700 16px sans-serif;background:none;border:0;color:#64748b;cursor:pointer";
    x.onclick = function () { auto = false; d.remove(); };
    row.appendChild(b); row.appendChild(x);
    document.body.appendChild(d);
    if (auto) {
      var n = 6;
      var soon = d.querySelector("#kc-soon");
      var tick = function () {
        if (!auto) return;
        soon.textContent = t.soon.replace("%d", n);
        if (n-- <= 0) { location.reload(); return; }
        setTimeout(tick, 1000);
      };
      tick();
    }
  }
  function check() {
    if (told) return;
    fetch("version.json?t=" + Date.now(), { cache: "no-store" }).then(function (r) { return r.ok ? r.json() : null; }).then(function (v) {
      if (!v || !v.sha || v.sha === BUILD || told) return;
      told = true;
      chime();
      var st = window.keeperState || "";
      var tried = "";
      try { tried = sessionStorage.getItem("keeperReloadFor") || ""; } catch (e) {}
      // Once per new build: if the page still comes back old (a cache), no auto reload.
      var auto = (st === "" || st === "boot" || st === "title") && tried !== v.sha;
      if (auto) {
        try { sessionStorage.setItem("keeperReloadFor", v.sha); } catch (e) {}
      }
      card(v, auto);
    }).catch(function () {});
  }
  check();
  setInterval(check, 60000);
  document.addEventListener("visibilitychange", function () { if (!document.hidden) check(); });
})();
