defmodule ThistleTea.Game.Entity.Logic.AI.BT.Combat do
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.Combat, as: CombatLogic
  alias ThistleTea.Game.World

  @default_attack_range 2.0

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
      distance when is_number(distance) -> in_combat_distance?(state, distance)
      _ -> false
    end
  end

  def in_combat_range?(_state, _blackboard), do: false

  def melee_attack(%{unit: %Unit{target: target}} = state, %Blackboard{} = blackboard)
      when is_integer(target) and target > 0 do
    blackboard = maybe_start_melee_attack(state, target, blackboard)

    if in_combat_range?(state, blackboard) do
      attack_speed = CombatLogic.attack_speed_ms(state)

      blackboard =
        if Blackboard.ready_for?(blackboard, :next_attack_at) do
          send_melee_attack(state, target)
          Blackboard.put_next_at(blackboard, :next_attack_at, attack_speed)
        else
          blackboard
        end

      {:success, state, blackboard}
    else
      {:success, state, blackboard}
    end
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

  defp send_melee_attack(state, target) when is_integer(target) do
    attack = melee_attack_payload(state)

    case :ets.lookup(:entities, target) do
      [{^target, pid, _map, _x, _y, _z}] ->
        GenServer.cast(pid, {:receive_attack, attack})

      [] ->
        :ok
    end
  end

  defp melee_attack_payload(%{object: %{guid: guid}} = state) do
    {min_damage, max_damage} = CombatLogic.damage_range(state)
    %{caster: guid, min_damage: min_damage, max_damage: max_damage}
  end

  defp in_combat_distance?(%{unit: %Unit{combat_reach: combat_reach}}, distance)
       when is_number(distance) and is_number(combat_reach) do
    distance <= max(combat_reach, @default_attack_range)
  end

  defp in_combat_distance?(_state, distance) when is_number(distance) do
    distance <= @default_attack_range
  end
end
