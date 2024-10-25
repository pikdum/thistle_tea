import { Map, View } from "ol";
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
          radius: size > 1 ? 15 : 5,
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

  const addMarker = (x, y) => {
    const newMarker = new Feature({
      geometry: new Point([x, y]),
    });
    vectorSource.addFeature(newMarker);
  };

  map.on("click", (event) => {
    const coords = map.getEventCoordinate(event.originalEvent);
    console.log(`Clicked at X: ${coords[0]}, Y: ${coords[1]}`);
  });

  // TODO: not very accurate, but good enough
  // these are their actual in-game coordinates
  const sourcePoints = [
    [-8913.14, -137.78], // Northshire Abbey
    [1668.45, 1662.34], // Shadow Grave
    [2271.09, -5341.49], // Light's Hope Chapel
    [-846.85, -520.79], // Southshore
    [-10619.08, 1036.77], // Sentinel Hill
  ];

  // these are the coordinates on the map image
  const targetPoints = [
    [9315.15, 3893.04], // Northshire Abbey
    [8656.9, 7777.56], // Shadow Grave
    [11247.6, 8037.48], // Light's Hope Chapel
    [9445.61, 6829.92], // Southshore
    [8866.79, 3240.56], // Sentinel Hill
  ];

  // Create the mapper
  const convertCoords = createCoordinateMapper(sourcePoints, targetPoints);

  const entitiesData = el.getAttribute("data-entities");
  const entities = JSON.parse(entitiesData);

  entities.forEach((entity) => {
    const [x, y] = convertCoords(entity.x, entity.y);
    addMarker(x, y);
  });
};
