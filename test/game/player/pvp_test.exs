defmodule ThistleTea.Game.Player.PvpTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Pvp, as: PvpData
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Player.Pvp
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  describe "arrive/2" do
    test "publishes, saves, and schedules a granted aura through its owner" do
      guid = System.unique_integer([:positive, :monotonic])

      character = %Character{
        id: guid,
        object: %Object{guid: guid},
        unit: %Unit{race: 1, class: 1, level: 60, health: 100, max_health: 100, power1: 0, max_power1: 0, auras: []},
        player: %Player{flags: 0},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: WorldRef.open(0), pvp: %PvpData{enforced?: true}}
      }

      on_exit(fn ->
        :ets.delete(CharacterStore, guid)
        Metadata.delete(guid)
        SpatialHash.remove(:players, guid)
      end)

      spell = %Spell{
        id: 2479,
        duration_ms: 30_000,
        aura_interrupt_flags: 0x1000,
        effects: [%Effect{type: :apply_aura, aura: :honorless_target, implicit_target_a: :caster}]
      }

      state = %State{guid: guid, character: character, ready: true}
      protected = Pvp.arrive(state, fn 2479 -> spell end)
      assert Aura.has_aura?(protected.character, :honorless_target)
      assert Aura.has_aura?(CharacterStore.get(guid), :honorless_target)
      assert Map.get(Metadata.get(guid).aura_stacks, 2479) == 1
      assert is_reference(protected.player_tick_ref)
      Process.cancel_timer(protected.player_tick_ref)
    end

    test "does not load protection while loading or outside enforced territory" do
      lookup = fn _id -> flunk("ineligible arrival loaded a spell") end
      loading = %State{}
      assert Pvp.arrive(loading, lookup) == loading

      safe = %State{ready: true, character: %Character{internal: %Internal{pvp: %PvpData{}}}}
      assert Pvp.arrive(safe, lookup) == safe
    end
  end
end
