defmodule ThistleTea.Game.Player.LiquidSpells do
  @moduledoc "Loads the spell associated with the player's sampled liquid at the owner boundary."

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.LiquidSpells, as: LiquidSpellLogic
  alias ThistleTea.Game.Player.Movement
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Terrain.Liquid
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  def context(%Character{} = character, liquid) do
    {_, _, z, _} = character.movement_block.position

    with id when is_integer(id) <- Liquid.spell_id(liquid, z),
         %Spell{} = spell <- SpellLoader.cached(id) do
      context = CastContext.from_caster(character, spell, character.object.guid)
      %{context | triggered?: true, target_role: :caster, target_hostile?: false}
    else
      _ -> nil
    end
  end

  def context(_entity, _liquid), do: nil

  def restore(%Character{} = character) do
    context = context(character, Movement.terrain_liquid(character))
    LiquidSpellLogic.reconcile(character, context, Time.now())
  end
end
