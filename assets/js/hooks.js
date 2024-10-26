import { setupMap } from "./map";

const hooks = {};

hooks.Map = {
  mounted() {
    const { addMarker, removeMarker, updateMarker, removeAllMarkers } =
      setupMap(this.el);
    this.cleanup = removeAllMarkers;
    this.handleEvent("entity_updates", ({ added, updated, removed }) => {
      added.forEach(addMarker);
      updated.forEach(updateMarker);
      removed.forEach(removeMarker);
    });
    this.pushEvent("map_ready", true);
  },
  reconnected() {
    if (this.cleanup) {
      this.cleanup();
    }
    this.pushEvent("map_ready", true);
  },
};

export default hooks;
