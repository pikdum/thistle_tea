defmodule ThistleTea.Game.Entity.Server.Mob.CreatureEventTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.CreatureArchetype
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.GameEvent.CreatureData
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.CreatureEvent, as: CreatureEventLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.GameEvent
  alias ThistleTea.Game.WorldRef

  setup [:creatures]

  describe "world event lifecycle" do
    test "updates every live copy and restores the original client fields", %{mob: mob, template: template} do
      copy = %{
        mob
        | object: %{mob.object | guid: Guid.runtime(:mob, mob.object.entry)},
          internal: %{mob.internal | world: WorldRef.instance(998, 82)}
      }

      on_exit(fn -> World.stop_entity(copy.object.guid) end)
      {:ok, pid} = World.start_entity(mob)
      {:ok, copy_pid} = World.start_entity(copy)
      assert :ok = GameEvent.set_events([49])

      for {guid, owner} <- [{mob.object.guid, pid}, {copy.object.guid, copy_pid}] do
        update = update(owner, template.entry)
        assert update.unit.display_id == 102
        assert Entity.pid(guid) == owner
        assert World.entry(guid) == template.entry
        assert Metadata.query(guid, [:name, :display_id, :level]) == %{name: "Event form", display_id: 102, level: 40}
      end

      assert :ok = GameEvent.set_events([])

      for {guid, owner} <- [{mob.object.guid, pid}, {copy.object.guid, copy_pid}] do
        update = update(owner, mob.object.entry)
        assert update.unit.display_id == 101
        assert World.entry(guid) == mob.object.entry
        assert Process.alive?(owner)
      end
    end

    test "initializes from cached activity and reapplies the event after respawn", %{mob: mob, template: template} do
      assert :ok = GameEvent.set_events([49])
      {:ok, pid} = World.start_entity(mob)
      assert World.entry(mob.object.guid) == template.entry
      assert update(pid, template.entry).unit.display_id == 102
      send(pid, {:script_respawn, true})
      assert update(pid, template.entry).unit.health > 0
      assert :ok = GameEvent.set_events([])
      assert update(pid, mob.object.entry).unit.display_id == 101
    end

    test "applies loaded start and end spells and removes the opposite aura", %{mob: mob} do
      start_spell = aura(990_701, :mod_melee_haste)
      end_spell = aura(990_702, :mod_scale)

      event = %CreatureData{
        event: 2,
        spell_start: start_spell.id,
        spell_end: end_spell.id,
        spellbook: %{start_spell.id => start_spell, end_spell.id => end_spell}
      }

      :ets.insert(CreatureEventLoader, {mob.internal.creature.db_guid, [event]})
      {:ok, pid} = World.start_entity(mob)
      GameEvent.set_events([2])
      assert aura_ids(pid, [start_spell.id]) == [start_spell.id]
      GameEvent.set_events([])
      assert aura_ids(pid, [end_spell.id]) == [end_spell.id]
      GameEvent.set_events([2])
      assert aura_ids(pid, [start_spell.id]) == [start_spell.id]
      send(pid, {:script_respawn, true})
      assert aura_ids(pid, [start_spell.id]) == [start_spell.id]
    end
  end

  defp creatures(_context) do
    original_events = GameEvent.get_events()
    GameEvent.set_events([])
    mob = build(990_601, "Original", 101, 20)
    template = build(990_602, "Event form", 102, 40) |> CreatureArchetype.from_mob()
    event = %CreatureData{event: 49, archetypes: [{1, template}]}
    :ets.insert(CreatureEventLoader, {mob.internal.creature.db_guid, [event]})

    on_exit(fn ->
      World.stop_entity(mob.object.guid)
      :ets.delete(CreatureEventLoader, mob.internal.creature.db_guid)
      GameEvent.set_events(original_events)
    end)

    %{mob: mob, template: template}
  end

  defp build(entry, name, display, level) do
    %Mangos.Creature{
      guid: Guid.low_guid(Guid.runtime(:mob, entry)),
      id: entry,
      modelid: display,
      selected_level: level,
      curhealth: 100,
      creature_movement: [],
      creature_template: %Mangos.CreatureTemplate{
        entry: entry,
        name: name,
        min_level: level,
        max_level: level,
        faction_alliance: 35,
        extra_flags: 2,
        melee_base_attack_time: 2_000
      }
    }
    |> Mob.build()
    |> then(&%{&1 | internal: %{&1.internal | world: WorldRef.instance(998, 81)}})
  end

  defp update(pid, entry, attempts \\ 100)

  defp update(pid, entry, attempts) when attempts > 0 do
    Entity.request_update_from(pid, self())
    assert_receive {:"$gen_cast", {:send_packet, %UpdateObject{} = update}}, 1_000

    if update.object.entry == entry do
      update
    else
      Process.sleep(10)
      update(pid, entry, attempts - 1)
    end
  end

  defp update(_pid, entry, _attempts), do: flunk("Creature did not publish entry #{entry}")

  defp aura_ids(pid, expected, attempts \\ 100)

  defp aura_ids(pid, expected, attempts) when attempts > 0 do
    actual = pid |> :sys.get_state() |> then(&Enum.map(&1.unit.auras, fn holder -> holder.spell.id end))

    if actual == expected do
      actual
    else
      Process.sleep(10)
      aura_ids(pid, expected, attempts - 1)
    end
  end

  defp aura_ids(_pid, expected, _attempts), do: flunk("Creature did not reconcile auras #{inspect(expected)}")

  defp aura(id, type) do
    %Spell{
      id: id,
      duration_ms: 30_000,
      effects: [%Effect{index: 0, type: :apply_aura, aura: type, base_points: 50, implicit_target_a: :caster}]
    }
  end
end
