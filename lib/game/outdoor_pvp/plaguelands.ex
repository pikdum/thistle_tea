defmodule ThistleTea.Game.OutdoorPvp.Plaguelands do
  @moduledoc "Eastern Plaguelands tower locations, world states, and faction rewards."

  @towers %{
    eastwall: %{
      entry: 182_097,
      position: {2574.51, -4794.89, 144.704, -1.45003},
      rotation: {-0.097056, 0.095578, -0.656229, 0.742165},
      banners: [{2539.61, -4801.55, 115.766, 2.00713}, {2569.6, -4772.93, 115.399, 2.72271}],
      states: [2361, 2359, 2360, 2357, 2358, 2354, 2356],
      credit_entry: 17_690,
      announcements: %{alliance: 13_631, horde: 13_636}
    },
    northpass: %{
      entry: 181_899,
      position: {3181.08, -4379.36, 174.123, -2.03472},
      rotation: {-0.065392, 0.119494, -0.842275, 0.521553},
      banners: [{3148.17, -4365.51, 145.029, 1.53589}, {3188.76, -4358.5, 144.555, 1.97222}],
      states: [2352, 2362, 2363, 2364, 2365, 2372, 2373],
      credit_entry: 17_696,
      announcements: %{alliance: 13_630, horde: 13_635}
    },
    plaguewood: %{
      entry: 182_098,
      position: {2962.71, -3042.31, 154.789, 2.08426},
      rotation: {-0.074807, -0.113837, 0.855928, 0.49883},
      banners: [{2975.5, -3060.36, 125.108, 5.23599}, {2992.63, -3022.95, 125.593, 3.03684}],
      states: [2353, 2366, 2367, 2368, 2369, 2370, 2371],
      credit_entry: 17_698,
      announcements: %{alliance: 13_629, horde: 13_634}
    },
    crown_guard: %{
      entry: 182_096,
      position: {1860.85, -3731.23, 196.716, -2.53214},
      rotation: {0.033967, -0.131914, 0.944741, -0.298177},
      banners: [{1838.42, -3703.56, 167.713, 0.890117}, {1877.6, -3716.76, 167.188, 1.74533}],
      states: [2355, 2374, 2375, 2376, 2377, 2378, 2379],
      credit_entry: 17_689,
      announcements: %{alliance: 13_632, horde: 13_633}
    }
  }
  @phases [
    :neutral,
    {:contested, :alliance},
    {:contested, :horde},
    {:progress, :alliance},
    {:progress, :horde},
    {:controlled, :alliance},
    {:controlled, :horde}
  ]
  @buffs %{alliance: [11_413, 11_414, 11_415, 1386], horde: [30_880, 30_683, 30_682, 29_520]}
  @credit_positions %{
    crown_guard: %{alliance: {1860.59, -3730.8, 197.854}, horde: {1860.48, -3731.34, 197.778}},
    eastwall: %{alliance: {2574.12, -4795.33, 145.871}, horde: {2574.0, -4794.79, 145.881}},
    plaguewood: %{alliance: {2962.6, -3041.96, 155.835}, horde: {2963.02, -3041.9, 155.965}},
    northpass: %{alliance: {3180.54, -4379.31, 175.275}, horde: {3180.48, -4379.07, 174.995}}
  }

  def towers, do: @towers
  def credit_position(tower, team), do: @credit_positions[tower][team]
  def objective_zone?(139), do: true
  def objective_zone?(_zone), do: false
  def buff_zone?(zone), do: zone in [139, 2017, 2057]
  def buffs, do: @buffs |> Map.values() |> List.flatten()
  def buff(team, count) when team in [:alliance, :horde] and count in 1..4, do: Enum.at(@buffs[team], count - 1)
  def buff(_team, _count), do: nil

  def tower_states(id, phase) do
    @towers[id].states
    |> Enum.zip(@phases)
    |> Enum.map(fn {field, candidate} -> {field, if(candidate == phase, do: 1, else: 0)} end)
  end

  def art_kit(nil), do: 21
  def art_kit(:alliance), do: 2
  def art_kit(:horde), do: 1
  def animation(nil), do: 2
  def animation(:alliance), do: 1
  def animation(:horde), do: 0

  def victory_text(:alliance), do: 13_638
  def victory_text(:horde), do: 13_637

  def phase_sound(_previous, {:controlled, :alliance}), do: 8455
  def phase_sound(_previous, {:controlled, :horde}), do: 8454
  def phase_sound({:controlled, :alliance}, {:progress, :alliance}), do: 8332
  def phase_sound({:controlled, :horde}, {:progress, :horde}), do: 8333
  def phase_sound(_previous, {:progress, :alliance}), do: 8173
  def phase_sound(_previous, {:progress, :horde}), do: 8213
  def phase_sound(_previous, _current), do: nil

  def broadcast_text_ids do
    [victory_text(:alliance), victory_text(:horde)] ++
      Enum.flat_map(Map.values(@towers), &Map.values(&1.announcements))
  end
end
