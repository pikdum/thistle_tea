defmodule ThistleTea.Game.Entity.Logic.GameObjectActionsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.GameObject, as: ObjectComponent
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.ObjectAction
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.GameObjectActions, as: Actions

  setup [:door]

  describe "activate/2" do
    test "uses the template's fixed-point delay and ignores repeated use", %{door: door} do
      assert %ObjectAction{auto_close_ms: 3_000, default_state: 0} =
               Actions.configuration(%GameObjectTemplate{type: 1, data: [0, 0, 3 * 65_536 + 1]}, 0)

      opened = Actions.activate(door)
      assert opened.game_object.state == 0
      assert opened.game_object.flags == 0x21
      assert [%Effects.RestoreGameObject{revision: 1, state: 1, delay_ms: 3_000}] = opened.internal.events
      assert Actions.activate(opened) == opened
    end

    test "restores a door whose initial state was open", %{door: door} do
      door = %{
        door
        | game_object: %{door.game_object | state: 0},
          internal: %{door.internal | object_action: %ObjectAction{default_state: 0}}
      }

      closed = Actions.activate(door)
      assert closed.game_object.state == 1
      assert Actions.reset(closed).game_object.state == 0
    end
  end

  describe "apply/3" do
    test "preserves other flags through unlock, lock and inert transitions", %{door: door} do
      locked = Actions.apply(door, 7, 1)
      assert locked.game_object.flags == 0x22
      assert locked.internal.object_action.lock_override
      inert = Actions.apply(locked, 16, 1)
      refute Actions.usable?(inert)
      assert inert.game_object.flags == 0x32
      active = inert |> Actions.apply(6, 1) |> Actions.apply(17, 1)
      assert active.game_object.flags == 0x20
      assert active.internal.object_action.lock_override == false
      assert Actions.usable?(active)
    end

    test "destroy and rebuild retain the normal reset lifecycle", %{door: door} do
      destroyed = Actions.apply(door, 12, 1)
      assert destroyed.game_object.state == 2
      restored = Actions.apply(destroyed, 13, 1)
      assert restored.game_object.state == 1
      assert restored.game_object.flags == 0x20
      refute restored.internal.object_action.active?
    end

    test "distinguishes animation, use, removal and undefined actions", %{door: door} do
      assert [%Effects.GameObjectCustomAnimation{animation: 3}] = Actions.apply(door, 4, 1).internal.events
      assert [%Effects.ActivateGameObject{user_guid: 7}] = Actions.apply(door, 8, 7).internal.events
      assert [%Effects.RemoveSelf{respawn_delay_ms: nil}] = Actions.apply(door, 15, 1).internal.events
      assert Actions.apply(door, 11, 1) == door
      assert Actions.apply(door, 23, 1) == door
    end
  end

  describe "restore/3" do
    test "old timers cannot undo reset and reopen even with an identical state", %{door: door} do
      reopened = door |> Actions.activate() |> Actions.reset() |> Actions.activate()
      assert reopened.game_object.state == 0
      assert Actions.restore(reopened, 1, 1) == reopened
      assert Actions.restore(reopened, 3, 1).game_object.state == 1
    end

    test "scripted changes invalidate an outstanding use timer", %{door: door} do
      destroyed = door |> Actions.activate() |> Actions.operate(:destroy, 0)
      assert Actions.restore(destroyed, 1, 1) == destroyed
    end

    test "direct script states preserve flags and invalidate old timers", %{door: door} do
      changed = Actions.set_state(door, 2)
      assert changed.game_object.flags == door.game_object.flags
      refute changed.internal.object_action.active?
      assert Actions.restore(changed, 0, 1) == changed
    end
  end

  defp door(_context) do
    %{
      door: %GameObject{
        game_object: %ObjectComponent{type_id: 0, state: 1, flags: 0x20},
        internal: %Internal{object_action: %ObjectAction{auto_close_ms: 3_000}}
      }
    }
  end
end
