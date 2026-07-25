defmodule ThistleTea.Game.Entity.Logic.Effects.SpellTypes do
  @moduledoc false

  effects = [
    {:SpellDamage, [:source_guid, :target_guid, :spell_id, :spell, :school, :damage, :proc_type],
     [proc_damage: nil, periodic?: false, resisted: 0, absorbed: 0, crit?: false, blocked: 0]},
    {:SpellHeal, [:source_guid, :target_guid, :spell_id, :spell, :school, :damage, :proc_type, :crit?],
     [periodic?: false]},
    {:SpellLogMiss, [:source_guid, :target_guid, :spell_id, :reason], []},
    {:PeriodicAuraLog, [:source_guid, :target_guid, :spell_id, :aura_type, :amount], [misc_value: 0]},
    {:AuraDuration, [:aura_slot, :duration_ms], []},
    {:RemoveAura, [:source_guid, :target_guid, :spell_id], []},
    {:HealEntity, [:target_guid, :amount], []},
    {:HealThreat, [:source_guid, :target_guid, :amount], []},
    {:ResurrectRequest, [:source_guid, :spell_id, :health, :mana], []},
    {:SpellCastResult, [:spell_id], []},
    {:SpellCastFailed, [:spell_id, :reason], []},
    {:SpellCooldown, [:source_guid, :spell_id, :duration_ms], []},
    {:SpellModifier, [:modifier_type, :effect_index, :operation, :amount], []},
    {:CooldownEvent, [:source_guid, :spell_id], []},
    {:ClearCooldown, [:target_guid, :spell_id], []},
    {:StandState, [:stand_state], []},
    {:SpellStart, [:source_guid, :spell_id, :duration_ms, :raw_targets], []},
    {:SpellGo, [:source_guid, :spell_id, :hit_guids, :misses, :raw_targets], [cast_item_guid: nil]},
    {:ChannelStart, [:source_guid, :spell_id, :channel_time_ms], []},
    {:ChannelUpdate, [:source_guid, :channel_time_ms], []},
    {:SpellDelayed, [:source_guid, :delay_ms], []},
    {:DelayAura, [:source_guid, :target_guid, :spell_id, :delay_ms], []},
    {:DeliverSpell, [:target_guid, :cast_context, :spell], []},
    {:DeliverSpellOutcome, [:source_guid, :target_guid, :spell, :outcome], []},
    {:DrainPower, [:target_guid, :misc_value], []},
    {:GrantPower, [:target_guid, :misc_value, :amount], []},
    {:RefreshPartyAura, [:spell, :amount], []},
    {:RedirectDamage, [:source_guid, :target_guid, :school, :amount], []},
    {:TriggerSpell, [:source_guid, :source_level, :target_guid, :spell_id],
     [
       target_role: nil,
       triggering_spell_id: nil,
       slot: nil,
       amount: nil,
       duration_ms: nil,
       resolve_targets?: false
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
