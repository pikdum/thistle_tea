defmodule ThistleTea.Game.Entity.Logic.Effects.SummonTypes do
  @moduledoc false

  effects = [
    {:SpawnAreaEffect, [:spell, :effect, :position, :duration_ms], []},
    {:SpawnFarsight, [:spell, :position, :duration_ms], []},
    {:DespawnAreaEffects, [:spell_id], []},
    {:DespawnEntity, [:target_guid], []},
    {:RemoveSelf, [:respawn_delay_ms], []},
    {:ActivateGameObject, [:user_guid], []},
    {:LeaveRitual, [:target_guid, :source_guid], []},
    {:SummonGameObject, [:entry, :duration_ms], [target_guid: nil, position: nil]},
    {:SummonRequest, [:source_guid, :target_guid, :amount, :position], []},
    {:SummonCreature, [:summon, :steps, :target_guid], []},
    {:ControlGranted, [:source_guid, :target_guid, :spell_id, :spells, :kind], []},
    {:ControlReleased, [:source_guid, :target_guid], []},
    {:ReleaseControlled, [:source_guid, :target_guid], [spell_id: nil]},
    {:ViewpointGranted, [:source_guid, :target_guid], []},
    {:ViewpointReleased, [:source_guid, :target_guid], []},
    {:SummonPet, [:source_guid, :entry, :spell_id], []},
    {:TameCreature, [:source_guid, :entry], []},
    {:DismissPet, [:target_guid], []},
    {:SummonTotem, [:entry, :slot, :duration_ms], []},
    {:DespawnSelf, [:duration_ms, :respawn_delay_ms], []},
    {:RespawnSelf, [:even_if_alive?], []}
  ]

  for {name, required, optional} <- effects do
    defmodule Module.concat(ThistleTea.Game.Entity.Logic.Effects, name) do
      @moduledoc false
      @enforce_keys required
      defstruct required ++ optional
    end
  end
end
