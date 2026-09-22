defmodule ThistleTea.Game.World.Loader.WildSummon do
  @moduledoc """
  Builds independent spell summons with template faction, creator loot, and
  timed death. Target Dummies use passive stationary behavior and shared auras.
  """

  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.KillReward
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement
  alias ThistleTea.Game.Entity.Logic.Engagement.Tap
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.Summon
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.Party

  @dummy_spells %{2673 => {4044, 4507}, 2674 => {4048, 4092}, 12_426 => {19_809, 4092}}

  def build(caster, %Effects.SummonWild{} = effect, position, now) do
    template = Summon.prototype(effect.entry).creature_template
    level = Enum.random(template.min_level..template.max_level)

    mob =
      Summon.build(effect.entry, caster.internal.world, position,
        level: level,
        stat_model: :creature,
        apply_addon_auras?: false
      )

    mob = %{mob | unit: Stats.recompute(mob.unit)}

    spawn = %{
      mob.internal.spawn
      | despawn_type: if(effect.duration_ms > 0, do: 11, else: 7),
        death_at: if(effect.duration_ms > 0, do: now + effect.duration_ms)
    }

    %{mob | unit: %{mob.unit | created_by_spell: effect.spell_id}, internal: %{mob.internal | spawn: spawn}}
    |> creator_loot(caster, template.creature_type_flags || 0)
    |> target_dummy(caster, now)
    |> Mob.apply_addon_auras(now)
  end

  defp creator_loot(mob, caster, flags) do
    if Bitwise.band(flags, 0x2000) == 0 do
      mob
    else
      mob = %{mob | unit: %{mob.unit | created_by: caster.object.guid}}
      player = KillReward.controlling_player(caster.object.guid, &Metadata.query(&1, [:owner_guid]))

      if is_integer(player) do
        group = Party.group_of(player)
        Engagement.claim(mob, %Tap{player: player, group_id: if(group, do: group.id)})
      else
        mob
      end
    end
  end

  defp target_dummy(%Mob{object: %{entry: entry}} = mob, caster, now) when is_map_key(@dummy_spells, entry) do
    {passive_id, spawn_id} = Map.fetch!(@dummy_spells, entry)
    unit = %{mob.unit | faction_template: caster.unit.faction_template, flags: 8}
    spawn = %{mob.internal.spawn | death_at: now + 15_000, death_in_combat?: true}
    creature = %{mob.internal.creature | stationary?: true}
    mob = %{mob | unit: unit, internal: %{mob.internal | spawn: spawn, creature: creature}}
    {mob, events} = Aura.apply_spell(mob, mob.object.guid, mob.unit.level, passive_spell(passive_id), now)

    mob
    |> Effects.enqueue(events)
    |> Effects.enqueue(Effects.trigger_spell(mob.object.guid, mob.unit.level, mob.object.guid, spawn_id))
  end

  defp target_dummy(mob, _caster, _now), do: mob

  defp passive_spell(id) do
    key = {:wild_passive, id}

    case :ets.lookup(Summon, key) do
      [{^key, spell}] ->
        spell

      [] ->
        spell = SpellLoader.load(id)
        :ets.insert(Summon, {key, spell})
        spell
    end
  end
end
