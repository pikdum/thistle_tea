defmodule ThistleTea.Game.Battleground.ResurrectionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Battleground.Lifecycle
  alias ThistleTea.Game.Battleground.Player
  alias ThistleTea.Game.Battleground.Resurrection
  alias ThistleTea.Game.Battleground.Roster
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player, as: PlayerComponent
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  setup [:waiting_ghost]

  describe "after_remove/2" do
    test "cancellation revokes an already dispatched wave and removes the roster entry", %{ghost: ghost} do
      assert Resurrection.ready?(ghost)
      {cancelled, effects} = Aura.cancel_spell(ghost, Resurrection.spell_id(), 100)
      refute Resurrection.ready?(cancelled)

      assert [%Effects.CancelBattlegroundResurrection{guid: 1, world: world}] =
               Enum.filter(effects, &match?(%Effects.CancelBattlegroundResurrection{}, &1))

      assert world == ghost.internal.world
      state = %State{guid: 1, character: cancelled}
      assert PlayerServer.handle_cast({:battleground_resurrect, {1.0, 2.0, 3.0, 0.0}}, state) == {:noreply, state}

      match = %{
        phase: :active,
        players: %{1 => %Player{guid: 1, name: "Ghost", team: :alliance, status: :inside}},
        resurrection_queue: MapSet.new(),
        next_resurrection_at: 0
      }

      match = Roster.queue_resurrection(match, 1).match
      assert MapSet.member?(match.resurrection_queue, 1)
      match = Roster.cancel_resurrection(match, 1).match
      assert Lifecycle.handle_timer(match, :resurrection_wave, 30_000, nil).effects == []
      assert Roster.cancel_resurrection(match, 1).match == match
    end

    test "resurrection clears waiting state and reapplication keeps it", %{ghost: ghost, spell: spell} do
      {refreshed, effects} = Aura.apply_spell(ghost, 1, 50, spell, 100)
      assert Resurrection.ready?(refreshed)
      refute Enum.any?(effects, &match?(%Effects.CancelBattlegroundResurrection{}, &1))

      {alive, effects} = Death.resurrect(refreshed, 1.0, 200)
      refute Resurrection.waiting?(alive)
      refute Resurrection.ready?(alive)
      assert Enum.any?(effects, &match?(%Effects.CancelBattlegroundResurrection{}, &1))
    end
  end

  defp waiting_ghost(_context) do
    spell = %Spell{
      id: 2584,
      duration_ms: -1,
      effects: [%Effect{index: 0, type: :apply_aura, aura: :dummy, base_points: 0}]
    }

    character = %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 1, max_health: 100, max_power1: 100, auras: []},
      player: %PlayerComponent{flags: 0x10},
      internal: %Internal{world: WorldRef.instance(529, 1)}
    }

    {ghost, _effects} = Aura.apply_spell(character, 1, 50, spell, 0)
    %{ghost: ghost, spell: spell}
  end
end
