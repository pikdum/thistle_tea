defmodule ThistleTea.Game.Network.Message.CmsgCreatureQuery do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CREATURE_QUERY

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message

  require Logger

  defstruct [:entry, :guid]

  @impl ClientMessage
  def handle(%__MODULE__{entry: entry, guid: guid}, state) do
    low_guid = Guid.low_guid(guid)

    creature =
      Mangos.Repo.get_by(Mangos.Creature, guid: low_guid)
      |> Mangos.Repo.preload(:creature_template)

    ct = creature.creature_template

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
      type_flags: ct.creature_type_flags,
      creature_type: ct.creature_type,
      creature_family: ct.family,
      creature_rank: ct.rank,
      unknown0: 0,
      spell_data_id: 0,
      display_id: creature.modelid,
      civilian: ct.civilian,
      racial_leader: ct.racial_leader
    })

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
end
