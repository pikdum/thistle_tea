defmodule ThistleTea.Game.World.Entity.Mob.GuardCall do
  @moduledoc """
  Answers a civilian's call for the guards. In a town with a guard post the
  call spends one of the post's charges, the civilian shouts, and the post's
  guard for the civilian's side appears five yards away to attack the enemy
  for two minutes. Elsewhere the nearest friendly guard within fifty yards
  joins the fight. The civilian's owner learns the answer by message.
  """

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Core.Creature.GuardPost
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Honor
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.EventSink.Context
  alias ThistleTea.Game.World.Loader.BroadcastText, as: BroadcastTextLoader
  alias ThistleTea.Game.World.Loader.ModelGeometry
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.Reaction
  alias ThistleTea.Game.World.System.GuardPosts

  @nearest_guard_range 50.0
  @summon_distance 5.0
  @guard_lifetime_ms 120_000
  @timed_or_dead_despawn 1
  @alliance_group 0x2
  @horde_group 0x4

  def answer(%Mob{} = entity, %Effects.CallGuards{enemy_guid: enemy}, context, opts \\ []) do
    {answer, effects} = respond(entity, enemy, opts)
    entity = EventSink.emit(entity, effects, context)
    Context.send(context, {:guard_call_answered, answer})
    entity
  end

  def respond(%Mob{movement_block: %{position: {x, y, z, _orientation}}} = entity, enemy, opts \\ []) do
    zone_and_area = Keyword.get(opts, :zone_and_area, &Pathfinding.get_zone_and_area/2)

    area =
      case zone_and_area.(entity.internal.world.map_id, {x, y, z}) do
        {_zone_id, area_id} when is_integer(area_id) -> area_id
        _unknown -> nil
      end

    if GuardPost.posted?(area),
      do: summon(entity, area, enemy, opts),
      else: {rouse(entity, enemy), []}
  end

  defp summon(entity, area, enemy, opts) do
    take = Keyword.get(opts, :take, &GuardPosts.take/1)

    case take.(area) do
      :ok ->
        shout = shout(entity, area, enemy)

        case GuardPost.guard(area, side(entity, enemy)) do
          entry when is_integer(entry) ->
            summon = %{
              entry: entry,
              position: near_point(entity, Keyword.get(opts, :walk, &Pathfinding.walk_hit_position/3)),
              despawn_type: @timed_or_dead_despawn,
              despawn_delay_ms: @guard_lifetime_ms,
              run?: true,
              unique?: false,
              attack_guid: enemy,
              script_id: 0
            }

            {{:summoned, entry}, shout ++ [Effects.summon_creature(summon, [], enemy)]}

          nil ->
            {:held, shout}
        end

      :denied ->
        {:denied, []}
    end
  end

  defp shout(entity, area, enemy) do
    model_id = ModelGeometry.get(entity.unit.display_id).model_id

    with text_id when is_integer(text_id) <- GuardPost.text_id(area, entity.unit.faction_template, model_id),
         %{text: text} when text != "" <- BroadcastTextLoader.get(text_id) do
      [Effects.monster_talk(text, :say, enemy)]
    else
      _ -> []
    end
  end

  defp rouse(entity, enemy) do
    {x, y, z, _orientation} = entity.movement_block.position

    entity.internal.world
    |> World.nearby_mobs_at({x, y, z}, @nearest_guard_range)
    |> Enum.sort_by(fn {guid, distance} -> {distance, guid} end)
    |> Enum.find(fn {guid, _distance} -> guid != entity.object.guid and guard?(entity, guid) end)
    |> case do
      {guard, _distance} -> Entity.assist_attack(guard, enemy)
      nil -> :ok
    end

    :held
  end

  defp guard?(entity, guid) do
    case Metadata.query(guid, [:guard?, :alive?]) do
      %{guard?: true, alive?: true} -> Reaction.friendly?(entity.object.guid, guid)
      _ -> false
    end
  end

  defp side(entity, enemy) do
    case enemy_team(enemy) do
      :alliance -> :horde
      :horde -> :alliance
      nil -> own_team(entity)
    end
  end

  defp enemy_team(guid) do
    case {Guid.entity_type(guid), Metadata.query(guid, [:race, :owner_guid, :charmed_by])} do
      {:player, %{race: race}} -> Honor.team(race)
      {_type, %{charmed_by: charmer}} when is_integer(charmer) and charmer > 0 -> player_team(charmer)
      {_type, %{owner_guid: owner}} when is_integer(owner) and owner > 0 -> player_team(owner)
      _unknown -> nil
    end
  end

  defp player_team(guid) do
    case {Guid.entity_type(guid), Metadata.query(guid, [:race])} do
      {:player, %{race: race}} -> Honor.team(race)
      _other -> nil
    end
  end

  defp own_team(entity) do
    case Metadata.query(entity.object.guid, [:faction_template]) do
      %{faction_template: %{faction_group: group}} when (group &&& @alliance_group) != 0 -> :alliance
      %{faction_template: %{faction_group: group}} when (group &&& @horde_group) != 0 -> :horde
      _other -> nil
    end
  end

  defp near_point(%Mob{movement_block: %{position: {x, y, z, orientation}}} = entity, walk) do
    destination = {x + @summon_distance * :math.cos(orientation), y + @summon_distance * :math.sin(orientation), z}

    case walk.(entity.internal.world.map_id, {x, y, z}, destination) do
      {px, py, pz} -> {px, py, pz, orientation + :math.pi()}
      _ -> {x, y, z, orientation}
    end
  end
end
