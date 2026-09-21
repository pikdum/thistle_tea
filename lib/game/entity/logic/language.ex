defmodule ThistleTea.Game.Entity.Logic.Language do
  @moduledoc """
  Resolves player speech from learned language effects and active language
  auras. Addon traffic keeps its protocol language; whispers, emotes, and
  availability messages use the universal language after validation.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  @addon 0xFFFFFFFF
  @language_skills %{
    1 => 109,
    2 => 113,
    3 => 115,
    6 => 111,
    7 => 98,
    8 => 139,
    9 => 140,
    10 => 137,
    11 => 138,
    12 => 141,
    13 => 313,
    14 => 315,
    33 => 673
  }
  @languages Map.keys(@language_skills)
  @chat_types [0, 1, 2, 3, 4, 5, 6, 8, 0x0E, 0x14, 0x15, 0x57, 0x58]
  @addon_types [1, 2, 3, 4, 0x0E, 0x57, 0x58]
  @status_types [0x14, 0x15]
  @universal_types [6, 8 | @status_types]

  def addon, do: @addon

  def resolve(%Character{}, type, @addon) when type in @addon_types, do: {:ok, @addon}
  def resolve(%Character{}, type, 0) when type in @status_types, do: {:ok, 0}

  def resolve(%Character{} = character, type, language) when type in @chat_types and language in @languages do
    if known?(character, language) do
      {:ok, if(type in @universal_types, do: 0, else: override(character, language))}
    else
      {:error, :not_learned}
    end
  end

  def resolve(%Character{}, _type, _language), do: {:error, :invalid_language}

  def known?(%Character{internal: %{spellbook: spellbook}}, language)
      when is_map(spellbook) and language in @languages do
    Enum.any?(spellbook, fn {_id, %Spell{effects: effects}} ->
      Enum.any?(effects, &match?(%Effect{type: :language, misc_value: ^language}, &1))
    end)
  end

  def known?(%Character{}, _language), do: false

  def skill_ids(%Character{} = character) do
    for {language, skill_id} <- @language_skills, known?(character, language), do: skill_id
  end

  defp override(character, language) do
    character
    |> Aura.auras_of_type(:mod_language)
    |> Enum.find_value(language, fn aura ->
      if aura.misc_value in @languages, do: aura.misc_value
    end)
  end
end
