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

import { createCoordinateMapper } from "./coordinate_mapper";

const WIDTH = 14476;
const HEIGHT = 10800;
const extent = [0, 0, WIDTH, HEIGHT];

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
      center: [WIDTH / 2, HEIGHT / 2],
      extent: extent,
      constrainOnlyCenter: true,
      maxZoom: 7,
      minZoom: 0,
      zoom: 2,
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

  // these are their actual in-game coordinates
  // TODO: right now this only uses 4 points
  // would be better if they were on the corners of the map
  // or figure out a better homography implementation
  const sourcePoints = {
    // Eastern Kingdoms
    0: [
      [-8913.14, -137.78], // Northshire Abbey
      [1668.45, 1662.34], // Shadow Grave
      [2271.09, -5341.49], // Light's Hope Chapel
      [-10619.08, 1036.77], // Sentinel Hill
    ],
    // Kalimdor
    1: [
      [-6815.12, 730.3], // Cenarion Hold
      [6462.24, 807.09], // Auberdine
      [-956.86, -3754.77], // Ratchet
      [-6291.55, -1158.62], // Marshal's Refuge
    ],
  };

  // coordinates on map image
  const targetPoints = {
    // Eastern Kingdoms
    0: [
      [9315.15, 3893.04], // Northshire Abbey
      [8656.9, 7777.56], // Shadow Grave
      [11247.6, 8037.48], // Light's Hope Chapel
      [8866.79, 3240.56], // Sentinel Hill
    ],
    // Kalimdor
    1: [
      [2115.13, 3181.3], // Cenarion Hold
      [2037.43, 8088.06], // Auberdine
      [3758.78, 5379.7], // Ratchet
      [2876.54, 3348.07], // Marshal's Refuge
    ],
  };

  const coordinateMapper = {
    0: createCoordinateMapper(sourcePoints[0], targetPoints[0]),
    1: createCoordinateMapper(sourcePoints[1], targetPoints[1]),
  };

  let markers = {};

  const addMarker = (entity) => {
    const convertCoords = coordinateMapper[entity.map];
    const [x, y] = convertCoords(entity.x, entity.y);
    const marker = new Feature({
      geometry: new Point([x, y]),
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
    const convertCoords = coordinateMapper[entity.map];
    const [x, y] = convertCoords(entity.x, entity.y);
    const marker = markers[entity.guid];
    marker.getGeometry().setCoordinates([x, y]);
  };

  const removeAllMarkers = () => {
    vectorSource.clear();
    markers = {};
  };

  return { addMarker, removeMarker, updateMarker, removeAllMarkers };
};
