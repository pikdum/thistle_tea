defmodule ThistleTea.Game.Entity.Logic.AI.BT.Charm do
  @moduledoc "Drives charmed players using immutable controller observations, learned spells, and navigation intents."

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Possession
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard.Charm, as: Memory
  alias ThistleTea.Game.Entity.Logic.AI.BT.Combat, as: CombatBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Random
  alias ThistleTea.Game.Entity.Logic.AI.BT.Detection
  alias ThistleTea.Game.Entity.Logic.AI.BT.Navigation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Spell, as: SpellBT
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.CombatControl
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Logic.PlayerCharm
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Entity.Logic.TargetRef
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Cooldowns

  def maintain(%Character{internal: %{possession: %Possession{kind: :charm} = control}} = entity, blackboard, context) do
    controller = Perception.metadata(context.perception, control.caster_guid)

    if not Core.dead?(entity) and controller_present?(entity, control, controller, context) do
      {:failure, entity, blackboard}
    else
      {entity, effects} = Aura.remove_spells(entity, [control.spell_id], context.now)
      {:failure, Effects.enqueue(entity, effects), entity.internal.blackboard}
    end
  end

  def maintain(entity, blackboard, _context), do: {:failure, entity, blackboard}

  def tick(%Character{internal: %{possession: %Possession{kind: :charm}}} = entity, blackboard, context) do
    blackboard = %{blackboard | charm: blackboard.charm || %Memory{}}

    if Aura.has_aura?(entity, :mod_stun) do
      {BT.running(200, :charm), entity, blackboard}
    else
      act(entity, blackboard, context)
    end
  end

  def tick(entity, blackboard, _context), do: {:failure, entity, blackboard}

  defp controller_present?(entity, control, controller, context) when is_map(controller) do
    controller[:alive?] == true and Navigation.target_valid_same_map?(entity, control.caster_guid, context) and
      (Guid.entity_type(control.caster_guid) == :player or controller[:in_combat] == true)
  end

  defp controller_present?(_entity, _control, _controller, _context), do: false

  defp act(%Character{internal: %{casting: %Cast{}}} = entity, blackboard, context) do
    {_status, entity, blackboard} = SpellBT.cast_tick(entity, blackboard, context.now)
    {BT.running(100, :charm), entity, blackboard}
  end

  defp act(entity, blackboard, context) do
    case victim(entity, context) do
      nil -> follow(entity, blackboard, context)
      target -> fight(entity, target, blackboard, context)
    end
  end

  defp victim(%Character{internal: %{possession: %Possession{reaction: :passive, command_target: nil}}}, _context),
    do: nil

  defp victim(entity, %Context{random: random} = context) do
    control = entity.internal.possession
    existing = control.command_target || entity.unit.target

    if valid_target?(entity, existing, context) do
      existing
    else
      control
      |> candidates(context.perception)
      |> Enum.filter(&valid_target?(entity, &1, context))
      |> then(&Random.choice(random, &1))
    end
  end

  defp candidates(control, perception) do
    controller = Perception.metadata(perception, control.caster_guid) || %{}

    if Guid.entity_type(control.caster_guid) == :player,
      do: [controller[:victim_guid]],
      else: Map.get(controller, :combat_targets, [])
  end

  defp valid_target?(entity, target, %Context{perception: perception} = context)
       when is_integer(target) and target > 0 do
    control = entity.internal.possession
    source = Perception.actor(perception, entity.object.guid)
    other = Perception.actor(perception, target)

    target not in [entity.object.guid, control.caster_guid] and other[:owner_guid] != control.caster_guid and
      Navigation.target_alive_same_map?(entity, target, context) and Detection.detectable?(entity, target, context) and
      Hostility.valid_attack_target?(source, other)
  end

  defp valid_target?(_entity, _target, _context), do: false

  defp fight(entity, target, blackboard, context) do
    {entity, blackboard} = engage(entity, target, blackboard, context)
    {entity, blackboard, casting?} = try_spell(entity, target, blackboard, context)

    if casting?, do: {BT.running(100, :charm), entity, blackboard}, else: attack(entity, target, blackboard, context)
  end

  defp engage(entity, target, blackboard, context) do
    blackboard =
      if entity.unit.target == target do
        blackboard
      else
        Blackboard.clear_attack_started(blackboard)
      end

    target_ref = TargetRef.new(target, Perception.metadata(context.perception, target) || %{})
    blackboard = Blackboard.enable_auto_attack(blackboard, target_ref)
    entity = if entity.unit.target == target, do: entity, else: Core.mark_broadcast_update(entity)
    entity = %{entity | unit: %{entity.unit | target: target}, internal: %{entity.internal | running: true}}
    entity = PlayerCombat.mark_initiated(entity, context.now)
    {entity, blackboard}
  end

  defp attack(entity, target, blackboard, context) do
    melee? = PlayerCharm.melee?(entity) or blackboard.charm.melee_fallback?

    cond do
      CombatBT.in_combat_range?(entity, blackboard, context) ->
        entity = halt_and_face(entity, target, context)
        {_status, entity, blackboard} = CombatBT.consume_extra_attacks(entity, blackboard, context)
        {_status, entity, blackboard} = CombatBT.melee_attack_with_context(entity, blackboard, context)
        {BT.running(100, :charm), entity, blackboard}

      not melee? and (Perception.distance(context.perception, target) || 100) <= 30 and
          Perception.line_of_sight?(context.perception, target) ->
        {BT.running(100, :charm), halt_and_face(entity, target, context), blackboard}

      true ->
        approach(entity, target, if(melee?, do: 1.5, else: 25.0), blackboard, context)
    end
  end

  defp try_spell(entity, target, %Blackboard{charm: memory} = blackboard, %Context{now: now} = context) do
    if now >= memory.next_cast_at do
      spell = Random.choice(context.random, entity.internal.possession.spells)
      distance = Perception.distance(context.perception, target) || 100

      available? =
        not is_nil(spell) and spell_available?(entity, spell, distance, now) and
          Perception.line_of_sight?(context.perception, target)

      memory = %{memory | next_cast_at: now + 1_500, melee_fallback?: not available?}

      entity =
        if available? do
          control = entity.internal.possession
          entity = halt_and_face(entity, target, context)

          Effects.enqueue(entity, %Effects.CharmCast{
            controller_guid: control.caster_guid,
            control_spell_id: control.spell_id,
            control_applied_at: control.applied_at,
            spell_id: spell.id,
            target_guid: target
          })
        else
          entity
        end

      {entity, %{blackboard | charm: memory}, available?}
    else
      {entity, blackboard, false}
    end
  end

  defp spell_available?(entity, spell, distance, now) do
    distance <= max(spell.range_yards || 0, 5.0) and distance >= (spell.min_range_yards || 0) and
      CombatControl.prevention(entity, spell) == :ok and
      Resources.can_pay_cost?(entity, spell.power_type, Resources.power_cost(entity, spell)) and
      not Cooldowns.on_cooldown?(entity, spell, now) and not Cooldowns.on_gcd?(entity, spell, now) and
      not Cooldowns.school_locked?(entity, Spell.school_mask(spell.school), now)
  end

  defp follow(entity, blackboard, context) do
    {entity, effects} = PlayerCombat.stop_attack(%{entity | internal: %{entity.internal | blackboard: blackboard}})
    entity = Effects.enqueue(entity, effects)
    blackboard = entity.internal.blackboard
    control = entity.internal.possession
    distance = Perception.distance(context.perception, control.caster_guid) || 0

    if control.command != :stay and distance > 3.0 do
      approach(entity, control.caster_guid, 2.0, blackboard, context)
    else
      {BT.running(200, :charm), halt(entity, context.now), blackboard}
    end
  end

  defp approach(entity, target, distance, %Blackboard{charm: memory} = blackboard, %Context{now: now} = context) do
    case Perception.position(context.perception, target) do
      {_world, tx, ty, tz} when now >= memory.next_move_at and entity.internal.rooted? != true ->
        {x, y, z, _} = entity.movement_block.position
        length = Math.distance({x, y, z}, {tx, ty, tz})
        fraction = max(length - distance, 0) / max(length, 0.001)
        destination = {x + (tx - x) * fraction, y + (ty - y) * fraction, z + (tz - z) * fraction}
        entity = %{entity | internal: %{entity.internal | running: true}}
        entity = Navigation.move_to(entity, destination, [run?: true, face_target: target], context)
        {BT.running(100, :charm), entity, %{blackboard | charm: %{memory | next_move_at: now + 500}}}

      _ ->
        {BT.running(100, :charm), entity, blackboard}
    end
  end

  defp halt_and_face(entity, target, context) do
    entity = halt(entity, context.now)
    {_world, tx, ty, _tz} = Perception.position(context.perception, target)
    {x, y, z, orientation} = entity.movement_block.position
    angle = :math.atan2(ty - y, tx - x)

    if abs(angle - orientation) > 0.1 do
      entity = %{entity | movement_block: %{entity.movement_block | position: {x, y, z, angle}}}
      Effects.enqueue(entity, Effects.set_facing({:angle, angle}))
    else
      entity
    end
  end

  defp halt(entity, now) do
    if Movement.moving?(entity, now), do: Movement.stop(entity, now), else: entity
  end
end
