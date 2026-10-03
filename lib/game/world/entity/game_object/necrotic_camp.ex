defmodule ThistleTea.Game.World.Entity.GameObject.NecroticCamp do
  @moduledoc """
  Runs a Scourge Invasion camp (`Core.GameEvent.ScourgeInvasion.Camp`) from
  its summoning circle for as long as the zone's attack event keeps the
  circle spawned. The circle raises the camp's Necrotic Shard (vmangos's
  Create Crystal). Every five seconds it calls minions out of the finders
  around it; each minion flickers in and roams within a yard of its finder
  for up to an hour.

  When the shard breaks, a damaged shard rises in its place. Every hour the
  damaged shard is made whole again and four Cultist Engineers come to
  channel into it, and each cultist that falls strikes it for a hundred. When
  the damaged shard falls, the cultists leave, and the circle and its
  campfires, skull piles, and summoner shields go with them.
  """

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.GameEvent.ScourgeInvasion.Camp
  alias ThistleTea.Game.Core.Math
  alias ThistleTea.Game.Core.Pet.SummonEvent
  alias ThistleTea.Game.Core.Rolls
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Metadata

  @circle 181_136
  @finder 16_356
  @doodads [181_136, 181_173, 181_174, 181_191, 181_192, 181_193, 181_194, 181_142]
  @raise :camp_raise
  @upkeep :camp_upkeep
  @buttress :camp_buttress
  @first_upkeep_ms 5_000
  @upkeep_ms 5_000
  @buttress_ms 3_600_000
  @finder_reach 60.0
  @occupied_reach 5.0
  @doodad_reach 60.0
  @minion_lifetime_ms 3_600_000
  @minion_wander 1.0
  @corpse_ms 30_000
  @timed_or_dead_despawn 1
  @corpse_timed_despawn 6
  @dead_despawn 7
  @minion_spawn_in 28_234
  @create_summoner_shield 28_132
  @damage_crystal 28_041
  @triggered 0x02

  def start(%GameObject{object: %{entry: @circle}} = state) do
    send(self(), @raise)
    %{state | internal: %{state.internal | camp: Camp.new(Rolls.system())}}
  end

  def start(%GameObject{} = state), do: state

  def raise_shard(%GameObject{internal: %{camp: %Camp{stage: :shard, shard: nil}}} = state) do
    Process.send_after(self(), @upkeep, @first_upkeep_ms)
    summon(state, Camp.shard(), state.movement_block.position, despawn_type: @dead_despawn)
  end

  def raise_shard(%GameObject{} = state), do: state

  def upkeep(%GameObject{internal: %{camp: %Camp{} = camp, world: world} = internal} = state) do
    if Camp.spawning?(camp) do
      Process.send_after(self(), @upkeep, @upkeep_ms)
      {camp, finders} = Camp.call(camp, finders(world, state.movement_block.position, camp), Time.now(), Rolls.system())
      state = %{state | internal: %{internal | camp: camp}}
      Enum.reduce(finders, state, &call_minion(&2, &1))
    else
      state
    end
  end

  def upkeep(%GameObject{} = state), do: state

  def buttress(%GameObject{internal: %{camp: %Camp{stage: :damaged} = camp}} = state) do
    Process.send_after(self(), @buttress, @buttress_ms)
    restore(camp.shard)

    state.movement_block.position
    |> Camp.cultist_positions()
    |> Enum.reduce(state, fn position, state ->
      summon(state, Camp.cultist(), position,
        despawn_type: @timed_or_dead_despawn,
        despawn_delay_ms: @buttress_ms,
        steps: [cast_self(@create_summoner_shield), cast_self(@minion_spawn_in)]
      )
    end)
  end

  def buttress(%GameObject{} = state), do: state

  def summon_event(%GameObject{internal: %{camp: %Camp{} = camp} = internal} = state, %SummonEvent{} = event) do
    guid = event.observation.guid

    case event.event do
      :summoned_unit ->
        %{state | internal: %{internal | camp: Camp.summoned(camp, guid, event.entry)}}

      :summoned_just_died ->
        {camp, transition} = Camp.died(camp, guid, event.entry)
        follow(%{state | internal: %{internal | camp: camp}}, transition, camp)

      :summoned_just_despawn ->
        %{state | internal: %{internal | camp: Camp.despawned(camp, guid, event.entry)}}

      _other ->
        state
    end
  end

  def summon_event(%GameObject{} = state, %SummonEvent{}), do: state

  defp follow(state, :shard_fell, _camp) do
    send(self(), @buttress)

    summon(state, Camp.damaged_shard(), state.movement_block.position,
      despawn_type: @corpse_timed_despawn,
      despawn_delay_ms: @corpse_ms
    )
  end

  defp follow(state, :cultist_fell, %Camp{shard: shard}) when is_integer(shard) do
    Entity.trigger_spell(shard, @damage_crystal, shard, triggered: true)
    state
  end

  defp follow(state, :camp_fell, %Camp{} = camp) do
    Enum.each(camp.cultists, &depart/1)
    {x, y, z, _orientation} = state.movement_block.position

    state.internal.world
    |> then(&World.nearby_units_exact(:game_objects, &1, {x, y, z}, @doodad_reach))
    |> Enum.filter(fn {guid, _distance} -> World.entry(guid) in @doodads and guid != state.object.guid end)
    |> Enum.each(fn {guid, _distance} -> Entity.hide_game_object(guid) end)

    send(self(), {:script_remove_object, nil})
    state
  end

  defp follow(state, _transition, _camp), do: state

  defp finders(world, {x, y, z, _orientation}, %Camp{} = camp) do
    minions = Enum.flat_map(camp.minions, &minion_position(world, &1))

    world
    |> World.nearby_mobs_at({x, y, z}, @finder_reach)
    |> Enum.filter(fn {guid, _distance} -> World.entry(guid) == @finder and alive?(guid) end)
    |> Enum.flat_map(fn {guid, distance} ->
      case World.position(guid) do
        {^world, fx, fy, fz} ->
          occupied? = Enum.any?(minions, &(Math.distance(&1, {fx, fy, fz}) <= @occupied_reach))
          [{guid, distance, occupied?}]

        _elsewhere ->
          []
      end
    end)
  end

  defp minion_position(world, guid) do
    case World.position(guid) do
      {^world, x, y, z} -> [{x, y, z}]
      _gone -> []
    end
  end

  defp alive?(guid), do: match?(%{alive?: true}, Metadata.get(guid))

  defp call_minion(%GameObject{internal: %{camp: camp, world: world}} = state, finder) do
    case World.position(finder) do
      {^world, x, y, z} ->
        orientation = :rand.uniform() * 2 * :math.pi()

        summon(state, Camp.minion_entry(camp, Rolls.system()), {x, y, z, orientation},
          despawn_type: @timed_or_dead_despawn,
          despawn_delay_ms: @minion_lifetime_ms,
          home: {x, y, z, orientation},
          wander_distance: @minion_wander,
          steps: [cast_self(@minion_spawn_in)]
        )

      _gone ->
        state
    end
  end

  defp summon(%GameObject{} = state, entry, position, opts) do
    summon = %{
      entry: entry,
      position: position,
      despawn_type: Keyword.fetch!(opts, :despawn_type),
      despawn_delay_ms: Keyword.get(opts, :despawn_delay_ms, 0),
      run?: false,
      unique?: false,
      attack_guid: nil,
      script_id: 0,
      home: Keyword.get(opts, :home),
      wander_distance: Keyword.get(opts, :wander_distance)
    }

    Effects.enqueue(state, Effects.summon_creature(summon, Keyword.get(opts, :steps, []), nil))
  end

  defp restore(guid) when is_integer(guid) do
    case Entity.pid(guid) do
      pid when is_pid(pid) -> send(pid, {:ai_script_steps, [%ScriptStep{command: :set_health_pct, datalong: 100}], nil})
      nil -> :ok
    end
  end

  defp restore(_guid), do: :ok

  defp depart(guid) do
    case Entity.pid(guid) do
      pid when is_pid(pid) -> send(pid, {:ai_script_steps, [%ScriptStep{command: :despawn}], nil})
      nil -> :ok
    end
  end

  defp cast_self(spell_id),
    do: %ScriptStep{command: :cast_spell, datalong: spell_id, datalong2: @triggered, target_self?: true}
end
