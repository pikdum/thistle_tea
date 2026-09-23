defmodule ThistleTea.Game.Entity.Logic.SilithystTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Aura.Change
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.GameObjectInteraction
  alias ThistleTea.Game.Entity.Logic.Pvp
  alias ThistleTea.Game.Entity.Logic.Silithyst
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  setup [:character]

  describe "pickup/2" do
    test "an existing carrier cannot consume another resource object", %{character: character} do
      for entry <- [181_597, 181_598] do
        template = %GameObjectTemplate{entry: entry, type: 10, data: List.duplicate(0, 24)}
        assert {:ok, _character} = GameObjectInteraction.prepare_readable_use(character, template, 0, 100)

        assert {:error, :already_carrying} =
                 GameObjectInteraction.prepare_readable_use(carry(character), template, 0, 100)
      end
    end

    test "dummy effect casts the carrier on the player and enables contested PvP", %{character: character} do
      spell = %Spell{id: 29_518, effects: [%Effect{index: 0, type: :dummy}]}
      context = %CastContext{caster_guid: 123, caster_level: 1, spell: spell}
      {character, events} = SpellEffect.receive(character, context, spell, 100)

      assert Pvp.active?(character)
      assert Pvp.contested?(character)
      refute character.internal.pvp.desired?
      refute character.internal.pvp.combat?
      assert Enum.any?(events, &match?(%Effects.TriggerSpell{source_guid: 1, target_guid: 1, spell_id: 29_519}, &1))
    end

    test "rejects duplicate carriers and dead players", %{character: character} do
      carrying = carry(character)
      assert Silithyst.pickup(carrying, 100) == {carrying, []}
      dead = %{character | unit: %{character.unit | health: 0}}
      assert Silithyst.pickup(dead, 100) == {dead, []}
    end
  end

  describe "refresh_pvp/2" do
    test "refreshes only while the resource is present", %{character: character} do
      carrying = character |> carry() |> Silithyst.refresh_pvp(0) |> Silithyst.refresh_pvp(15_000)
      assert carrying.internal.pvp.contested_remaining_ms == 30_000
      {dropped, _events} = Aura.remove_spells(carrying, [29_519], 15_001)
      expired = dropped |> Pvp.tick(45_000) |> Silithyst.refresh_pvp(45_000)
      refute Pvp.contested?(expired)
      refute Pvp.active?(Pvp.tick(expired, 315_000))
    end
  end

  describe "turn_in/3" do
    test "consumes the carrier once and emits rewards without a dropped mound", %{character: character} do
      carrying = carry(character)
      assert {:ok, delivered, :alliance, {1, 10}, effects} = Silithyst.turn_in(carrying, 4162, 100)
      refute Aura.has_spell?(delivered, 29_519)

      assert Enum.map(Enum.filter(effects, &match?(%Effects.TriggerSpell{}, &1)), & &1.spell_id) == [
               29_534,
               31_420,
               31_247
             ]

      refute Enum.any?(effects, &match?(%Effects.SummonGameObject{}, &1))
      assert Silithyst.turn_in(delivered, 4162, 101) == :unavailable
    end

    test "requires the correct faction, world, and living carrier", %{character: character} do
      carrying = carry(character)
      assert Silithyst.turn_in(carrying, 4168, 100) == :unavailable
      assert Silithyst.turn_in(carrying, 1, 100) == :unavailable
      assert Silithyst.turn_in(character, 4162, 100) == :unavailable
      assert Silithyst.turn_in(%{carrying | unit: %{carrying.unit | health: 0}}, 4162, 100) == :unavailable

      assert Silithyst.turn_in(%{carrying | internal: %{carrying.internal | world: WorldRef.open(0)}}, 4162, 100) ==
               :unavailable

      horde = %{carrying | unit: %{carrying.unit | race: 2}}
      assert {:ok, _, :horde, _, _} = Silithyst.turn_in(horde, 4168, 100)
    end
  end

  describe "after_remove/3" do
    test "removes the team aura with its carrier and rejects delayed orphan applications", %{character: character} do
      carrying = carry(character)
      team_spell = aura_spell(29_894, :use_normal_movement_speed)
      {carrying, _events} = Aura.apply_spell(carrying, 1, 60, team_spell, 20)
      assert Aura.has_spell?(carrying, 29_894)
      {dropped, _events} = Aura.cancel_spell(carrying, 29_519, 100)
      refute Aura.has_spell?(dropped, 29_894)
      {late, _events} = Aura.apply_spell(dropped, 1, 60, team_spell, 101)
      refute Aura.has_spell?(late, 29_894)
    end

    test "cancellation drops one unowned mound and repeated cleanup is inert", %{character: character} do
      {dropped, events} = character |> carry() |> Aura.cancel_spell(29_519, 100)

      assert [
               %Effects.SummonGameObject{
                 entry: 181_597,
                 duration_ms: 180_000,
                 owned?: false,
                 position: {1.0, 2.0, 3.0, +0.0}
               }
             ] = drops(events)

      assert Aura.remove_spells(dropped, [29_519], 101) == {dropped, []}
    end

    test "death uses the same drop transition", %{character: character} do
      carrying = carry(character)
      dead = %{carrying | unit: %{carrying.unit | health: 0}}
      {dead, events} = Aura.transition(dead, %Change{holders: [], cause: :death, now: 100})
      refute Aura.has_spell?(dead, 29_519)
      assert length(drops(events)) == 1
    end

    test "mounting, stealth and invisibility interrupt and drop the carrier", %{character: character} do
      for type <- [:mounted, :mod_stealth, :mod_invisibility] do
        spell = aura_spell(123, type)
        {updated, events} = Aura.apply_spell(carry(character), 1, 60, spell, 100)
        refute Aura.has_spell?(updated, 29_519)
        assert length(drops(events)) == 1
      end
    end

    test "refreshing the same carrier does not duplicate a dropped resource", %{character: character} do
      {updated, events} = Aura.apply_spell(carry(character), 1, 60, carrier_spell(), 100)
      assert Aura.has_spell?(updated, 29_519)
      assert drops(events) == []
    end
  end

  defp character(_context) do
    {:ok,
     character: %Character{
       object: %Object{guid: 1},
       unit: %Unit{health: 100, max_health: 100, level: 60, race: 1, flags: 0, auras: []},
       player: %Player{},
       internal: %Internal{world: WorldRef.open(1)},
       movement_block: %MovementBlock{position: {1.0, 2.0, 3.0, +0.0}}
     }}
  end

  defp carry(character), do: character |> Aura.apply_spell(1, 60, carrier_spell(), 10) |> elem(0)
  defp carrier_spell, do: %{aura_spell(29_519, :effect_immunity) | aura_interrupt_flags: 0x3A0000}
  defp drops(events), do: Enum.filter(events, &match?(%Effects.SummonGameObject{}, &1))

  defp aura_spell(id, type) do
    %Spell{
      id: id,
      duration_ms: -1,
      effects: [%Effect{index: 0, type: :apply_aura, aura: type, base_points: 1, misc_value: 85}]
    }
  end
end
