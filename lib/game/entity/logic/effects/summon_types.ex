defmodule ThistleTea.Game.Entity.Logic.Effects.SummonTypes do
  @moduledoc false

  effects = [
    {:SpawnAreaEffect, [:spell, :effect, :position, :duration_ms], []},
    {:SpawnFarsight, [:spell, :position, :duration_ms], []},
    {:DespawnAreaEffects, [:spell_id], []},
    {:DespawnEntity, [:target_guid], []},
    {:RemoveSelf, [:respawn_delay_ms], []},
    {:ActivateGameObject, [:user_guid], []},
    {:SpellGameObjectAction, [:target_guid, :spell_id, :action], []},
    {:ApplyGameObjectAction, [:target_guid, :source_guid, :world, :spell_id, :action], []},
    {:RestoreGameObject, [:revision, :state, :delay_ms], []},
    {:FinishGameObjectUse, [:revision, :delay_ms], []},
    {:RespawnGameObject, [:blueprint, :duration_ms], []},
    {:DespawnGameObject, [:blueprint, :respawn_delay_ms], []},
    {:LoadGameObjectSpawn, [:blueprint], []},
    {:OperateGameObject, [:action, :reset_delay_ms], [blueprint: nil]},
    {:LeaveRitual, [:target_guid, :source_guid], []},
    {:SummonGameObject, [:entry, :duration_ms], [spell_id: nil, target_guid: nil, position: nil, owned?: true]},
    {:SummonRequest, [:source_guid, :target_guid, :amount, :position], []},
    {:SummonCreature, [:summon, :steps, :target_guid], []},
    {:ControlGranted, [:source_guid, :target_guid, :spell_id, :spells, :kind], []},
    {:ControlReleased, [:source_guid, :target_guid], []},
    {:ReleaseControlled, [:source_guid, :target_guid], [spell_id: nil]},
    {:ViewpointGranted, [:source_guid, :target_guid], []},
    {:ViewpointReleased, [:source_guid, :target_guid], []},
    {:SummonPet, [:source_guid, :entry, :spell_id], [health_percent: nil, level_offset: 0.0]},
    {:SummonMiniPet, [:entry, :spell_id, :duration_ms], [position: nil]},
    {:SummonWild, [:entry, :spell_id, :count, :duration_ms, :position], [radius_yards: 0.0, scatter?: false]},
    {:SummonGuardians, [:entry, :spell_id, :count, :duration_ms],
     [position: nil, radius_yards: 0.0, level_offset: 0.0, cast_item_guid: nil, triggered?: false, replace?: false]},
    {:TameCreature, [:source_guid, :entry], []},
    {:DismissPet, [:target_guid], []},
    {:LearnPetSpell, [:target_guid, :spell], []},
    {:PetAbilityUsed, [:spell_id], []},
    {:LearnPetRecipe, [:source_guid, :target_guid, :spell_id], []},
    {:PetHappinessChanged, [:source_guid, :target_guid, :happiness], []},
    {:PetProgressChanged, [:source_guid, :target_guid, :progress], []},
    {:PetReactionChanged, [:source_guid, :target_guid, :reaction_state], []},
    {:PetDied, [:source_guid, :target_guid], []},
    {:PetBroke, [:source_guid, :target_guid], []},
    {:SummonTotem, [:entry, :slot, :duration_ms], [spell_id: 0, health: 0]},
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
