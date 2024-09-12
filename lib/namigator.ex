defmodule ThistleTea.Namigator do
  use Rustler, otp_app: :thistle_tea, crate: "thistletea_namigator"

  def build(_wow_dir, _map_dir), do: :erlang.nif_error(:nif_not_loaded)
  def load(_map_dir), do: :erlang.nif_error(:nif_not_loaded)
  def get_zone_and_area(_map, _x, _y, _z), do: :erlang.nif_error(:nif_not_loaded)

  def find_random_point_around_circle(_map, _x, _y, _z, _radius),
    do: :erlang.nif_error(:nif_not_loaded)
end
