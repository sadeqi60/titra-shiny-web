/* Standalone Shiny web bridge for Titra (1:1 AnyWidget traitlet adapter + chunked large JSON uploads) */
(function () {
  var host = document.getElementById("titra_host");
  if (!host) return;

  var listeners = {};
  var dirtyKeys = new Set();
  var store = {
    payload: {},
    selection: {},
    dag_state: {},
    svg_output: "",
    preset: "beta_ftg",
    report_request: {},
    report_result: {},
    input_request: {},
    input_state: { data_dir: "", files: [], loaded: "", report: null, modality: "lfp" },
    capabilities: { wasm: true, typst: false, docx: true },
  };

  function emit(ev) {
    var list = listeners[ev] || [];
    for (var i = 0; i < list.length; i++) {
      try { list[i](); } catch (e) { console.error("Titra listener error:", ev, e); }
    }
  }

  function sendChunked(directKey, chunkKey, req) {
    if (typeof window.Shiny === "undefined") return;
    var raw = JSON.stringify(req || {});
    var CHUNK = 900000;
    if (raw.length <= CHUNK) {
      window.Shiny.setInputValue(directKey, req, { priority: "event" });
      return;
    }
    var txId = "tx_" + Date.now() + "_" + Math.random().toString(36).slice(2, 7);
    var total = Math.ceil(raw.length / CHUNK);
    var idx = 0;
    function sendNext() {
      window.Shiny.setInputValue(
        chunkKey,
        { tx: txId, index: idx, total: total, data: raw.slice(idx * CHUNK, (idx + 1) * CHUNK) },
        { priority: "event" }
      );
      idx++;
      if (idx < total) setTimeout(sendNext, 12);
    }
    sendNext();
  }

  var model = {
    get: function (k) { return store[k]; },
    set: function (k, v) { store[k] = v; dirtyKeys.add(k); },
    save_changes: function () {
      var keys = Array.from(dirtyKeys);
      dirtyKeys.clear();
      if (typeof window.Shiny === "undefined") return;
      for (var i = 0; i < keys.length; i++) {
        var k = keys[i];
        if (k === "input_request") sendChunked("titra_input_request", "titra_input_chunk", store.input_request);
        else if (k === "report_request") sendChunked("titra_report_request", "titra_report_chunk", store.report_request);
        else if (k === "selection" || k === "dag_state" || k === "preset") window.Shiny.setInputValue("titra_" + k, store[k]);
      }
    },
    on: function (ev, fn) { (listeners[ev] = listeners[ev] || []).push(fn); },
    off: function (ev, fn) {
      if (!listeners[ev]) return;
      listeners[ev] = listeners[ev].filter(function (x) { return x !== fn; });
    },
  };

  function applyPatch(patch) {
    var order = ["capabilities", "selection", "preset", "payload", "input_state", "report_result", "dag_state"];
    var seen = new Set();
    for (var i = 0; i < order.length; i++) {
      var k = order[i];
      if (Object.prototype.hasOwnProperty.call(patch, k)) {
        seen.add(k);
        store[k] = patch[k];
        emit("change:" + k);
      }
    }
    Object.keys(patch).forEach(function (k) {
      if (!seen.has(k)) {
        store[k] = patch[k];
        emit("change:" + k);
      }
    });
  }

  function installHandler() {
    if (typeof window.Shiny !== "undefined" && window.Shiny.addCustomMessageHandler) {
      window.Shiny.addCustomMessageHandler("titra_web_patch", function (patch) {
        applyPatch(patch || {});
      });
    } else {
      setTimeout(installHandler, 40);
    }
  }
  installHandler();

  import("./nr_dag.js")
    .then(function (mod) {
      var api = mod && (mod.default || mod);
      api.render({ model: model, el: host });
    })
    .catch(function (err) {
      host.innerHTML =
        '<div style="padding:28px;font-family:Georgia,serif;color:#B81D33">Failed to load Titra Studio: ' +
        String(err && err.message ? err.message : err) +
        "</div>";
    });
})();
