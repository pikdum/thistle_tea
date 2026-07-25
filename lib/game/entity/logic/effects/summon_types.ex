defmodule ThistleTea.Game.Entity.Logic.Effects.SummonTypes do
  @moduledoc false

  effects = [
    {:SpawnAreaEffect, [:spell, :effect, :position, :duration_ms], []},
    {:SpawnFarsight, [:spell, :position, :duration_ms], []},
    {:DespawnAreaEffects, [:spell_id], []},
    {:DespawnEntity, [:target_guid], []},
    {:LeaveRitual, [:target_guid, :source_guid], []},
    {:SummonGameObject, [:entry, :duration_ms], [target_guid: nil]},
    {:SummonRequest, [:source_guid, :target_guid, :amount, :position], []},
    {:SummonCreature, [:summon, :steps, :target_guid], []},
    {:ControlGranted, [:source_guid, :target_guid, :spell_id, :spells, :enabled?], []},
    {:ControlReleased, [:source_guid, :target_guid], []},
    {:ReleaseControlled, [:source_guid, :target_guid], [spell_id: nil]},
    {:ViewpointGranted, [:source_guid, :target_guid], []},
    {:ViewpointReleased, [:source_guid, :target_guid], []},
    {:SummonPet, [:source_guid, :entry, :spell_id], []},
    {:TameCreature, [:source_guid, :entry], []},
    {:DismissPet, [:source_guid], [reason: nil]},
    {:SummonTotem, [:entry, :slot, :duration_ms], []},
    {:DespawnSelf, [:duration_ms, :respawn_delay_ms], []}
  ]

  for {name, required, optional} <- effects do
    type = name |> Atom.to_string() |> Macro.underscore() |> String.to_atom()

    defmodule Module.concat(ThistleTea.Game.Entity.Logic.Effects, name) do
      @moduledoc false
      @enforce_keys required
      defstruct [type: type] ++ required ++ optional
    end
  end
end
