defmodule ThistleTea.Game.Entity.Logic.Effects.SpellTypes do
  @moduledoc false

  effects = [
    {:DeathItemReward, [:target_guid, :item_id, :count, :victim], []},
    {:TeachSpell, [:spell, :skill_steps], [cast_item_guid: nil]},
    {:SpellMagnetsChanged, [:magnets], []},
    {:SingleTargetAurasChanged, [:claims], []},
    {:SingleTargetAurasLeft, [], []},
    {:SingleTargetCasterDied, [], []},
    {:SpellDamage, [:source_guid, :target_guid, :spell_id, :spell, :school, :damage, :proc_type],
     [
       proc_damage: nil,
       periodic?: false,
       triggered_by_proc?: false,
       resisted: 0,
       absorbed: 0,
       crit?: false,
       blocked: 0
     ]},
    {:SpellHeal, [:source_guid, :target_guid, :spell_id, :spell, :school, :damage, :proc_type, :crit?],
     [periodic?: false]},
    {:SpellLogMiss, [:source_guid, :target_guid, :spell_id, :reason], []},
    {:SpellDamageImmune, [:source_guid, :target_guid, :spell_id], []},
    {:SpellDispel, [:source_guid, :target_guid, :spell_ids], []},
    {:SpellExtraAttacks, [:source_guid, :target_guid, :spell_id, :count], []},
    {:SpellEnergize, [:source_guid, :target_guid, :spell_id, :power_type, :amount], []},
    {:SpellPowerDrain, [:source_guid, :target_guid, :spell_id, :power_type, :amount, :multiplier], []},
    {:LeechPower, [:source_guid, :target_guid, :spell, :power_type, :amount, :multiplier],
     [periodic?: false, threat_multiplier: 1.0]},
    {:AddThreat, [:source_guid, :target_guid, :amount], []},
    {:DispelFailed, [:source_guid, :target_guid, :spell_ids], []},
    {:PeriodicAuraLog, [:source_guid, :target_guid, :spell_id, :aura_type, :amount], [misc_value: 0, multiplier: 0.0]},
    {:AuraDuration, [:aura_slot, :duration_ms], []},
    {:RemoveAura, [:source_guid, :target_guid, :spell_id], []},
    {:HealEntity, [:target_guid, :amount], [source_guid: nil, spell: nil]},
    {:HealThreat, [:source_guid, :target_guid, :amount], []},
    {:ResurrectRequest, [:source_guid, :spell_id, :health, :mana], [delayed?: true]},
    {:SpellCastResult, [:spell_id], []},
    {:SpellCastFailed, [:spell_id, :reason],
     [required_focus_id: 0, required_area: 0, equipped_item_class: -1, equipped_item_subclass_mask: 0]},
    {:CheckCastRequirements, [:cast, :now], []},
    {:CastRequirementsResolved, [:cast, :requirements, :now], []},
    {:StartTriggeredChannel, [:spell, :targets, :context], [cast_item_guid: nil]},
    {:SpellCooldown, [:source_guid, :spell_id, :duration_ms], []},
    {:SpellSchoolLockout, [:source_guid, :cooldowns], []},
    {:SpellInterrupted, [:source_guid, :target_guid, :spell_id, :interrupted_spell_id], []},
    {:SpellModifier, [:modifier_type, :effect_index, :operation, :amount], []},
    {:PetSpellModifiers, [:source_guid, :target_guid, :holders], []},
    {:CooldownEvent, [:source_guid, :spell_id], []},
    {:ActivateCooldown, [:target_guid, :spell_id], [started_at: nil, cancel?: false]},
    {:ClearCooldown, [:target_guid, :spell_id], []},
    {:StandState, [:stand_state], []},
    {:SpellStart, [:source_guid, :spell_id, :duration_ms, :targets], []},
    {:SpellGo, [:source_guid, :spell_id, :hit_guids, :misses, :targets], [cast_item_guid: nil, projectile: nil]},
    {:ChannelStart, [:source_guid, :spell_id, :channel_time_ms], []},
    {:ChannelUpdate, [:source_guid, :channel_time_ms], []},
    {:SpellDelayed, [:source_guid, :delay_ms], []},
    {:DelayAura, [:source_guid, :target_guid, :spell_id, :delay_ms], []},
    {:DeliverSpell, [:target_guid, :cast_context, :spell], [delay_ms: nil]},
    {:ProcDamage, [:target_guid, :spell, :effect_index], []},
    {:TriggerSpellRequest, [:source_guid, :target_guid, :spell_id, :opts], []},
    {:ScriptedCast, [:entry, :target_guid], []},
    {:CharmCast, [:controller_guid, :control_spell_id, :control_applied_at, :spell_id, :target_guid], []},
    {:DeliverHealThreat, [:mob_guid, :source_guid, :target_guid, :amount], []},
    {:SpellContact, [:target_guid, :other_guid, :decision, :now], []},
    {:DrainPower, [:target_guid, :misc_value], []},
    {:GrantPower, [:target_guid, :misc_value, :amount], [source_guid: nil, spell: nil]},
    {:AddComboPoints, [:source_guid, :target_guid, :amount], [retention: nil]},
    {:DeliverSpellToQuery, [:source_guid, :source_level, :spell, :query], [exclude_guids: []]},
    {:TriggerSpell, [:source_guid, :source_level, :target_guid, :spell_id],
     [
       cast_item_guid: nil,
       target_role: nil,
       extra_attack?: false,
       triggering_spell_id: nil,
       slot: nil,
       amount: nil,
       effect_base_points: %{},
       duration_ms: nil,
       hit_context: nil,
       resolve_targets?: false,
       requires_living_target?: false
     ]}
  ]

  for {name, required, optional} <- effects do
    defmodule Module.concat(ThistleTea.Game.Entity.Logic.Effects, name) do
      @moduledoc false
      @enforce_keys required
      defstruct required ++ optional
    end
  end
end
