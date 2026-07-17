defmodule ThistleTea.Game.Entity.Logic.Reactive do
  @moduledoc """
  Reactive combat state following vmangos reactives: the DEFENSE and
  HEALTHLESS_20 aura-state bits on the unit (which light Revenge and Execute
  on the client) and the hidden combo point marking a recently dodged target
  (which lights Overpower). Timed windows last 4 seconds and expire on the
  owner's tick; the health bit is re-derived from every health change.
  """
  import Bitwise, only: [|||: 2, &&&: 2, bnot: 1, <<<: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Core

  @defense_bit 1 <<< 0
  @healthless_20_bit 1 <<< 1
  @reactive_mask @defense_bit ||| @healthless_20_bit
  @window_ms 4_000
  @warrior 1
  @healthless_threshold 0.2

  def mark_defense(%Character{internal: %Internal{}} = entity, now) when is_integer(now) do
    mark_defense(entity, nil, nil, now)
  end

  def mark_defense(entity, _now), do: entity

  def mark_defense(%Character{internal: %Internal{} = internal} = entity, target_guid, outcome, now)
      when outcome in [:dodge, :parry, :block, nil] and is_integer(now) do
    internal = %{
      internal
      | defense_state_until: now + @window_ms,
        defense_target_guid: target_guid,
        defense_outcome: outcome
    }

    sync(%{entity | internal: internal}, now)
  end

  def mark_defense(entity, _target_guid, _outcome, _now), do: entity

  def mark_dodging_target(
        %Character{unit: %Unit{class: @warrior}, player: player, internal: %Internal{} = internal} = entity,
        victim_guid,
        now
      )
      when is_integer(victim_guid) and victim_guid > 0 and is_integer(now) do
    %{
      entity
      | player: %{player | field_combo_target: victim_guid, combo_points: 1},
        internal: %{internal | combo_expires_at: now + @window_ms, combo_target_guid: victim_guid}
    }
    |> Core.mark_broadcast_update()
  end

  def mark_dodging_target(entity, _victim_guid, _now), do: entity

  def add_combo_points(%Character{player: player, internal: %Internal{} = internal} = entity, target_guid, amount)
      when is_integer(target_guid) and target_guid > 0 and is_integer(amount) and amount > 0 do
    current = if internal.combo_target_guid == target_guid, do: player.combo_points || 0, else: 0

    %{
      entity
      | player: %{player | field_combo_target: target_guid, combo_points: min(current + amount, 5)},
        internal: %{internal | combo_expires_at: nil, combo_target_guid: target_guid}
    }
    |> Core.mark_broadcast_update()
  end

  def add_combo_points(entity, _target_guid, _amount), do: entity

  def tick(entity, now) when is_integer(now) do
    entity
    |> expire_combo(now)
    |> expire_defense(now)
    |> sync(now)
  end

  def tick(entity, _now), do: entity

  def sync(%{unit: %Unit{} = unit} = entity, now) do
    preserved = (unit.aura_state || 0) &&& bnot(@reactive_mask)
    put_aura_state(entity, preserved ||| healthless_bit(unit) ||| defense_bit(entity, now))
  end

  def sync(entity, _now), do: entity

  def sync_health(%{unit: %Unit{} = unit} = entity) do
    current = (unit.aura_state || 0) &&& bnot(@healthless_20_bit)
    put_aura_state(entity, current ||| healthless_bit(unit))
  end

  def sync_health(entity), do: entity

  def defense_active?(%Character{internal: %Internal{defense_state_until: until}}, now) do
    is_integer(until) and now < until
  end

  def defense_active?(_entity, _now), do: false

  def defense_target_active?(
        %Character{
          internal: %Internal{defense_state_until: until, defense_target_guid: target_guid, defense_outcome: outcome}
        },
        target_guid,
        outcome,
        now
      )
      when is_integer(target_guid) and is_integer(now) do
    is_integer(until) and now < until
  end

  def defense_target_active?(_entity, _target_guid, _outcome, _now), do: false

  def combo_active?(
        %Character{player: player, internal: %Internal{combo_expires_at: expires_at} = internal},
        target_guid,
        now
      ) do
    is_integer(player.combo_points) and player.combo_points > 0 and
      internal.combo_target_guid == target_guid and
      (is_nil(expires_at) or now < expires_at)
  end

  def combo_active?(_entity, _target_guid, _now), do: false

  def consume_combo(%Character{player: player, internal: %Internal{} = internal} = entity) do
    if is_integer(player.combo_points) and player.combo_points > 0 do
      %{
        entity
        | player: %{player | combo_points: 0},
          internal: %{internal | combo_expires_at: nil, combo_target_guid: nil}
      }
      |> Core.mark_broadcast_update()
    else
      entity
    end
  end

  def consume_combo(entity), do: entity

  def clear_combo_target(%Character{internal: %Internal{combo_target_guid: target_guid}} = entity, target_guid)
      when is_integer(target_guid) do
    consume_combo(entity)
  end

  def clear_combo_target(entity, _target_guid), do: entity

  defp expire_combo(%Character{internal: %Internal{combo_expires_at: expires_at}} = entity, now)
       when is_integer(expires_at) and now >= expires_at do
    consume_combo(entity)
  end

  defp expire_combo(entity, _now), do: entity

  defp expire_defense(%Character{internal: %Internal{defense_state_until: expires_at} = internal} = entity, now)
       when is_integer(expires_at) and now >= expires_at do
    %{
      entity
      | internal: %{
          internal
          | defense_state_until: nil,
            defense_target_guid: nil,
            defense_outcome: nil
        }
    }
  end

  defp expire_defense(entity, _now), do: entity

  defp put_aura_state(%{unit: %Unit{aura_state: current} = unit} = entity, bits) do
    if (current || 0) == bits do
      entity
    else
      %{entity | unit: %{unit | aura_state: bits}}
      |> Core.mark_broadcast_update()
    end
  end

  defp healthless_bit(%Unit{health: health, max_health: max_health})
       when is_integer(health) and is_integer(max_health) and max_health > 0 do
    if health > 0 and health < max_health * @healthless_threshold, do: @healthless_20_bit, else: 0
  end

  defp healthless_bit(_unit), do: 0

  defp defense_bit(entity, now) do
    if defense_active?(entity, now), do: @defense_bit, else: 0
  end
end
