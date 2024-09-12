use namigator::raw::{build_bvh, build_map, bvh_files_exist, map_files_exist, PathfindMap};
use namigator::vanilla::Map;
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
    pub fn new() -> Self {
        Self {
            maps: HashMap::new(),
        }
    }

    pub fn load(&mut self, out_dir: &str) -> Result<(), String> {
        let output = PathBuf::from(out_dir);

        const MAPS_TO_PROCESS: &[Map] = &[
            Map::EasternKingdoms,
            Map::Kalimdor,
            Map::DevelopmentLand,
            // TODO: add all
        ];

        for &map in MAPS_TO_PROCESS {
            let map_file_name = map.directory_name();
            let map_id = map.as_int();

            let pathfind_map =
                PathfindMap::new(&output, map_file_name).map_err(|e| e.to_string())?;

            self.maps.insert(map_id, pathfind_map);
        }

        Ok(())
    }

    pub fn get_zone_and_area(
        &mut self,
        map_id: u32,
        x: f32,
        y: f32,
        z: f32,
    ) -> Result<(u32, u32), String> {
        if let Some(map) = self.maps.get_mut(&map_id) {
            let _adt = map.load_adt_at(x, y);
            // TODO: maybe keep tack of loaded adts, so i can unload them later?
            map.get_zone_and_area(x, y, z).map_err(|e| e.to_string())
        } else {
            Err(format!("Map with ID '{}' not found", map_id))
        }
    }

    pub fn find_random_point_around_circle(
        &mut self,
        map_id: u32,
        start: Vector3d,
        radius: f32,
    ) -> Result<Vector3d, String> {
        if let Some(map) = self.maps.get_mut(&map_id) {
            let _adt = map.load_adt_at(start.x, start.y);
            // TODO: maybe keep tack of loaded adts, so i can unload them later?
            map.find_random_point_around_circle(start, radius)
                .map_err(|e| e.to_string())
        } else {
            Err(format!("Map with ID '{}' not found", map_id))
        }
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn build(wow_dir: String, out_dir: String) -> NifResult<bool> {
    let data_path = PathBuf::from(wow_dir);
    let output = PathBuf::from(out_dir);

    println!("Building maps...");
    println!("Source: {:?}", data_path);
    println!("Output: {:?}", output);

    let threads = std::thread::available_parallelism()
        .map(|n| n.get().saturating_sub(2).max(1) as u32)
        .unwrap_or(1);

    if !bvh_files_exist(&output).map_err(|e| rustler::Error::Term(Box::new(e.to_string())))? {
        println!("Building BVH...");
        build_bvh(&data_path, &output, threads)
            .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;
    } else {
        println!("BVH already built, skipping...");
    }

    const MAPS_TO_PROCESS: &[Map] = &[
        Map::EasternKingdoms,
        Map::Kalimdor,
        Map::DevelopmentLand,
        // TODO: add all
    ];

    for &map in MAPS_TO_PROCESS {
        let map_file_name = map.directory_name();

        if !map_files_exist(&output, map_file_name)
            .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?
        {
            println!("Building {map} [{map_file_name}]...");
            build_map(&data_path, &output, map_file_name, "", threads)
                .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;
        } else {
            println!("{map} ({map_file_name}) already built, skipping...");
        }
    }

    Ok(true)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn load(out_dir: String) -> NifResult<bool> {
    let mut maps = PathfindingMaps::new();
    match maps.load(&out_dir) {
        Ok(()) => {
            let mut global_maps = PATHFINDING_MAPS.lock().unwrap();
            *global_maps = Some(maps);
            Ok(true)
        }
        Err(_) => Ok(false),
    }
}

#[rustler::nif]
fn get_zone_and_area(map_id: u32, x: f32, y: f32, z: f32) -> NifResult<Option<(u32, u32)>> {
    let mut global_maps = PATHFINDING_MAPS.lock().unwrap();
    match &mut *global_maps {
        Some(maps) => match maps.get_zone_and_area(map_id, x, y, z) {
            Ok((zone, area)) => Ok(Some((zone, area))),
            Err(_) => Ok(None),
        },
        None => Ok(None),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn find_random_point_around_circle(
    map_id: u32,
    x: f32,
    y: f32,
    z: f32,
    radius: f32,
) -> NifResult<Option<(f32, f32, f32)>> {
    let mut global_maps = PATHFINDING_MAPS.lock().unwrap();
    match &mut *global_maps {
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
