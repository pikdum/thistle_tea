import { setupMap } from "./map";

const hooks = {};

hooks.Map = {
  mounted() {
    const { addMarker, removeMarker, updateMarker } = setupMap(this.el);
    window.addEventListener("phx:entity_updates", (e) => {
      const { added, updated, removed } = e.detail;
      added.forEach(addMarker);
      updated.forEach(updateMarker);
      removed.forEach(removeMarker);
    });
  },
  destroyed() {
    window.removeEventListener("phx:entity_updates");
  },
};

export default hooks;
