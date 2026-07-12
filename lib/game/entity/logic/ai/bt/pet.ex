defmodule ThistleTea.Game.Entity.Logic.AI.BT.Pet do
  @moduledoc """
  Owned-pet behavior tree: obeys explicit attack/stay/follow commands, runs
  creature spell lists in combat, and follows its owner while idle.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Aura, as: AuraBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Combat, as: CombatBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob.Spells, as: MobSpells
  alias ThistleTea.Game.Entity.Logic.AI.BT.Regen, as: RegenBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Spell, as: SpellBT
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Logic.Threat
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata

  @follow_distance 2.0
  @follow_angle :math.pi() / 2
  @follow_start_distance 0.25
  @follow_repath_distance 0.5
  @follow_prediction_ms 500
  @follow_tick_ms 100
  @idle_delay_ms 500
  @act_enabled 0xC1
  @act_disabled 0x81

  def tree do
    BT.selector([
      AuraBT.tick_step(),
      RegenBT.tick_step(),
      BT.sequence([BT.condition(&dead?/2), BT.action(&idle/2)]),
      SpellBT.casting_sequence(),
      BT.sequence([
        BT.condition(&in_combat?/2),
        BT.selector([
          BT.sequence([BT.condition(&target_invalid?/2), BT.action(&clear_combat/2)]),
          MobSpells.step(),
          BT.sequence([
            BT.condition(&CombatBT.in_combat_range?/2),
            BT.action(&halt_for_melee/2),
            CombatBT.melee_sequence()
          ]),
          BT.action(&chase_target/2)
        ])
      ]),
      BT.sequence([BT.condition(&aggressive?/2), BT.action(&acquire_aggressive_target/2)]),
      BT.sequence([BT.condition(&should_follow?/2), BT.action(&follow_owner/2)]),
      BT.action(&idle/2)
    ])
  end

  def command(%Mob{internal: %Internal{pet: %Pet{} = pet}} = state, :stay, _target_guid) do
    position = xyz(state.movement_block.position)
    pet = %{pet | command_state: :stay, stay_position: position}

    state
    |> clear_combat_state()
    |> then(fn state -> %{state | internal: %{state.internal | pet: pet, in_combat: false}} end)
    |> Movement.halt(Time.now())
  end

  def command(%Mob{internal: %Internal{pet: %Pet{} = pet} = internal} = state, :follow, _target_guid) do
    state = clear_combat_state(state)
    %{state | internal: %{internal | pet: %{pet | command_state: :follow, stay_position: nil}, in_combat: false}}
  end

  def command(%Mob{internal: %Internal{pet: %Pet{} = pet} = internal, unit: unit} = state, :attack, target_guid)
      when is_integer(target_guid) and target_guid > 0 do
    state = %{
      state
      | internal: %{internal | pet: %{pet | command_state: :attack}, in_combat: true},
        unit: %{unit | target: target_guid}
    }

    state
    |> Threat.add(target_guid, 0)
    |> Combat.sync_combat_flag()
  end

  def command(%Mob{} = state, _command, _target_guid), do: state

  def reaction(%Mob{internal: %Internal{pet: %Pet{} = pet} = internal} = state, reaction)
      when reaction in [:passive, :defensive, :aggressive] do
    state = %{state | internal: %{internal | pet: %{pet | reaction_state: reaction}}}

    if reaction == :passive do
      state
      |> clear_combat_state()
      |> Movement.halt(Time.now())
    else
      state
    end
  end

  def reaction(%Mob{} = state, _reaction), do: state

  def set_actions(%Mob{} = state, actions) when is_list(actions) do
    Enum.reduce(actions, state, &set_action/2)
  end

  def set_actions(%Mob{} = state, _actions), do: state

  defp dead?(state, _blackboard), do: Core.dead?(state)

  defp in_combat?(%Mob{internal: %Internal{in_combat: true}, unit: %Unit{target: target}}, _blackboard)
       when is_integer(target) and target > 0, do: true

  defp in_combat?(_state, _blackboard), do: false

  defp target_invalid?(%Mob{internal: %Internal{map: map}, unit: %Unit{target: target}}, _blackboard) do
    case World.target_position(target) do
      {^map, _x, _y, _z} -> target_dead?(target)
      _ -> true
    end
  end

  defp target_dead?(guid) do
    case Metadata.query(guid, [:alive?]) do
      %{alive?: false} -> true
      _ -> false
    end
  end

  defp clear_combat(state, blackboard), do: {:success, clear_combat_state(state), blackboard}

  defp clear_combat_state(%Mob{internal: %Internal{pet: %Pet{} = pet} = internal, unit: unit} = state) do
    pet = if pet.command_state == :attack, do: %{pet | command_state: :follow}, else: pet
    state = %{state | internal: %{internal | in_combat: false, pet: pet}, unit: %{unit | target: 0}}

    state
    |> Threat.wipe()
    |> Combat.sync_combat_flag()
  end

  defp should_follow?(%Mob{internal: %Internal{pet: %Pet{command_state: :follow}}}, _blackboard), do: true
  defp should_follow?(_state, _blackboard), do: false

  defp aggressive?(%Mob{internal: %Internal{pet: %Pet{reaction_state: :aggressive}}}, _blackboard), do: true
  defp aggressive?(_state, _blackboard), do: false

  defp acquire_aggressive_target(state, blackboard) do
    target_guid =
      state
      |> World.nearby_mobs(20.0)
      |> Enum.find_value(fn {guid, _distance} -> if Hostility.valid_attack_target?(state, guid), do: guid end)

    case target_guid do
      guid when is_integer(guid) -> {:success, command(state, :attack, guid), blackboard}
      _ -> {:failure, state, blackboard}
    end
  end

  defp follow_owner(%Mob{internal: %Internal{pet: %Pet{owner_guid: owner_guid}, map: map}} = state, blackboard) do
    now = Time.now()

    with {^map, x, y, z} <- World.projected_position(owner_guid, @follow_prediction_ms, now),
         %{orientation: orientation} when is_number(orientation) <- Metadata.query(owner_guid, [:orientation]) do
      destination = follow_position({x, y, z}, orientation)
      state = Movement.sync_position(state, now)

      state =
        if should_repath?(state, destination) do
          velocity = catchup_velocity(state, destination)

          state
          |> run()
          |> Movement.move_to(destination, [velocity: velocity], now)
        else
          state
        end

      {{:running, @follow_tick_ms}, state, blackboard}
    else
      _ -> {:success, Event.enqueue(state, Event.despawn_self(0, 0)), blackboard}
    end
  end

  defp chase_target(%Mob{internal: %Internal{map: map}, unit: %Unit{target: target}} = state, blackboard) do
    state =
      case World.target_position(target) do
        {^map, x, y, z} -> state |> run() |> Movement.move_to({x, y, z}, [face_target: target], Time.now())
        _ -> state
      end

    {{:running, @idle_delay_ms}, state, blackboard}
  end

  defp idle(state, blackboard), do: {{:running, @idle_delay_ms}, state, blackboard}

  defp halt_for_melee(state, blackboard), do: {:success, Movement.halt(state, Time.now()), blackboard}

  defp follow_position({x, y, z}, orientation) do
    angle = orientation + @follow_angle
    {x + :math.cos(angle) * @follow_distance, y + :math.sin(angle) * @follow_distance, z}
  end

  defp distance_to(%Mob{movement_block: %{position: {x, y, z, _o}}}, {tx, ty, tz}) do
    :math.sqrt(:math.pow(tx - x, 2) + :math.pow(ty - y, 2) + :math.pow(tz - z, 2))
  end

  defp run(%Mob{internal: %Internal{} = internal} = state), do: %{state | internal: %{internal | running: true}}

  defp should_repath?(state, destination) do
    distance_to(state, destination) > @follow_start_distance and
      destination_changed?(state.movement_block.spline_nodes, destination)
  end

  defp destination_changed?([_ | _] = nodes, destination) do
    point_distance(List.last(nodes), destination) > @follow_repath_distance
  end

  defp destination_changed?(_nodes, _destination), do: true

  defp catchup_velocity(%Mob{movement_block: %{run_speed: speed}} = state, destination)
       when is_number(speed) and speed > 0 do
    distance = distance_to(state, destination)
    factor = if distance > speed, do: min(1.0 + 0.04 * (distance - speed), 2.1), else: 1.0
    speed * factor
  end

  defp catchup_velocity(_state, _destination), do: nil

  defp point_distance({x, y, z}, {tx, ty, tz}) do
    :math.sqrt(:math.pow(tx - x, 2) + :math.pow(ty - y, 2) + :math.pow(tz - z, 2))
  end

  defp set_action(
         %{position: position, action: spell_id, action_type: action_type},
         %Mob{internal: %Internal{pet: %Pet{} = pet, spellbook: spellbook} = internal} = state
       )
       when position in 0..9 and is_integer(spell_id) and is_integer(action_type) do
    if spell_id == 0 or Map.has_key?(spellbook, spell_id) do
      autocast = update_autocast(pet.autocast, spell_id, action_type)
      pet = %{pet | action_bar: Map.put(pet.action_bar, position, {spell_id, action_type}), autocast: autocast}
      %{state | internal: %{internal | pet: pet}}
    else
      state
    end
  end

  defp set_action(_action, state), do: state

  defp update_autocast(autocast, spell_id, @act_enabled) when spell_id > 0, do: MapSet.put(autocast, spell_id)
  defp update_autocast(autocast, spell_id, @act_disabled) when spell_id > 0, do: MapSet.delete(autocast, spell_id)
  defp update_autocast(autocast, _spell_id, _action_type), do: autocast

  defp xyz({x, y, z, _o}), do: {x, y, z}
end
