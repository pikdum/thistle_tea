defmodule ThistleTea.Game.World.Entity.Player.EmotesTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.Player.Emotes
  alias ThistleTea.Game.World.Loader.Emote, as: Loader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Position
  alias ThistleTea.Game.World.Presence

  setup [:catalog, :player]

  describe "text/4" do
    test "retains dancing for observers and emits localized text without a one-shot", %{state: state} do
      updated = Emotes.text(state, 34, 0xFFFFFFFF, 0)
      character = EventSink.emit_pending(updated.character)
      assert character.unit.npc_emote_state == 10
      assert character.internal.broadcast_update?
      assert character.internal.events == []
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgTextEmote{text_emote: 34, name: ""}}}
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgEmote{}}}
    end

    test "names same-world targets and preserves NPC emote callbacks", %{state: state} do
      guid = Guid.runtime(:mob, 123)
      target = %{state.character | object: %Object{guid: guid}, internal: %Internal{name: "Café"}}
      {:ok, _} = Entity.register(guid)
      Metadata.put(guid, %{name: "Café"})
      Position.put(target, :mobs)

      on_exit(fn ->
        Metadata.delete(guid)
        Position.remove(target, :mobs)
      end)

      updated = Emotes.text(state, 101, 7, guid)
      EventSink.emit_pending(updated.character)
      assert_receive {:"$gen_cast", {:receive_emote, _, 101}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgTextEmote{name: "Café", emote: 7}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgEmote{emote: 3}}}

      elsewhere = %{target | internal: %{target.internal | world: WorldRef.instance(0, 999)}}
      Position.put(elsewhere, :mobs)
      updated = Emotes.text(state, 101, 7, guid)
      assert %Effects.TextEmote{name: ""} = List.last(updated.character.internal.events)
      refute_receive {:"$gen_cast", {:receive_emote, _, 101}}
    end

    test "ignores unknown text IDs, dead actors and requests before world entry", %{state: state} do
      assert Emotes.text(state, 9999, 0, 0) == state
      dead = %{state | character: %{state.character | unit: %{state.character.unit | health: 0}}}
      assert Emotes.text(dead, 101, 0, 0) == dead
      loading = %{state | ready: false}
      assert Emotes.text(loading, 101, 0, 0) == loading
    end
  end

  describe "stand/2" do
    test "acknowledges the owner's posture through the effect context", %{state: state} do
      character = state |> Emotes.stand(1) |> Map.fetch!(:character) |> EventSink.emit_pending()
      assert character.unit.stand_state == 1
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgStandstateUpdate{stand_state: 1}}}
      assert Emotes.stand(state, 7) == state
    end
  end

  describe "scripted emotes" do
    test "uses the same cached persistent and one-shot animation rules", %{state: state} do
      dancing = EventSink.emit(state.character, Effects.emote(10))
      assert dancing.unit.npc_emote_state == 10
      assert EventSink.emit(dancing, Effects.emote(0)).unit.npc_emote_state == 0
      EventSink.emit(state.character, Effects.emote(3))
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgEmote{emote: 3}}}
      assert EventSink.emit(state.character, Effects.emote(9999)) == state.character
    end
  end

  defp catalog(_context) do
    saved = :ets.tab2list(Loader)

    Loader.load([%{id: 0, spec_proc: 0}, %{id: 3, spec_proc: 0}, %{id: 10, spec_proc: 2}], [
      %{id: 34, emote: 10},
      %{id: 101, emote: 3}
    ])

    on_exit(fn ->
      :ets.delete_all_objects(Loader)
      :ets.insert(Loader, saved)
    end)
  end

  defp player(_context) do
    guid = Guid.from_low_guid(:player, System.unique_integer([:positive, :monotonic]))
    {:ok, _} = Entity.register(guid)

    character = %Character{
      object: %Object{guid: guid},
      player: %Player{flags: 0},
      unit: %Unit{health: 100, max_health: 100, auras: [], flags: 0, npc_emote_state: 0, stand_state: 0},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    Presence.enter(character, %{})
    on_exit(fn -> Presence.leave(character) end)
    %{state: %{ready: true, guid: guid, character: character}}
  end
end
