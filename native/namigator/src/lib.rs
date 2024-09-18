use namigator::raw::{build_bvh, build_map, bvh_files_exist, map_files_exist, PathfindMap};
use namigator::vanilla::Map;
use namigator::Vector3d;
use once_cell::sync::Lazy;
use rustler::NifResult;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Mutex;

static PATHFINDING_MAPS: Lazy<Mutex<Option<PathfindingMaps>>> = Lazy::new(|| Mutex::new(None));

static MAPS_TO_PROCESS: &[Map] = &[
    Map::EasternKingdoms,
    Map::Kalimdor,
    Map::DevelopmentLand,
    // TODO: add all other maps here
];

struct PathfindingMaps {
    maps: HashMap<u32, PathfindMap>,
}

impl PathfindingMaps {
    fn new() -> Self {
        Self {
            maps: HashMap::new(),
        }
    }

    fn load(&mut self, out_dir: &str) -> Result<(), String> {
        let output = PathBuf::from(out_dir);

        for &map in MAPS_TO_PROCESS {
            let map_file_name = map.directory_name();
            let map_id = map.as_int();

            let pathfind_map =
                PathfindMap::new(&output, map_file_name).map_err(|e| e.to_string())?;

            self.maps.insert(map_id, pathfind_map);
        }

        Ok(())
    }

    fn with_map<F, R>(&mut self, map_id: u32, f: F) -> Result<R, String>
    where
        F: FnOnce(&mut PathfindMap) -> Result<R, String>,
    {
        self.maps
            .get_mut(&map_id)
            .ok_or_else(|| format!("Map with ID '{}' not found", map_id))
            .and_then(f)
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
    with_global_maps(|maps| {
        maps.with_map(map_id, |map| {
            map.get_zone_and_area(x, y, z).map_err(|e| e.to_string())
        })
    })
}

#[rustler::nif]
fn find_random_point_around_circle(
    map_id: u32,
    x: f32,
    y: f32,
    z: f32,
    radius: f32,
) -> NifResult<Option<(f32, f32, f32)>> {
    with_global_maps(|maps| {
        maps.with_map(map_id, |map| {
            let start = Vector3d { x, y, z };
            map.find_random_point_around_circle(start, radius)
                .map(|point| (point.x, point.y, point.z))
                .map_err(|e| e.to_string())
        })
    })
}

#[rustler::nif(schedule = "DirtyCpu")]
fn load_all_adts(map_id: u32) -> NifResult<Option<u32>> {
    with_global_maps(|maps| {
        maps.with_map(map_id, |map| map.load_all_adts().map_err(|e| e.to_string()))
    })
}

#[rustler::nif]
fn load_adt_at(map_id: u32, x: f32, y: f32) -> NifResult<Option<(f32, f32)>> {
    with_global_maps(|maps| {
        maps.with_map(map_id, |map| {
            map.load_adt_at(x, y).map_err(|e| e.to_string())
        })
    })
}

#[rustler::nif]
fn unload_adt(map_id: u32, x: i32, y: i32) -> NifResult<Option<()>> {
    with_global_maps(|maps| {
        maps.with_map(map_id, |map| {
            map.unload_adt(x, y).map_err(|e| e.to_string())
        })
    })
}

#[rustler::nif]
fn find_path(
    map_id: u32,
    start_x: f32,
    start_y: f32,
    start_z: f32,
    stop_x: f32,
    stop_y: f32,
    stop_z: f32,
) -> NifResult<Option<Vec<(f32, f32, f32)>>> {
    with_global_maps(|maps| {
        maps.with_map(map_id, |map| {
            let start = Vector3d {
                x: start_x,
                y: start_y,
                z: start_z,
            };
            let stop = Vector3d {
                x: stop_x,
                y: stop_y,
                z: stop_z,
            };
            map.find_path(start, stop)
                .map(|path| path.iter().map(|&v| (v.x, v.y, v.z)).collect())
                .map_err(|e| e.to_string())
        })
    })
}

fn with_global_maps<F, R>(f: F) -> NifResult<Option<R>>
where
    F: FnOnce(&mut PathfindingMaps) -> Result<R, String>,
{
    let mut global_maps = PATHFINDING_MAPS.lock().unwrap();
    match &mut *global_maps {
        Some(maps) => match f(maps) {
            Ok(result) => Ok(Some(result)),
            Err(_) => Ok(None),
        },
        None => Ok(None),
    }
}

rustler::init!("Elixir.Namigator");
