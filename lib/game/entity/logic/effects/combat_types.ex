defmodule ThistleTea.Game.Entity.Logic.Effects.CombatTypes do
  @moduledoc false

  effects = [
    {:DeliverAttack, [:target_guid, :attack], []},
    {:AttackStart, [:source_guid, :target_guid], []},
    {:StartAttack, [:target_guid], []},
    {:AttackStop, [:source_guid, :target_guid], []},
    {:DuelDefeat, [:source_guid, :target_guid], []},
    {:DuelInterrupted, [:target_guid], []},
    {:DuelRequest, [:source_guid, :source_level, :target_guid, :entry, :position, :facing], []},
    {:AttackNotInRange, [], []},
    {:AttackerGained, [:target_guid], []},
    {:AttackerLost, [:target_guid], []},
    {:ThreatRefGained, [:target_guid], []},
    {:ThreatRefLost, [:target_guid], []},
    {:DropThreat, [:target_guid], []},
    {:DropNearbyThreat, [], []},
    {:DropNearbyThreatResolved, [:target_guids, :metadata], []},
    {:BladeFlurry, [:target_guid, :damage, :spell_id], []},
    {:SecondaryMelee, [:target_guid, :damage, :spell_id, :range_yards], []},
    {:TapClaimed, [:player_guid], [:group_id]},
    {:TapCleared, [], []},
    {:AttackOutcome, [:target_guid, :source_guid, :outcome, :damage, :proc_damage, :spell_id], []},
    {:AttackerStateUpdate, [:source_guid, :target_guid, :damage, :attack], []},
    {:CallAssistance, [:target_guid], []},
    {:CallForHelp, [:target_guid], []}
  ]

  for {name, required, optional} <- effects do
    defmodule Module.concat(ThistleTea.Game.Entity.Logic.Effects, name) do
      @moduledoc false
      @enforce_keys required
      defstruct required ++ optional
    end
  end
end
