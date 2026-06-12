defmodule ThistleTea.Game.Network.Message.CmsgCreatureQuery do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CREATURE_QUERY

  alias ThistleTea.Game.Entity.Data.CreatureTemplate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Loader.CreatureTemplate, as: CreatureTemplateLoader
  alias ThistleTea.Game.World.Metadata

  require Logger

  defstruct [:entry, :guid]

  @impl ClientMessage
  def handle(%__MODULE__{entry: entry, guid: guid}, state) do
    case CreatureTemplateLoader.get(entry) do
      %CreatureTemplate{} = ct ->
        Logger.info("CMSG_CREATURE_QUERY",
          target_name: ct.name
        )

        Network.send_packet(%Message.SmsgCreatureQueryResponse{
          creature_entry: entry,
          found: true,
          name1: ct.name,
          name2: "",
          name3: "",
          name4: "",
          sub_name: ct.sub_name,
          type_flags: ct.type_flags,
          creature_type: ct.creature_type,
          creature_family: ct.family,
          creature_rank: ct.rank,
          unknown0: 0,
          spell_data_id: 0,
          display_id: display_id(guid, ct),
          civilian: ct.civilian,
          racial_leader: ct.racial_leader
        })

      _ ->
        Network.send_packet(%Message.SmsgCreatureQueryResponse{creature_entry: entry, found: false})
    end

    state
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<entry::little-size(32), guid::little-size(64)>> = payload

    %__MODULE__{
      entry: entry,
      guid: guid
    }
  end

  defp display_id(guid, %CreatureTemplate{} = ct) do
    case Metadata.query(guid, [:display_id]) do
      %{display_id: display_id} when is_integer(display_id) and display_id > 0 -> display_id
      _ -> ct.display_id
    end
  end
end
