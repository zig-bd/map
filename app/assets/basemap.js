(function () {
  if (window.__zigBasemap) return;

  var STYLE = "https://tiles.openfreemap.org/styles/liberty";
  var MAX_MISS = 120;

  window.__zigBasemap = {
    map: null,
    lastKey: "",
    pending: null,
    raf: 0,
    misses: 0,
    observing: false,

    sync: function (lng, lat, z) {
      this.pending = { lng: lng, lat: lat, z: z };
      if (this.raf) return;
      var self = this;
      this.raf = requestAnimationFrame(function () {
        self.raf = 0;
        self.flush();
      });
    },

    flush: function () {
      if (typeof maplibregl === "undefined") {
        this.reschedule();
        return;
      }
      var el = document.getElementById("maplibre-basemap");
      if (!el) {
        this.misses += 1;
        if (this.misses < MAX_MISS) this.reschedule();
        return;
      }
      this.misses = 0;

      var p = this.pending;
      if (!p) return;
      var key =
        p.lng.toFixed(5) + "," + p.lat.toFixed(5) + "," + Number(p.z).toFixed(4);

      if (!this.map) {
        if (el.clientWidth < 2 || el.clientHeight < 2) {
          this.reschedule();
          return;
        }
        this.map = new maplibregl.Map({
          container: el,
          style: STYLE,
          center: [p.lng, p.lat],
          zoom: p.z,
          interactive: false,
          attributionControl: false,
          fadeDuration: 0,
          renderWorldCopies: false,
          pitchWithRotate: false,
          dragRotate: false,
        });
        this.lastKey = key;
        this.watch(el);
        var map = this.map;
        map.once("load", function () {
          map.resize();
        });
        requestAnimationFrame(function () {
          map.resize();
        });
        return;
      }

      this.map.resize();
      if (this.lastKey === key) return;
      this.lastKey = key;
      this.map.jumpTo({ center: [p.lng, p.lat], zoom: p.z });
    },

    reschedule: function () {
      if (this.raf) return;
      var self = this;
      this.raf = requestAnimationFrame(function () {
        self.raf = 0;
        self.flush();
      });
    },

    watch: function (el) {
      if (this.observing || typeof ResizeObserver === "undefined") return;
      this.observing = true;
      var self = this;
      new ResizeObserver(function () {
        if (self.map) self.map.resize();
      }).observe(el);
    },
  };
})();
