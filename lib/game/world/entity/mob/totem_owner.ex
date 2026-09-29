defmodule ThistleTea.Game.World.Entity.Mob.TotemOwner do
  @moduledoc "Removes a departing totem's area auras and notifies its owning entity."

  alias ThistleTea.Game.Core.Entity.Commands
  alias ThistleTea.Game.Core.Entity.Component.Internal.Totem
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Party
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  def stopped(%Mob{internal: %{totem: %Totem{owner_guid: owner}}} = totem) do
    recipients = recipients(totem, owner)

    for spell <- Map.values(totem.internal.spellbook || %{}),
        Enum.any?(spell.effects, &(&1.type == :apply_area_aura)),
        guid <- recipients do
      Entity.remove_aura(guid, spell.id, totem.object.guid)
    end

    case Entity.pid(owner) do
      pid when is_pid(pid) -> send(pid, %Commands.TotemStopped{guid: totem.object.guid})
      _missing -> :ok
    end
  end

  def stopped(_entity), do: :ok

  defp recipients(totem, owner) do
    nearby = World.nearby_players(totem, 120) ++ World.nearby_mobs(totem, 120)

    party =
      case PartySystem.group_of(owner) do
        nil -> []
        group -> Enum.map(Party.subgroup_members(group, owner), & &1.guid)
      end

    Enum.uniq([owner | party ++ Enum.map(nearby, &elem(&1, 0))])
  end
end
