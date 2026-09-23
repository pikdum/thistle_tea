defmodule ThistleTea.Game.Entity.Logic.ResurrectionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ResurrectionOffer
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Resurrection
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.WorldRef

  setup [:dead_character]

  describe "offer/5" do
    test "Rebirth bypasses the client corpse countdown", %{character: character, context: context} do
      spell = %Spell{id: 20_484, attributes: MapSet.new([:no_resurrection_timer])}
      assert {_, [%{delayed?: false}]} = Resurrection.offer(character, context, spell, 70, 135)
      assert {_, [%{delayed?: true}]} = Resurrection.offer(character, context, %Spell{id: 2006}, 70, 135)
    end

    test "keeps the first offer and its cast position", %{character: character, context: context} do
      {offered, [_request]} = Resurrection.offer(character, context, %Spell{id: 2006}, 70, 135)
      assert offered.internal.pending_resurrect.position == context.caster_position
      assert offered.internal.pending_resurrect.orientation == 1.5
      assert {^offered, []} = Resurrection.offer(offered, %{context | caster_guid: 10}, %Spell{id: 2008}, 90, 200)
      {alive, _} = Death.resurrect(character, 1.0, 100)
      assert {^alive, []} = Resurrection.offer(alive, context, %Spell{id: 2006}, 70, 135)
    end
  end

  describe "respond/3" do
    test "requires the offering caster and accepts once", %{offered: offered} do
      assert Resurrection.respond(offered, 10, 1) == offered
      assert Resurrection.respond(offered, 9, 2) == offered
      accepted = Resurrection.respond(offered, 9, 1)
      assert %ResurrectionOffer{phase: :accepted} = accepted.internal.pending_resurrect
      assert Resurrection.respond(accepted, 9, 1) == accepted
      refute Death.alive?(accepted)
    end

    test "declining permits a later offer", %{offered: offered, context: context} do
      declined = Resurrection.respond(offered, 9, 0)
      assert declined.internal.pending_resurrect == nil
      assert {next, [_]} = Resurrection.offer(declined, %{context | caster_guid: 10}, %Spell{id: 2008}, 90, 200)
      assert next.internal.pending_resurrect.caster_guid == 10
    end
  end

  describe "cancel_transfer/1" do
    test "ordinary travel preserves offers but cancels accepted recovery", %{offered: offered} do
      assert Resurrection.cancel_transfer(offered) == offered
      accepted = Resurrection.respond(offered, 9, 1)
      assert Resurrection.cancel_transfer(accepted).internal.pending_resurrect == nil
    end
  end

  describe "resurrect_with/4" do
    test "all recovery clears offers and spell recovery fills energy", %{offered: offered} do
      {restored, _} = Death.resurrect_with(offered, 500, 500, 100)
      assert restored.unit.health == 100
      assert restored.unit.power1 == 80
      assert restored.unit.power2 == 0
      assert restored.unit.power4 == 100
      assert restored.internal.pending_resurrect == nil
      {restored, _} = Death.resurrect(offered, 0.5, 100)
      assert restored.internal.pending_resurrect == nil
    end
  end

  defp dead_character(_context) do
    character = %Character{
      object: %Object{guid: 8},
      unit: %Unit{health: 0, max_health: 100, max_power1: 80, max_power4: 100, power4: 3, power2: 10, auras: []},
      player: %Player{flags: 0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{}
    }

    context = %CastContext{caster_guid: 9, caster_position: {WorldRef.open(0), 1.0, 2.0, 3.0}, caster_orientation: 1.5}
    {offered, _} = Resurrection.offer(character, context, %Spell{id: 2006}, 70, 135)
    %{character: character, context: context, offered: offered}
  end
end
