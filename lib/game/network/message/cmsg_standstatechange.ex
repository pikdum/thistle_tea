defmodule ThistleTea.Game.Network.Message.CmsgStandstatechange do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_STANDSTATECHANGE

  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Time

  @seated_states [1, 2, 3]

  defstruct [:animation_state]

  @impl ClientMessage
  def handle(
        %__MODULE__{animation_state: animation_state},
        %{character: %Character{unit: %Unit{} = unit} = character} = state
      ) do
    character = %{character | unit: %{unit | stand_state: animation_state}}
    {character, auras_changed?} = maybe_interrupt_auras(character, animation_state)

    %UpdateObject{update_type: :values, object_type: :player}
    |> struct(Map.from_struct(character))
    |> World.broadcast_packet(character, include_self?: auras_changed?)

    # TODO: for some reason players are stuck sitting
    %{state | character: character}
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<animation_state::little-size(32)>> = payload

    %__MODULE__{
      animation_state: animation_state
    }
  end

  defp maybe_interrupt_auras(character, animation_state) when animation_state in @seated_states do
    {character, false}
  end

  defp maybe_interrupt_auras(character, _animation_state) do
    auras_before = character.unit.auras
    {character, events} = AuraLogic.remove_with_interrupt_flags(character, AuraLogic.interrupt_mask(:stand), Time.now())

    character =
      character
      |> Event.enqueue(events)
      |> EventSink.emit_pending()

    {character, character.unit.auras != auras_before}
  end
end
