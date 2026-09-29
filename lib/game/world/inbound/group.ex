defmodule ThistleTea.Game.World.Inbound.Group do
  @moduledoc "Handles decoded party, raid, and meeting stone client messages."

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.Player.Groups
  alias ThistleTea.Game.World.Entity.Player.MeetingStones

  def messages do
    [
      Message.CmsgGroupAccept,
      Message.CmsgGroupAssistantLeader,
      Message.CmsgGroupChangeSubGroup,
      Message.CmsgGroupDecline,
      Message.CmsgGroupDisband,
      Message.CmsgGroupInvite,
      Message.CmsgGroupRaidConvert,
      Message.CmsgGroupSetLeader,
      Message.CmsgGroupSwapSubGroup,
      Message.CmsgGroupUninvite,
      Message.CmsgGroupUninviteGuid,
      Message.CmsgLootMethod,
      Message.CmsgMeetingstoneInfo,
      Message.CmsgMeetingstoneJoin,
      Message.CmsgMeetingstoneLeave,
      Message.CmsgRequestPartyMemberStats,
      Message.MsgMinimapPing,
      Message.MsgRaidReadyCheck,
      Message.MsgRaidTargetUpdate,
      Message.MsgRandomRoll
    ]
  end

  def handle(%Message.CmsgGroupAccept{}, state), do: Groups.accept(state)

  def handle(%Message.CmsgGroupAssistantLeader{guid: guid, enabled?: enabled?}, state),
    do: Groups.set_assistant(state, guid, enabled?)

  def handle(%Message.CmsgGroupChangeSubGroup{name: name, subgroup: subgroup}, state),
    do: Groups.change_subgroup(state, name, subgroup)

  def handle(%Message.CmsgGroupDecline{}, state), do: Groups.decline(state)
  def handle(%Message.CmsgGroupDisband{}, state), do: Groups.leave(state)
  def handle(%Message.CmsgGroupInvite{name: name}, state), do: Groups.invite(state, name)
  def handle(%Message.CmsgGroupRaidConvert{}, state), do: Groups.convert_raid(state)
  def handle(%Message.CmsgGroupSetLeader{guid: guid}, state), do: Groups.set_leader(state, guid)

  def handle(%Message.CmsgGroupSwapSubGroup{first: first, second: second}, state),
    do: Groups.swap_subgroups(state, first, second)

  def handle(%Message.CmsgGroupUninvite{name: name}, state), do: Groups.uninvite_name(state, name)
  def handle(%Message.CmsgGroupUninviteGuid{guid: guid}, state), do: Groups.uninvite_guid(state, guid)

  def handle(%Message.CmsgLootMethod{} = message, state),
    do: Groups.set_loot(state, message.loot_method, message.master_looter, message.loot_threshold)

  def handle(%Message.CmsgMeetingstoneInfo{}, state), do: MeetingStones.request(state, :info)
  def handle(%Message.CmsgMeetingstoneJoin{guid: guid}, state), do: MeetingStones.join(state, guid)
  def handle(%Message.CmsgMeetingstoneLeave{}, state), do: MeetingStones.request(state, :leave)
  def handle(%Message.CmsgRequestPartyMemberStats{guid: guid}, state), do: Groups.request_member_stats(state, guid)
  def handle(%Message.MsgMinimapPing{x: x, y: y}, state), do: Groups.minimap_ping(state, x, y)
  def handle(%Message.MsgRaidReadyCheck{ready?: ready?}, state), do: Groups.ready_check(state, ready?)

  def handle(%Message.MsgRaidTargetUpdate{icon: icon, target: target}, state),
    do: Groups.target_icon(state, icon, target)

  def handle(%Message.MsgRandomRoll{minimum: minimum, maximum: maximum}, state),
    do: Groups.random_roll(state, minimum, maximum)
end
