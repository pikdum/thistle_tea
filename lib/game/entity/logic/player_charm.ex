defmodule ThistleTea.Game.Entity.Logic.PlayerCharm do
  @moduledoc "Selects the learned abilities and combat role used by a charmed player's AI."

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Possession
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Spell

  def spells(%Character{internal: %{spellbook: spellbook}}) when is_map(spellbook) do
    spellbook
    |> Map.values()
    |> Enum.filter(&usable?/1)
    |> Enum.group_by(&rank_key/1)
    |> Enum.map(fn {_key, ranks} -> Enum.max_by(ranks, &{&1.rank || 0, &1.spell_level, &1.id}) end)
    |> Enum.sort_by(& &1.id)
  end

  def spells(_entity), do: []

  def melee?(%Character{unit: %{class: class}}), do: class in [1, 2, 4, 11]

  def command(%Character{internal: %{possession: %Possession{kind: :charm} = control}} = entity, command, target, now) do
    case command do
      :attack when is_integer(target) and target > 0 ->
        %{entity | internal: %{entity.internal | possession: %{control | command: :attack, command_target: target}}}

      command when command in [:stay, :follow, :passive] ->
        entity = Casting.interrupt(entity, now)
        {entity, effects} = PlayerCombat.stop_attack(entity)
        control = if command == :passive, do: %{control | reaction: :passive}, else: %{control | command: command}
        entity = %{entity | internal: %{entity.internal | possession: %{control | command_target: nil}}}
        Effects.enqueue(entity, effects)

      reaction when reaction in [:defensive, :aggressive] ->
        %{entity | internal: %{entity.internal | possession: %{control | reaction: reaction}}}

      _unknown ->
        entity
    end
  end

  defp usable?(%Spell{spell_family: family} = spell) do
    family != 0 and Spell.harmful?(spell) and not Spell.breaks_on_damage?(spell) and
      not Enum.any?([:passive, :do_not_display, :no_autocast_ai], &Spell.attribute?(spell, &1))
  end

  defp rank_key(%Spell{first_in_chain: first}) when is_integer(first) and first > 0, do: {:chain, first}
  defp rank_key(%Spell{} = spell), do: {spell.spell_family, spell.spell_icon, spell.spell_visual, spell.name}
end
