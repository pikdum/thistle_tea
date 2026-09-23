defmodule ThistleTea.Game.Entity.Logic.Effects.CombatTypes do
  @moduledoc false

  effects = [
    {:CombatLeashEvent, [:ref, :event], []},
    {:CreatureGroupEvent, [:event], []},
    {:CreatureGroupCommand, [:command], []},
    {:EnterEvade, [:target_guid], []},
    {:PlayerDefeated, [:source_guid, :count_death?], []},
    {:BattlegroundDeath, [:world, :defeat], []},
    {:HonorDamage, [:source_guid, :damage, :now, :lethal?, :honorless?], []},
    {:HonorContribution, [:player_guid, :damage, :now, :lethal?, :honorless?], []},
    {:HonorCreatureKill, [:source_guid], []},
    {:HonorAward, [:target_guid, :award], []},
    {:DurabilityDamage, [:source_guid, :lethal?, :environmental?], []},
    {:DurabilityLoss, [:target_guid, :mode, :amount, :scope], [death?: false, caster_guid: nil, spell_id: nil]},
    {:EnvironmentalDamage, [:type, :damage], [absorbed: 0, resisted: 0]},
    {:DeliverAttack, [:target_guid, :attack], []},
    {:AdvanceCombatSkill, [:target_guid, :skill_id], []},
    {:PvpContact, [:target_guid, :role, :other, :now], [combat?: true]},
    {:PvpFlagsChanged, [:enabled?], []},
    {:AttackStart, [:source_guid, :target_guid], []},
    {:StartAttack, [:target_guid], []},
    {:AttackStop, [:source_guid, :target_guid], []},
    {:DuelDefeat, [:source_guid, :target_guid], []},
    {:DuelInterrupted, [:target_guid], []},
    {:DuelRequest, [:source_guid, :source_level, :target_guid, :entry, :position, :facing], []},
    {:AttackNotInRange, [], []},
    {:AttackBadFacing, [], []},
    {:AttackerGained, [:target_guid], []},
    {:AttackerLost, [:target_guid], []},
    {:ThreatRefGained, [:target_guid], []},
    {:ThreatRefLost, [:target_guid], []},
    {:TemporaryThreat, [:target_guid, :incarnation_id, :amount], []},
    {:DropThreat, [:target_guid], []},
    {:DropNearbyThreat, [], []},
    {:DropNearbyThreatResolved, [:target_guids, :metadata], []},
    {:BladeFlurry, [:target_guid, :damage, :spell_id], []},
    {:SecondaryMelee, [:target_guid, :damage, :spell_id, :range_yards], []},
    {:TapClaimed, [:player_guid], [:group_id]},
    {:TapCleared, [], []},
    {:AttackOutcome, [:target_guid, :source_guid, :outcome, :damage, :proc_damage, :spell_id],
     [hand: :mainhand, extra_attack?: false, proc_ex: nil]},
    {:AttackerStateUpdate, [:source_guid, :target_guid, :damage, :attack], []},
    {:CallAssistance, [:target_guid], []},
    {:CallForHelp, [:target_guid], [:radius]}
  ]

  for {name, required, optional} <- effects do
    defmodule Module.concat(ThistleTea.Game.Entity.Logic.Effects, name) do
      @moduledoc false
      @enforce_keys required
      defstruct required ++ optional
    end
  end
end
