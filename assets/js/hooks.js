import { setupMap } from "./map";

const hooks = {};

hooks.Map = {
  mounted() {
    setupMap(this.el);
  },
  updated() {
    console.log("Map updated");
  },
  destroyed() {
    console.log("Map destroyed");
  },
};

export default hooks;
