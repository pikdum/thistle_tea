defmodule ThistleTea.Game.World.Inbound.Character do
  @moduledoc "Handles decoded character settings (action bars, selection, sheath, stand state, and reputation flags) client messages."

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity.Player.Emotes
  alias ThistleTea.Game.World.Entity.Player.Reputation

  require Logger

  @max_action_buttons 120

  def messages do
    [
      Message.CmsgSetActionButton,
      Message.CmsgSetActionbarToggles,
      Message.CmsgSetFactionAtwar,
      Message.CmsgSetFactionInactive,
      Message.CmsgSetSelection,
      Message.CmsgSetWatchedFaction,
      Message.CmsgSetsheathed,
      Message.CmsgStandstatechange
    ]
  end

  def handle(%Message.CmsgSetActionButton{button: button}, state) when button >= @max_action_buttons do
    state
  end

  def handle(%Message.CmsgSetActionButton{button: button, packed_data: packed_data}, state) do
    internal = state.character.internal

    action_buttons = internal.action_buttons || %{}

    action_buttons =
      case packed_data do
        0 -> Map.delete(action_buttons, button)
        _ -> Map.put(action_buttons, button, packed_data)
      end

    put_in(state.character.internal, %{internal | action_buttons: action_buttons})
  end

  def handle(
        %Message.CmsgSetActionbarToggles{action_bar: action_bar},
        %{character: %Character{player: %Player{} = player} = character} = state
      ) do
    %{state | character: %{character | player: %{player | action_bars: action_bar}}}
  end

  def handle(%Message.CmsgSetActionbarToggles{}, state), do: state

  def handle(%Message.CmsgSetFactionAtwar{}, %{character: %Character{internal: %{in_combat: true}}} = state), do: state

  def handle(%Message.CmsgSetFactionAtwar{index: index, flags: flags}, %{ready: true} = state) do
    Reputation.set_at_war(state, index, (flags &&& 0x02) != 0)
  end

  def handle(%Message.CmsgSetFactionAtwar{}, state), do: state

  def handle(%Message.CmsgSetFactionInactive{index: index, inactive: inactive}, %{ready: true} = state) do
    Reputation.set_inactive(state, index, inactive != 0)
  end

  def handle(%Message.CmsgSetFactionInactive{}, state), do: state

  def handle(%Message.CmsgSetSelection{guid: guid}, %{character: %{unit: %Unit{} = unit} = character} = state) do
    character = %{character | unit: %{unit | target: guid}} |> Entity.mark_broadcast_update()

    state
    |> then(&%{&1 | character: character, target: guid})
    |> Reputation.reveal_target(guid)
  end

  def handle(%Message.CmsgSetSelection{guid: guid}, state) do
    %{state | target: guid}
  end

  def handle(%Message.CmsgSetWatchedFaction{index: index}, %{ready: true} = state) do
    Reputation.set_watched(state, index)
  end

  def handle(%Message.CmsgSetWatchedFaction{}, state), do: state

  def handle(
        %Message.CmsgSetsheathed{sheath_state: sheath_state},
        %{character: %Character{unit: %Unit{} = unit} = character} = state
      ) do
    Logger.info("CMSG_SETSHEATHED")
    character = %{character | unit: %{unit | sheath_state: sheath_state}}

    # TODO: this doesn't show the unsheathing animation
    %UpdateObject{update_type: :values, object_type: :player}
    |> struct(Map.from_struct(character))
    |> World.broadcast_packet(state.character)

    %{state | character: character}
  end

  def handle(%Message.CmsgStandstatechange{animation_state: animation_state}, state),
    do: Emotes.stand(state, animation_state)
end
