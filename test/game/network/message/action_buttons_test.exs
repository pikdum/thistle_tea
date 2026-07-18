defmodule ThistleTea.Game.Network.Message.ActionButtonsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Network.Message.CmsgSetActionbarToggles
  alias ThistleTea.Game.Network.Message.CmsgSetActionButton
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Message.SmsgActionButtons
  alias ThistleTea.Game.Network.Opcodes

  defp state_with_buttons(action_buttons) do
    %{character: %Character{internal: %Internal{action_buttons: action_buttons}}}
  end

  describe "SmsgActionButtons.to_binary/1" do
    test "encodes 120 buttons as packed little-endian u32s" do
      binary = SmsgActionButtons.to_binary(%SmsgActionButtons{buttons: %{}})

      assert byte_size(binary) == 480
      assert binary == :binary.copy(<<0::little-size(32)>>, 120)
    end

    test "places packed values at their button index" do
      spell = 6603
      item = 117 + Bitwise.bsl(0x80, 24)
      binary = SmsgActionButtons.to_binary(%SmsgActionButtons{buttons: %{0 => spell, 83 => item}})

      assert <<^spell::little-size(32), _::binary-size(328), ^item::little-size(32), _::binary>> = binary
    end
  end

  describe "CmsgSetActionButton.from_binary/1" do
    test "parses button index and packed data" do
      assert %CmsgSetActionButton{button: 5, packed_data: 0x80000075} =
               CmsgSetActionButton.from_binary(<<5::little-size(8), 0x80000075::little-size(32)>>)
    end
  end

  describe "CmsgSetActionButton.handle/2" do
    test "sets a button" do
      state =
        CmsgSetActionButton.handle(
          %CmsgSetActionButton{button: 3, packed_data: 6603},
          state_with_buttons(%{})
        )

      assert state.character.internal.action_buttons == %{3 => 6603}
    end

    test "clears a button when packed data is zero" do
      state =
        CmsgSetActionButton.handle(
          %CmsgSetActionButton{button: 3, packed_data: 0},
          state_with_buttons(%{3 => 6603, 4 => 78})
        )

      assert state.character.internal.action_buttons == %{4 => 78}
    end

    test "ignores out-of-range buttons" do
      state =
        CmsgSetActionButton.handle(
          %CmsgSetActionButton{button: 120, packed_data: 6603},
          state_with_buttons(%{})
        )

      assert state.character.internal.action_buttons == %{}
    end
  end

  describe "CmsgSetActionbarToggles.from_binary/1" do
    test "parses the action bar toggle mask" do
      assert %CmsgSetActionbarToggles{action_bar: 0x0F} =
               CmsgSetActionbarToggles.from_binary(<<0x0F>>)
    end

    test "is registered for dispatch" do
      assert Dispatch.implemented?(Opcodes.get(:CMSG_SET_ACTIONBAR_TOGGLES))
    end
  end

  describe "CmsgSetActionbarToggles.handle/2" do
    test "sets the action bar toggle mask" do
      state = %{character: %Character{player: %Player{}}}

      state =
        CmsgSetActionbarToggles.handle(
          %CmsgSetActionbarToggles{action_bar: 0x0F},
          state
        )

      assert state.character.player.action_bars == 0x0F
    end

    test "clears the action bar toggle mask" do
      state = %{character: %Character{player: %Player{action_bars: 0x0F}}}

      state =
        CmsgSetActionbarToggles.handle(
          %CmsgSetActionbarToggles{action_bar: 0},
          state
        )

      assert state.character.player.action_bars == 0
    end

    test "ignores toggles before character login" do
      state = %{character: nil}

      assert CmsgSetActionbarToggles.handle(
               %CmsgSetActionbarToggles{action_bar: 0x0F},
               state
             ) == state
    end
  end
end
