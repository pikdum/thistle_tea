defmodule ThistleTea.Game.Entity.Logic.ChatStatusTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.ChatStatus, as: Status
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.ChatStatus
  alias ThistleTea.Game.Party.MemberStats

  setup [:character]

  describe "change/3" do
    test "updates messages, toggles empty requests and preserves unrelated flags", %{character: character} do
      afk = ChatStatus.change(character, :afk, "Tea break")
      assert afk.player.flags == 0x203
      assert afk.internal.chat_status == %Status{mode: :afk, message: "Tea break"}
      assert afk.internal.broadcast_update?
      assert ChatStatus.tag(afk) == 1

      updated = ChatStatus.change(afk, :afk, "Still away")
      assert updated.internal.chat_status.message == "Still away"
      assert updated.player.flags == afk.player.flags

      available = ChatStatus.change(updated, :afk, "")
      assert available.internal.chat_status == %Status{}
      assert available.player.flags == 0x201
      assert ChatStatus.tag(available) == 0
      assert ChatStatus.change(available, :afk, "").internal.chat_status.mode == :afk
    end

    test "switches mutually exclusive modes", %{character: character} do
      dnd = character |> ChatStatus.change(:afk, "Away") |> ChatStatus.change(:dnd, "Busy")
      assert dnd.player.flags == 0x205
      assert dnd.internal.chat_status == %Status{mode: :dnd, message: "Busy"}
      assert ChatStatus.tag(dnd) == 2
      assert ChatStatus.change(dnd, :afk, "Back soon").player.flags == 0x203
      assert ChatStatus.change(dnd, :dnd, "").player.flags == 0x201
    end

    test "rejects AFK requests during combat while allowing DND", %{character: character} do
      fighting = %{character | internal: %{character.internal | in_combat: true}}
      assert ChatStatus.change(fighting, :afk, "Away") == fighting
      assert ChatStatus.change(fighting, :dnd, "Busy").internal.chat_status.mode == :dnd
    end
  end

  describe "reset/1" do
    test "clears session status and stale projected bits on reconnect", %{character: character} do
      for mode <- [:afk, :dnd] do
        reset = character |> ChatStatus.change(mode, "Old reply") |> ChatStatus.reset()
        assert reset.internal.chat_status == %Status{}
        assert reset.player.flags == 0x201
        assert ChatStatus.reset(reset) == reset
      end

      stale = %{character | player: %{character.player | flags: 0x207}}
      assert ChatStatus.reset(stale).player.flags == 0x201
    end
  end

  describe "party status" do
    test "projects availability with death and online status", %{character: character} do
      character = %{
        character
        | object: %Object{guid: 10},
          unit: %Unit{health: 1, max_health: 100}
      }

      assert MemberStats.from_character(ChatStatus.change(character, :afk, "")).status == 0x41
      assert MemberStats.from_character(ChatStatus.change(character, :dnd, "")).status == 0x81
      dead = %{character | unit: %{character.unit | health: 0}}
      assert MemberStats.from_character(ChatStatus.change(dead, :dnd, "")).status == 0x85
    end
  end

  defp character(_context) do
    %{character: %Character{player: %Player{flags: 0x201}, internal: %Internal{}}}
  end
end
