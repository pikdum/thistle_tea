defmodule ThistleTea.Game.World.Loader.Totem do
  @moduledoc "Builds stationary wards and elemental totems from boot-cached creature templates."

  import Ecto.Query

  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Totems
  alias ThistleTea.Game.World.Loader.Summon
  alias ThistleTea.Game.World.Pathfinding

  @effects [74, 87, 88, 89, 90]

  def preload do
    DBC.all(
      from(s in Spell,
        where: s.effect_0 in @effects or s.effect_1 in @effects or s.effect_2 in @effects
      )
    )
    |> Enum.flat_map(fn row ->
      for index <- 0..2,
          Map.fetch!(row, :"effect_#{index}") in @effects,
          entry = Map.fetch!(row, :"effect_misc_value_#{index}"),
          entry > 0,
          do: entry
    end)
    |> Enum.uniq()
    |> Summon.preload()
  end

  def build(owner, %Effects.SummonTotem{} = effect, now) do
    position = owner.movement_block.position |> Totems.position(effect.slot) |> ground(owner.internal.world.map_id)

    effect.entry
    |> Summon.build(owner.internal.world, position, stat_model: :creature)
    |> Summon.attach_owner(owner.object.guid)
    |> Totems.prepare(owner, effect, now)
  end

  defp ground({x, y, z, orientation}, map_id) do
    height =
      map_id
      |> Pathfinding.find_heights({x, y})
      |> Enum.filter(&(abs(&1 - z) <= 5.0))
      |> Enum.min_by(&abs(&1 - z), fn -> z end)

    {x, y, height, orientation}
  end
end
