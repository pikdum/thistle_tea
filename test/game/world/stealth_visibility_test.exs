defmodule ThistleTea.Game.World.StealthVisibilityTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.StealthDetection
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.Visibility
  alias ThistleTea.Game.WorldRef

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

      {character, _} = ThistleTea.Game.Entity.Logic.Aura.apply_spell(state.character, state.guid, 10, spell, 0)
      Presence.sync(character, StealthDetection.target_metadata(character))
      state = %{state | character: character, tracked_entities: MapSet.new([target])}
      assert Visibility.can_see?(state, target)

      state = Message.CmsgCancelAura.handle(%Message.CmsgCancelAura{spell_id: spell.id}, state)
      refute Visibility.tracked?(state, target)
      assert Metadata.get(state.guid).stealth_detection_bonus == 0
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgDestroyObject{guid: ^target}, force: true}}
    end
  end

  describe "stealth_detection_tick/2" do
    test "hides and recreates targets when either side moves within a cell", %{state: state, target: target} do
      state = %{state | tracked_entities: MapSet.new([target])}
      state = tick(state)
      refute Visibility.tracked?(state, target)
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgDestroyObject{guid: ^target}, force: true}}

      state = %{state | character: move(state.character, 12.0)}
      state = tick(state)
      self_guid = state.guid
      assert_receive {:"$gen_cast", {:send_update_to, ^self_guid}}

      SpatialHash.insert(:players, target, WorldRef.open(451), 16_343.2, 16_318.1, 69.44)
      state = %{state | tracked_entities: MapSet.new([target])} |> tick()
      refute Visibility.tracked?(state, target)
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgDestroyObject{guid: ^target}, force: true}}
      Visibility.leave_player(state)
    end

    test "detects again when Vanish immunity ends without movement", %{state: state, target: target} do
      state = with_detection(state)
      Metadata.update(target, %{undetectable_until: ThistleTea.Game.Time.now() + 10_000})
      refute Visibility.can_see?(state, target)
      Metadata.update(target, %{undetectable_until: ThistleTea.Game.Time.now()})
      state = tick(state)
      self_guid = state.guid
      assert_receive {:"$gen_cast", {:send_update_to, ^self_guid}}
      Visibility.leave_player(state)
    end

    test "ignores stale timers after leaving and reentering", %{state: state} do
      state = Visibility.schedule_stealth_detection(state)
      old_ref = state.stealth_detection_ref
      left = Visibility.leave_player(state)
      assert left.stealth_detection_ref == nil
      assert Process.read_timer(old_ref) == false
      assert Visibility.stealth_detection_tick(left, old_ref) == left

      entered = Visibility.enter_player(left)
      assert entered.stealth_detection_ref != old_ref
      assert Visibility.stealth_detection_tick(entered, old_ref) == entered
      Visibility.leave_player(entered)
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
      target: target
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

  defp tick(state) do
    if is_reference(state.stealth_detection_ref), do: Process.cancel_timer(state.stealth_detection_ref)
    ref = make_ref()
    Visibility.stealth_detection_tick(%{state | stealth_detection_ref: ref}, ref)
  end
end
