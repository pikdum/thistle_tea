defmodule ThistleTea.Game.Entity.Logic.Reactive do
  @moduledoc """
  Target-bound defensive windows for Revenge, Riposte, Mongoose Bite and
  Counterattack, plus the combo target for Overpower. Independent windows last
  four seconds and project their client aura-state bits on the owner's tick.
  Health aura states are re-derived from every health change.
  """
  import Bitwise, only: [|||: 2, &&&: 2, bnot: 1, <<<: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ReactiveWindow
  alias ThistleTea.Game.Entity.Logic.ComboPoints
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Wounded

  @defense_bit 1 <<< 0
  @hunter_parry_bit 1 <<< 6
  @healthless_20_bit 1 <<< 1
  @health_mask @healthless_20_bit ||| 0x700
  @reactive_mask @defense_bit ||| @hunter_parry_bit ||| @health_mask
  @window_ms 4_000
  @warrior 1
  @hunter 3
  @rogue 4
  @healthless_threshold 0.2

  def mark_defense(%Character{unit: %Unit{health: health, class: class}} = entity, target_guid, outcome, now)
      when is_number(health) and health > 0 and outcome in [:dodge, :parry, :block] and is_integer(now) do
    window = %ReactiveWindow{target_guid: target_guid, expires_at: now + @window_ms}

    entity
    |> open_window(window_kind(class, outcome), window, now)
    |> sync(now)
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

  defdelegate add_combo_points(entity, target_guid, amount), to: ComboPoints, as: :add

  def tick(entity, now) when is_integer(now) do
    entity
    |> expire_combo(now)
    |> expire_windows(now)
    |> sync(now)
  end

  def tick(entity, _now), do: entity

  def next_tick_at(%Character{internal: %Internal{} = internal}) do
    [expires_at(internal.defense_window), expires_at(internal.hunter_parry_window), internal.combo_expires_at]
    |> Enum.filter(&is_integer/1)
    |> Enum.min(fn -> nil end)
  end

  def next_tick_at(_entity), do: nil

  def sync(%{unit: %Unit{} = unit} = entity, now) do
    preserved = (unit.aura_state || 0) &&& bnot(@reactive_mask)

    put_aura_state(
      entity,
      preserved ||| healthless_bit(unit) ||| Wounded.aura_state(entity) ||| window_bits(entity, now)
    )
  end

  def sync(entity, _now), do: entity

  def sync_health(%{unit: %Unit{} = unit} = entity) do
    current = (unit.aura_state || 0) &&& bnot(@health_mask)
    put_aura_state(entity, current ||| healthless_bit(unit) ||| Wounded.aura_state(entity))
  end

  def sync_health(entity), do: entity

  def defense_active?(entity, now), do: active?(entity, :defense, now)

  def active?(entity, kind, now) do
    case window(entity, kind) do
      %ReactiveWindow{expires_at: expires_at} -> now < expires_at
      nil -> false
    end
  end

  def target_active?(entity, kind, target_guid, now) when is_integer(target_guid) and target_guid > 0 do
    case window(entity, kind) do
      %ReactiveWindow{target_guid: ^target_guid, expires_at: expires_at} -> now < expires_at
      _ -> false
    end
  end

  def target_active?(_entity, _kind, _target_guid, _now), do: false

  def clear(%Character{internal: %Internal{} = internal} = entity, now) do
    %{entity | internal: %{internal | defense_window: nil, hunter_parry_window: nil}}
    |> consume_combo(now)
    |> sync(now)
  end

  def clear(entity, _now), do: entity

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

  defdelegate consume_combo(entity), to: ComboPoints, as: :consume
  defdelegate consume_combo(entity, now), to: ComboPoints, as: :consume

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

  defp expire_windows(%Character{internal: %Internal{} = internal} = entity, now) do
    %{
      entity
      | internal: %{
          internal
          | defense_window: expire_window(internal.defense_window, now),
            hunter_parry_window: expire_window(internal.hunter_parry_window, now)
        }
    }
  end

  defp expire_windows(entity, _now), do: entity

  defp expire_window(%ReactiveWindow{expires_at: expires_at}, now) when now >= expires_at, do: nil
  defp expire_window(window, _now), do: window

  defp expires_at(%ReactiveWindow{expires_at: at}), do: at
  defp expires_at(nil), do: nil

  defp window_kind(@rogue, :dodge), do: nil
  defp window_kind(@hunter, :parry), do: :hunter_parry
  defp window_kind(_class, _outcome), do: :defense

  defp open_window(entity, :defense, window, _now) do
    %{entity | internal: %{entity.internal | defense_window: window}}
  end

  defp open_window(entity, :hunter_parry, window, now) do
    %{entity | internal: %{entity.internal | hunter_parry_window: window}}
    |> ComboPoints.add(window.target_guid, 1, now)
  end

  defp open_window(entity, nil, _window, _now), do: entity

  defp window(%Character{internal: %Internal{defense_window: window}}, :defense), do: window
  defp window(%Character{internal: %Internal{hunter_parry_window: window}}, :hunter_parry), do: window
  defp window(_entity, _kind), do: nil

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

  defp window_bits(entity, now) do
    defense = if active?(entity, :defense, now), do: @defense_bit, else: 0
    parry = if active?(entity, :hunter_parry, now), do: @hunter_parry_bit, else: 0
    defense ||| parry
  end
end
