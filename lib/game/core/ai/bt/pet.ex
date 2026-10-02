defmodule ThistleTea.Game.Core.AI.BT.Pet do
  @moduledoc """
  Owned-pet behavior tree: obeys explicit attack/stay/follow commands, runs
  creature spell lists in combat, and follows its owner while idle.
  """

  alias ThistleTea.Game.Core.AI.BT
  alias ThistleTea.Game.Core.AI.BT.Acquisition
  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Combat, as: CombatBT
  alias ThistleTea.Game.Core.AI.BT.Confusion
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.EventAI
  alias ThistleTea.Game.Core.AI.BT.Fear, as: FearBT
  alias ThistleTea.Game.Core.AI.BT.Follow
  alias ThistleTea.Game.Core.AI.BT.Mob.Spells, as: MobSpells
  alias ThistleTea.Game.Core.AI.BT.Navigation
  alias ThistleTea.Game.Core.AI.BT.Pet.TargetSelection
  alias ThistleTea.Game.Core.AI.BT.Spell, as: SpellBT
  alias ThistleTea.Game.Core.AI.NavigationIntent
  alias ThistleTea.Game.Core.Combat.Engagement
  alias ThistleTea.Game.Core.Creature.CreatureReaction
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Movement
  alias ThistleTea.Game.Core.Movement.Distraction
  alias ThistleTea.Game.Core.Spell.Casting

  @follow_distance 2.0
  @follow_angle :math.pi() / 2
  @idle_delay_ms 500

  def tree do
    BT.selector([
      BT.sequence([BT.condition(&dead?/2), BT.action(&idle/2)]),
      BT.action(&Confusion.tick/3),
      BT.action(&FearBT.tick/3),
      CombatBT.extra_attacks_step(),
      BT.action(&EventAI.tick/3),
      SpellBT.casting_sequence(),
      BT.action(&return_to_command/3),
      BT.sequence([
        BT.condition(&in_combat?/2),
        BT.selector([
          BT.sequence([BT.condition(&target_invalid?/3), BT.action(&continue_combat/3)]),
          MobSpells.step(),
          BT.sequence([
            BT.condition(&CombatBT.in_combat_range?/3),
            BT.action(&halt_for_melee/3),
            CombatBT.melee_sequence()
          ]),
          BT.action(&chase_target/3)
        ])
      ]),
      BT.action(&autocast_self_spell/3),
      BT.sequence([BT.condition(&aggressive?/2), BT.action(&acquire_aggressive_target/3)]),
      BT.action(&Distraction.tick/3),
      BT.sequence([BT.condition(&should_follow?/2), BT.action(&follow_owner/3)]),
      BT.action(&idle/2)
    ])
  end

  defp autocast_self_spell(%Mob{} = state, blackboard, %Context{} = context) do
    MobSpells.try_cast(state, blackboard, context, self_only?: true)
  end

  def command(state, command, target_guid, now)

  def command(%Mob{internal: %Internal{pet: %Pet{possessed?: true} = pet}} = state, command, _target, _now)
      when command in [:stay, :follow] do
    position = if command == :stay, do: xyz(state.movement_block.position)
    pet = %{pet | command_state: command, stay_position: position, attack_command?: false}
    %{state | internal: %{state.internal | pet: pet}} |> returning(nil)
  end

  def command(%Mob{internal: %Internal{pet: %Pet{} = pet}} = state, :stay, _target_guid, now) do
    state = Movement.sync_position(state, now)
    position = xyz(state.movement_block.position)
    pet = %{pet | command_state: :stay, stay_position: position, attack_command?: false}

    state
    |> halt(now)
    |> then(fn state -> %{state | internal: %{state.internal | pet: pet}} end)
    |> returning(nil)
  end

  def command(%Mob{internal: %Internal{pet: %Pet{} = pet}} = state, :follow, _target_guid, now) do
    state = clear_combat_state(state, now)
    pet = %{pet | command_state: :follow, stay_position: nil, attack_command?: false}
    %{state | internal: %{state.internal | pet: pet}} |> returning(:command)
  end

  def command(%Mob{internal: %Internal{pet: %Pet{} = pet}} = state, :attack, target_guid, now)
      when is_integer(target_guid) and target_guid > 0 do
    state = %{state | internal: %{state.internal | pet: %{pet | attack_command?: true}}} |> returning(nil)

    %Engagement.Result{entity: state} =
      Engagement.enter(state, target_guid, now, allow_passive?: true, selection: :target)

    state
  end

  def command(%Mob{internal: %{pet: %Pet{kind: :hunter}}} = state, :dismiss, _target, _now), do: state

  def command(%Mob{internal: %{pet: %Pet{kind: kind} = pet}} = state, :dismiss, _target, _now)
      when kind in [:charmed, :possessed] do
    Effects.enqueue(state, Effects.release_controlled(pet.owner_guid, state.object.guid, pet.control_spell_id))
  end

  def command(%Mob{internal: %{pet: %Pet{}}} = state, :dismiss, _target, _now) do
    Effects.enqueue(state, Effects.despawn_self(0, 0))
  end

  def command(%Mob{} = state, _command, _target_guid, _now), do: state

  def reaction(%Mob{internal: %Internal{pet: %Pet{}}} = state, reaction, now)
      when reaction in [:passive, :defensive, :aggressive] do
    state = CreatureReaction.set(state, reaction)

    if reaction == :passive do
      state
      |> clear_combat_state(now)
      |> Movement.stop(now)
    else
      state
    end
  end

  def reaction(%Mob{} = state, _reaction, _now), do: state

  defp dead?(%Mob{internal: %Internal{pet: %Pet{broken?: true}}}, _blackboard), do: true
  defp dead?(state, _blackboard), do: Entity.dead?(state)

  defp in_combat?(%Mob{internal: %Internal{in_combat: true}, unit: %Unit{target: target}}, _blackboard)
       when is_integer(target) and target > 0, do: true

  defp in_combat?(_state, _blackboard), do: false

  defp target_invalid?(%Mob{unit: %Unit{target: target}} = state, _blackboard, %Context{} = context) do
    not Navigation.target_alive_same_map?(state, target, context)
  end

  defp continue_combat(state, blackboard, %Context{now: now} = context) do
    previous_victim = state.unit.target
    pet = %{state.internal.pet | attack_command?: false}
    blackboard = blackboard |> Blackboard.clear_chase() |> Blackboard.reset_spells()
    state = %{state | internal: %{state.internal | pet: pet, blackboard: blackboard}}
    %Engagement.Result{entity: state} = Engagement.stop_attack(state)
    state = state |> Casting.cancel(now) |> halt(now)

    state =
      case TargetSelection.next(state, context, previous_victim) do
        nil -> clear_combat_state(state, now)
        target -> Engagement.enter(state, target, now, selection: :target).entity
      end

    {:success, state, state.internal.blackboard}
  end

  def victim_died(%Mob{unit: %{target: victim}, internal: %{pet: %Pet{}}} = state, victim, %Context{} = context) do
    if Entity.dead?(state) do
      state
    else
      {:success, state, _blackboard} = continue_combat(state, Blackboard.ensure(state.internal.blackboard), context)
      state
    end
  end

  def victim_died(%Mob{} = state, _victim, %Context{}), do: state

  def clear_combat_state(%Mob{internal: %Internal{pet: %Pet{} = pet}} = state, now) do
    pet = %{pet | attack_command?: false}
    %Engagement.Result{entity: state} = Engagement.leave(state, :pet_command, now)

    %{state | internal: %{state.internal | pet: pet}}
    |> halt(now)
    |> returning(:combat)
  end

  defp should_follow?(%Mob{internal: %Internal{pet: %Pet{command_state: :follow}}}, _blackboard), do: true
  defp should_follow?(_state, _blackboard), do: false

  defp aggressive?(%Mob{internal: %Internal{pet: %Pet{reaction_state: :aggressive}}}, blackboard),
    do: not Blackboard.pet_returning?(blackboard)

  defp aggressive?(_state, _blackboard), do: false

  defp acquire_aggressive_target(state, blackboard, %Context{now: now} = context) do
    case Acquisition.nearest(state, context) do
      guid when is_integer(guid) ->
        %Engagement.Result{entity: state} = Engagement.enter(state, guid, now, selection: :target)
        {:success, state, blackboard}

      _ ->
        {:failure, state, blackboard}
    end
  end

  defp return_to_command(
         %Mob{internal: %{pet: %Pet{command_state: :stay, stay_position: destination}}} = state,
         %Blackboard{pet: %{returning: reason}} = blackboard,
         %Context{now: now} = context
       )
       when reason != nil and is_tuple(destination) do
    state = Movement.sync_position(state, now)

    if NavigationIntent.reached?(xyz(state.movement_block.position), destination) do
      finish_return(Movement.stop(state, now), blackboard)
    else
      state =
        if Movement.moving?(state, now) or NavigationIntent.pending?(state),
          do: state,
          else: state |> run() |> Navigation.move_to(destination, [], context)

      {{:running, Follow.tick_ms()}, state, blackboard}
    end
  end

  defp return_to_command(
         %Mob{internal: %{pet: %Pet{owner_guid: owner, command_state: :follow}}} = state,
         %Blackboard{pet: %{returning: reason}} = blackboard,
         %Context{now: now, perception: perception} = context
       )
       when reason != nil do
    state = Movement.sync_position(state, now)

    case Perception.position(perception, owner) do
      {_world, x, y, z} ->
        if distance_to(state, {x, y, z}) <= Follow.stationary_slack(state, @follow_distance, owner, perception),
          do: finish_return(state, blackboard),
          else: follow_owner(state, blackboard, context)

      _ ->
        follow_owner(state, blackboard, context)
    end
  end

  defp return_to_command(state, %Blackboard{pet: %{returning: reason}} = blackboard, _context) when reason != nil,
    do: finish_return(state, blackboard)

  defp return_to_command(state, blackboard, _context), do: {:failure, state, blackboard}

  defp finish_return(state, blackboard), do: {:success, state, Blackboard.return_pet(blackboard, nil)}

  defp returning(%Mob{} = state, reason) do
    blackboard = state.internal.blackboard |> Blackboard.ensure() |> Blackboard.return_pet(reason)
    %{state | internal: %{state.internal | blackboard: blackboard}}
  end

  defp halt(%Mob{} = state, now) do
    state = Movement.stop(state, now)
    %{state | internal: %{state.internal | navigation_intents: []}}
  end

  def follow_owner(%Mob{internal: %Internal{pet: %Pet{owner_guid: owner_guid}}} = state, blackboard, context) do
    case Follow.step(state, owner_guid, @follow_distance, follow_angle(state), context) do
      {:ok, state} -> {{:running, Follow.tick_ms()}, state, blackboard}
      :lost -> {:success, Effects.enqueue(state, Effects.despawn_self(0, 0)), blackboard}
    end
  end

  defp chase_target(
         %Mob{internal: %{pet: %Pet{command_state: :stay, attack_command?: false}}} = state,
         blackboard,
         %Context{now: now}
       ) do
    {{:running, @idle_delay_ms}, Movement.stop(state, now), blackboard}
  end

  defp chase_target(
         %Mob{internal: %Internal{world: world}, unit: %Unit{target: target}} = state,
         blackboard,
         %Context{perception: perception} = context
       ) do
    state =
      case Perception.grounded_position(perception, target) do
        {^world, x, y, z} -> state |> run() |> chase_with_context(target, {x, y, z}, context)
        _ -> state
      end

    {{:running, @idle_delay_ms}, state, blackboard}
  end

  defp idle(state, blackboard), do: {{:running, @idle_delay_ms}, state, blackboard}

  defp halt_for_melee(state, blackboard, %Context{now: now}) do
    {:success, Movement.stop(state, now), blackboard}
  end

  defp follow_angle(%Mob{internal: %{pet: %Pet{kind: :mini_pet}}}), do: :math.pi()
  defp follow_angle(%Mob{internal: %{pet: %Pet{follow_angle: angle}}}) when is_number(angle), do: angle
  defp follow_angle(_state), do: @follow_angle

  defp distance_to(%Mob{movement_block: %{position: {x, y, z, _o}}}, {tx, ty, tz}) do
    :math.sqrt(:math.pow(tx - x, 2) + :math.pow(ty - y, 2) + :math.pow(tz - z, 2))
  end

  defp run(%Mob{internal: %Internal{} = internal} = state), do: %{state | internal: %{internal | running: true}}

  defp chase_with_context(%Mob{} = state, target_guid, destination, %Context{} = context) do
    Navigation.chase(state, target_guid, destination, context)
  end

  defp xyz({x, y, z, _o}), do: {x, y, z}
end
