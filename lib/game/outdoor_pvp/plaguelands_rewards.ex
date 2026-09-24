defmodule ThistleTea.Game.OutdoorPvp.PlaguelandsRewards do
  @moduledoc "Pure ownership-dependent tower services, reinforcements, and victory flares."

  alias ThistleTea.Game.OutdoorPvp.CapturePoint
  alias ThistleTea.Game.OutdoorPvp.Towers

  defmodule Spawn do
    @moduledoc false
    defstruct [:kind, :entry, :position, :faction, :aura, :waypoint_entry]
  end

  @squad_positions [
    {2532.85, -4764.92, 103.617, 2.35619},
    {2533.33, -4769.31, 104.396, 2.37365},
    {2537.34, -4773.92, 105.941, 2.21657},
    {2537.77, -4765.94, 104.432, 2.3911},
    {2542.57, -4770.22, 106.145, 2.42601}
  ]
  @flares %{
    crown_guard: %{alliance: {1855.66, -3725.0, 197.044, 1.53589}, horde: {1853.12, -3722.62, 197.406, 0.628317}},
    eastwall: %{alliance: {2563.26, -4795.15, 145.852, 1.81514}, horde: {2565.27, -4797.59, 147.846, 3.05433}},
    northpass: %{alliance: {3171.86, -4377.2, 174.898, 0.174532}, horde: {3169.76, -4375.13, 175.458, 2.70526}},
    plaguewood: %{alliance: {2971.41, -3038.36, 157.492, 5.35816}, horde: {2973.17, -3037.19, 156.443, 1.97222}}
  }

  def creature_entries, do: [17_209, 17_635, 17_647, 17_995, 17_996, 18_039]
  def aura_ids, do: [17_327, 31_309, 31_954, 31_951]

  def spawns(%Towers{points: points}) do
    Map.new(
      Enum.flat_map(points, fn {id, point} ->
        owner = CapturePoint.owner(point)
        services(id, owner) ++ flare(id, point.phase)
      end)
    )
  end

  def graveyard_owner(%Towers{points: points}) do
    case points[:crown_guard] do
      %CapturePoint{} = point -> CapturePoint.owner(point)
      nil -> nil
    end
  end

  defp services(_id, nil), do: []

  defp services(:northpass, team) do
    {shrine, aura, position} =
      case team do
        :alliance -> {181_682, 180_100, {3167.72, -4355.91, 138.785, 1.69297}}
        :horde -> {181_955, 180_101, {3167.5, -4356.25, 138.821, 1.69297}}
      end

    [{{:northpass, :shrine}, object(shrine, position)}, {{:northpass, :aura}, object(aura, position)}]
  end

  defp services(:plaguewood, team) do
    {faction, aura} = if team == :alliance, do: {774, 17_327}, else: {775, 31_309}

    [
      {{:plaguewood, :flightmaster},
       %Spawn{kind: :mob, entry: 17_209, position: {2987.5, -3049.11, 120.126, 5.75959}, faction: faction, aura: aura}}
    ]
  end

  defp services(:crown_guard, team) do
    {banner, aura, faction} = if team == :alliance, do: {180_421, 31_954, 774}, else: {180_422, 31_951, 775}

    [
      {{:crown_guard, :aura}, object(banner, {1985.47, -3653.88, 120.172, 1.46608})},
      {{:crown_guard, :spirit},
       %Spawn{
         kind: :mob,
         entry: 18_039,
         position: {1856.58, -3714.72, 194.637, 0.762214},
         faction: faction,
         aura: aura,
         waypoint_entry: 18_039
       }}
    ]
  end

  defp services(:eastwall, team) do
    {commander, soldier} = if team == :alliance, do: {17_635, 17_647}, else: {17_995, 17_996}

    for {position, index} <- Enum.with_index(@squad_positions) do
      {{:eastwall, index}, %Spawn{kind: :mob, entry: if(index == 0, do: commander, else: soldier), position: position}}
    end
  end

  defp flare(id, {:controlled, team}) do
    entry = if team == :alliance, do: 181_852, else: 181_853
    [{{id, :flare}, object(entry, @flares[id][team])}]
  end

  defp flare(_id, _phase), do: []
  defp object(entry, position), do: %Spawn{kind: :game_object, entry: entry, position: position}
end
