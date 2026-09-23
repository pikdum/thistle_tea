defmodule ThistleTea.Game.Entity.Server.DeferredCooldownTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.GameObject, as: GameObjectComponent
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Ritual
  alias ThistleTea.Game.Entity.Data.Component.Internal.Summon
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Server.Player
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.World
  alias ThistleTea.Game.WorldRef

  setup [:owner]

  describe "handle_info/2" do
    test "projects exactly one client cooldown event", %{state: state, event: event, spell: spell} do
      EventSink.emit(state.character, event, Context.new(self()))
      assert_received ^event
      {:noreply, state} = Player.handle_info(event, state)
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgCooldownEvent{spell_id: 18_540}}}
      refute Cooldowns.pending(state.character, spell.id)
      assert {:noreply, ^state} = Player.handle_info(event, state)
      refute_received {:"$gen_cast", {:send_packet, %Message.SmsgCooldownEvent{}}}
    end
  end

  describe "game object lifecycle" do
    test "ordinary object removal starts its owner's deferred cooldown", %{state: state, event: event} do
      object = object(state.guid, event)
      {:ok, _pid} = World.start_entity(object)
      World.stop_entity(object.object.guid)
      assert_receive ^event
    end

    test "ritual completion starts the timer and later removal cannot restart it", %{
      state: state,
      event: event,
      spell: spell
    } do
      object = object(state.guid, event)

      ritual = %Ritual{
        owner_guid: state.guid,
        required_participants: 2,
        users: MapSet.new([state.guid]),
        persistent?: true
      }

      object = %{object | internal: %{object.internal | ritual: ritual}}
      {:ok, pid} = World.start_entity(object)
      GenServer.cast(pid, {:gameobject_use, state.guid + 1, 60})
      assert :sys.get_state(pid).internal.ritual.completed?
      assert_receive ^event
      {:noreply, restored} = Player.handle_info(event, state)
      deadline = Cooldowns.ready_at(restored.character, spell)
      World.stop_entity(object.object.guid)
      assert_receive ^event
      assert {:noreply, ^restored} = Player.handle_info(event, restored)
      assert Cooldowns.ready_at(restored.character, spell) == deadline
    end

    test "removing an unfinished ritual releases the pending lock", %{state: state, event: event, spell: spell} do
      object = object(state.guid, event)
      ritual = %Ritual{owner_guid: state.guid, required_participants: 2, users: MapSet.new([state.guid])}
      object = %{object | internal: %{object.internal | ritual: ritual}}
      {:ok, _pid} = World.start_entity(object)
      World.stop_entity(object.object.guid)
      canceled = %{event | cancel?: true}
      assert_receive ^canceled
      {:noreply, restored} = Player.handle_info(canceled, state)
      refute Cooldowns.on_cooldown?(restored.character, spell, 500)
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgClearCooldown{spell_id: 18_540}}}
    end
  end

  defp owner(_context) do
    guid = System.unique_integer([:positive]) + 70_000_000
    Entity.register(guid)
    spell = %Spell{id: 18_540, recovery_time_ms: 3_600_000, attributes: MapSet.new([:cooldown_on_event])}
    character = %Character{object: %Object{guid: guid}, unit: %Unit{health: 100, auras: []}, internal: %Internal{}}
    character = Cooldowns.start(character, spell, 100)
    event = %Effects.ActivateCooldown{target_guid: guid, spell_id: spell.id, started_at: 100}
    %{state: %State{guid: guid, ready: true, character: character}, event: event, spell: spell}
  end

  defp object(owner, event) do
    guid = Guid.from_low_guid(:game_object, 900_040, System.unique_integer([:positive]))
    on_exit(fn -> World.stop_entity(guid) end)

    %GameObject{
      object: %Object{guid: guid, entry: 900_040},
      game_object: %GameObjectComponent{state: 1},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: WorldRef.open(900_051), summon: %Summon{owner_guid: owner, cooldown_event: event}}
    }
  end
end
