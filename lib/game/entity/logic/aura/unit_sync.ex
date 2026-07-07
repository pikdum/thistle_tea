defmodule ThistleTea.Game.Entity.Logic.Aura.UnitSync do
  @moduledoc """
  Derives the unit's aura-driven fields from its holders: recomputed stats,
  transform display id, the packed aura id/flag/level blocks the client
  renders, and display-slot allocation (positive 0-31, negative 32-47).
  """
  import Bitwise, only: [|||: 2, <<<: 2, &&&: 2, bnot: 1]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Spell

  @max_slots 48
  @max_positive_slots 32

  @aflag_cancelable 0x01
  @aflag_eff_index_2 0x02
  @aflag_eff_index_1 0x04
  @aflag_eff_index_0 0x08

  @unit_flag_disarmed 0x00200000

  def sync_unit(%Unit{} = unit) do
    unit
    |> Stats.recompute()
    |> sync_transform()
    |> sync_shapeshift()
    |> sync_disarm()
    |> sync_aura_fields()
  end

  def next_free_slot(holders, negative?) do
    used = MapSet.new(holders, & &1.slot)
    range = if negative?, do: @max_positive_slots..(@max_slots - 1), else: 0..(@max_positive_slots - 1)
    Enum.find(range, &(not MapSet.member?(used, &1)))
  end

  defp sync_transform(%Unit{auras: holders} = unit) when is_list(holders) do
    transform =
      holders
      |> Enum.flat_map(fn %Holder{auras: auras} -> auras end)
      |> Enum.find(fn %Aura{type: type, misc_value: misc} -> type == :transform and is_integer(misc) and misc > 0 end)

    case {transform, unit.native_display_id} do
      {%Aura{misc_value: display_id}, _native} -> %{unit | display_id: display_id}
      {nil, native} when is_integer(native) and native > 0 -> %{unit | display_id: native}
      _ -> unit
    end
  end

  defp sync_transform(unit), do: unit

  defp sync_shapeshift(%Unit{auras: holders} = unit) when is_list(holders) do
    form =
      holders
      |> Enum.flat_map(fn %Holder{auras: auras} -> auras end)
      |> Enum.find_value(0, fn
        %Aura{type: :mod_shapeshift, misc_value: misc} when is_integer(misc) and misc > 0 -> misc
        _ -> nil
      end)

    %{unit | shapeshift_form: form}
  end

  defp sync_shapeshift(unit), do: unit

  defp sync_disarm(%Unit{auras: holders} = unit) when is_list(holders) do
    disarmed? = Enum.any?(holders, &Holder.has_aura_type?(&1, :mod_disarm))
    flags = unit.flags || 0

    flags =
      if disarmed? do
        flags ||| @unit_flag_disarmed
      else
        flags &&& bnot(@unit_flag_disarmed)
      end

    %{unit | flags: flags}
  end

  defp sync_disarm(unit), do: unit

  defp sync_aura_fields(%Unit{auras: holders} = unit) when is_list(holders) and holders != [] do
    %{
      unit
      | aura: pack_aura_ids(holders),
        aura_flags: pack_aura_flags(holders),
        aura_levels: pack_aura_levels(holders),
        aura_applications: pack_aura_applications(holders)
    }
  end

  defp sync_aura_fields(%Unit{} = unit) do
    %{
      unit
      | aura: 0,
        aura_flags: <<0::size(@max_slots * 4)>>,
        aura_levels: <<0::size(@max_slots * 8)>>,
        aura_applications: <<0::size(@max_slots * 8)>>
    }
  end

  defp pack_aura_ids(holders) do
    Enum.reduce(holders, 0, fn %Holder{slot: slot, spell: %Spell{id: id}}, acc ->
      acc ||| id <<< (32 * slot)
    end)
  end

  defp pack_aura_flags(holders) do
    int =
      Enum.reduce(holders, 0, fn %Holder{} = holder, acc ->
        acc ||| holder_flag_bits(holder) <<< (4 * holder.slot)
      end)

    <<int::little-size(24 * 8)>>
  end

  defp holder_flag_bits(%Holder{auras: auras, negative?: negative?}) do
    base = if negative?, do: 0, else: @aflag_cancelable

    Enum.reduce(auras, base, fn %Aura{index: index}, acc ->
      acc ||| aura_index_bit(index)
    end)
  end

  defp aura_index_bit(0), do: @aflag_eff_index_0
  defp aura_index_bit(1), do: @aflag_eff_index_1
  defp aura_index_bit(2), do: @aflag_eff_index_2
  defp aura_index_bit(_), do: 0

  defp pack_aura_levels(holders) do
    for slot <- 0..(@max_slots - 1), into: <<>> do
      level = level_for_slot(holders, slot)
      <<level::8>>
    end
  end

  defp pack_aura_applications(holders) do
    for slot <- 0..(@max_slots - 1), into: <<>> do
      apps =
        case Enum.find(holders, &(&1.slot == slot)) do
          %Holder{stacks: stacks} when is_integer(stacks) and stacks > 1 -> stacks - 1
          _ -> 0
        end

      <<apps::8>>
    end
  end

  defp level_for_slot(holders, slot) do
    case Enum.find(holders, &(&1.slot == slot)) do
      %Holder{caster_level: level} when is_integer(level) -> level
      _ -> 0
    end
  end
end
