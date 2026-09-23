defmodule ThistleTea.Game.World.ResurrectionTarget do
  @moduledoc "Projects the owned body for resurrection while the released player is elsewhere."

  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Visibility

  def info(caster, %Target{} = targets) do
    guid = Target.unit_guid(targets)

    with true <- is_integer(guid) and Guid.entity_type(guid) == :player,
         %{} = metadata <-
           Metadata.query(guid, [:alive?, :ghost?, :faction_template, :unit_flags, :creature_type, :combat_reach]),
         body when is_integer(body) <- body_guid(targets, guid, metadata),
         {world, _x, _y, _z} = position <- World.position(body),
         true <- world == caster.internal.world do
      metadata = Map.put(metadata, :guid, guid)

      %{
        guid: guid,
        alive?: Map.get(metadata, :alive?, true),
        hostile?: Hostility.hostile?(caster, metadata),
        friendly?: Hostility.friendly?(caster, metadata),
        visible?: Visibility.can_see?(%{guid: caster.object.guid, character: caster}, body),
        unit_flags: Map.get(metadata, :unit_flags, 0),
        creature_type: Map.get(metadata, :creature_type),
        combat_reach: Map.get(metadata, :combat_reach),
        position: position,
        los?: World.line_of_sight?(caster, body)
      }
    else
      _invalid -> :unknown
    end
  end

  defp body_guid(%Target{selection: {:corpse, corpse, guid}}, guid, %{ghost?: true}) do
    if corpse == Corpse.guid_for(guid) and Metadata.query(corpse, [:owner]) == %{owner: guid}, do: corpse
  end

  defp body_guid(%Target{selection: {:corpse, _, _}}, _guid, _metadata), do: nil

  defp body_guid(_targets, guid, %{ghost?: true} = metadata) do
    body_guid(Target.corpse(Corpse.guid_for(guid), guid), guid, metadata)
  end

  defp body_guid(_targets, guid, _metadata), do: guid
end
