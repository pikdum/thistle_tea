defmodule ThistleTea.Game.Player.Instances do
  @moduledoc "Instance admission feedback and safe login recovery when a saved location is unavailable."

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.HomeBind
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.System.Instance, as: InstanceSystem
  alias ThistleTea.Game.WorldRef

  def reject(:raid_group_required), do: Network.send_packet(%Message.SmsgRaidGroupOnly{})
  def reject(reason), do: Network.send_packet(%Message.SmsgTransferAborted{reason: reason})

  def restore(character, guid, opts \\ [])

  def restore(%Character{internal: %{world: %WorldRef{instance_id: id, map_id: map}}} = character, guid, opts)
      when is_integer(id) do
    enter = Keyword.get(opts, :enter, &InstanceSystem.enter/2)

    case enter.(map, guid) do
      {:ok, world} -> %{character | internal: %{character.internal | world: world}}
      {:error, _reason} -> return_home(character)
    end
  end

  def restore(%Character{} = character, _guid, _opts), do: character

  defp return_home(%Character{internal: %{home_bind: %HomeBind{} = home}} = character) do
    {x, y, z} = home.position
    internal = %{character.internal | world: WorldRef.open(home.map_id), area: home.area_id}
    movement = %{character.movement_block | position: {x, y, z, 0.0}}
    %{character | internal: internal, movement_block: movement}
  end
end
