defmodule ThistleTea.Game.Entity.Logic.HealingReceivedTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.HealingReceived
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Server.Mob, as: MobServer
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  setup [:entity]

  describe "amount/2" do
    test "combines only the strongest reduction and increase", %{entity: entity} do
      entity = with_modifiers(entity, [-50, -20, 30, 10])
      assert HealingReceived.amount(entity, 200) == 130
    end

    test "counts stacks and clamps complete suppression", %{entity: entity} do
      holder = %{modifier(1, -10) | stacks: 10}
      entity = %{entity | unit: %{entity.unit | auras: [holder, modifier(2, 50)]}}
      assert HealingReceived.amount(entity, 200) == 0
      entity = %{entity | unit: %{entity.unit | auras: [%{holder | stacks: 20}]}}
      assert HealingReceived.amount(entity, 200) == 0
    end

    test "ignores school masks and unrelated auras", %{entity: entity} do
      holder = modifier(1, -50)
      unrelated = %{modifier(2, -100) | auras: [%AuraData{type: :mod_damage_percent_taken, amount: -100}]}
      entity = %{entity | unit: %{entity.unit | auras: [holder, unrelated]}}
      assert HealingReceived.amount(entity, 200) == 100
      assert HealingReceived.amount(entity, -100) == 0
    end
  end

  describe "receive/4" do
    test "modifies direct healing and its feedback and effective threat", %{entity: entity} do
      entity = with_modifiers(entity, [-50, -20, 30])
      {entity, events} = SpellEffect.receive(entity, 2, heal_spell(), 0)
      assert entity.unit.health == 230
      assert Enum.any?(events, &match?(%Effects.SpellHeal{damage: 130}, &1))
      assert Enum.any?(events, &match?(%Effects.HealThreat{amount: 65.0}, &1))
    end

    test "suppresses maximum-health heals", %{entity: entity} do
      context = %CastContext{caster_guid: 2, caster_level: 60, caster_max_health: 800}
      spell = %{heal_spell() | effects: [%Effect{type: :heal_max_health}]}
      {entity, events} = SpellEffect.receive(with_modifiers(entity, [-50]), context, spell, 0)
      assert entity.unit.health == 500
      assert Enum.any?(events, &match?(%Effects.SpellHeal{damage: 400}, &1))
    end
  end

  describe "tick/2" do
    test "uses current modifiers on every tick without changing the snapshot", %{entity: entity} do
      {entity, _events} = Aura.apply_spell(entity, 2, 60, hot_spell(), 0)
      {entity, _events} = Aura.tick(entity, 1_000)
      assert entity.unit.health == 300
      entity = %{entity | unit: %{entity.unit | auras: [modifier(10, -50) | entity.unit.auras]}}
      {entity, events} = Aura.tick(entity, 2_000)
      assert entity.unit.health == 400
      assert Enum.any?(events, &match?(%Effects.PeriodicAuraLog{amount: 100}, &1))
      assert Enum.any?(events, &match?(%Effects.SpellHeal{damage: 100, periodic?: true}, &1))
      assert Enum.any?(events, &match?(%Effects.HealThreat{amount: 50.0}, &1))
      {entity, _events} = Aura.remove_spells(entity, [10], 2_100)
      {entity, _events} = Aura.tick(entity, 3_000)
      assert entity.unit.health == 600
      [holder] = entity.unit.auras
      assert hd(holder.auras).amount == 200
      assert hd(holder.auras).next_tick_at == 4_000
    end

    test "modifies percentage-health ticks and caps threat at effective healing", %{entity: entity} do
      spell = hot_spell(:obs_mod_health, 20)
      entity = with_modifiers(entity, [-50])
      {entity, _events} = Aura.apply_spell(entity, 2, 60, spell, 0)
      entity = %{entity | unit: %{entity.unit | health: 970}}
      {entity, events} = Aura.tick(entity, 1_000)
      assert entity.unit.health == 1_000
      assert Enum.any?(events, &match?(%Effects.PeriodicAuraLog{amount: 100}, &1))
      assert Enum.any?(events, &match?(%Effects.HealThreat{amount: 15.0}, &1))
    end

    test "scales stacked HoTs and preserves ticks under total suppression", %{entity: entity} do
      spell = %{hot_spell() | stack_amount: 3}
      {entity, _events} = Aura.apply_spell(entity, 2, 60, spell, 0)
      {entity, _events} = Aura.apply_spell(entity, 2, 60, spell, 0)
      {entity, _events} = Aura.tick(entity, 1_000)
      assert entity.unit.health == 500
      entity = %{entity | unit: %{entity.unit | auras: [modifier(10, -100) | entity.unit.auras]}}
      {entity, events} = Aura.tick(entity, 2_000)
      assert entity.unit.health == 500
      assert Enum.any?(events, &match?(%Effects.PeriodicAuraLog{amount: 0}, &1))
      refute Enum.any?(events, &match?(%Effects.HealThreat{}, &1))
      {entity, _events} = Aura.remove_spells(entity, [10], 2_100)
      {entity, _events} = Aura.tick(entity, 3_000)
      assert entity.unit.health == 900
    end
  end

  describe "heal/2" do
    test "transferred healing uses the receiving owner's modifiers", %{entity: entity} do
      entity = with_modifiers(entity, [-50])
      assert HealingReceived.heal(entity, 200).unit.health == 200
      player = %Character{object: entity.object, unit: entity.unit, internal: entity.internal}
      assert HealingReceived.heal(player, 200).unit.health == 200
      dead = %{entity | unit: %{entity.unit | health: 0}}
      assert HealingReceived.heal(dead, 200).unit.health == 0
    end
  end

  describe "handle_cast/2" do
    test "player and creature owners apply transferred healing exactly once", %{entity: entity} do
      entity = with_modifiers(entity, [-50])
      {:noreply, healed, {:continue, :maybe_broadcast}} = MobServer.handle_cast({:receive_heal, 200}, entity)
      assert healed.unit.health == 200

      player = %Character{object: entity.object, unit: entity.unit, internal: entity.internal}

      {:noreply, state, {:continue, :maybe_broadcast_update}} =
        PlayerServer.handle_cast({:receive_heal, 200}, %{character: player})

      assert state.character.unit.health == 200
    end

    test "a delayed transfer cannot resurrect either owner", %{entity: entity} do
      dead = %{entity | unit: %{entity.unit | health: 0}}
      {:noreply, ^dead, {:continue, :maybe_broadcast}} = MobServer.handle_cast({:receive_heal, 200}, dead)
      player = %Character{object: dead.object, unit: dead.unit, internal: dead.internal}
      state = %{character: player}

      assert {:noreply, ^state, {:continue, :maybe_broadcast_update}} =
               PlayerServer.handle_cast({:receive_heal, 200}, state)
    end
  end

  describe "aura lifecycle" do
    test "partial dispels reduce suppression without resetting expiry", %{entity: entity} do
      holder = %{modifier(10, -10) | stacks: 5, expires_at: 5_000}
      entity = %{entity | unit: %{entity.unit | auras: [holder]}}
      assert HealingReceived.amount(entity, 200) == 100
      {entity, _events} = Aura.dispel(entity, 3, 1_000)
      assert HealingReceived.amount(entity, 200) == 120
      assert hd(entity.unit.auras).expires_at == 5_000
      {entity, _events} = Aura.tick(entity, 5_000)
      assert HealingReceived.amount(entity, 200) == 200
    end

    test "removing the strongest reduction resumes the weaker one", %{entity: entity} do
      entity = with_modifiers(entity, [-50, -20])
      {entity, _events} = Aura.remove_spells(entity, [10], 0)
      assert HealingReceived.amount(entity, 200) == 160
      entity = Core.take_damage(entity, 100, 0)
      assert entity.unit.health == 0
      assert HealingReceived.amount(entity, 200) == 200
    end
  end

  defp entity(_context) do
    %{
      entity: %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 1_000, level: 60, auras: []},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end

  defp with_modifiers(entity, amounts) do
    holders = amounts |> Enum.with_index(10) |> Enum.map(fn {amount, id} -> modifier(id, amount) end)
    %{entity | unit: %{entity.unit | auras: holders}}
  end

  defp modifier(id, amount) do
    %Holder{
      spell: %Spell{id: id, dispel_type: 3},
      caster_guid: 2,
      negative?: amount < 0,
      auras: [%AuraData{type: :mod_healing_pct, amount: amount, misc_value: 0}]
    }
  end

  defp heal_spell do
    %Spell{id: 1, school: :holy, effects: [%Effect{type: :heal, base_points: 200}]}
  end

  defp hot_spell(type \\ :periodic_heal, amount \\ 200) do
    %Spell{
      id: 1,
      school: :holy,
      duration_ms: 5_000,
      effects: [
        %Effect{
          index: 0,
          type: :apply_aura,
          aura: type,
          base_points: amount,
          amplitude_ms: 1_000,
          implicit_target_a: :target_ally
        }
      ]
    }
  end
end
