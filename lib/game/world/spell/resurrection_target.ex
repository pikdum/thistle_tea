defmodule ThistleTea.Game.World.Spell.ResurrectionTarget do
  @moduledoc "Projects player bodies and eligible pet corpses for resurrection targeting."

  alias ThistleTea.Game.Core.Combat.Hostility
  alias ThistleTea.Game.Core.Entity.Corpse
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Pet.PetResurrection
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Reaction
  alias ThistleTea.Game.World.Visibility

  def info(caster, %Target{} = targets, spell \\ nil) do
    guid = Target.unit_guid(targets)

    with true <- is_integer(guid),
         %{} = metadata <-
           Metadata.query(guid, [
             :alive?,
             :ghost?,
             :faction_template,
             :unit_flags,
             :creature_type,
             :combat_reach,
             :owner_guid,
             :pet_kind
             | Reaction.actor_keys()
           ]),
         true <- eligible?(guid, metadata, spell),
         body when is_integer(body) <- body_guid(targets, guid, metadata),
         {world, _x, _y, _z} = position <- World.position(body),
         true <- world == caster.internal.world do
      source = Reaction.actor(caster)
      metadata = Reaction.actor(Map.put(metadata, :guid, guid))

      %{
        guid: guid,
        alive?: Map.get(metadata, :alive?, true),
        hostile?: Hostility.hostile?(source, metadata),
        friendly?: Hostility.friendly?(source, metadata),
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

  defp eligible?(guid, metadata, spell) do
    Guid.entity_type(guid) == :player or eligible_pet?(metadata, spell)
  end

  defp eligible_pet?(%{owner_guid: owner, pet_kind: kind}, %Spell{effects: effects}) when is_integer(owner) do
    PetResurrection.resurrectable_kind?(kind) and World.position(owner) != nil and
      Enum.any?(effects, &(&1.type == :resurrect_new))
  end

  defp eligible_pet?(_metadata, _spell), do: false

  defp body_guid(%Target{selection: {:corpse, corpse, guid}}, guid, %{ghost?: true}) do
    if corpse == Corpse.guid_for(guid) and Metadata.query(corpse, [:owner]) == %{owner: guid}, do: corpse
  end

  defp body_guid(%Target{selection: {:corpse, _, _}}, _guid, _metadata), do: nil

  defp body_guid(_targets, guid, %{ghost?: true} = metadata) do
    body_guid(Target.corpse(Corpse.guid_for(guid), guid), guid, metadata)
  end

  defp body_guid(_targets, guid, _metadata), do: guid
end
