#include <cstdint>
#include <memory>
#include <mutex>
#include <optional>
#include <stdexcept>
#include <string>
#include <tuple>
#include <utility>
#include <variant>
#include <vector>

#include <fine.hpp>
#include <fine/sync.hpp>

#include "pathfind/pathfind_c_bindings.hpp"

class PathfindError : public std::runtime_error {
public:
  explicit PathfindError(PathfindResultType result)
      : std::runtime_error("namigator error " +
                           std::to_string(static_cast<unsigned int>(result))),
        result(result) {}

  PathfindResultType result;
};

class PathfindMap {
public:
  PathfindMap(std::string data_path, std::string map_name)
      : name(std::move(map_name)), map(nullptr, pathfind_free_map),
        mutex("thistle_tea", "namigator_map", name) {
    PathfindResultType result =
        static_cast<PathfindResultType>(Result::UNKNOWN_EXCEPTION);
    auto *raw_map = pathfind_new_map(data_path.c_str(), name.c_str(), &result);

    if (!ok(result) || raw_map == nullptr) {
      throw PathfindError(result);
    }

    map.reset(raw_map);
  }

  pathfind::Map *get() const { return map.get(); }

  std::unique_lock<fine::Mutex> acquire() { return std::unique_lock(mutex); }

private:
  static bool ok(PathfindResultType result) {
    return result == static_cast<PathfindResultType>(Result::SUCCESS);
  }

  std::string name;
  std::unique_ptr<pathfind::Map, decltype(&pathfind_free_map)> map;
  fine::Mutex mutex;
};

FINE_RESOURCE(PathfindMap);

using MapResource = fine::ResourcePtr<PathfindMap>;
using LoadResult = std::variant<fine::Ok<MapResource>, fine::Error<uint64_t>>;
using Point2 = std::tuple<double, double>;
using Point3 = std::tuple<double, double, double>;
using ZoneAndArea = std::tuple<uint64_t, uint64_t>;

static bool ok(PathfindResultType result) {
  return result == static_cast<PathfindResultType>(Result::SUCCESS);
}

static bool buffer_too_small(PathfindResultType result) {
  return result == static_cast<PathfindResultType>(Result::BUFFER_TOO_SMALL);
}

static float f(double value) { return static_cast<float>(value); }

LoadResult load_map_native(ErlNifEnv *, std::string data_path,
                           std::string map_name) {
  try {
    return fine::Ok<MapResource>(fine::make_resource<PathfindMap>(
        std::move(data_path), std::move(map_name)));
  } catch (const PathfindError &error) {
    return fine::Error<uint64_t>(static_cast<uint64_t>(error.result));
  }
}
FINE_NIF(load_map_native, ERL_NIF_DIRTY_JOB_CPU_BOUND);

std::optional<ZoneAndArea> get_zone_and_area_native(ErlNifEnv *,
                                                    MapResource map, double x,
                                                    double y, double z) {
  auto lock = map->acquire();
  unsigned int zone = 0;
  unsigned int area = 0;
  auto result =
      pathfind_get_zone_and_area(map->get(), f(x), f(y), f(z), &zone, &area);

  if (!ok(result)) {
    return std::nullopt;
  }

  return ZoneAndArea(static_cast<uint64_t>(zone), static_cast<uint64_t>(area));
}
FINE_NIF(get_zone_and_area_native, ERL_NIF_DIRTY_JOB_CPU_BOUND);

std::optional<Point3>
find_random_point_around_circle_native(ErlNifEnv *, MapResource map, double x,
                                       double y, double z, double radius) {
  auto lock = map->acquire();
  float random_x = 0.0f;
  float random_y = 0.0f;
  float random_z = 0.0f;
  auto result = pathfind_find_random_point_around_circle(
      map->get(), f(x), f(y), f(z), f(radius), &random_x, &random_y, &random_z);

  if (!ok(result)) {
    return std::nullopt;
  }

  return Point3(random_x, random_y, random_z);
}
FINE_NIF(find_random_point_around_circle_native, ERL_NIF_DIRTY_JOB_CPU_BOUND);

std::optional<uint64_t> load_all_adts_native(ErlNifEnv *, MapResource map) {
  auto lock = map->acquire();
  int32_t amount = 0;
  auto result = pathfind_load_all_adts(map->get(), &amount);

  if (!ok(result)) {
    return std::nullopt;
  }

  return static_cast<uint64_t>(amount);
}
FINE_NIF(load_all_adts_native, ERL_NIF_DIRTY_JOB_CPU_BOUND);

std::optional<Point2> load_adt_native(ErlNifEnv *, MapResource map, int64_t x,
                                      int64_t y) {
  auto lock = map->acquire();
  float adt_x = 0.0f;
  float adt_y = 0.0f;
  auto result = pathfind_load_adt(map->get(), static_cast<int>(x),
                                  static_cast<int>(y), &adt_x, &adt_y);

  if (!ok(result)) {
    return std::nullopt;
  }

  return Point2(adt_x, adt_y);
}
FINE_NIF(load_adt_native, ERL_NIF_DIRTY_JOB_CPU_BOUND);

std::optional<Point2> load_adt_at_native(ErlNifEnv *, MapResource map, double x,
                                         double y) {
  auto lock = map->acquire();
  float adt_x = 0.0f;
  float adt_y = 0.0f;
  auto result = pathfind_load_adt_at(map->get(), f(x), f(y), &adt_x, &adt_y);

  if (!ok(result)) {
    return std::nullopt;
  }

  return Point2(adt_x, adt_y);
}
FINE_NIF(load_adt_at_native, ERL_NIF_DIRTY_JOB_CPU_BOUND);

std::optional<bool> unload_adt_native(ErlNifEnv *, MapResource map, int64_t x,
                                      int64_t y) {
  auto lock = map->acquire();
  auto result =
      pathfind_unload_adt(map->get(), static_cast<int>(x), static_cast<int>(y));

  if (!ok(result)) {
    return std::nullopt;
  }

  return true;
}
FINE_NIF(unload_adt_native, ERL_NIF_DIRTY_JOB_CPU_BOUND);

std::optional<std::vector<Point3>>
find_path_native(ErlNifEnv *, MapResource map, double start_x, double start_y,
                 double start_z, double stop_x, double stop_y, double stop_z) {
  auto lock = map->acquire();
  unsigned int amount = 0;
  std::vector<Vertex> buffer(256);
  auto result = pathfind_find_path(map->get(), f(start_x), f(start_y),
                                   f(start_z), f(stop_x), f(stop_y), f(stop_z),
                                   buffer.data(), buffer.size(), &amount);

  if (buffer_too_small(result) && amount > buffer.size()) {
    buffer.resize(amount);
    result = pathfind_find_path(map->get(), f(start_x), f(start_y), f(start_z),
                                f(stop_x), f(stop_y), f(stop_z), buffer.data(),
                                buffer.size(), &amount);
  }

  if (!ok(result)) {
    return std::nullopt;
  }

  std::vector<Point3> path;
  path.reserve(amount);

  for (unsigned int i = 0; i < amount; ++i) {
    path.emplace_back(buffer[i].x, buffer[i].y, buffer[i].z);
  }

  return path;
}
FINE_NIF(find_path_native, ERL_NIF_DIRTY_JOB_CPU_BOUND);

std::optional<Point3>
find_point_between_points_native(ErlNifEnv *, MapResource map, double start_x,
                                 double start_y, double start_z, double stop_x,
                                 double stop_y, double stop_z,
                                 double distance) {
  auto lock = map->acquire();
  Vertex point{};
  auto result = pathfind_find_point_in_between_vectors(
      map->get(), f(distance), f(start_x), f(start_y), f(start_z), f(stop_x),
      f(stop_y), f(stop_z), &point);

  if (!ok(result)) {
    return std::nullopt;
  }

  return Point3(point.x, point.y, point.z);
}
FINE_NIF(find_point_between_points_native, ERL_NIF_DIRTY_JOB_CPU_BOUND);

std::optional<std::vector<double>>
find_heights_native(ErlNifEnv *, MapResource map, double x, double y) {
  auto lock = map->acquire();
  unsigned int amount = 0;
  std::vector<float> buffer(4096);
  auto result = pathfind_find_heights(map->get(), f(x), f(y), buffer.data(),
                                      buffer.size(), &amount);

  if (!ok(result)) {
    return std::nullopt;
  }

  std::vector<double> heights;
  heights.reserve(amount);

  for (unsigned int i = 0; i < amount; ++i) {
    heights.push_back(buffer[i]);
  }

  return heights;
}
FINE_NIF(find_heights_native, ERL_NIF_DIRTY_JOB_CPU_BOUND);

FINE_INIT("Elixir.ThistleTea.Native.Namigator");
