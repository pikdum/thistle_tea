defmodule ThistleTea.Game.Entity.Logic.Hostility do
  @moduledoc false

  import Bitwise, only: [&&&: 2, |||: 2]

  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Guid
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
    |> target_metadata()
    |> then(&valid_hostile_target?(source, &1))
  end

  def valid_hostile_target?(source, target) do
    alive?(target) and targetable?(target) and hostile?(source, target)
  end

  def valid_attack_target?(source, target) when is_integer(target) do
    target
    |> target_metadata()
    |> then(&valid_attack_target?(source, &1))
  end

  def valid_attack_target?(source, target) do
    alive?(target) and targetable?(target) and attack_reaction_allows?(source, target)
  end

  def attackable?(source, target) do
    valid_attack_target?(source, target)
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

  defp target_metadata(guid) when is_integer(guid) do
    case Metadata.query(guid, [:alive?, :faction_template, :faction_can_have_reputation?, :unit_flags]) do
      nil -> %{guid: guid}
      metadata -> Map.put(metadata, :guid, guid)
    end
  end

  defp attack_reaction_allows?(source, target) do
    cond do
      hostile?(source, target) or hostile?(target, source) -> true
      friendly?(source, target) or friendly?(target, source) -> false
      player_involved?(source, target) -> neutral_player_creature_attackable?(source, target)
      true -> false
    end
  end

  defp player_involved?(source, target) do
    player_controlled?(source) != player_controlled?(target)
  end

  defp neutral_player_creature_attackable?(source, target) do
    source
    |> non_player_target(target)
    |> faction_can_have_reputation?()
    |> Kernel.not()
  end

  defp non_player_target(source, target) do
    if player_controlled?(source), do: target, else: source
  end

  defp player_controlled?(entity) do
    entity
    |> guid()
    |> Guid.entity_type()
    |> Kernel.==(:player)
  end

  defp guid(%{guid: guid}) when is_integer(guid), do: guid
  defp guid(%{object: %{guid: guid}}) when is_integer(guid), do: guid
  defp guid(_entity), do: nil

  defp faction_can_have_reputation?(%{faction_can_have_reputation?: can_have_reputation?})
       when is_boolean(can_have_reputation?) do
    can_have_reputation?
  end

  defp faction_can_have_reputation?(_entity), do: false

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
