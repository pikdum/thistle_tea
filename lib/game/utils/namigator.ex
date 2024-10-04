defmodule Namigator do
  use Rustler, otp_app: :thistle_tea, crate: "namigator"

  def build(_wow_dir, _out_dir), do: :erlang.nif_error(:nif_not_loaded)
  def load(_out_dir), do: :erlang.nif_error(:nif_not_loaded)
  def get_zone_and_area(_map_id, _x, _y, _z), do: :erlang.nif_error(:nif_not_loaded)

  def find_random_point_around_circle(_map_id, _x, _y, _z, _radius),
    do: :erlang.nif_error(:nif_not_loaded)

  def load_all_adts(_map_id), do: :erlang.nif_error(:nif_not_loaded)
  def load_adt_at(_map_id, _x, _y), do: :erlang.nif_error(:nif_not_loaded)
  def unload_adt(_map_id, _x, _y), do: :erlang.nif_error(:nif_not_loaded)

  def find_path(_map_id, _start_x, _start_y, _start_z, _stop_x, _stop_y, _stop_z),
    do: :erlang.nif_error(:nif_not_loaded)
end
