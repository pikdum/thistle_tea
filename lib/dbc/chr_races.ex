defmodule ChrRaces do
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "ChrRaces" do
    field(:flags, :integer)
    field(:faction, :integer)
    field(:exploration_sound, :integer)
    field(:male_display, :integer)
    field(:female_display, :integer)
    field(:client_prefix, :string)
    field(:speed_modifier, :float)
    field(:base_lang, :integer)
    field(:creature_type, :integer)
    field(:login_effect, :integer)
    field(:unknown1, :integer)
    field(:res_sickness_spell, :integer)
    field(:splash_sound_entry, :integer)
    field(:unknown2, :integer)
    field(:client_file_path, :string)
    field(:cinematic_sequence, :integer)
    field(:name_en_gb, :string)
    field(:name_ko_kr, :string)
    field(:name_fr_fr, :string)
    field(:name_de_de, :string)
    field(:name_en_cn, :string)
    field(:name_en_tw, :string)
    field(:name_es_es, :string)
    field(:name_es_mx, :string)
    field(:name_flags, :string)
    field(:facial_hair_customisation_0, :string)
    field(:facial_hair_customisation_1, :string)
    field(:hair_customisation, :string)
  end
end
