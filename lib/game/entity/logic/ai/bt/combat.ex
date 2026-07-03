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
  alias ThistleTea.Game.Entity.Logic.Combat, as: CombatLogic
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.MeleeSpell
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
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

  def in_combat?(%Character{internal: %Internal{in_combat: true}, unit: %Unit{target: target}}, %Blackboard{
        auto_attacking: true
      })
      when is_integer(target) and target > 0 do
    true
  end

  def in_combat?(%Character{}, _blackboard), do: false

  def in_combat?(%{internal: %Internal{in_combat: true}, unit: %Unit{target: target}}, _blackboard)
      when is_integer(target) and target > 0 do
    true
  end

  def in_combat?(_state, _blackboard), do: false

  def target_valid_same_map?(%{internal: %Internal{map: map}, unit: %Unit{target: target}}, _blackboard) do
    case World.target_position(target) do
      {^map, _x, _y, _z} -> true
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

    {state, blackboard} =
      cond do
        in_range and attack_ready ->
          attack_speed = CombatLogic.attack_speed_ms(state)
          state = send_melee_attack(state, target)
          {state, Blackboard.put_next_at(blackboard, :next_attack_at, attack_speed, now)}

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

  def wait_for_next_attack(state, %Blackboard{} = blackboard) do
    wait_for_next_attack(state, blackboard, Time.now())
  end

  def wait_for_next_attack(state, %Blackboard{} = blackboard, now) when is_integer(now) do
    delay_ms = Blackboard.delay_until(blackboard, :next_attack_at, now)

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
    {state, attack, queued_spell} = melee_attack_payload(state)
    attack = CombatLogic.finalize_attack(attack)

    state =
      state
      |> Resources.spend_power(queued_spell, Time.now())
      |> Resources.gain_outgoing_auto_attack_rage(attack)
      |> queue_self_update()
      |> queue_queued_spell_go(queued_spell, target)

    Event.enqueue(state, Event.deliver_attack(target, attack))
  end

  defp melee_attack_payload(%{object: %{guid: guid}} = state) do
    {state, queued_spell} = MeleeSpell.consume_next_swing(state)
    {min_damage, max_damage} = CombatLogic.damage_range(state)
    attack = %{caster: guid, min_damage: min_damage, max_damage: max_damage}
    {state, MeleeSpell.apply_to_attack(attack, queued_spell), queued_spell}
  end

  defp queue_queued_spell_go(%{object: %{guid: guid}} = state, %{id: spell_id}, target)
       when is_integer(guid) and is_integer(spell_id) and is_integer(target) do
    Event.enqueue(state, Event.spell_go(guid, spell_id, [target], unit_target_raw(target)))
  end

  defp queue_queued_spell_go(state, _queued_spell, _target), do: state

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
