defmodule ThistleTea.Game.Network.Message.CmsgCancelCast do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CANCEL_CAST

  alias ThistleTea.Game.Entity.Logic.AI.BT.Spell, as: SpellBT
  alias ThistleTea.Game.Network.Message

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

  def cancel_spell(state, reason \\ @spell_failed_interrupted)

  def cancel_spell(%{character: character} = state, reason) do
    case Map.get(character.internal, :casting) do
      nil ->
        state

      casting ->
        spell_id = Map.get(casting, :spell_id, 0)

        Network.send_packet(%Message.SmsgCastResult{
          spell: spell_id,
          result: 2,
          reason: reason,
          required_spell_focus: nil,
          area: nil,
          equipped_item_class: nil,
          equipped_item_subclass_mask: nil,
          equipped_item_inventory_type_mask: nil
        })

        Network.send_packet(%Message.SmsgSpellFailure{
          guid: state.guid,
          spell: spell_id,
          result: reason
        })

        %Message.SmsgSpellFailedOther{
          caster: state.guid,
          id: spell_id
        }
        |> World.broadcast_packet(character, exclude_self?: true)

        character = SpellBT.clear_cast(character)

        state
        |> Map.put(:character, character)
        |> Map.delete(:spell)
    end
  end

  def cancel_spell(state, _reason), do: state
end
