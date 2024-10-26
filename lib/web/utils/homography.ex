defmodule ThistleTeaWeb.Homography do
  require Logger

  def init() do
    # TODO: getting worse results the more points
    # there has to be a better way
    points = %{
      0 => {
        [
          # Northshire Abbey
          [-8913.14, -137.78],
          # Shadow Grave
          [1668.45, 1662.34],
          # Light's Hope Chapel
          [2271.09, -5341.49],
          # Southshore
          [-846.85, -520.79]
          # Sentinel Hill
          # [-10619.08, 1036.77]
        ],
        [
          # Northshire Abbey
          [9315.15, 3893.04],
          # Shadow Grave
          [8656.9, 7777.56],
          # Light's Hope Chapel
          [11247.6, 8037.48],
          # Southshore
          [9445.61, 6829.92]
          # Sentinel Hill
          # [8866.79, 3240.56]
        ]
      },
      1 => {
        [
          # Moonglade
          # [7981.32, -2576.5],
          # Auberdine
          [6462.24, 807.09],
          # Astranaar
          # [2751.61, -419.84],
          # Crossroads
          # [-456.4, -2642.82],
          # Ratchet
          [-956.86, -3754.77],
          # Cenarion Hold
          # [-6815.12, 730.3],
          # Marshal's Refuge
          [-6291.55, -1158.62],
          # Thunderbluff
          # [-1280.03, 127.35],
          # Aldrassil
          [10390.99, 758.16]
          # Wellspring River Waterfall
          # [10870.0, 1014.0]
        ],
        [
          # Moonglade
          # [3313.47, 8667.19],
          # Auberdine
          [2037.43, 8088.06],
          # Astranaar
          # [2513.56, 6691.44],
          # Crossroads
          # [3348.72, 5550.98],
          # Ratchet
          [3758.78, 5379.7],
          # Cenarion Hold
          # [2115.13, 3181.3],
          # Marshal's Refuge
          [2876.54, 3348.07],
          # Thunderbluff
          # [2314.04, 5223.38],
          # Aldrassil
          [2043.013, 9515.08]
          # Wellspring River Waterfall
          # [1773.04, 9722.90]
        ]
      }
    }

    homographies =
      Enum.map(points, fn {map_id, {source, target}} ->
        h = find_homography(source, target)
        {map_id, h}
      end)
      |> Map.new()

    :persistent_term.put(:homographies, homographies)
  end

  def transform({x, y}, map_id) do
    homographies = :persistent_term.get(:homographies)
    homography = Map.get(homographies, map_id)
    transform_point({x, y}, homography)
  end

  def find_homography(a, b) do
    source = Nx.tensor(a, type: :f32)
    target = Nx.tensor(b, type: :f32)
    {homography, _} = Evision.findHomography(source, target)
    homography |> Evision.Mat.to_nx(Nx.BinaryBackend)
  end

  def transform_point({x, y}, homography) do
    p = Nx.tensor([x, y, 1], type: :f32)
    transformed = Nx.dot(homography, p)
    [new_x, new_y, w] = Nx.to_list(transformed)
    {new_x / w, new_y / w}
  end
end
