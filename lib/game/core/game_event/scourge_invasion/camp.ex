defmodule ThistleTea.Game.Core.GameEvent.ScourgeInvasion.Camp do
  @moduledoc """
  A Scourge camp around a summoning circle, after vmangos's `NecroticShard`
  and minion spawner AIs.

  The camp's Necrotic Shard calls minions of its camp type out of the finders
  around it, one to three every five seconds, nearest first. A finder that
  calls one rests for two and a half to three and a third minutes, and none
  calls while a minion still stands on it. One minion in 217 is a rare, unless
  the camp already has a rare.

  Minions slain around the shard wear it down. When it breaks, a damaged
  shard takes its place, and four cultists come every hour to channel into
  it. When the damaged shard falls too, the camp is lost.

  `summoned/3`, `died/3`, and `despawned/3` follow the camp's summons through
  their summon events, and `died/3` names the transition a death brings
  about. A rare counts against the camp until its corpse is gone.
  """

  alias ThistleTea.Game.Core.Rolls

  @shard 16_136
  @damaged_shard 16_172
  @cultist 16_230
  @types [:ghost_ghoul, :ghost_skeleton, :ghoul_skeleton]
  @minions %{
    ghost_ghoul: {16_298, 16_141},
    ghost_skeleton: {16_298, 16_299},
    ghoul_skeleton: {16_141, 16_299}
  }
  @rares %{
    ghost_ghoul: {16_379, 14_697},
    ghost_skeleton: {16_379, 16_380},
    ghoul_skeleton: {14_697, 16_380}
  }
  @rare_odds 217
  @fewest_rest_ms 150_000
  @most_rest_ms 200_000
  @cultist_reach_x 6.95
  @cultist_reach_y 6.75

  defstruct [
    :type,
    :shard,
    stage: :shard,
    minions: MapSet.new(),
    rares: MapSet.new(),
    resting: %{},
    cultists: MapSet.new()
  ]

  def new(%Rolls{} = rolls), do: %__MODULE__{type: Enum.at(@types, Rolls.integer(rolls, :camp_type, 0, 2))}

  def shard, do: @shard

  def damaged_shard, do: @damaged_shard

  def cultist, do: @cultist

  def summon_entries do
    minions = Enum.flat_map(Map.values(@minions) ++ Map.values(@rares), &Tuple.to_list/1)
    Enum.uniq([@shard, @damaged_shard, @cultist | minions])
  end

  def spawning?(%__MODULE__{stage: stage}), do: stage in [:shard, :damaged]

  def call(%__MODULE__{} = camp, candidates, now, %Rolls{} = rolls) when is_list(candidates) and is_integer(now) do
    count = Rolls.integer(rolls, :finders, 1, 3)

    called =
      candidates
      |> Enum.sort_by(fn {guid, distance, _occupied?} -> {distance, guid} end)
      |> Enum.reject(fn {guid, _distance, occupied?} -> occupied? or Map.get(camp.resting, guid, now) > now end)
      |> Enum.take(count)
      |> Enum.map(&elem(&1, 0))

    resting =
      Enum.reduce(called, camp.resting, fn guid, resting ->
        Map.put(resting, guid, now + Rolls.integer(rolls, :finder_rest, @fewest_rest_ms, @most_rest_ms))
      end)

    {%{camp | resting: resting}, called}
  end

  def minion_entry(%__MODULE__{type: type} = camp, %Rolls{} = rolls) do
    rare? = MapSet.size(camp.rares) == 0 and Rolls.integer(rolls, :rare_minion, 1, @rare_odds) == 1
    pair = if rare?, do: Map.fetch!(@rares, type), else: Map.fetch!(@minions, type)
    elem(pair, Rolls.integer(rolls, :minion, 0, 1))
  end

  def summoned(%__MODULE__{} = camp, guid, entry) when entry in [@shard, @damaged_shard], do: %{camp | shard: guid}

  def summoned(%__MODULE__{} = camp, guid, @cultist), do: %{camp | cultists: MapSet.put(camp.cultists, guid)}

  def summoned(%__MODULE__{} = camp, guid, entry) do
    if rare?(entry),
      do: %{camp | minions: MapSet.put(camp.minions, guid), rares: MapSet.put(camp.rares, guid)},
      else: %{camp | minions: MapSet.put(camp.minions, guid)}
  end

  def died(%__MODULE__{stage: :shard} = camp, _guid, @shard), do: {%{camp | stage: :damaged, shard: nil}, :shard_fell}

  def died(%__MODULE__{stage: :damaged} = camp, _guid, @damaged_shard),
    do: {%{camp | stage: :fallen, shard: nil}, :camp_fell}

  def died(%__MODULE__{} = camp, guid, @cultist) do
    if MapSet.member?(camp.cultists, guid) and camp.stage == :damaged,
      do: {%{camp | cultists: MapSet.delete(camp.cultists, guid)}, :cultist_fell},
      else: {%{camp | cultists: MapSet.delete(camp.cultists, guid)}, nil}
  end

  def died(%__MODULE__{} = camp, guid, _entry), do: {%{camp | minions: MapSet.delete(camp.minions, guid)}, nil}

  def despawned(%__MODULE__{} = camp, guid, _entry) do
    %{
      camp
      | minions: MapSet.delete(camp.minions, guid),
        rares: MapSet.delete(camp.rares, guid),
        cultists: MapSet.delete(camp.cultists, guid)
    }
  end

  def cultist_positions({x, y, z, orientation}) do
    for index <- 0..3 do
      angle = index * :math.pi() / 2 + orientation
      {x + @cultist_reach_x * :math.cos(angle), y + @cultist_reach_y * :math.sin(angle), z, angle - :math.pi()}
    end
  end

  defp rare?(entry), do: Enum.any?(Map.values(@rares), &(entry in Tuple.to_list(&1)))
end
