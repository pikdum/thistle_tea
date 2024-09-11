use namigator::raw::{build_bvh, build_map, bvh_files_exist, map_files_exist, PathfindMap};
use namigator::vanilla::{Map, VanillaMap};
use namigator::Vector3d;
use once_cell::sync::Lazy;
use rustler::{Encoder, Env, NifResult, Term};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Mutex;

static PATHFINDING_MAPS: Lazy<Mutex<Option<PathfindingMaps>>> = Lazy::new(|| Mutex::new(None));

#[derive(Debug)]
pub struct PathfindingMaps {
    maps: HashMap<Map, VanillaMap>,
    raw_maps: HashMap<String, PathfindMap>,
}

impl PathfindingMaps {
    pub fn new(wow_dir: &str, out_dir: &str) -> Result<Self, String> {
        let data_path = PathBuf::from(wow_dir);
        let output = PathBuf::from(out_dir);

        println!("Building and using maps for pathfind from data directory '{}' and outputting to '{}'. This may take a while.", data_path.display(), output.display());
        let mut m = HashMap::new();
        let mut raw_m = HashMap::new();

        let threads = {
            let t = std::thread::available_parallelism().unwrap().get() as u32;
            let t = t.saturating_sub(2);
            if t == 0 {
                1
            } else {
                t
            }
        };

        if !bvh_files_exist(&output).map_err(|e| e.to_string())? {
            println!("Building gameobjects.");
            build_bvh(&data_path, &output, threads).map_err(|e| e.to_string())?;
            println!("Gameobjects built.");
        } else {
            println!("Gameobjects already built.");
        }

        const MAP: Map = Map::DevelopmentLand;
        const MAP_FILE_NAME: &str = "development";

        if !map_files_exist(&output, MAP_FILE_NAME).map_err(|e| e.to_string())? {
            println!("Building map {MAP} ({})", MAP_FILE_NAME);
            build_map(&data_path, &output, MAP_FILE_NAME, "", threads)
                .map_err(|e| e.to_string())?;
            println!("Finished building {MAP} ({})", MAP_FILE_NAME);
        } else {
            println!("{MAP} ({}) already built.", MAP_FILE_NAME);
        }

        let mut v = VanillaMap::build_gameobjects_and_map(&data_path, &output, MAP, threads)
            .map_err(|e| e.to_string())?;
        v.load_all_adts().map_err(|e| e.to_string())?;
        m.insert(MAP, v);
        println!("VanillaMap inserted with key: {:?}", MAP);

        let mut raw_map = PathfindMap::new(&output, MAP_FILE_NAME).map_err(|e| e.to_string())?;
        raw_map.load_all_adts().map_err(|e| e.to_string())?;
        raw_m.insert(MAP_FILE_NAME.to_string(), raw_map);
        println!("PathfindMap inserted with key: {}", MAP_FILE_NAME);

        println!("Finished setting up maps");

        Ok(Self {
            maps: m,
            raw_maps: raw_m,
        })
    }

    pub fn get(&self, map: &Map) -> Option<&VanillaMap> {
        self.maps.get(&map)
    }

    pub fn get_zone_and_area(
        &self,
        map_name: &str,
        x: f32,
        y: f32,
        z: f32,
    ) -> Result<(u32, u32), String> {
        if let Some(map) = self.raw_maps.get(map_name) {
            map.get_zone_and_area(x, y, z).map_err(|e| e.to_string())
        } else {
            Err(format!("Map '{}' not found", map_name))
        }
    }

    pub fn find_random_point_around_circle(
        &self,
        map_name: &str,
        start: Vector3d,
        radius: f32,
    ) -> Result<Vector3d, String> {
        if let Some(map) = self.raw_maps.get(map_name) {
            map.find_random_point_around_circle(start, radius)
                .map_err(|e| e.to_string())
        } else {
            Err(format!("Map '{}' not found", map_name))
        }
    }
}

#[rustler::nif]
fn build(wow_dir: String, out_dir: String) -> NifResult<bool> {
    match PathfindingMaps::new(&wow_dir, &out_dir) {
        Ok(maps) => {
            let mut global_maps = PATHFINDING_MAPS.lock().unwrap();
            *global_maps = Some(maps);
            println!("PathfindingMaps built successfully");
            Ok(true)
        }
        Err(e) => {
            eprintln!("Error building PathfindingMaps: {}", e);
            Ok(false)
        }
    }
}

#[rustler::nif]
fn get_map(map_name: String) -> NifResult<bool> {
    println!("get_map called with map_name: {}", map_name);
    let global_maps = PATHFINDING_MAPS.lock().unwrap();
    match &*global_maps {
        Some(maps) => {
            let map = match map_name.as_str() {
                "development" => Map::DevelopmentLand,
                // Add other map variants as needed
                _ => {
                    println!("Unknown map name: {}", map_name);
                    return Ok(false);
                }
            };
            let result = maps.get(&map).is_some();
            println!("Map {} found: {}", map_name, result);
            Ok(result)
        }
        None => {
            println!("PathfindingMaps not initialized");
            Ok(false)
        }
    }
}

#[rustler::nif]
fn get_zone_and_area(map_name: String, x: f32, y: f32, z: f32) -> NifResult<Option<(u32, u32)>> {
    let global_maps = PATHFINDING_MAPS.lock().unwrap();
    match &*global_maps {
        Some(maps) => match maps.get_zone_and_area(&map_name, x, y, z) {
            Ok((zone, area)) => Ok(Some((zone, area))),
            Err(_) => Ok(None),
        },
        None => Ok(None),
    }
}

#[rustler::nif]
fn find_random_point_around_circle(
    map_name: String,
    x: f32,
    y: f32,
    z: f32,
    radius: f32,
) -> NifResult<Option<(f32, f32, f32)>> {
    let global_maps = PATHFINDING_MAPS.lock().unwrap();
    match &*global_maps {
        Some(maps) => {
            let start = Vector3d { x: x, y: y, z: z };
            match maps.find_random_point_around_circle(&map_name, start, radius) {
                Ok(point) => Ok(Some((point.x, point.y, point.z))),
                Err(_) => Ok(None),
            }
        }
        None => Ok(None),
    }
}

rustler::init!("Elixir.ThistleTea.Namigator");
