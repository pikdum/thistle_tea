defmodule ThistleTea.Game.World.Visibility.GameObjects do
  @moduledoc "Observer-specific visibility for spawned objects and hostile stealthed traps."

  alias ThistleTea.Game.Core.Aura.Invisibility
  alias ThistleTea.Game.Core.Combat.Hostility
  alias ThistleTea.Game.Core.Entity.Character

  def can_see?(_character, _guid, %{go_spawned?: false}), do: false

  def can_see?(%Character{} = character, guid, %{go_trap_stealthed?: true} = metadata) do
    not hostile?(character, guid, metadata) or
      Map.has_key?(Invisibility.metadata(character).invisibility_detection, 3)
  end

  def can_see?(_character, _guid, _metadata), do: true

  defp hostile?(character, _guid, %{owner_guid: owner}) when is_integer(owner) and owner > 0,
    do: Hostility.hostile?(owner, character)

  defp hostile?(_character, _guid, %{faction_template_id: nil}), do: true
  defp hostile?(character, guid, _metadata), do: Hostility.hostile?(guid, character)
end
