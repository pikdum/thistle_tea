defmodule ThistleTea.Game.World.Entity.GameObject.Goober do
  @moduledoc "Object-owner boundary for quest-object admission, scripts, and spell delivery."

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.GameObject.Goober
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.GameObject.SpellCast
  alias ThistleTea.Game.World.Loader.EventScript, as: EventScriptLoader
  alias ThistleTea.Game.World.Loader.GameObjectScript, as: GameObjectScriptLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  def use(%GameObject{internal: %{world: world}} = object, user_guid, world, quest_allowed?, now) do
    if match?({^world, _, _, _}, World.position(user_guid)) do
      Goober.use(object, quest_allowed?, now)
    else
      {:unavailable, object}
    end
  end

  def use(object, _user_guid, _world, _quest_allowed?, _now), do: {:unavailable, object}

  def start_script(%GameObject{internal: %{goober: goober}} = object, user_guid) do
    steps =
      if goober.event_id > 0 do
        EventScriptLoader.get(goober.event_id)
      else
        GameObjectScriptLoader.get(GameObject.db_guid(object))
      end

    ported = GameObjectScriptLoader.ported(object.object.entry, object.movement_block.position)
    Entity.start_script(user_guid, ported ++ steps, object.object.guid)
  end

  def start_spell(%GameObject{internal: %{goober: %{spell_id: id}}} = object, user_guid) when id > 0 do
    case SpellLoader.cached(id) do
      %Spell{cast_time_ms: delay} = spell when is_integer(delay) and delay > 0 ->
        Process.send_after(self(), {:game_object_spell, spell, user_guid}, delay)
        Effects.enqueue(object, Effects.spell_start(object.object.guid, id, delay, Target.unit(user_guid)))

      %Spell{} = spell ->
        finish_spell(object, spell, user_guid)

      _ ->
        object
    end
  end

  def start_spell(object, _user_guid), do: object

  def finish_spell(%GameObject{internal: %{world: world}} = object, %Spell{} = spell, user_guid) do
    if match?({^world, _, _, _}, World.position(user_guid)) do
      SpellCast.launch(object, spell, user_guid)
    else
      object
    end
  end
end
