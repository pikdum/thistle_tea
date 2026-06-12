defmodule ThistleTea.Game.Network.Message.CmsgCancelAura do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CANCEL_AURA

  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.AI.BT.Spell, as: SpellBT
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Time

  defstruct [:spell_id]

  @impl ClientMessage
  def handle(%__MODULE__{spell_id: spell_id}, %{character: %Character{} = character} = state) do
    auras_before = character.unit.auras

    character = maybe_clear_channel(character, spell_id)
    {character, events} = AuraLogic.cancel_spell(character, spell_id, Time.now())

    character =
      character
      |> Event.enqueue(events)
      |> EventSink.emit_pending()

    character =
      if character.unit.auras == auras_before do
        character
      else
        update = Core.update_object(character, :values)
        Network.send_packet(update)
        World.broadcast_packet(update, character, include_self?: false)
        %{character | internal: %{character.internal | broadcast_update?: false}}
      end

    %{state | character: character}
  end

  def handle(%__MODULE__{}, state), do: state

  @impl ClientMessage
  def from_binary(<<spell_id::little-size(32), _rest::binary>>) do
    %__MODULE__{spell_id: spell_id}
  end

  def from_binary(_payload), do: %__MODULE__{}

  defp maybe_clear_channel(
         %Character{internal: %{casting: %Cast{spell: %Spell{id: spell_id} = spell}}} = character,
         spell_id
       ) do
    if Spell.attribute?(spell, :channeled) do
      SpellBT.clear_cast(character)
    else
      character
    end
  end

  defp maybe_clear_channel(character, _spell_id), do: character
end
