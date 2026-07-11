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
  @window_ms 4_000
  @warrior 1
  @healthless_threshold 0.2

  def mark_defense(%Character{internal: %Internal{} = internal} = entity, now) when is_integer(now) do
    sync(%{entity | internal: %{internal | defense_state_until: now + @window_ms}}, now)
  end

  def mark_defense(entity, _now), do: entity

  def mark_dodging_target(
        %Character{unit: %Unit{class: @warrior}, player: player, internal: %Internal{} = internal} = entity,
        victim_guid,
        now
      )
      when is_integer(victim_guid) and victim_guid > 0 and is_integer(now) do
    %{
      entity
      | player: %{player | field_combo_target: victim_guid, combo_points: 1},
        internal: %{internal | combo_expires_at: now + @window_ms}
    }
    |> Core.mark_broadcast_update()
  end

  def mark_dodging_target(entity, _victim_guid, _now), do: entity

  def add_combo_points(%Character{player: player, internal: %Internal{} = internal} = entity, target_guid, amount)
      when is_integer(target_guid) and target_guid > 0 and is_integer(amount) and amount > 0 do
    current = if player.field_combo_target == target_guid, do: player.combo_points || 0, else: 0

    %{
      entity
      | player: %{player | field_combo_target: target_guid, combo_points: min(current + amount, 5)},
        internal: %{internal | combo_expires_at: nil}
    }
    |> Core.mark_broadcast_update()
  end

  def add_combo_points(entity, _target_guid, _amount), do: entity

  def tick(entity, now) when is_integer(now) do
    entity
    |> expire_combo(now)
    |> sync(now)
  end

  def tick(entity, _now), do: entity

  def sync(%{unit: %Unit{} = unit} = entity, now) do
    put_aura_state(entity, healthless_bit(unit) ||| defense_bit(entity, now))
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

  def combo_active?(%Character{player: player, internal: %Internal{combo_expires_at: expires_at}}, target_guid, now) do
    is_integer(player.combo_points) and player.combo_points > 0 and
      player.field_combo_target == target_guid and
      (is_nil(expires_at) or now < expires_at)
  end

  def combo_active?(_entity, _target_guid, _now), do: false

  def consume_combo(%Character{player: player, internal: %Internal{} = internal} = entity) do
    if is_integer(player.combo_points) and player.combo_points > 0 do
      %{
        entity
        | player: %{player | field_combo_target: 0, combo_points: 0},
          internal: %{internal | combo_expires_at: nil}
      }
      |> Core.mark_broadcast_update()
    else
      entity
    end
  end

  def consume_combo(entity), do: entity

  defp expire_combo(%Character{internal: %Internal{combo_expires_at: expires_at}} = entity, now)
       when is_integer(expires_at) and now >= expires_at do
    consume_combo(entity)
  end

  defp expire_combo(entity, _now), do: entity

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
