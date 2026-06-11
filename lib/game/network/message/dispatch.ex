defmodule ThistleTea.Game.Network.Message.Dispatch do
  @moduledoc false
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet

  @movement_opcodes [
                      :MSG_MOVE_START_FORWARD,
                      :MSG_MOVE_START_BACKWARD,
                      :MSG_MOVE_STOP,
                      :MSG_MOVE_START_STRAFE_LEFT,
                      :MSG_MOVE_START_STRAFE_RIGHT,
                      :MSG_MOVE_STOP_STRAFE,
                      :MSG_MOVE_JUMP,
                      :MSG_MOVE_START_TURN_LEFT,
                      :MSG_MOVE_START_TURN_RIGHT,
                      :MSG_MOVE_STOP_TURN,
                      :MSG_MOVE_START_PITCH_UP,
                      :MSG_MOVE_START_PITCH_DOWN,
                      :MSG_MOVE_STOP_PITCH,
                      :MSG_MOVE_SET_RUN_MODE,
                      :MSG_MOVE_SET_WALK_MODE,
                      :MSG_MOVE_FALL_LAND,
                      :MSG_MOVE_START_SWIM,
                      :MSG_MOVE_STOP_SWIM,
                      :MSG_MOVE_SET_FACING,
                      :MSG_MOVE_SET_PITCH,
                      :MSG_MOVE_HEARTBEAT,
                      :CMSG_MOVE_FALL_RESET
                    ]
                    |> Map.new(fn opcode -> {opcode, Message.MsgMove} end)

  @messages %{
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
              CMSG_SET_ACTION_BUTTON: Message.CmsgSetActionButton,
              CMSG_STANDSTATECHANGE: Message.CmsgStandstatechange,
              CMSG_CAST_SPELL: Message.CmsgCastSpell,
              CMSG_PLAYER_LOGIN: Message.CmsgPlayerLogin,
              CMSG_SET_ACTIVE_MOVER: Message.CmsgSetActiveMover,
              MSG_MOVE_WORLDPORT_ACK: Message.CmsgMoveWorldportAck,
              CMSG_FORCE_RUN_SPEED_CHANGE_ACK: Message.CmsgForceRunSpeedChangeAck,
              CMSG_FORCE_MOVE_ROOT_ACK: Message.CmsgForceMoveRootAck,
              CMSG_FORCE_MOVE_UNROOT_ACK: Message.CmsgForceMoveUnrootAck,
              CMSG_LOGOUT_REQUEST: Message.CmsgLogoutRequest,
              CMSG_LOGOUT_CANCEL: Message.CmsgLogoutCancel,
              CMSG_CANCEL_CAST: Message.CmsgCancelCast,
              CMSG_CANCEL_CHANNELLING: Message.CmsgCancelChannelling,
              CMSG_CANCEL_AURA: Message.CmsgCancelAura,
              CMSG_AUTOEQUIP_ITEM: Message.CmsgAutoequipItem,
              CMSG_SWAP_INV_ITEM: Message.CmsgSwapInvItem,
              CMSG_SWAP_ITEM: Message.CmsgSwapItem,
              CMSG_SPLIT_ITEM: Message.CmsgSplitItem,
              CMSG_DESTROYITEM: Message.CmsgDestroyitem,
              CMSG_USE_ITEM: Message.CmsgUseItem,
              CMSG_LIST_INVENTORY: Message.CmsgListInventory,
              CMSG_BUY_ITEM: Message.CmsgBuyItem,
              CMSG_SELL_ITEM: Message.CmsgSellItem,
              CMSG_LOOT: Message.CmsgLoot,
              CMSG_AUTOSTORE_LOOT_ITEM: Message.CmsgAutostoreLootItem,
              CMSG_LOOT_MONEY: Message.CmsgLootMoney,
              CMSG_LOOT_RELEASE: Message.CmsgLootRelease,
              CMSG_QUESTGIVER_STATUS_QUERY: Message.CmsgQuestgiverStatusQuery,
              CMSG_QUEST_QUERY: Message.CmsgQuestQuery,
              CMSG_QUESTGIVER_HELLO: Message.CmsgQuestgiverHello,
              CMSG_QUESTGIVER_QUERY_QUEST: Message.CmsgQuestgiverQueryQuest,
              CMSG_QUESTGIVER_ACCEPT_QUEST: Message.CmsgQuestgiverAcceptQuest,
              CMSG_QUESTLOG_REMOVE_QUEST: Message.CmsgQuestlogRemoveQuest,
              CMSG_QUESTGIVER_COMPLETE_QUEST: Message.CmsgQuestgiverCompleteQuest,
              CMSG_QUESTGIVER_REQUEST_REWARD: Message.CmsgQuestgiverRequestReward,
              CMSG_QUESTGIVER_CHOOSE_REWARD: Message.CmsgQuestgiverChooseReward,
              CMSG_TRAINER_LIST: Message.CmsgTrainerList,
              CMSG_TRAINER_BUY_SPELL: Message.CmsgTrainerBuySpell,
              CMSG_REPOP_REQUEST: Message.CmsgRepopRequest,
              MSG_MOVE_TELEPORT_ACK: Message.CmsgMoveTeleportAck,
              MSG_CORPSE_QUERY: Message.MsgCorpseQuery,
              CMSG_RECLAIM_CORPSE: Message.CmsgReclaimCorpse,
              CMSG_SPIRIT_HEALER_ACTIVATE: Message.CmsgSpiritHealerActivate
            }
            |> Map.merge(@movement_opcodes)
            |> Map.new(fn {opcode, module} -> {Opcodes.get(opcode), module} end)

  def to_message(%Packet{opcode: opcode, payload: payload}) do
    module = Map.fetch!(@messages, opcode)

    payload
    |> module.from_binary()
    |> struct(opcode: opcode)
  end

  def implemented?(opcode) when is_number(opcode) do
    Map.has_key?(@messages, opcode)
  end
end
