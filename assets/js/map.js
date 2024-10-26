import { Map, View, Overlay } from "ol";
import TileLayer from "ol/layer/Tile";
import VectorLayer from "ol/layer/Vector";
import VectorSource from "ol/source/Vector";
import XYZ from "ol/source/XYZ";
import Projection from "ol/proj/Projection";
import Feature from "ol/Feature";
import Point from "ol/geom/Point";
import { Style, Circle, Fill, Stroke, Text } from "ol/style";
import Cluster from "ol/source/Cluster";
import { bbox as bboxStrategy } from "ol/loadingstrategy";
import { FullScreen, defaults as defaultControls } from "ol/control";

const WIDTH = 14476;
const HEIGHT = 10800;
const extent = [0, 0, WIDTH, HEIGHT];

// bit custom to make it look nice
const CENTER = [6328.524649884811, 6002.505656354451];
const INITIAL_ZOOM = 1.3;

export const setupMap = (el) => {
  const projection = new Projection({
    code: "game-map",
    units: "pixels",
    extent: extent,
  });

  const vectorSource = new VectorSource({
    strategy: bboxStrategy,
  });

  const clusterSource = new Cluster({
    distance: 40,
    source: vectorSource,
  });

  const markerLayer = new VectorLayer({
    source: clusterSource,
    style: (feature) => {
      const size = feature.get("features").length;
      return new Style({
        image: new Circle({
          radius: size > 1 ? 20 : 10,
          fill: new Fill({ color: size > 1 ? "orange" : "brown" }),
          stroke: new Stroke({
            color: "white",
            width: 2,
          }),
        }),
        text:
          size > 1
            ? new Text({
                text: size.toString(),
                fill: new Fill({ color: "white" }),
                font: "bold 18px sans-serif",
              })
            : null,
      });
    },
  });

  const popup = document.createElement("div");
  popup.className =
    "absolute bottom-4 -translate-x-1/2 rounded-md bg-black text-white opacity-80 p-2 px-4";

  const overlay = new Overlay({
    element: popup,
    offset: [0, 0],
    positioning: "bottom-center",
    stopEvent: false,
  });

  const map = new Map({
    target: el.id,
    controls: defaultControls().extend([
      new FullScreen({ source: "map-wrapper", inactiveClassName: "bottom-4" }),
    ]),
    layers: [
      new TileLayer({
        source: new XYZ({
          url: "https://fly.storage.tigris.dev/vanilla-map/{z}/{x}/{y}.png",
          minZoom: 0,
          maxZoom: 7,
          projection: projection,
        }),
      }),
      markerLayer,
    ],
    overlays: [overlay],
    view: new View({
      projection: projection,
      center: CENTER,
      extent: extent,
      constrainOnlyCenter: true,
      maxZoom: 7,
      minZoom: 0,
      zoom: INITIAL_ZOOM,
    }),
  });

  map.on("pointermove", (event) => {
    if (event.dragging) {
      popup.style.display = "none";
      return;
    }

    const feature = map.forEachFeatureAtPixel(
      event.pixel,
      (feature) => feature,
    );

    if (feature) {
      const features = feature.get("features");
      if (features) {
        const names = features
          .map((f) => f.get("guid"))
          .sort((a, b) => a.localeCompare(b))
          .join("\n");
        popup.innerHTML = names;
        popup.style.display = "block";
        overlay.setPosition(event.coordinate);
      }
    } else {
      popup.style.display = "none";
    }
  });

  map.on("click", (event) => {
    const coords = map.getEventCoordinate(event.originalEvent);
    console.log(`[${coords[0]}, ${coords[1]}]`);
  });

  let markers = {};

  const addMarker = (entity) => {
    const marker = new Feature({
      geometry: new Point([entity.x, entity.y]),
      guid: entity.name,
    });
    vectorSource.addFeature(marker);
    markers[entity.guid] = marker;
  };

  const removeMarker = (entity) => {
    const marker = markers[entity.guid];
    vectorSource.removeFeature(marker);
    delete markers[entity.guid];
  };

  const updateMarker = (entity) => {
    const marker = markers[entity.guid];
    marker.getGeometry().setCoordinates([entity.x, entity.y]);
  };

  const removeAllMarkers = () => {
    vectorSource.clear();
    markers = {};
  };

  return { addMarker, removeMarker, updateMarker, removeAllMarkers };
};
