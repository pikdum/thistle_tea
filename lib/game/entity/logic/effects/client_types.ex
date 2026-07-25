defmodule ThistleTea.Game.Entity.Logic.Effects.ClientTypes do
  @moduledoc false

  effects = [
    {:ConsumeCastItem, [:cast_item_guid], []},
    {:FeedPet, [:cast_item_guid, :target_guid, :spell_id, :range_yards], []},
    {:EnchantItem, [:target_guid, :spell, :effect], []},
    {:OpenGameObject, [:target_guid], []},
    {:CreateItem, [:item_id, :count], []},
    {:GiveItem, [:target_guid, :item_id, :count], []},
    {:ConsumeReagents, [:reagents], []},
    {:MonsterTalk, [:text, :chat_type, :target_guid], []},
    {:Emote, [:emote_id], []},
    {:ScriptSteps, [:steps, :target_guid, :duration_ms], []},
    {:ForwardScriptSteps, [:target_guid, :steps, :source_guid], []},
    {:PlaySound, [:sound_id], []},
    {:PlayObjectSound, [:sound_id], []}
  ]

  for {name, required, optional} <- effects do
    defmodule Module.concat(ThistleTea.Game.Entity.Logic.Effects, name) do
      @moduledoc false
      @enforce_keys required
      defstruct required ++ optional
    end
  end
end
