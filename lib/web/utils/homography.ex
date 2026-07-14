defmodule ThistleTeaWeb.Homography do
  @moduledoc """
  Maps world coordinates onto the web map's image space via per-map
  homographies fitted from known reference points.
  """
  @homographies %{
    0 =>
      {{0.0473108071805853, -0.4283110937591768, 9257.776291194366},
       {0.3844485796177209, -0.02051269638333569, 7141.308341552495},
       {5.174022696727513e-6, -7.429693433368984e-6, 1.0}},
    1 =>
      {{-0.008559679970398887, -0.38002413479627795, 2364.0523891095927},
       {0.35570543285316697, -0.023340739805165746, 5667.127168629889},
       {-2.355107737045165e-6, -2.776803517146084e-6, 0.9999999999999999}}
  }

  def transform({x, y}, map_id) do
    homography = Map.fetch!(@homographies, map_id)
    transform_point({x, y}, homography)
  end

  def transform_point({x, y}, {{a, b, c}, {d, e, f}, {g, h, i}}) do
    new_x = a * x + b * y + c
    new_y = d * x + e * y + f
    w = g * x + h * y + i
    {new_x / w, new_y / w}
  end
end
