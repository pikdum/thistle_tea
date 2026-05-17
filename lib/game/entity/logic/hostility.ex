defmodule ThistleTea.Game.Entity.Logic.Hostility do
  @moduledoc false

  import Bitwise, only: [&&&: 2, |||: 2]

  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.World.Metadata

  @unit_flag_non_attackable 0x00000002
  @unit_flag_not_selectable 0x02000000

  def hostile?(source, target) do
    with %FactionTemplate{} = source_template <- faction_template(source),
         %FactionTemplate{} = target_template <- faction_template(target) do
      FactionTemplate.hostile_to?(source_template, target_template)
    else
      _ -> false
    end
  end

  def friendly?(source, target) do
    with %FactionTemplate{} = source_template <- faction_template(source),
         %FactionTemplate{} = target_template <- faction_template(target) do
      FactionTemplate.friendly_to?(source_template, target_template)
    else
      _ -> false
    end
  end

  def neutral_to_all?(source) do
    source
    |> faction_template()
    |> FactionTemplate.neutral_to_all?()
  end

  def can_initiate_attack?(source) do
    alive?(source) and targetable?(source) and not neutral_to_all?(source)
  end

  def valid_hostile_target?(source, target) when is_integer(target) do
    target
    |> Metadata.query([:alive?, :faction_template, :unit_flags])
    |> then(&valid_hostile_target?(source, &1))
  end

  def valid_hostile_target?(source, target) do
    alive?(target) and targetable?(target) and hostile?(source, target)
  end

  def attackable?(source, target) do
    valid_hostile_target?(source, target)
  end

  def faction_template(%FactionTemplate{} = faction_template), do: faction_template
  def faction_template(%{faction_template: %FactionTemplate{} = faction_template}), do: faction_template

  def faction_template(%{object: %{guid: guid}}) when is_integer(guid) do
    case Metadata.query(guid, [:faction_template]) do
      %{faction_template: %FactionTemplate{} = faction_template} -> faction_template
      _ -> nil
    end
  end

  def faction_template(_source), do: nil

  defp alive?(%{alive?: false}), do: false
  defp alive?(%{unit: %Unit{}} = entity), do: not Core.dead?(entity)
  defp alive?(_target), do: true

  defp targetable?(%{unit_flags: flags}) when is_integer(flags), do: targetable_unit_flags?(flags)
  defp targetable?(%{unit: %Unit{flags: flags}}) when is_integer(flags), do: targetable_unit_flags?(flags)
  defp targetable?(_target), do: true

  defp targetable_unit_flags?(flags) when is_integer(flags) do
    (flags &&& (@unit_flag_non_attackable ||| @unit_flag_not_selectable)) == 0
  end
end
