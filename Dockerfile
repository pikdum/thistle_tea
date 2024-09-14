FROM elixir:1.17 AS build
ENV MIX_ENV=prod
COPY --from=rust:latest /usr/local/cargo/bin/* /usr/local/bin/
RUN rustup default stable
WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs mix.lock ./
RUN mix deps.get
COPY . .
RUN mix compile
RUN mix release

FROM elixir:1.17
WORKDIR /app
COPY --from=build /app/_build/prod/rel/thistle_tea ./
EXPOSE 3724
EXPOSE 8085
CMD ["/app/bin/thistle_tea", "start"]
