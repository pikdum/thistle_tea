FROM docker.io/library/elixir:1.20 AS build
ENV MIX_ENV=prod
COPY --from=docker.io/oven/bun:1 /usr/local/bin/bun /usr/local/bin/bun
RUN apt-get update && apt-get install -y --no-install-recommends g++ make git \
    && rm -rf /var/lib/apt/lists/*
# the Fine C++ NIF compiles against namigator (rev matches flake.nix namigator-src)
RUN git clone https://github.com/pikdum/namigator /opt/namigator \
    && git -C /opt/namigator checkout 3ffc08cdbb0266f00c4d79a705d20e8e7c5ba8a5 \
    && git -C /opt/namigator submodule update --init recastnavigation
ENV NAMIGATOR_SRC=/opt/namigator
WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
COPY . .
RUN mix compile
RUN cd assets && bun install
RUN mix assets.deploy
RUN mix release

FROM docker.io/library/elixir:1.20
WORKDIR /app
COPY --from=build /app/_build/prod/rel/thistle_tea ./
EXPOSE 3724
EXPOSE 8085
EXPOSE 4000
CMD ["/app/bin/thistle_tea", "start"]
