defmodule ThistleTea.Game.Player.SpellAreas do
  @moduledoc "Reconciles location-dependent player auras through the shared aura lifecycle."

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Entity.SpellReception
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Area
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellArea, as: SpellAreaLoader
  alias ThistleTea.Game.World.SpellAreas, as: AreaEnvironment

  def reconcile(state, options \\ [])

  def reconcile(%State{character: %Character{} = character} = state, options) do
    rules = Keyword.get_lazy(options, :rules, &SpellAreaLoader.autocast_rules/0)

    if relevant?(character, rules) do
      context = Keyword.get_lazy(options, :context, fn -> AreaEnvironment.context(character) end)
      snapshot = snapshot(character, context)

      if snapshot == state.spell_area_snapshot do
        state
      else
        character = reconcile_character(character, rules, context, options)
        %{state | character: character, spell_area_snapshot: snapshot(character, context)}
      end
    else
      %{state | spell_area_snapshot: nil}
    end
  end

  def reconcile(state, _options), do: state

  defp relevant?(character, rules) do
    Enum.any?(character.unit.auras || [], &Area.restricted?(&1.spell)) or
      Enum.any?(rules, &Area.player_matches?(&1, Area.player(character)))
  end

  defp snapshot(character, context), do: {%{context | player: Area.player(character)}, Death.alive?(character)}

  defp reconcile_character(character, rules, context, options) do
    now = Keyword.get_lazy(options, :now, &Time.now/0)
    lookup = Keyword.get(options, :spell_lookup, &SpellLoader.cached/1)
    character = remove_invalid(character, context, now)

    rules
    |> Enum.map(& &1.spell_id)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.reduce(character, fn id, character ->
      context = %{context | player: Area.player(character)}

      if Death.alive?(character) and not Aura.has_spell?(character, id) and
           Enum.any?(rules, &(&1.spell_id == id and Area.matches?(&1, context))) do
        apply_automatic(character, lookup.(id), now)
      else
        character
      end
    end)
    |> remove_invalid(context, now)
  end

  defp remove_invalid(character, context, now) do
    context = %{context | player: Area.player(character)}

    ids =
      for %Holder{spell: spell} <- character.unit.auras || [],
          Area.validate(spell, context) != :ok,
          do: spell.id

    case ids do
      [] ->
        character

      ids ->
        {character, effects} = Aura.remove_spells(character, ids, now)
        character |> EventSink.emit(effects) |> remove_invalid(context, now)
    end
  end

  defp apply_automatic(character, %Spell{} = spell, now) do
    guid = character.object.guid
    context = %{CastContext.from_caster(character, spell, guid) | triggered?: true}
    {character, effects} = SpellReception.receive(character, context, spell, now)
    EventSink.emit(character, [Effects.spell_go(guid, spell.id, [guid], Target.unit(guid)) | effects])
  end

  defp apply_automatic(character, _spell, _now), do: character
end
