defmodule ThistleTea.Game.World.Inbound.Guild do
  @moduledoc "Handles decoded guild, charter, and tabard client messages."

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.Player.Guilds
  alias ThistleTea.Game.World.Entity.Player.Petitions

  def messages do
    [
      Message.CmsgGuildAccept,
      Message.CmsgGuildAddRank,
      Message.CmsgGuildCreate,
      Message.CmsgGuildDecline,
      Message.CmsgGuildDelRank,
      Message.CmsgGuildDemote,
      Message.CmsgGuildDisband,
      Message.CmsgGuildInfo,
      Message.CmsgGuildInfoText,
      Message.CmsgGuildInvite,
      Message.CmsgGuildLeader,
      Message.CmsgGuildLeave,
      Message.CmsgGuildMotd,
      Message.CmsgGuildPromote,
      Message.CmsgGuildQuery,
      Message.CmsgGuildRank,
      Message.CmsgGuildRemove,
      Message.CmsgGuildRoster,
      Message.CmsgGuildSetOfficerNote,
      Message.CmsgGuildSetPublicNote,
      Message.CmsgOfferPetition,
      Message.CmsgPetitionBuy,
      Message.CmsgPetitionQuery,
      Message.CmsgPetitionShowSignatures,
      Message.CmsgPetitionShowlist,
      Message.CmsgPetitionSign,
      Message.CmsgTurnInPetition,
      Message.MsgPetitionDeclineClient,
      Message.MsgPetitionRenameClient,
      Message.MsgSaveGuildEmblemClient,
      Message.MsgTabardvendorActivateClient
    ]
  end

  def handle(%Message.CmsgGuildAccept{}, state), do: Guilds.accept(state)

  def handle(%Message.CmsgGuildAddRank{name: name}, state), do: Guilds.add_rank(state, name)

  def handle(%Message.CmsgGuildCreate{name: name}, state), do: Guilds.create(state, name)

  def handle(%Message.CmsgGuildDecline{}, state), do: Guilds.decline(state)

  def handle(%Message.CmsgGuildDelRank{}, state), do: Guilds.delete_rank(state)

  def handle(%Message.CmsgGuildDemote{name: name}, state), do: Guilds.demote(state, name)

  def handle(%Message.CmsgGuildDisband{}, state), do: Guilds.disband(state)

  def handle(%Message.CmsgGuildInfo{}, state), do: Guilds.info(state)

  def handle(%Message.CmsgGuildInfoText{info: info}, state), do: Guilds.set_info(state, info)

  def handle(%Message.CmsgGuildInvite{name: name}, state), do: Guilds.invite(state, name)

  def handle(%Message.CmsgGuildLeader{name: name}, state), do: Guilds.set_leader(state, name)

  def handle(%Message.CmsgGuildLeave{}, state), do: Guilds.leave(state)

  def handle(%Message.CmsgGuildMotd{motd: motd}, state), do: Guilds.set_motd(state, motd)

  def handle(%Message.CmsgGuildPromote{name: name}, state), do: Guilds.promote(state, name)

  def handle(%Message.CmsgGuildQuery{guild_id: id}, state), do: Guilds.query(state, id)

  def handle(%Message.CmsgGuildRank{rank_id: rank_id, rights: rights, name: name}, state),
    do: Guilds.edit_rank(state, rank_id, rights, name)

  def handle(%Message.CmsgGuildRemove{name: name}, state), do: Guilds.remove(state, name)

  def handle(%Message.CmsgGuildRoster{}, state), do: Guilds.roster(state)

  def handle(%Message.CmsgGuildSetOfficerNote{name: name, note: note}, state),
    do: Guilds.set_note(state, name, :officer_note, note)

  def handle(%Message.CmsgGuildSetPublicNote{name: name, note: note}, state),
    do: Guilds.set_note(state, name, :public_note, note)

  def handle(%Message.CmsgOfferPetition{item_guid: item_guid, target_guid: target_guid}, state),
    do: Petitions.offer(state, item_guid, target_guid)

  def handle(%Message.CmsgPetitionBuy{npc_guid: guid, name: name}, state), do: Petitions.buy(state, guid, name)

  def handle(%Message.CmsgPetitionQuery{petition_id: id, item_guid: guid}, state), do: Petitions.query(state, id, guid)

  def handle(%Message.CmsgPetitionShowSignatures{item_guid: guid}, state), do: Petitions.show_signatures(state, guid)

  def handle(%Message.CmsgPetitionShowlist{npc_guid: guid}, state), do: Petitions.show_list(state, guid)

  def handle(%Message.CmsgPetitionSign{item_guid: guid}, state), do: Petitions.sign(state, guid)

  def handle(%Message.CmsgTurnInPetition{item_guid: guid}, state), do: Petitions.turn_in(state, guid)

  def handle(%Message.MsgPetitionDeclineClient{item_guid: guid}, state), do: Petitions.decline(state, guid)

  def handle(%Message.MsgPetitionRenameClient{item_guid: guid, name: name}, state),
    do: Petitions.rename(state, guid, name)

  def handle(%Message.MsgSaveGuildEmblemClient{vendor_guid: vendor_guid, emblem: emblem}, state),
    do: Guilds.save_emblem(state, vendor_guid, emblem)

  def handle(%Message.MsgTabardvendorActivateClient{vendor_guid: vendor_guid}, state),
    do: Guilds.activate_tabard(state, vendor_guid)
end
