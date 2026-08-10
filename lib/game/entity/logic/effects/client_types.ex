defmodule ThistleTea.Game.Entity.Logic.Effects.ClientTypes do
  @moduledoc false

  effects = [
    {:CancelAutoRepeat, [], []},
    {:ConsumeCastItem, [:cast_item_guid], []},
    {:FeedPet, [:cast_item_guid, :target_guid, :spell_id, :range_yards], []},
    {:EnchantItem, [:target_guid, :spell, :effect], []},
    {:OpenGameObject, [:target_guid], []},
    {:CreateItem, [:item_id, :count], []},
    {:GiveItem, [:target_guid, :item_id, :count], []},
    {:ConsumeReagents, [:reagents], []},
    {:MonsterTalk, [:text, :chat_type, :target_guid], []},
    {:Emote, [:emote_id], []},
    {:GameObjectCustomAnimation, [:animation], []},
    {:ScriptSteps, [:steps, :target_guid, :duration_ms], []},
    {:ScriptedEventCommand, [:world, :source_guid, :target_guid, :step], []},
    {:InstanceDataCommand, [:world, :field, :value, :mode], [script_id: nil]},
    {:InstanceCreatureEvent, [:world, :creature_guid, :creature_entry, :event], [db_guid: nil]},
    {:SendScriptEvent, [:owner_guid, :invoker_guid, :event_id, :data], []},
    {:ForwardScriptSteps, [:target_guid, :steps, :source_guid], []},
    {:SendTaxiPath, [:target_guid, :path_id], []},
    {:PlaySound, [:sound_id], []},
    {:PlayObjectSound, [:sound_id], []},
    {:FactionAtWarChanged, [:index, :enabled], []},
    {:ForcedReactionsChanged, [:reactions, :friendly_faction_ids], []},
    {:ReputationChange, [:faction_id, :value], []},
    {:QuestCastCredit, [:target_guids, :spell_id], []},
    {:QuestEventCredit, [:player_guid, :quest_id], [group?: false, distance: 0, world_object_guid: nil]},
    {:QuestFail, [:player_guid, :quest_id], [group?: false]},
    {:QuestInteractionCredit, [:player_guid, :target_guid], []},
    {:QuestKillCredit, [:player_guid, :creature_entry], [group?: false]}
  ]

  for {name, required, optional} <- effects do
    defmodule Module.concat(ThistleTea.Game.Entity.Logic.Effects, name) do
      @moduledoc false
      @enforce_keys required
      defstruct required ++ optional
    end
  end
end
