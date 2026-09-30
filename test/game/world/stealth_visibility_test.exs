defmodule ThistleTea.Game.World.StealthVisibilityTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Aura.StealthDetection
  alias ThistleTea.Game.Core.Combat.Proximity.Announcement
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Inbound
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.Groups
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.World.Proximity
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.Visibility

  @moduletag :namigator_maps

  setup [:observers]

  describe "can_see?/2" do
    test "each observer uses its own position, facing and detection auras", %{state: state, target: target} do
      refute Visibility.can_see?(state, target)
      boosted = with_detection(state)
      assert Visibility.can_see?(boosted, target)

      turned = turn(boosted, :math.pi())
      refute Visibility.can_see?(turned, target)
      assert Visibility.can_see?(%{state | character: move(state.character, 12.0)}, target)
      refute Visibility.can_see?(state, target)
    end

    test "ownership and marks reveal only the appropriate observer", %{state: state, target: target} do
      Metadata.update(target, %{stalked_by: [state.guid]})
      assert Visibility.can_see?(state, target)
      Metadata.update(target, %{stalked_by: [state.guid + 1]})
      refute Visibility.can_see?(state, target)
      Metadata.update(target, %{owner_guid: state.guid})
      assert Visibility.can_see?(state, target)
    end

    test "client cancellation removes the bonus, publishes it and destroys the target", %{state: state, target: target} do
      spell = %Spell{
        id: 20_600,
        duration_ms: 20_000,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_stealth_detect, base_points: 50, misc_value: 0}]
      }

      {character, _} = Aura.apply_spell(state.character, state.guid, 10, spell, 0)
      Presence.sync(character, StealthDetection.target_metadata(character))
      state = %{state | character: character, tracked_entities: MapSet.new([target])}
      assert Visibility.can_see?(state, target)

      state = Inbound.handle(%Inbound.CmsgCancelAura{spell_id: spell.id}, state)
      refute Visibility.tracked?(state, target)
      assert Metadata.get(state.guid).stealth_detection_bonus == 0
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgDestroyObject{guid: ^target}, force: true}}
    end
  end

  describe "reveal_nearby/1" do
    test "re-checks hidden units near a viewer that moves or turns", %{state: state, target: target} do
      state = %{state | tracked_entities: MapSet.new([target])} |> Visibility.reveal_nearby()
      refute Visibility.tracked?(state, target)
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgDestroyObject{guid: ^target}, force: true}}

      state = %{state | character: move(state.character, 12.0)} |> Visibility.reveal_nearby()
      self_guid = state.guid
      assert_receive {:"$gen_cast", {:send_update_to, ^self_guid}}
    end

    test "turning away hides a unit only seen from the front", %{state: state, target: target} do
      state = %{state | tracked_entities: MapSet.new([target])} |> with_detection()
      assert Visibility.reveal_nearby(state) == state

      state = state |> turn(:math.pi()) |> Visibility.reveal_nearby()
      refute Visibility.tracked?(state, target)
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgDestroyObject{guid: ^target}, force: true}}
    end

    test "leaves units that are not listed as hidden alone", %{state: state, target: target, cell: cell} do
      Group.leave(Groups, Proximity.hidden_key(cell))
      state = %{state | tracked_entities: MapSet.new([target])} |> Visibility.reveal_nearby()
      assert Visibility.tracked?(state, target)
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgDestroyObject{}, force: true}}
    end
  end

  describe "hear/2" do
    test "a hidden announcement re-checks its announcer where it now stands", %{state: state, target: target} do
      state = %{state | character: move(state.character, 12.0)}
      self_guid = state.guid
      Visibility.hear(state, announcement(target, true))
      assert_receive {:"$gen_cast", {:send_update_to, ^self_guid}}

      SpatialHash.insert(:players, target, WorldRef.open(451), 16_343.2, 16_318.1, 69.44)
      state = %{state | tracked_entities: MapSet.new([target])}
      assert Visibility.hear(state, announcement(target, false)) == state
      state = Visibility.hear(state, announcement(target, true))
      refute Visibility.tracked?(state, target)
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgDestroyObject{guid: ^target}, force: true}}
    end

    test "the announcement that ends Vanish's immunity reveals a unit nobody moved", %{state: state, target: target} do
      state = with_detection(state)
      Metadata.update(target, %{undetectable_until: ThistleTea.Game.Core.Time.now() + 10_000})
      refute Visibility.can_see?(state, target)
      Metadata.update(target, %{undetectable_until: ThistleTea.Game.Core.Time.now()})
      Visibility.hear(state, announcement(target, true))
      self_guid = state.guid
      assert_receive {:"$gen_cast", {:send_update_to, ^self_guid}}
    end
  end

  defp observers(_context) do
    guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
    target = Guid.from_low_guid(:player, System.unique_integer([:positive]))
    world = WorldRef.open(451)

    character = %Character{
      object: %Object{guid: guid},
      unit: %Unit{level: 10, health: 100, max_health: 100, auras: []},
      internal: %Internal{world: world},
      movement_block: %MovementBlock{position: {16_303.2, 16_318.1, 69.44, 0.0}}
    }

    Presence.enter(character, StealthDetection.target_metadata(character))
    SpatialHash.insert(:players, target, world, 16_323.2, 16_318.1, 69.44)
    Metadata.put(target, %{stealthed?: true, stealth_skill: 50, level: 10, player?: true})
    Entity.register(target)
    cell = Visibility.current_cell(character)
    Group.join(Visibility.group_name(), Visibility.cell_key(cell), %{guid: target, type: :player})
    Group.join(Groups, Proximity.hidden_key(cell), %{guid: target})

    on_exit(fn ->
      Presence.leave(character)
      SpatialHash.remove(:players, target)
      Metadata.delete(target)
    end)

    %{
      state: %State{
        guid: guid,
        character: character,
        player_guids: [target],
        visibility_cells: MapSet.new([cell]),
        cell_activator: nil
      },
      target: target,
      cell: cell
    }
  end

  defp with_detection(state) do
    aura = %Holder{auras: [%Aura{type: :mod_stealth_detect, misc_value: 0, amount: 50}]}
    %{state | character: %{state.character | unit: %{state.character.unit | auras: [aura]}}}
  end

  defp move(character, distance) do
    {x, y, z, o} = character.movement_block.position
    character = %{character | movement_block: %{character.movement_block | position: {x + distance, y, z, o}}}
    Presence.relocate(character)
    character
  end

  defp turn(state, orientation) do
    character = state.character
    {x, y, z, _o} = character.movement_block.position
    %{state | character: %{character | movement_block: %{character.movement_block | position: {x, y, z, orientation}}}}
  end

  defp announcement(guid, hidden?) do
    %Announcement{
      guid: guid,
      world: WorldRef.open(451),
      position: {16_323.2, 16_318.1, 69.44},
      level: 10,
      hidden?: hidden?
    }
  end
end
