defmodule ThistleTea.Game.Entity.Logic.AI.BT.Combat do
  @moduledoc """
  Shared melee combat behavior-tree subtree: in-combat and range checks, swing
  execution, and waiting out the attack timer. Used by both mob and player
  trees.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AttackTable
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Combat, as: CombatLogic
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Entity.Logic.MeleeSpell
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Entity.SpellTargetResolver
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Targets
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Metadata

  @attack_retry_delay_ms 100

  def melee_sequence do
    BT.sequence([
      BT.condition(&in_combat?/2),
      BT.condition(&target_valid_same_map?/2),
      BT.action(&melee_attack/2),
      BT.action(&wait_for_next_attack/2)
    ])
  end

  def in_combat?(%Character{unit: %Unit{target: target}}, %Blackboard{auto_attacking: true})
      when is_integer(target) and target > 0 do
    true
  end

  def in_combat?(%Character{}, _blackboard), do: false

  def in_combat?(%{internal: %Internal{in_combat: true}, unit: %Unit{target: target}}, _blackboard)
      when is_integer(target) and target > 0 do
    true
  end

  def in_combat?(_state, _blackboard), do: false

  def target_valid_same_map?(%{internal: %Internal{world: world}, unit: %Unit{target: target}}, _blackboard) do
    case World.target_position(target) do
      {^world, _x, _y, _z} -> true
      _ -> false
    end
  end

  def target_valid_same_map?(_state, _blackboard), do: false

  def in_combat_range?(%{unit: %Unit{target: target}} = state, _blackboard) do
    case World.distance_to_guid(state, target) do
      distance when is_number(distance) -> distance <= combat_reach(state, target)
      _ -> false
    end
  end

  def in_combat_range?(_state, _blackboard), do: false

  def melee_attack(%{unit: %Unit{target: target}} = state, %Blackboard{} = blackboard)
      when is_integer(target) and target > 0 do
    melee_attack(state, blackboard, Time.now())
  end

  def melee_attack(state, blackboard), do: {:success, state, blackboard}

  def melee_attack(%{unit: %Unit{target: target}} = state, %Blackboard{} = blackboard, now)
      when is_integer(target) and target > 0 and is_integer(now) do
    {state, blackboard} = maybe_start_melee_attack(state, target, blackboard)
    in_range = in_combat_range?(state, blackboard)
    attack_ready = Blackboard.ready_for?(blackboard, :next_attack_at, now)
    offhand_ready = offhand_ready?(state, blackboard, now)

    {state, blackboard} =
      cond do
        in_range and (attack_ready or offhand_ready) ->
          perform_ready_attacks(state, target, blackboard, attack_ready, offhand_ready, now)

        in_range ->
          {state, blackboard}

        attack_ready ->
          handle_out_of_range(state, blackboard, now)

        true ->
          {state, blackboard}
      end

    {:success, state, blackboard}
  end

  def melee_attack(state, blackboard, _now), do: {:success, state, blackboard}

  defp perform_ready_attacks(state, target, blackboard, main_ready?, offhand_ready?, now) do
    state = PlayerCombat.mark_initiated(state, now)
    {state, blackboard} = perform_main_hand(state, target, blackboard, main_ready?, now)
    perform_offhand(state, target, blackboard, offhand_ready?, now)
  end

  defp perform_main_hand(state, target, blackboard, true, now) do
    speed = CombatLogic.attack_speed_ms(state)
    {send_melee_attack(state, target), Blackboard.put_next_at(blackboard, :next_attack_at, speed, now)}
  end

  defp perform_main_hand(state, _target, blackboard, false, _now), do: {state, blackboard}

  defp perform_offhand(state, target, blackboard, true, now) do
    speed = CombatLogic.offhand_attack_speed_ms(state)

    {send_offhand_attack(state, target), Blackboard.put_next_at(blackboard, :next_offhand_attack_at, speed, now)}
  end

  defp perform_offhand(state, _target, blackboard, false, _now), do: {state, blackboard}

  def wait_for_next_attack(state, %Blackboard{} = blackboard) do
    wait_for_next_attack(state, blackboard, Time.now())
  end

  def wait_for_next_attack(state, %Blackboard{} = blackboard, now) when is_integer(now) do
    delays = [Blackboard.delay_until(blackboard, :next_attack_at, now)]

    delays =
      if CombatLogic.offhand_damage_range(state) do
        [Blackboard.delay_until(blackboard, :next_offhand_attack_at, now) | delays]
      else
        delays
      end

    delay_ms = Enum.min(delays)

    status =
      if delay_ms > 0 do
        {:running, delay_ms}
      else
        :running
      end

    {status, state, blackboard}
  end

  def wait_for_next_attack(state, blackboard, _now), do: {:running, state, blackboard}

  defp maybe_start_melee_attack(state, target, %Blackboard{attack_started: true} = blackboard)
       when is_integer(target) do
    {state, blackboard}
  end

  defp maybe_start_melee_attack(%{object: %{guid: guid}} = state, target, %Blackboard{} = blackboard)
       when is_integer(target) do
    state = Event.enqueue(state, CombatLogic.attack_start(guid, target))
    {state, Map.put(blackboard, :attack_started, true)}
  end

  defp handle_out_of_range(%Character{} = state, blackboard, now) do
    blackboard = Blackboard.put_next_at(blackboard, :next_attack_at, @attack_retry_delay_ms, now)
    {Event.enqueue(state, Event.attack_not_in_range()), blackboard}
  end

  defp handle_out_of_range(state, blackboard, now) do
    blackboard = Blackboard.put_next_at(blackboard, :next_attack_at, @attack_retry_delay_ms, now)
    {state, blackboard}
  end

  defp send_melee_attack(state, target) when is_integer(target) do
    {state, queued_spell} = MeleeSpell.consume_next_swing(state)

    case queued_spell do
      %Spell{} = spell -> send_queued_spell_swing(state, spell, target)
      _no_queued_spell -> send_white_swing(state, target)
    end
  end

  defp send_white_swing(state, target) do
    attack = CombatLogic.finalize_attack(melee_attack_payload(state))

    state
    |> maybe_weapon_skill_up(target)
    |> queue_self_update()
    |> Event.enqueue(Event.deliver_attack(target, attack))
  end

  defp send_offhand_attack(state, target) do
    {min_damage, max_damage} = CombatLogic.offhand_damage_range(state)

    attack =
      state
      |> melee_attack_payload()
      |> Map.merge(%{min_damage: min_damage, max_damage: max_damage, offhand?: true})
      |> CombatLogic.finalize_attack()

    Event.enqueue(state, Event.deliver_attack(target, attack))
  end

  defp offhand_ready?(state, blackboard, now) do
    not is_nil(CombatLogic.offhand_damage_range(state)) and
      Blackboard.ready_for?(blackboard, :next_offhand_attack_at, now)
  end

  defp send_queued_spell_swing(state, %Spell{} = spell, target) do
    targets = queued_spell_targets(state, spell, target)

    state
    |> maybe_weapon_skill_up(target)
    |> Resources.spend_power(spell, Time.now())
    |> queue_self_update()
    |> queue_queued_spell_go(spell, target, targets)
    |> deliver_queued_spell(spell, targets)
  end

  defp queued_spell_targets(state, %Spell{} = spell, target) do
    case SpellTargetResolver.resolve(state, spell, Targets.unit(target)) do
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

      Event.enqueue(entity, Event.deliver_spell(target, context, spell))
    end)
  end

  defp melee_attack_payload(%{object: %{guid: guid}} = state) do
    {min_damage, max_damage} = CombatLogic.damage_range(state)

    %{
      caster: guid,
      min_damage: min_damage,
      max_damage: max_damage,
      threat_multiplier: Aura.percent_multiplier(state, :mod_threat, Spell.school_mask(:physical))
    }
    |> Map.merge(AttackTable.attacker_context(state))
    |> Map.merge(attack_skill_context(state))
  end

  defp attack_skill_context(%Character{unit: unit, player: player}) when is_struct(player) do
    default = Skills.max_for_level(unit.level || 1)
    %{caster_attack_skill: Skills.value(player.skills, weapon_skill_id(player), default)}
  end

  defp attack_skill_context(_state), do: %{}

  defp weapon_skill_id(player) do
    Skills.main_hand_weapon_skill(player, &ItemLoader.get_template/1)
  end

  defp maybe_weapon_skill_up(%Character{unit: unit, player: player} = state, target) when is_struct(player) do
    opts = [player_level: unit.level || 1, intellect: unit.intellect || 0]

    with false <- Guid.entity_type(target) == :player,
         {:gained, skills} <- Skills.combat_skill_up(player.skills, weapon_skill_id(player), opts) do
      Core.mark_broadcast_update(%{state | player: %{player | skills: skills}})
    else
      _no_gain -> state
    end
  end

  defp maybe_weapon_skill_up(state, _target), do: state

  defp queue_queued_spell_go(%{object: %{guid: guid}} = state, %{id: spell_id}, target, targets)
       when is_integer(guid) and is_integer(spell_id) and is_integer(target) and is_list(targets) do
    Event.enqueue(state, [
      Event.spell_cast_result(spell_id),
      Event.spell_go(guid, spell_id, targets, unit_target_raw(target))
    ])
  end

  defp queue_queued_spell_go(state, _queued_spell, _target, _targets), do: state

  defp unit_target_raw(target) do
    <<0x0002::little-size(16)>> <> BinaryUtils.pack_guid(target)
  end

  defp queue_self_update(%{internal: %Internal{broadcast_update?: true}} = state) do
    Event.enqueue(state, Event.object_update(:values))
  end

  defp queue_self_update(state), do: state

  defp combat_reach(%{unit: unit} = state, target) do
    CombatLogic.melee_reach(combat_reach_value(unit), target_combat_reach(state, target))
  end

  defp combat_reach_value(%Unit{combat_reach: combat_reach}) when is_number(combat_reach) and combat_reach > 0 do
    combat_reach
  end

  defp combat_reach_value(combat_reach) when is_number(combat_reach) and combat_reach > 0 do
    combat_reach
  end

  defp combat_reach_value(_unit), do: Unit.default_combat_reach()

  defp target_combat_reach(%{object: %{guid: guid}, unit: unit}, target) when is_integer(target) and target == guid do
    combat_reach_value(unit)
  end

  defp target_combat_reach(_state, target) when is_integer(target) do
    case Metadata.query(target, [:combat_reach]) do
      %{combat_reach: combat_reach} -> combat_reach_value(combat_reach)
      _ -> Unit.default_combat_reach()
    end
  end

  defp target_combat_reach(_state, _target), do: Unit.default_combat_reach()
end
