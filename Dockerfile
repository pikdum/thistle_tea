FROM docker.io/library/elixir:1.18 AS build
ENV MIX_ENV=prod
COPY --from=docker.io/library/rust:slim /usr/local/cargo /usr/local/cargo
COPY --from=docker.io/library/rust:slim /usr/local/rustup /usr/local/rustup
COPY --from=docker.io/oven/bun:1 /usr/local/bin/bun /usr/local/bin/bun
ENV RUSTUP_HOME=/usr/local/rustup
ENV CARGO_HOME=/usr/local/cargo
ENV PATH=/usr/local/cargo/bin:$PATH
WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
COPY . .
RUN mix compile
RUN cd assets && bun install
RUN mix assets.deploy
RUN mix release

FROM docker.io/library/elixir:1.18
WORKDIR /app
COPY --from=build /app/_build/prod/rel/thistle_tea ./
EXPOSE 3724
EXPOSE 8085
EXPOSE 4000
CMD ["/app/bin/thistle_tea", "start"]
