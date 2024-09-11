use namigator::raw::{build_bvh, build_map, bvh_files_exist, map_files_exist, PathfindMap};
use namigator::vanilla::{Map, VanillaMap};
use namigator::Vector3d;
use once_cell::sync::Lazy;
use rustler::NifResult;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Mutex;

static PATHFINDING_MAPS: Lazy<Mutex<Option<PathfindingMaps>>> = Lazy::new(|| Mutex::new(None));

#[derive(Debug)]
pub struct PathfindingMaps {
    maps: HashMap<u32, PathfindMap>,
}

impl PathfindingMaps {
    pub fn new(wow_dir: &str, out_dir: &str) -> Result<Self, String> {
        let data_path = PathBuf::from(wow_dir);
        let output = PathBuf::from(out_dir);

        println!("Building and using maps for pathfind from data directory '{}' and outputting to '{}'. This may take a while.", data_path.display(), output.display());
        let mut maps = HashMap::new();

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

        // Hardcoded list of Map variants to process
        const MAPS_TO_PROCESS: &[Map] = &[
            Map::EasternKingdoms,
            Map::Kalimdor,
            Map::DevelopmentLand,
            // Add other Map variants you want to process
        ];

        for &map in MAPS_TO_PROCESS {
            let map_file_name = map.directory_name();
            let map_id = map.as_int();

            if !map_files_exist(&output, map_file_name).map_err(|e| e.to_string())? {
                println!("Building map {:?} ({map_file_name})", map);
                build_map(&data_path, &output, map_file_name, "", threads)
                    .map_err(|e| e.to_string())?;
                println!("Finished building {:?} ({map_file_name})", map);
            } else {
                println!("{:?} ({map_file_name}) already built.", map);
            }

            let mut vanilla_map = VanillaMap::new(&output, map).map_err(|e| e.to_string())?;
            vanilla_map.load_all_adts().map_err(|e| e.to_string())?;

            let mut pathfind_map =
                PathfindMap::new(&output, map_file_name).map_err(|e| e.to_string())?;
            pathfind_map.load_all_adts().map_err(|e| e.to_string())?;

            maps.insert(map_id, pathfind_map);
            println!("PathfindMap inserted with key: {}", map_id);
        }

        println!("Finished setting up maps");

        Ok(Self { maps })
    }

    pub fn get_zone_and_area(
        &self,
        map_id: u32,
        x: f32,
        y: f32,
        z: f32,
    ) -> Result<(u32, u32), String> {
        if let Some(map) = self.maps.get(&map_id) {
            map.get_zone_and_area(x, y, z).map_err(|e| e.to_string())
        } else {
            Err(format!("Map with ID '{}' not found", map_id))
        }
    }

    pub fn find_random_point_around_circle(
        &self,
        map_id: u32,
        start: Vector3d,
        radius: f32,
    ) -> Result<Vector3d, String> {
        if let Some(map) = self.maps.get(&map_id) {
            map.find_random_point_around_circle(start, radius)
                .map_err(|e| e.to_string())
        } else {
            Err(format!("Map with ID '{}' not found", map_id))
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
fn get_zone_and_area(map_id: u32, x: f32, y: f32, z: f32) -> NifResult<Option<(u32, u32)>> {
    let global_maps = PATHFINDING_MAPS.lock().unwrap();
    match &*global_maps {
        Some(maps) => match maps.get_zone_and_area(map_id, x, y, z) {
            Ok((zone, area)) => Ok(Some((zone, area))),
            Err(_) => Ok(None),
        },
        None => Ok(None),
    }
}

#[rustler::nif]
fn find_random_point_around_circle(
    map_id: u32,
    x: f32,
    y: f32,
    z: f32,
    radius: f32,
) -> NifResult<Option<(f32, f32, f32)>> {
    let global_maps = PATHFINDING_MAPS.lock().unwrap();
    match &*global_maps {
        Some(maps) => {
            let start = Vector3d { x, y, z };
            match maps.find_random_point_around_circle(map_id, start, radius) {
                Ok(point) => Ok(Some((point.x, point.y, point.z))),
                Err(_) => Ok(None),
            }
        }
        None => Ok(None),
    }
}

rustler::init!("Elixir.ThistleTea.Namigator");
