PRIV_DIR := $(MIX_APP_PATH)/priv
NIF_PATH := $(PRIV_DIR)/native/namigator_ex.so
STAMP := $(PRIV_DIR)/native/.namigator_src.$(notdir $(NAMIGATOR_SRC))
C_SRC := $(shell pwd)/c_src
NAMIGATOR_SRC ?=

ifeq ($(strip $(NAMIGATOR_SRC)),)
$(error NAMIGATOR_SRC is unset — enter the devenv shell, or point it at a namigator checkout with the recastnavigation submodule)
endif

CXX ?= c++
TARGET_ABI ?= $(shell uname -s | tr '[:upper:]' '[:lower:]')

CPPFLAGS := -shared -fPIC -fvisibility=hidden -std=c++17 -Wno-multichar -DDT_POLYREF64
CPPFLAGS += -I$(ERTS_INCLUDE_DIR) -I$(FINE_INCLUDE_DIR)
CPPFLAGS += -I$(NAMIGATOR_SRC)
CPPFLAGS += -I$(NAMIGATOR_SRC)/pathfind
CPPFLAGS += -I$(NAMIGATOR_SRC)/recastnavigation/Detour/Include
CPPFLAGS += -I$(NAMIGATOR_SRC)/recastnavigation/Recast/Include

LDFLAGS += -pthread

ifeq ($(TARGET_ABI),darwin)
CPPFLAGS += -undefined dynamic_lookup -flat_namespace
endif

ifeq ($(DEBUG),1)
CPPFLAGS += -g
else
# -DNDEBUG matches namigator's supported Release build: its runtime queries
# guard invariants with assert(), which would abort the whole BEAM if they
# tripped on a reachable off-mesh/edge position inside this NIF.
CPPFLAGS += -O3 -DNDEBUG
endif

NAMIGATOR_SOURCES := \
	$(NAMIGATOR_SRC)/pathfind/BVH.cpp \
	$(NAMIGATOR_SRC)/pathfind/Map.cpp \
	$(NAMIGATOR_SRC)/pathfind/Tile.cpp \
	$(NAMIGATOR_SRC)/pathfind/pathfind_c_bindings.cpp \
	$(NAMIGATOR_SRC)/utility/AABBTree.cpp \
	$(NAMIGATOR_SRC)/utility/BinaryStream.cpp \
	$(NAMIGATOR_SRC)/utility/BoundingBox.cpp \
	$(NAMIGATOR_SRC)/utility/MathHelper.cpp \
	$(NAMIGATOR_SRC)/utility/Matrix.cpp \
	$(NAMIGATOR_SRC)/utility/Quaternion.cpp \
	$(NAMIGATOR_SRC)/utility/Ray.cpp \
	$(NAMIGATOR_SRC)/utility/String.cpp \
	$(NAMIGATOR_SRC)/utility/Vector.cpp

RECAST_SOURCES := \
	$(wildcard $(NAMIGATOR_SRC)/recastnavigation/Detour/Source/*.cpp) \
	$(wildcard $(NAMIGATOR_SRC)/recastnavigation/Recast/Source/*.cpp)

SOURCES := $(C_SRC)/namigator_ex.cpp $(NAMIGATOR_SOURCES) $(RECAST_SOURCES)

all: $(NIF_PATH)
	@ echo > /dev/null

# Nix store sources have normalized mtimes, so encode the store path in a stamp
# name to make input changes visible without invalidating every invocation.
$(STAMP):
	@ mkdir -p $(PRIV_DIR)/native
	@ touch $(STAMP)

$(NIF_PATH): $(SOURCES) $(STAMP)
	@test -d "$(NAMIGATOR_SRC)/recastnavigation/Detour/Source" || (echo "missing namigator recastnavigation submodule under $(NAMIGATOR_SRC)" >&2; exit 1)
	@ mkdir -p $(PRIV_DIR)/native
	$(CXX) $(CPPFLAGS) $(SOURCES) -o $(NIF_PATH) $(LDFLAGS)

clean:
	rm -f $(NIF_PATH) $(PRIV_DIR)/native/.namigator_src*

.PHONY: all clean
