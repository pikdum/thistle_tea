FROM elixir:1.17-alpine AS build
ENV MIX_ENV prod
WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs mix.lock ./
RUN mix deps.get
COPY . .
RUN mix compile
RUN mix release

FROM elixir:1.17-alpine
WORKDIR /app
COPY --from=build /app/_build/prod/rel/thistle_tea ./
COPY --from=build /app/mangos0.sqlite ./
COPY --from=build /app/dbc.sqlite ./
EXPOSE 3724
EXPOSE 8085
CMD ["/app/bin/thistle_tea", "start"]
