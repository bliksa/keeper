// Injected into build/web/index.html by tools/export_web.sh (BUILD_SHA is replaced).
// Checks version.json (written next to the page at export) on load, every minute
// and when the tab comes back. A newer build: a chime, then on the boot / title
// screens the page reloads at once; during play or in developer mode (unsaved
// edits) a bar offers the reload (the game reports its state in
// window.keeperState, main.gd _report_state).
(function () {
  var BUILD = "BUILD_SHA";
  var told = false;
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
  function bar(sha) {
    var d = document.createElement("div");
    d.style.cssText = "position:fixed;left:50%;top:12px;transform:translateX(-50%);z-index:20;background:#f0eee9;color:#0f3d34;" +
      "font:600 14px KeeperComfortaa,sans-serif;padding:10px 14px 10px 18px;border-radius:18px;box-shadow:0 4px 18px rgba(0,0,0,.35);display:flex;gap:12px;align-items:center";
    d.innerHTML = "<span>New version (" + sha + ")</span>";
    var b = document.createElement("button");
    b.textContent = "Reload";
    b.style.cssText = "font:700 13px KeeperComfortaa,sans-serif;background:#16a34a;color:#fff;border:0;border-radius:12px;padding:7px 14px;cursor:pointer";
    b.onclick = function () { location.reload(); };
    var x = document.createElement("button");
    x.textContent = "×";
    x.style.cssText = "font:700 16px sans-serif;background:none;border:0;color:#64748b;cursor:pointer";
    x.onclick = function () { d.remove(); };
    d.appendChild(b); d.appendChild(x);
    document.body.appendChild(d);
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
      if ((st === "" || st === "boot" || st === "title") && tried !== v.sha) {
        // Once per new build: if the page still comes back old (a cache), the bar.
        try { sessionStorage.setItem("keeperReloadFor", v.sha); } catch (e) {}
        setTimeout(function () { location.reload(); }, 900);
      } else {
        bar(v.sha);
      }
    }).catch(function () {});
  }
  check();
  setInterval(check, 60000);
  document.addEventListener("visibilitychange", function () { if (!document.hidden) check(); });
})();
