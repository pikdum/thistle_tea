defmodule ThistleTea.Game.Player.WeaponProcs do
  @moduledoc "Resolves an accepted weapon hit against current usable equipment and cached spell data."

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Logic.CombatWeapon
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.WeaponProcs, as: ProcLogic
  alias ThistleTea.Game.Player.Enchantments
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata

  def trigger(%Character{} = character, %Effects.TriggerWeaponProcs{} = hit, now, roll \\ &:rand.uniform/0) do
    with true <- hit.source_guid == character.object.guid and hit.target_guid != character.object.guid,
         true <- Death.alive?(character),
         %{alive?: true} <- Metadata.query(hit.target_guid, [:alive?]),
         weapon when not is_nil(weapon) <- CombatWeapon.usable(character, hit.hand),
         %Item{} = item <- ItemStore.get(item_guid(character.player, hit.hand)),
         false <- Item.broken?(item),
         %{class: 2} = template <- Item.template(item) do
      spells = Map.new(ProcLogic.spells(template), fn {id, _ppm} -> {id, SpellLoader.cached(id)} end)
      {events, enchantments?} = ProcLogic.innate_events(character, hit, item, spells, now, roll)
      character = Effects.enqueue(character, events)

      if enchantments? do
        Enchantments.trigger_weapon_procs(
          character,
          %{
            victim_guid: hit.target_guid,
            outcome: :normal,
            hand: hit.hand,
            extra_attack?: hit.extra_attack?
          },
          roll
        )
      else
        character
      end
    else
      _ineligible -> character
    end
  end

  defp item_guid(%Player{mainhand: guid}, :mainhand), do: guid
  defp item_guid(%Player{offhand: guid}, :offhand), do: guid
  defp item_guid(%Player{ranged: guid}, :ranged), do: guid
  defp item_guid(_player, _hand), do: nil
end
