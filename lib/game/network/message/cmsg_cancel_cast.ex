defmodule ThistleTea.Game.Network.Message.CmsgCancelCast do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CANCEL_CAST

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Util

  require Logger

  @spell_failed_interrupted 0x23

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state) do
    Logger.info("CMSG_CANCEL_CAST")
    cancel_spell(state)
  end

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end

  def cancel_spell(state, reason \\ @spell_failed_interrupted) do
    case Map.get(state, :spell) do
      nil ->
        state

      spell ->
        Process.cancel_timer(spell.cast_timer)

        Util.send_packet(%Message.SmsgCastResult{
          spell: spell.spell_id,
          result: 2,
          reason: reason,
          required_spell_focus: nil,
          area: nil,
          equipped_item_class: nil,
          equipped_item_subclass_mask: nil,
          equipped_item_inventory_type_mask: nil
        })

        Util.send_packet(%Message.SmsgSpellFailure{
          guid: state.guid,
          spell: spell.spell_id,
          result: reason
        })

        packet =
          Message.to_packet(%Message.SmsgSpellFailedOther{
            caster: state.guid,
            id: spell.spell_id
          })

        for pid <- Map.get(state, :player_pids, []) do
          if pid != self() do
            GenServer.cast(pid, {:send_packet, packet.opcode, packet.payload})
          end
        end

        Map.delete(state, :spell)
    end
  end
end
