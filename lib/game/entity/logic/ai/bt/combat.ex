defmodule ThistleTea.Game.Entity.Logic.AI.BT.Combat do
  alias ThistleTea.Character
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.Combat, as: CombatLogic
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata

  @attack_retry_delay_ms 100
  @default_attack_range 2.0
  @melee_range_offset 1.333

  def melee_sequence do
    BT.sequence([
      BT.condition(&in_combat?/2),
      BT.condition(&target_valid_same_map?/2),
      BT.action(&melee_attack/2),
      BT.action(&wait_for_next_attack/2)
    ])
  end

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
    blackboard = maybe_start_melee_attack(state, target, blackboard)
    in_range = in_combat_range?(state, blackboard)
    attack_ready = Blackboard.ready_for?(blackboard, :next_attack_at)

    {state, blackboard} =
      cond do
        in_range and attack_ready ->
          attack_speed = CombatLogic.attack_speed_ms(state)
          send_melee_attack(state, target)
          {state, Blackboard.put_next_at(blackboard, :next_attack_at, attack_speed)}

        in_range ->
          {state, blackboard}

        attack_ready ->
          handle_out_of_range(state, blackboard)

        true ->
          {state, blackboard}
      end

    {:success, state, blackboard}
  end

  def melee_attack(state, blackboard), do: {:success, state, blackboard}

  def wait_for_next_attack(state, %Blackboard{} = blackboard) do
    delay_ms = Blackboard.delay_until(blackboard, :next_attack_at)

    status =
      if delay_ms > 0 do
        {:running, delay_ms}
      else
        :running
      end

    {status, state, blackboard}
  end

  defp maybe_start_melee_attack(_state, target, %Blackboard{attack_started: true} = blackboard)
       when is_integer(target) do
    blackboard
  end

  defp maybe_start_melee_attack(%{object: %{guid: guid}} = state, target, %Blackboard{} = blackboard)
       when is_integer(target) do
    CombatLogic.attack_start(guid, target)
    |> World.broadcast_packet(state)

    blackboard
    |> Map.put(:attack_started, true)
    |> maybe_start_attack_timer(state)
  end

  defp maybe_start_attack_timer(%Blackboard{next_attack_at: 0} = blackboard, state) do
    attack_speed = CombatLogic.attack_speed_ms(state)
    Blackboard.put_next_at(blackboard, :next_attack_at, attack_speed)
  end

  defp maybe_start_attack_timer(blackboard, _state), do: blackboard

  defp handle_out_of_range(state, blackboard) do
    blackboard = Blackboard.put_next_at(blackboard, :next_attack_at, @attack_retry_delay_ms)
    {send_out_of_range(state), blackboard}
  end

  defp send_out_of_range(%Character{} = state) do
    Packet.build(<<>>, Opcodes.get(:SMSG_ATTACKSWING_NOTINRANGE))
    |> Network.send_packet()

    state
  end

  defp send_out_of_range(state), do: state

  defp send_melee_attack(state, target) when is_integer(target) do
    attack = melee_attack_payload(state)

    Entity.receive_attack(target, attack)
  end

  defp melee_attack_payload(%{object: %{guid: guid}} = state) do
    {min_damage, max_damage} = CombatLogic.damage_range(state)
    %{caster: guid, min_damage: min_damage, max_damage: max_damage}
  end

  defp combat_reach(%{unit: unit} = state, target) do
    reach = combat_reach_value(unit) + target_combat_reach(state, target) + @melee_range_offset
    max(reach, @default_attack_range)
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
