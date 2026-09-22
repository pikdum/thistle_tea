defmodule ThistleTea.Game.Entity.Logic.AI.BT.Combat do
  @moduledoc """
  Shared melee combat behavior-tree subtree: in-combat and range checks, swing
  execution, and waiting out the attack timer. Used by both mob and player
  trees.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard.Combat, as: CombatMemory
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Detection
  alias ThistleTea.Game.Entity.Logic.AI.BT.Navigation
  alias ThistleTea.Game.Entity.Logic.AttackTable
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Combat, as: CombatLogic
  alias ThistleTea.Game.Entity.Logic.CombatControl
  alias ThistleTea.Game.Entity.Logic.CombatSkills
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Disarm
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Entity.Logic.MeleeSpell
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Entity.SpellTargetResolver
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Target

  @attack_retry_delay_ms 100
  @attack_display_delay_ms 200

  def melee_sequence do
    BT.sequence([
      BT.condition(&in_combat?/2),
      BT.condition(&target_valid_same_map?/3),
      BT.action(&melee_attack_with_context/3),
      BT.action(&wait_for_next_attack_with_context/3)
    ])
  end

  def in_combat?(%Character{unit: %Unit{target: target}}, %Blackboard{combat: %CombatMemory{auto_attacking: true}})
      when is_integer(target) and target > 0 do
    true
  end

  def in_combat?(%Character{}, _blackboard), do: false

  def in_combat?(%{internal: %Internal{in_combat: true}, unit: %Unit{target: target}}, _blackboard)
      when is_integer(target) and target > 0 do
    true
  end

  def in_combat?(_state, _blackboard), do: false

  def target_valid_same_map?(%{unit: %Unit{target: target}} = state, _blackboard, %Context{} = context) do
    Navigation.target_valid_same_map?(state, target, context) and
      Detection.detectable?(state, target, context)
  end

  def target_valid_same_map?(_state, _blackboard, %Context{}), do: false

  def in_combat_range?(
        %{movement_block: %{position: {x, y, z, _orientation}}, unit: %Unit{target: target}} = state,
        _blackboard,
        %Context{perception: perception}
      ) do
    case Perception.position(perception, target) do
      {_world, tx, ty, tz} ->
        distance = :math.sqrt(:math.pow(tx - x, 2) + :math.pow(ty - y, 2) + :math.pow(tz - z, 2))
        distance <= combat_reach(state, target, perception)

      _ ->
        false
    end
  end

  def in_combat_range?(_state, _blackboard, %Context{}), do: false

  def melee_attack_with_context(%{internal: %Internal{casting: %Cast{}}} = state, blackboard, %Context{}),
    do: {:success, state, blackboard}

  def melee_attack_with_context(
        %{unit: %Unit{target: target}} = state,
        %Blackboard{} = blackboard,
        %Context{now: now} = context
      )
      when is_integer(target) and target > 0 do
    {state, blackboard} = maybe_start_melee_attack(state, target, blackboard)
    attack_ready = Blackboard.ready_for?(blackboard, :next_attack_at, now)
    offhand_ready = offhand_ready?(state, blackboard, now)

    {state, blackboard} =
      if attack_ready or offhand_ready do
        state = face_melee_victim(state, blackboard, context)

        case attack_readiness(state, blackboard, context) do
          :ok -> perform_ready_attacks(state, target, blackboard, attack_ready, now)
          error -> retry_attacks(state, blackboard, error, now)
        end
      else
        {state, blackboard}
      end

    {:success, state, blackboard}
  end

  def melee_attack_with_context(state, blackboard, %Context{}), do: {:success, state, blackboard}

  defp perform_ready_attacks(state, target, blackboard, main_ready?, now) do
    {state, events} = Aura.remove_with_interrupt_flags(state, Aura.interrupt_mask(:attack), now)
    state = Effects.enqueue(state, events)
    state = PlayerCombat.mark_initiated(state, now)
    blackboard = clear_swing_error(blackboard)
    {state, blackboard} = perform_main_hand(state, target, blackboard, main_ready?, now)
    perform_offhand(state, target, blackboard, offhand_ready?(state, blackboard, now), now)
  end

  defp perform_main_hand(state, target, blackboard, true, now) do
    speed = CombatLogic.attack_speed_ms(state)

    blackboard =
      if CombatLogic.offhand_damage_range(state),
        do: delay_nearby_attack(blackboard, :next_offhand_attack_at, now),
        else: blackboard

    {send_melee_attack(state, target, now), Blackboard.put_next_at(blackboard, :next_attack_at, speed, now)}
  end

  defp perform_main_hand(state, _target, blackboard, false, _now), do: {state, blackboard}

  defp perform_offhand(state, target, blackboard, true, now) do
    speed = CombatLogic.offhand_attack_speed_ms(state)
    blackboard = delay_nearby_attack(blackboard, :next_attack_at, now)

    {send_offhand_attack(state, target), Blackboard.put_next_at(blackboard, :next_offhand_attack_at, speed, now)}
  end

  defp perform_offhand(state, _target, blackboard, false, _now), do: {state, blackboard}

  def wait_for_next_attack(state, %Blackboard{} = blackboard, now) when is_integer(now) do
    delay_ms = next_attack_delay(state, blackboard, now)
    status = if delay_ms > 0, do: {:running, delay_ms}, else: :running
    {status, state, blackboard}
  end

  def next_attack_delay(state, %Blackboard{} = blackboard, now) do
    delays = [Blackboard.delay_until(blackboard, :next_attack_at, now)]

    delays =
      if CombatLogic.offhand_damage_range(state) do
        [Blackboard.delay_until(blackboard, :next_offhand_attack_at, now) | delays]
      else
        delays
      end

    Enum.min(delays)
  end

  defp wait_for_next_attack_with_context(state, %Blackboard{} = blackboard, %Context{now: now}) do
    wait_for_next_attack(state, blackboard, now)
  end

  defp maybe_start_melee_attack(state, target, %Blackboard{combat: %CombatMemory{attack_started: true}} = blackboard)
       when is_integer(target) do
    {state, blackboard}
  end

  defp maybe_start_melee_attack(%{object: %{guid: guid}} = state, target, %Blackboard{} = blackboard)
       when is_integer(target) do
    state = Effects.enqueue(state, CombatLogic.attack_start(guid, target))
    combat = %{blackboard.combat | attack_started: true}
    {state, %{blackboard | combat: combat}}
  end

  defp delay_nearby_attack(blackboard, key, now) do
    if Blackboard.delay_until(blackboard, key, now) < @attack_display_delay_ms,
      do: Blackboard.put_next_at(blackboard, key, @attack_display_delay_ms, now),
      else: blackboard
  end

  defp retry_attacks(state, blackboard, error, now) do
    state = notify_swing_error(state, blackboard, error)
    blackboard = delay_ready_attack(blackboard, :next_attack_at, now)

    blackboard =
      if CombatLogic.offhand_damage_range(state),
        do: delay_ready_attack(blackboard, :next_offhand_attack_at, now),
        else: blackboard

    {state, %{blackboard | combat: %{blackboard.combat | last_swing_error: error}}}
  end

  defp delay_ready_attack(blackboard, key, now) do
    if Blackboard.ready_for?(blackboard, key, now),
      do: Blackboard.put_next_at(blackboard, key, @attack_retry_delay_ms, now),
      else: blackboard
  end

  defp notify_swing_error(%Character{} = state, blackboard, error) do
    if blackboard.combat.last_swing_error == error do
      state
    else
      case error do
        :not_in_range -> Effects.enqueue(state, Effects.attack_not_in_range())
        :bad_facing -> Effects.enqueue(state, %Effects.AttackBadFacing{})
        _ -> state
      end
    end
  end

  defp notify_swing_error(state, _blackboard, _error), do: state

  defp clear_swing_error(%Blackboard{} = blackboard) do
    %{blackboard | combat: %{blackboard.combat | last_swing_error: nil}}
  end

  defp send_melee_attack(state, target, now) when is_integer(target) and is_integer(now) do
    {state, queued_spell} = MeleeSpell.consume_next_swing(state)

    case queued_spell do
      %Spell{} = spell -> send_queued_spell_swing(state, spell, target, now)
      _no_queued_spell -> send_white_swing(state, target)
    end
  end

  def extra_attacks_step, do: BT.action(&consume_extra_attacks/3)

  def consume_extra_attacks(
        state,
        %Blackboard{combat: %CombatMemory{extra_attacks: count}} = blackboard,
        %Context{} = context
      )
      when count > 0 do
    state = face_melee_victim(state, blackboard, context)

    if extra_attack_ready?(state, blackboard, context) do
      {state, events} = Aura.remove_with_interrupt_flags(state, Aura.interrupt_mask(:attack), context.now)
      state = state |> Effects.enqueue(events) |> PlayerCombat.mark_initiated(context.now)
      state = Enum.reduce(1..count, state, fn _attack, entity -> send_white_swing(entity, entity.unit.target, true) end)
      blackboard = %{blackboard | combat: %{blackboard.combat | extra_attacks: 0}}
      blackboard = Blackboard.put_next_at(blackboard, :next_attack_at, CombatLogic.attack_speed_ms(state), context.now)
      {:failure, state, blackboard}
    else
      {:failure, state, blackboard}
    end
  end

  def consume_extra_attacks(state, blackboard, _context), do: {:failure, state, blackboard}

  defp extra_attack_ready?(state, blackboard, context) do
    in_combat?(state, blackboard) and attack_readiness(state, blackboard, context) == :ok
  end

  defp attack_readiness(state, blackboard, context) do
    cond do
      CombatControl.auto_attack_blocked?(state) -> :cannot_attack
      not Death.alive?(state) -> :dead
      match?(%{alive?: false}, Perception.metadata(context.perception, state.unit.target)) -> :dead
      not target_valid_same_map?(state, blackboard, context) -> :unavailable
      not in_combat_range?(state, blackboard, context) -> :not_in_range
      not facing_target?(state, context) -> :bad_facing
      true -> :ok
    end
  end

  defp face_melee_victim(%Mob{internal: %Internal{casting: nil}} = state, blackboard, %Context{now: now} = context) do
    if in_combat?(state, blackboard) and attack_readiness(state, blackboard, context) == :bad_facing and
         not Movement.moving?(state, now) do
      {_world, x, y, _z} = Perception.position(context.perception, state.unit.target)
      state |> Movement.face_towards({x, y}) |> Effects.enqueue(Effects.set_facing({:target, state.unit.target}))
    else
      state
    end
  end

  defp face_melee_victim(state, _blackboard, _context), do: state

  defp facing_target?(%{unit: %Unit{target: target}, movement_block: %{position: {x, y, _z, orientation}}}, context) do
    case Perception.position(context.perception, target) do
      {_world, tx, ty, _tz} ->
        dx = tx - x
        dy = ty - y
        dx * dx + dy * dy <= 1.4 * 1.4 or :math.cos(:math.atan2(dy, dx) - orientation) >= 0.5

      _ ->
        false
    end
  end

  defp send_white_swing(state, target, extra_attack? \\ false) do
    attack = state |> melee_attack_payload() |> Map.put(:extra_attack?, extra_attack?) |> CombatLogic.finalize_attack()

    Effects.enqueue(state, Effects.deliver_attack(target, attack))
  end

  defp send_offhand_attack(state, target) do
    {min_damage, max_damage} = CombatLogic.offhand_damage_range(state)

    attack =
      state
      |> melee_attack_payload(:offhand)
      |> Map.merge(%{min_damage: min_damage, max_damage: max_damage, offhand?: true})
      |> CombatLogic.finalize_attack()

    Effects.enqueue(state, Effects.deliver_attack(target, attack))
  end

  defp offhand_ready?(state, blackboard, now) do
    not is_nil(CombatLogic.offhand_damage_range(state)) and
      Blackboard.ready_for?(blackboard, :next_offhand_attack_at, now)
  end

  defp send_queued_spell_swing(state, %Spell{} = spell, target, now) do
    case Disarm.validate(state, spell) do
      :ok ->
        send_valid_queued_spell_swing(state, spell, target, now)

      {:error, reason} ->
        state
        |> Effects.enqueue(Effects.spell_cast_failed(spell.id, reason))
        |> send_white_swing(target)
    end
  end

  defp send_valid_queued_spell_swing(state, %Spell{} = spell, target, now) do
    cost = Resources.power_cost(state, spell)

    if Resources.can_pay_cost?(state, spell.power_type, cost) do
      targets = queued_spell_targets(state, spell, target)

      state
      |> Resources.spend_cost(spell.power_type, cost, now)
      |> queue_queued_spell_go(spell, target, targets)
      |> deliver_queued_spell(spell, targets)
    else
      state
      |> Effects.enqueue(Effects.spell_cast_failed(spell.id, :no_power))
      |> send_white_swing(target)
    end
  end

  defp queued_spell_targets(state, %Spell{} = spell, target) do
    case SpellTargetResolver.resolve(state, spell, Target.unit(target)) do
      [] -> [target]
      targets -> targets
    end
  end

  defp deliver_queued_spell(state, %Spell{} = spell, targets) do
    Enum.reduce(targets, state, fn target, entity ->
      context = %{
        CastContext.from_caster(entity, spell, target)
        | selected_target_guid: List.first(targets),
          target_hostile?: Hostility.valid_attack_target?(entity, target)
      }

      Effects.enqueue(entity, Effects.deliver_spell(target, context, spell))
    end)
  end

  defp melee_attack_payload(%{object: %{guid: guid}} = state, hand \\ :mainhand) do
    {min_damage, max_damage} = CombatLogic.damage_range(state)

    %{
      caster: guid,
      caster_owner_guid: caster_owner_guid(state),
      min_damage: min_damage,
      max_damage: max_damage,
      threat_multiplier: Aura.percent_multiplier(state, :mod_threat, Spell.school_mask(:physical))
    }
    |> Map.merge(AttackTable.attacker_context(state, hand))
    |> Map.merge(CombatSkills.snapshot(state, hand))
  end

  defp caster_owner_guid(%{internal: %{pet: %{owner_guid: owner_guid}}}) when is_integer(owner_guid), do: owner_guid
  defp caster_owner_guid(%{object: %{guid: guid}}), do: guid

  defp queue_queued_spell_go(%{object: %{guid: guid}} = state, %{id: spell_id}, target, targets)
       when is_integer(guid) and is_integer(spell_id) and is_integer(target) and is_list(targets) do
    Effects.enqueue(state, [
      Effects.spell_cast_result(spell_id),
      Effects.spell_go(guid, spell_id, targets, Target.unit(target))
    ])
  end

  defp queue_queued_spell_go(state, _queued_spell, _target, _targets), do: state

  defp combat_reach(%{unit: unit}, target, perception) do
    CombatLogic.melee_reach(combat_reach_value(unit), perceived_target_combat_reach(target, perception))
  end

  defp combat_reach_value(%Unit{combat_reach: combat_reach}) when is_number(combat_reach) and combat_reach > 0 do
    combat_reach
  end

  defp combat_reach_value(combat_reach) when is_number(combat_reach) and combat_reach > 0 do
    combat_reach
  end

  defp combat_reach_value(_unit), do: Unit.default_combat_reach()

  defp perceived_target_combat_reach(target, perception) when is_integer(target) do
    case Perception.metadata(perception, target) do
      %{combat_reach: combat_reach} -> combat_reach_value(combat_reach)
      _ -> Unit.default_combat_reach()
    end
  end

  defp perceived_target_combat_reach(_target, _perception), do: Unit.default_combat_reach()
end
