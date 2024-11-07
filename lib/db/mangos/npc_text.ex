defmodule NpcText do
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "npc_text" do
    # Text Group 0
    field(:text0_0, :string)
    field(:text0_1, :string)
    field(:lang0, :integer, default: 0)
    field(:prob0, :float, default: 0.0)
    field(:em0_0_delay, :integer)
    field(:em0_0, :integer)
    field(:em0_1_delay, :integer)
    field(:em0_1, :integer)
    field(:em0_2_delay, :integer)
    field(:em0_2, :integer)

    # Text Group 1
    field(:text1_0, :string)
    field(:text1_1, :string)
    field(:lang1, :integer, default: 0)
    field(:prob1, :float, default: 0.0)
    field(:em1_0_delay, :integer)
    field(:em1_0, :integer)
    field(:em1_1_delay, :integer)
    field(:em1_1, :integer)
    field(:em1_2_delay, :integer)
    field(:em1_2, :integer)

    # Text Group 2
    field(:text2_0, :string)
    field(:text2_1, :string)
    field(:lang2, :integer, default: 0)
    field(:prob2, :float, default: 0.0)
    field(:em2_0_delay, :integer)
    field(:em2_0, :integer)
    field(:em2_1_delay, :integer)
    field(:em2_1, :integer)
    field(:em2_2_delay, :integer)
    field(:em2_2, :integer)

    # Text Group 3
    field(:text3_0, :string)
    field(:text3_1, :string)
    field(:lang3, :integer, default: 0)
    field(:prob3, :float, default: 0.0)
    field(:em3_0_delay, :integer)
    field(:em3_0, :integer)
    field(:em3_1_delay, :integer)
    field(:em3_1, :integer)
    field(:em3_2_delay, :integer)
    field(:em3_2, :integer)

    # Text Group 4
    field(:text4_0, :string)
    field(:text4_1, :string)
    field(:lang4, :integer, default: 0)
    field(:prob4, :float, default: 0.0)
    field(:em4_0_delay, :integer)
    field(:em4_0, :integer)
    field(:em4_1_delay, :integer)
    field(:em4_1, :integer)
    field(:em4_2_delay, :integer)
    field(:em4_2, :integer)

    # Text Group 5
    field(:text5_0, :string)
    field(:text5_1, :string)
    field(:lang5, :integer, default: 0)
    field(:prob5, :float, default: 0.0)
    field(:em5_0_delay, :integer)
    field(:em5_0, :integer)
    field(:em5_1_delay, :integer)
    field(:em5_1, :integer)
    field(:em5_2_delay, :integer)
    field(:em5_2, :integer)

    # Text Group 6
    field(:text6_0, :string)
    field(:text6_1, :string)
    field(:lang6, :integer, default: 0)
    field(:prob6, :float, default: 0.0)
    field(:em6_0_delay, :integer)
    field(:em6_0, :integer)
    field(:em6_1_delay, :integer)
    field(:em6_1, :integer)
    field(:em6_2_delay, :integer)
    field(:em6_2, :integer)

    # Text Group 7
    field(:text7_0, :string)
    field(:text7_1, :string)
    field(:lang7, :integer, default: 0)
    field(:prob7, :float, default: 0.0)
    field(:em7_0_delay, :integer)
    field(:em7_0, :integer)
    field(:em7_1_delay, :integer)
    field(:em7_1, :integer)
    field(:em7_2_delay, :integer)
    field(:em7_2, :integer)
  end
end
