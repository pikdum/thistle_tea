ExUnit.start()
ExUnit.configure(exclude: [vmangos_db: true, dbc_db: true, namigator_maps: true])

Code.require_file("support/pet_control_owner.exs", __DIR__)
