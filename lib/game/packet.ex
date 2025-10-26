defmodule ThistleTea.Game.Packet do
  alias ThistleTea.Game.Message

  defstruct [
    :opcode,
    :size,
    :payload
  ]

  @l %{
       CMSG_AUTH_SESSION: Message.CmsgAuthSession,
       CMSG_CHAR_ENUM: Message.CmsgCharEnum,
       CMSG_CHAR_CREATE: Message.CmsgCharCreate,
       CMSG_MESSAGECHAT: Message.CmsgMessagechat,
       CMSG_JOIN_CHANNEL: Message.CmsgJoinChannel,
       CMSG_LEAVE_CHANNEL: Message.CmsgLeaveChannel,
       CMSG_TEXT_EMOTE: Message.CmsgTextEmote,
       CMSG_PING: Message.CmsgPing,
       CMSG_NAME_QUERY: Message.CmsgNameQuery,
       CMSG_ITEM_QUERY_SINGLE: Message.CmsgItemQuerySingle,
       CMSG_ITEM_NAME_QUERY: Message.CmsgItemNameQuery,
       CMSG_GAMEOBJECT_QUERY: Message.CmsgGameobjectQuery,
       CMSG_CREATURE_QUERY: Message.CmsgCreatureQuery,
       CMSG_WHO: Message.CmsgWho,
       CMSG_GOSSIP_HELLO: Message.CmsgGossipHello,
       CMSG_GOSSIP_SELECT_OPTION: Message.CmsgGossipSelectOption,
       CMSG_NPC_TEXT_QUERY: Message.CmsgNpcTextQuery,
       CMSG_ATTACKSWING: Message.CmsgAttackswing,
       CMSG_ATTACKSTOP: Message.CmsgAttackstop,
       CMSG_SETSHEATHED: Message.CmsgSetsheathed,
       CMSG_SET_SELECTION: Message.CmsgSetSelection,
       CMSG_STANDSTATECHANGE: Message.CmsgStandstatechange,
       CMSG_CAST_SPELL: Message.CmsgCastSpell,
       CMSG_PLAYER_LOGIN: Message.CmsgPlayerLogin,
       MSG_MOVE_WORLDPORT_ACK: Message.CmsgMoveWorldportAck,
       CMSG_LOGOUT_REQUEST: Message.CmsgLogoutRequest,
       CMSG_LOGOUT_CANCEL: Message.CmsgLogoutCancel,
       CMSG_CANCEL_CAST: Message.CmsgCancelCast
     }
     |> Map.new(fn {k, v} -> {ThistleTea.Opcodes.get(k), v} end)

  def build(payload, opcode) when is_number(opcode) and is_binary(payload) do
    %__MODULE__{
      opcode: opcode,
      size: byte_size(payload) + 2,
      payload: payload
    }
  end

  def to_message(%__MODULE__{opcode: opcode, payload: payload}) do
    module = Map.fetch!(@l, opcode)
    module.from_binary(payload)
  end

  def implemented?(opcode) when is_number(opcode) do
    Map.has_key?(@l, opcode)
  end
end
