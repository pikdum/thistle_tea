defmodule ThistleTea.Game.Entity.Logic.Effects.ClientTypes do
  @moduledoc false

  effects = [
    {:StartMirrorTimer, [:timer, :remaining, :duration, :scale], []},
    {:StopMirrorTimer, [:timer], []},
    {:CancelAutoRepeat, [], []},
    {:FeignDeathResisted, [], []},
    {:ConsumeCastItem, [:cast_item_guid], []},
    {:TransformItem, [:cast_item_guid, :spell, :item_id], []},
    {:FeedPet, [:cast_item_guid, :target_guid, :spell_id, :range_yards], []},
    {:EnchantItem, [:target_guid, :spell, :effect], [cast_item_guid: nil]},
    {:OpenGameObject, [:target_guid], [spell_id: nil, range_yards: nil]},
    {:OpenLock, [:target_guid, :spell], [cast_item_guid: nil, success_events: []]},
    {:PickPocket, [:target_guid, :spell_id], []},
    {:SkinCorpse, [:target_guid, :spell_id], []},
    {:RemoveInsignia, [:targets, :spell_id], []},
    {:CancelBattlegroundResurrection, [:world, :guid], []},
    {:DisenchantItem, [:target_guid, :spell_id], []},
    {:CreateItem, [:item_id, :count], [spell_id: nil]},
    {:GiveItem, [:target_guid, :item_id, :count], [partial?: false]},
    {:ConsumeReagents, [:reagents], []},
    {:LaunchRanged, [:kind, :request, :now], []},
    {:MonsterTalk, [:text, :chat_type, :target_guid], []},
    {:Emote, [:emote_id], []},
    {:EmoteAnimation, [:emote_id], []},
    {:EmoteState, [:emote_id], []},
    {:TextEmote, [:text_emote, :emote, :name], []},
    {:GameObjectCustomAnimation, [:animation], []},
    {:ScriptSteps, [:steps, :target_guid, :duration_ms], [run_id: nil, receipt: nil]},
    {:ScriptedEventCommand, [:world, :source_guid, :target_guid, :step], [reply: nil]},
    {:ScriptCompleted, [:run_id, :completion, :status], []},
    {:ScriptReply, [:request, :status], []},
    {:InstanceDataCommand, [:world, :field, :value, :mode], [script_id: nil]},
    {:InstanceCreatureEvent, [:world, :creature_guid, :creature_entry, :event], [db_guid: nil, bind_player: nil]},
    {:SendScriptEvent, [:owner_guid, :invoker_guid, :event_id, :data], []},
    {:ForwardScriptSteps, [:target_guid, :steps, :source_guid], [reply: nil]},
    {:StartGroupScript, [:steps, :target_guid], []},
    {:SendTaxiPath, [:target_guid, :path_id], [spell_id: nil]},
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
