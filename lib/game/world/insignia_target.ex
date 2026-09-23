defmodule ThistleTea.Game.World.InsigniaTarget do
  @moduledoc "Resolves battleground bodies independently of the victim's current ghost position or connection."

  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.Logic.Insignia
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Visibility

  def info(caster, %Target{} = targets) do
    owner = Target.unit_guid(targets)

    with true <- is_integer(owner) and Guid.entity_type(owner) == :player,
         body when is_integer(body) <- body_guid(targets, owner),
         %{insignia: %{} = insignia} <- Metadata.get(body),
         position when is_tuple(position) <- World.position(body) do
      Map.merge(insignia, %{
        guid: owner,
        body_guid: body,
        position: position,
        visible?: Visibility.can_see?(%{guid: caster.object.guid, character: caster}, body),
        los?: World.line_of_sight?(caster, body)
      })
    else
      _invalid -> :unknown
    end
  end

  def actor(guid) do
    with %{insignia: %{team: team}, alive?: alive?} <- Metadata.get(guid),
         position when is_tuple(position) <- World.position(guid) do
      %{guid: guid, team: team, alive?: alive?, position: position}
    else
      _missing -> :unknown
    end
  end

  def validate_owner(character, looter_guid) do
    {x, y, z, _orientation} = character.movement_block.position

    body =
      Map.merge(Insignia.projection(character), %{
        position: {character.internal.world, x, y, z},
        visible?: true,
        los?: World.line_of_sight?(character, looter_guid)
      })

    Insignia.validate_actor(actor(looter_guid), body)
  end

  defp body_guid(%Target{selection: {:corpse, corpse, owner}}, owner) do
    if corpse == Corpse.guid_for(owner) and match?(%{owner: ^owner}, Metadata.get(corpse)), do: corpse
  end

  defp body_guid(_targets, owner) do
    case Metadata.get(owner) do
      %{ghost?: true} -> body_guid(Target.corpse(Corpse.guid_for(owner), owner), owner)
      %{alive?: false} -> owner
      _invalid -> nil
    end
  end
end
