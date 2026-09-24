defmodule ThistleTea.Game.Entity.Logic.TotemsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Commands
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.Internal.Totem
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Entity.Logic.Totems
  alias ThistleTea.Game.Entity.Server.Mob, as: MobServer
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.EntitySupervisor
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  setup [:totem]

  describe "prepare/4" do
    test "snapshots owner timing modifiers for the summon and its periodic aura" do
      modifier = %Holder{
        spell: %Spell{id: 50, spell_family: 11},
        auras: [
          %ThistleTea.Game.Aura{type: :add_flat_modifier, misc_value: 1, amount: -2000, class_mask: 0x08000000},
          %ThistleTea.Game.Aura{type: :add_flat_modifier, misc_value: 19, amount: -2000, class_mask: 0x20}
        ]
      }

      owner = character(%{})
      owner = %{owner | unit: %{owner.unit | auras: [modifier]}}

      spell = %Spell{
        id: 1535,
        spell_family: 11,
        family_flags_0: 0x28000000,
        duration_ms: 5000,
        effects: [%Effect{index: 0, type: :summon_totem, misc_value: 5879, base_points: 5}]
      }

      context = CastContext.from_caster(owner, spell, owner.object.guid)
      assert {_, [%Effects.SummonTotem{duration_ms: 3000} = effect]} = SpellEffect.receive(owner, context, spell, 1000)

      ward =
        Totems.prepare(
          %Mob{object: %Object{guid: 2}, unit: %Unit{auras: []}, internal: %Internal{}},
          owner,
          effect,
          1000
        )

      assert ward.internal.totem.expires_at == 4000

      spell = %Spell{
        id: 8443,
        spell_family: 11,
        family_flags_0: 0x20,
        duration_ms: -1,
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            aura: :periodic_trigger_spell,
            amplitude_ms: 4000,
            trigger_spell_id: 8349
          }
        ]
      }

      context = CastContext.from_caster(ward, spell, 2)
      {ward, _events} = Aura.apply_spell(ward, context, spell, 1000)
      assert [%Holder{auras: [%{amplitude_ms: 2000, next_tick_at: 3000}]}] = ward.unit.auras
    end

    test "retains spell health and projects the area aura without buffing the totem itself" do
      owner = character(%{})

      mob = %Mob{
        object: %Object{guid: 200},
        unit: %Unit{health: 1, max_health: 1, stamina: 22, base_stamina: 22},
        internal: %Internal{}
      }

      effect = %{Effects.summon_totem(14_465, nil, 120_000) | spell_id: 23_034, health: 1500}
      ward = Totems.prepare(mob, owner, effect, 1000)
      assert ward.unit.health == 1500
      assert ward.unit.max_health == 1500
      assert ward.unit.created_by_spell == 23_034
      assert ward.internal.totem.expires_at == 121_000
      assert ward.internal.loot == nil

      spell = %Spell{
        id: 23_033,
        duration_ms: -1,
        effects: [
          %Effect{
            index: 0,
            type: :apply_area_aura,
            aura: :mod_increase_health_percent,
            base_points: 15,
            misc_value: 0,
            radius_yards: 45.0
          }
        ]
      }

      {ward, _events} = Aura.apply_spell(ward, ward.object.guid, 60, spell, 1000)
      assert Stats.recompute(ward.unit).max_health == 1500
      assert [%{auras: [%{type: :none}], next_area_refresh_at: 2000}] = ward.unit.auras
      assert {_, [_ | _]} = Aura.tick(ward, 2000)

      owner = %{owner | unit: %{owner.unit | base_health: 1000, stamina: 0}}
      {owner, _events} = Aura.apply_spell(owner, ward.object.guid, 60, spell, 1000)
      assert owner.unit.max_health == 1150
      {owner, _events} = Aura.remove_source_spell(owner, spell.id, ward.object.guid, 1500)
      assert owner.unit.max_health == 1000
    end
  end

  describe "started/3" do
    test "independent wards coexist with elemental slots and each other" do
      owner = character(%{1 => 100}) |> Totems.started(nil, 200) |> Totems.started(nil, 201)
      assert owner.internal.totem_guids == %{1 => 100, {:unslotted, 200} => 200, {:unslotted, 201} => 201}
      owner = Totems.stopped(owner, 200)
      assert Map.values(owner.internal.totem_guids) |> Enum.sort() == [100, 201]
      assert length(Totems.dismiss_all(owner).internal.events) == 2
    end

    test "the spell pipeline retains entry, duration, health, and creating spell" do
      owner = character(%{})

      spell = %Spell{
        id: 23_034,
        duration_ms: 120_000,
        effects: [%Effect{index: 0, type: :summon_totem, misc_value: 14_465, base_points: 1500}]
      }

      context = %CastContext{caster_guid: owner.object.guid, caster_level: 60, target_role: :caster}

      assert {^owner,
              [%Effects.SummonTotem{entry: 14_465, slot: nil, health: 1500, spell_id: 23_034, duration_ms: 120_000}]} =
               SpellEffect.receive(owner, context, spell, 1000)
    end
  end

  describe "dismiss_all/1" do
    test "clears slots and queues each child exactly once", %{guid: guid} do
      character = character(%{1 => guid, 2 => guid})
      dismissed = Totems.dismiss_all(character)
      assert dismissed.internal.totem_guids == %{}
      assert [%Effects.DespawnEntity{target_guid: ^guid}] = dismissed.internal.events
      assert Totems.dismiss_all(dismissed) == dismissed
    end
  end

  describe "handle_info/2" do
    test "stopped totems clear only their own slots", %{guid: guid} do
      character = character(%{1 => guid, 2 => guid + 1})
      command = %Commands.TotemStopped{guid: guid}
      {:noreply, state} = PlayerServer.handle_info(command, %State{character: character})
      assert state.character.internal.totem_guids == %{2 => guid + 1}
      assert {:noreply, ^state} = PlayerServer.handle_info(command, state)
    end

    test "a late totem start is stopped immediately for a dead player", %{guid: guid, pid: pid} do
      character = character(%{})
      character = %{character | unit: %{character.unit | health: 0}}
      command = %Commands.TotemStarted{slot: 2, guid: guid}
      {:noreply, state} = PlayerServer.handle_info(command, %State{character: character})
      assert state.character.internal.totem_guids == %{}
      assert state.character.internal.events == []
      refute Process.alive?(pid)
      refute Entity.online?(guid)
    end
  end

  describe "leave_world/1" do
    test "stops totems and saves cleared slots on logout", %{guid: guid, pid: pid} do
      character = character(%{2 => guid}) |> CharacterStore.put()
      assert %State{character: nil} = State.leave_world(%State{character: character})
      assert CharacterStore.get(character.id).internal.totem_guids == %{}
      assert CharacterStore.get(character.id).internal.events == []
      refute Process.alive?(pid)
    end
  end

  describe "prepare_worldport/3" do
    test "dismisses independent wards before changing world", %{guid: guid, pid: pid} do
      character = character(%{{:unslotted, guid} => guid})
      state = State.prepare_worldport(%State{character: character}, WorldRef.open(0), WorldRef.instance(529, 1))
      assert state.character.internal.totem_guids == %{}
      refute Process.alive?(pid)
    end
  end

  describe "handle_continue/2" do
    test "dead totems stop without loot or respawn and notify their owner" do
      owner = System.unique_integer([:positive]) + 10_000_000
      guid = Guid.runtime(:mob, 5925)
      Entity.register(owner)

      totem = %Mob{
        object: %Object{guid: guid, entry: 5925},
        unit: %Unit{health: 0, max_health: 70, level: 50, auras: []},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{
          world: WorldRef.open(451),
          totem: %Totem{owner_guid: owner},
          spawn: %Spawn{},
          spellbook: %{23_033 => %Spell{id: 23_033, effects: [%Effect{type: :apply_area_aura}]}}
        }
      }

      on_exit(fn -> Metadata.delete(guid) end)
      assert {:noreply, stopped} = MobServer.handle_continue(:maybe_broadcast, totem)
      assert stopped.internal.death_finalized?
      assert stopped.internal.spawn.respawn_ref == nil
      assert_receive :totem_stop
      assert {:stop, :normal, ^stopped} = MobServer.handle_info(:totem_stop, stopped)
      MobServer.terminate(:normal, stopped)
      assert_receive {:"$gen_cast", {:remove_aura, 23_033, ^guid}}
      assert_receive %Commands.TotemStopped{guid: ^guid}
    end
  end

  describe "child_spec/1" do
    test "a stopped supervised totem never respawns from its original state" do
      guid = Guid.runtime(:mob, 5925)
      owner = System.unique_integer([:positive]) + 10_000_000
      Entity.register(owner)

      totem = %Mob{
        object: %Object{guid: guid, entry: 5925},
        unit: %Unit{health: 70, max_health: 70, level: 50, auras: []},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{
          world: WorldRef.open(451),
          totem: %Totem{owner_guid: owner},
          creature: %Creature{},
          spawn: %Spawn{}
        }
      }

      {:ok, pid} = World.start_entity(totem)
      ref = Process.monitor(pid)
      send(pid, :totem_stop)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
      assert_receive %Commands.TotemStopped{guid: ^guid}
      assert MobServer.child_spec(totem).restart == :temporary
      refute Entity.online?(guid)
    end
  end

  defp totem(_) do
    guid = System.unique_integer([:positive]) + 9_000_000
    {:ok, pid} = EntitySupervisor.start_child(guid, {Agent, fn -> Entity.register(guid) end})
    on_exit(fn -> if Process.alive?(pid), do: World.stop_entity(pid) end)
    %{guid: guid, pid: pid}
  end

  defp character(totems) do
    id = System.unique_integer([:positive]) + 10_000_000
    on_exit(fn -> :ets.delete(CharacterStore, id) end)

    %Character{
      id: id,
      object: %Object{guid: id},
      unit: %Unit{health: 100, max_health: 100, level: 60, auras: []},
      player: %Player{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{totem_guids: totems}
    }
  end
end
