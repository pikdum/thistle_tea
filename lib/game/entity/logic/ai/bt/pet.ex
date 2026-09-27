defmodule ThistleTea.Game.Entity.Logic.AI.BT.Pet do
  @moduledoc """
  Owned-pet behavior tree: obeys explicit attack/stay/follow commands, runs
  creature spell lists in combat, and follows its owner while idle.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Acquisition
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Combat, as: CombatBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Confusion
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Fear, as: FearBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob.Spells, as: MobSpells
  alias ThistleTea.Game.Entity.Logic.AI.BT.Navigation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Spell, as: SpellBT
  alias ThistleTea.Game.Entity.Logic.AI.NavigationIntent
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Distraction
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Time

  @follow_distance 2.0
  @follow_angle :math.pi() / 2
  @follow_start_distance 0.25
  @follow_repath_distance 0.5
  @stationary_slack_factor 1.4
  @follow_prediction_ms 500
  @follow_tick_ms 100
  @idle_delay_ms 500

  def tree do
    BT.selector([
      BT.sequence([BT.condition(&dead?/2), BT.action(&idle/2)]),
      BT.action(&Confusion.tick/3),
      BT.action(&FearBT.tick/3),
      BT.action(&return_to_command/3),
      CombatBT.extra_attacks_step(),
      SpellBT.casting_sequence(),
      BT.sequence([
        BT.condition(&in_combat?/2),
        BT.selector([
          BT.sequence([BT.condition(&target_invalid?/3), BT.action(&clear_combat/3)]),
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

  def command(state, command, target_guid, now \\ Time.now())

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

  def command(%Mob{} = state, _command, _target_guid, _now), do: state

  def reaction(%Mob{internal: %Internal{pet: %Pet{} = pet} = internal} = state, reaction)
      when reaction in [:passive, :defensive, :aggressive] do
    state = %{state | internal: %{internal | pet: %{pet | reaction_state: reaction}}}

    if reaction == :passive do
      state
      |> clear_combat_state()
      |> Movement.stop(Time.now())
    else
      state
    end
  end

  def reaction(%Mob{} = state, _reaction), do: state

  defp dead?(%Mob{internal: %Internal{pet: %Pet{broken?: true}}}, _blackboard), do: true
  defp dead?(state, _blackboard), do: Core.dead?(state)

  defp in_combat?(%Mob{internal: %Internal{in_combat: true}, unit: %Unit{target: target}}, _blackboard)
       when is_integer(target) and target > 0, do: true

  defp in_combat?(_state, _blackboard), do: false

  defp target_invalid?(%Mob{unit: %Unit{target: target}} = state, _blackboard, %Context{} = context) do
    not Navigation.target_alive_same_map?(state, target, context)
  end

  defp clear_combat(state, blackboard, %Context{now: now}) do
    state = %{state | internal: %{state.internal | blackboard: blackboard}} |> clear_combat_state(now)
    {:success, state, state.internal.blackboard}
  end

  def clear_combat_state(%Mob{internal: %Internal{pet: %Pet{} = pet}} = state, now \\ Time.now()) do
    pet = %{pet | attack_command?: false}
    %Engagement.Result{entity: state} = Engagement.leave(state, :pet_command)

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

      {{:running, @follow_tick_ms}, state, blackboard}
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
        if distance_to(state, {x, y, z}) <= stationary_slack(state, owner, perception),
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

  def follow_owner(
        %Mob{internal: %Internal{pet: %Pet{owner_guid: owner_guid}, world: world}} = state,
        blackboard,
        %Context{now: now, perception: perception} = context
      ) do
    with {^world, x, y, z} <- Perception.projected_position(perception, owner_guid, @follow_prediction_ms),
         %{orientation: orientation} when is_number(orientation) <- Perception.metadata(perception, owner_guid) do
      destination = follow_position(state, {x, y, z}, orientation)
      state = Movement.sync_position(state, now)

      state =
        if should_repath?(state, destination, owner_guid, {x, y, z}, context) do
          velocity = catchup_velocity(state, destination)

          state
          |> run()
          |> follow_with_context(destination, orientation, velocity, context)
          |> face(orientation)
        else
          state
        end

      {{:running, @follow_tick_ms}, state, blackboard}
    else
      _ -> {:success, Effects.enqueue(state, Effects.despawn_self(0, 0)), blackboard}
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

  defp face(%Mob{movement_block: %MovementBlock{position: {x, y, z, _o}} = movement_block} = state, orientation) do
    %{state | movement_block: %{movement_block | position: {x, y, z, orientation}}}
  end

  defp follow_position(state, {x, y, z}, orientation) do
    angle = orientation + follow_angle(state)
    {x + :math.cos(angle) * @follow_distance, y + :math.sin(angle) * @follow_distance, z}
  end

  defp follow_angle(%Mob{internal: %{pet: %Pet{kind: :mini_pet}}}), do: :math.pi()
  defp follow_angle(%Mob{internal: %{pet: %Pet{follow_angle: angle}}}) when is_number(angle), do: angle
  defp follow_angle(_state), do: @follow_angle

  defp distance_to(%Mob{movement_block: %{position: {x, y, z, _o}}}, {tx, ty, tz}) do
    :math.sqrt(:math.pow(tx - x, 2) + :math.pow(ty - y, 2) + :math.pow(tz - z, 2))
  end

  defp run(%Mob{internal: %Internal{} = internal} = state), do: %{state | internal: %{internal | running: true}}

  defp should_repath?(state, destination, owner_guid, owner_position, %Context{} = context) do
    not settled_at_owner?(state, owner_guid, owner_position, context) and
      distance_to(state, destination) > @follow_start_distance and
      destination_changed?(state.movement_block.spline_nodes, destination)
  end

  defp settled_at_owner?(state, owner_guid, owner_position, %Context{now: now, perception: perception}) do
    not Perception.moving?(perception, owner_guid) and not Movement.moving?(state, now) and
      distance_to(state, owner_position) <= stationary_slack(state, owner_guid, perception)
  end

  defp stationary_slack(%Mob{unit: %Unit{bounding_radius: radius}}, owner_guid, perception) do
    @stationary_slack_factor * @follow_distance + bounding_radius(radius) +
      owner_bounding_radius(owner_guid, perception)
  end

  defp owner_bounding_radius(owner_guid, perception) do
    case Perception.metadata(perception, owner_guid) do
      %{bounding_radius: radius} -> bounding_radius(radius)
      _ -> Unit.default_bounding_radius()
    end
  end

  defp bounding_radius(radius) when is_number(radius) and radius > 0, do: radius
  defp bounding_radius(_radius), do: Unit.default_bounding_radius()

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

  defp chase_with_context(%Mob{} = state, target_guid, destination, %Context{} = context) do
    Navigation.chase(state, target_guid, destination, context)
  end

  defp follow_with_context(%Mob{} = state, destination, orientation, velocity, %Context{} = context) do
    Navigation.follow(state, destination, orientation, velocity, context)
  end

  defp xyz({x, y, z, _o}), do: {x, y, z}
end
