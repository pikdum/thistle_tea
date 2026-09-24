defmodule ThistleTea.Game.Entity.Logic.TauntTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Aura.Change
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.Threat
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  setup [:mob]

  describe "receive/4" do
    @tag :dbc_db
    test "Taunt and Growl keep their threat match after the forced attack ends", %{mob: mob} do
      for id <- [355, 6795] do
        spell = SpellLoader.load(id)
        context = %CastContext{caster_guid: 2, caster_level: 60, target_guid: 100, target_hostile?: true}
        {taunted, events} = SpellEffect.receive(mob, context, spell, 1_000)
        assert SpellEffect.successful_hit?(events)
        assert Aura.has_aura?(taunted, :mod_taunt)
        assert taunted.internal.threat[2] == 500.0
        assert taunted.internal.temporary_threat == %{}
        {expired, _events} = Aura.expire_due(taunted, 1_000 + spell.duration_ms)
        assert expired.internal.threat[2] == 500.0
        refute Aura.has_aura?(expired, :mod_taunt)
      end
    end

    @tag :dbc_db
    test "Challenging Shout and Roar return their borrowed threat", %{mob: mob} do
      for id <- [1161, 5209] do
        spell = SpellLoader.load(id)
        context = %CastContext{caster_guid: 2, caster_level: 60, target_guid: 100, target_hostile?: true}
        {taunted, events} = SpellEffect.receive(mob, context, spell, 1_000)
        assert SpellEffect.successful_hit?(events)
        assert Aura.has_aura?(taunted, :mod_taunt)
        assert taunted.internal.threat[2] == 500.0
        assert taunted.internal.temporary_threat == %{2 => 450.0}
        {expired, _events} = Aura.expire_due(taunted, 1_000 + spell.duration_ms)
        assert expired.internal.threat[2] == 50.0
        assert expired.internal.temporary_threat == %{}
      end
    end
  end

  describe "apply_spell/5" do
    test "borrows the victim's threat and preserves threat earned during the aura", %{mob: mob} do
      {taunted, _events} = Aura.apply_spell(mob, 2, 60, challenge(1161), 1_000)
      assert taunted.internal.threat == %{1 => 500.0, 2 => 500.0, 3 => 600.0}
      assert taunted.internal.temporary_threat == %{2 => 450.0}

      %{entity: taunted, decision: {:switch, 2}} = select(taunted)
      assert %Effects.AttackerLost{target_guid: 1} in taunted.internal.events
      assert %Effects.AttackerGained{target_guid: 2} in taunted.internal.events

      {expired, _events} = taunted |> Threat.add(2, 25) |> Aura.expire_due(7_000)
      assert expired.internal.threat[2] == 75.0
      assert expired.internal.temporary_threat == %{}
      assert %{decision: {:switch, 3}} = select(expired)
    end

    test "refreshing does not borrow twice", %{mob: mob} do
      {taunted, _events} = Aura.apply_spell(mob, 2, 60, challenge(1161), 1_000)
      {refreshed, _events} = Aura.apply_spell(taunted, 2, 60, challenge(1161), 2_000)
      assert refreshed.internal.threat == taunted.internal.threat
      assert refreshed.internal.temporary_threat == %{2 => 450.0}

      {expired, _events} = Aura.expire_due(refreshed, 8_000)
      assert expired.internal.threat[2] == 50.0
    end

    test "does not overwrite an existing temporary modifier", %{mob: mob} do
      faded = Threat.set_temporary(mob, 2, -20)
      {taunted, _events} = Aura.apply_spell(faded, 2, 60, challenge(1161), 1_000)
      assert taunted.internal.threat[2] == 30.0
      assert taunted.internal.temporary_threat == %{2 => -20}
      assert %{decision: {:switch, 2}} = select(taunted)
    end

    test "permanent taunt matching is retained after the aura expires", %{mob: mob} do
      taunted = Threat.taunt(mob, 2)
      {taunted, _events} = Aura.apply_spell(taunted, 2, 60, challenge(355), 1_000)
      {expired, _events} = Aura.expire_due(taunted, 7_000)
      assert expired.internal.threat[2] == 500.0
      assert expired.internal.temporary_threat == %{}
    end

    test "does not borrow threat from a dead target or a missing reference", %{mob: mob} do
      for entity <- [%{mob | unit: %{mob.unit | health: 0}}, Threat.remove(mob, 2)] do
        {taunted, _events} = Aura.apply_spell(entity, 2, 60, challenge(1161), 1_000)
        assert taunted.internal.threat == entity.internal.threat
        assert taunted.internal.temporary_threat == %{}
      end
    end
  end

  describe "select/2" do
    test "the newest taunt wins and expiry restores the earlier caster", %{mob: mob} do
      {taunted, _events} = Aura.apply_spell(mob, 2, 60, challenge(1161), 1_000)
      %{entity: taunted} = select(taunted)
      {overlapped, _events} = Aura.apply_spell(taunted, 3, 60, challenge(355, 3_000), 2_000)
      assert length(overlapped.unit.auras) == 2
      %{entity: overlapped, decision: {:switch, 3}} = select(overlapped)
      {expired, _events} = Aura.expire_due(overlapped, 5_000)
      assert %{decision: {:switch, 2}} = select(expired)
    end

    test "a refreshed taunt takes priority even in its earlier holder position", %{mob: mob} do
      {taunted, _events} = Aura.apply_spell(mob, 2, 60, challenge(1161), 1_000)
      {taunted, _events} = Aura.apply_spell(taunted, 3, 60, challenge(355), 2_000)
      %{entity: taunted} = select(taunted)
      {refreshed, _events} = Aura.apply_spell(taunted, 2, 60, challenge(1161), 3_000)
      assert %{decision: {:switch, 2}} = select(refreshed)
    end

    test "equal timestamps use holder application order", %{mob: mob} do
      {taunted, _events} = Aura.apply_spell(mob, 2, 60, challenge(1161), 1_000)
      {taunted, _events} = Aura.apply_spell(taunted, 3, 60, challenge(355), 1_000)
      assert %{decision: {:switch, 3}} = select(taunted)
    end

    test "an invalid current taunter yields to an older valid taunt", %{mob: mob} do
      {taunted, _events} = Aura.apply_spell(mob, 2, 60, challenge(1161), 1_000)
      {taunted, _events} = Aura.apply_spell(taunted, 3, 60, challenge(355), 2_000)
      %{entity: taunted} = select(taunted)
      %{entity: selected, decision: {:switch, 2}} = select(taunted, &(&1 != 3))
      refute Map.has_key?(selected.internal.threat, 3)
    end

    test "an invalid final taunter yields to ordinary threat selection", %{mob: mob} do
      {taunted, _events} = Aura.apply_spell(mob, 2, 60, challenge(1161), 1_000)
      %{entity: taunted} = select(taunted)
      %{entity: selected, decision: {:switch, 3}} = select(taunted, &(&1 != 2))
      assert selected.internal.temporary_threat == %{}
      assert %{decision: :none} = select(taunted, fn _guid -> false end)
    end
  end

  describe "transition/2" do
    test "removal restores threat and combat cleanup cannot restore stale amounts", %{mob: mob} do
      {taunted, _events} = Aura.apply_spell(mob, 2, 60, challenge(1161), 1_000)

      for cause <- [:removed, :dispelled, :death] do
        {removed, _events} = Aura.transition(taunted, %Change{holders: [], cause: cause, now: 2_000})
        assert removed.internal.threat == mob.internal.threat
        assert removed.internal.temporary_threat == %{}
      end

      for cleared <- [Engagement.leave(taunted, :evade).entity, Engagement.reset(taunted).entity] do
        {expired, _events} = cleared |> Threat.add(2, 10) |> Aura.expire_due(7_000)
        assert expired.internal.threat == %{2 => 10.0}
        assert expired.internal.temporary_threat == %{}
      end
    end

    test "same-caster overlapping auras retain the loan until the last one ends", %{mob: mob} do
      {taunted, _events} = Aura.apply_spell(mob, 2, 60, challenge(1161), 1_000)
      {taunted, _events} = Aura.apply_spell(taunted, 2, 60, challenge(694, 3_000), 2_000)
      {taunted, _events} = Aura.expire_due(taunted, 5_000)
      assert taunted.internal.temporary_threat == %{2 => 450.0}
      {expired, _events} = Aura.expire_due(taunted, 7_000)
      assert expired.internal.threat[2] == 50.0
      assert expired.internal.temporary_threat == %{}
    end
  end

  defp select(entity, valid? \\ fn _guid -> true end) do
    Engagement.select(entity, valid?: valid?, in_melee?: fn _guid -> false end)
  end

  defp mob(_context) do
    %{
      mob: %Mob{
        object: %Object{guid: 100},
        unit: %Unit{health: 1000, max_health: 1000, level: 60, target: 1, auras: []},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{in_combat: true, threat: %{1 => 500.0, 2 => 50.0, 3 => 600.0}}
      }
    }
  end

  defp challenge(id, duration \\ 6_000) do
    %Spell{
      id: id,
      duration_ms: duration,
      effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_taunt, base_points: 0}]
    }
  end
end
