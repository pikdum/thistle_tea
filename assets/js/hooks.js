import { setupMap } from "./map";

const hooks = {};

hooks.Map = {
  mounted() {
    const { addMarker, removeMarker, updateMarker } = setupMap(this.el);
    this.handleEvent("entity_updates", ({ added, updated, removed }) => {
      added.forEach(addMarker);
      updated.forEach(updateMarker);
      removed.forEach(removeMarker);
    });
    this.pushEvent("map_ready", true);
  },
};

export default hooks;
