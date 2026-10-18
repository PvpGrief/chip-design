SRC    := $(wildcard src/*.v)
TOP    := tt_um_pvpgrief_pong
BUILD  := build
SIM    := $(BUILD)/obj/sim_pong

FRAMES ?= 1200
EVERY  ?= 2

.PHONY: all lint test sim gif synth playground clean

all: lint test sim

lint:
	verilator --lint-only -Wall -Isrc $(SRC) --top-module $(TOP)

# Icarus Verilog smoke test (2 frames: sync timing + known pixels)
test: $(BUILD)/tb.vvp
	vvp -n $<

$(BUILD)/tb.vvp: $(SRC) test/tb_smoke.v | $(BUILD)
	iverilog -g2005 -Wall -o $@ -s tb_smoke test/tb_smoke.v $(SRC)

# Verilator "virtual monitor" with robot players: decodes the pins, checks
# timing, buttons, the gamepad path, rallies and scoring.
sim: $(SIM)
	$(SIM) --mode test

$(SIM): $(SRC) sim/sim_main.cpp | $(BUILD)
	verilator --cc --exe --build -O3 -Wall -Isrc $(SRC) $(abspath sim/sim_main.cpp) \
	  --top-module $(TOP) -Mdir $(BUILD)/obj -o sim_pong -CFLAGS -O2

# Render an animated preview to docs/preview.gif
gif: $(SIM)
	rm -rf $(BUILD)/frames && mkdir -p $(BUILD)/frames
	$(SIM) --mode demo --frames $(FRAMES) --every $(EVERY) --out $(BUILD)/frames
	python3 sim/make_gif.py $(BUILD)/frames docs/preview.gif --every $(EVERY)

# Single-file bundle for https://vga-playground.com
playground:
	python3 sim/make_playground.py

synth: | $(BUILD)
	yosys -q -p "read_verilog $(SRC); synth -flatten -top $(TOP); tee -o $(BUILD)/synth_stat.txt stat"

$(BUILD):
	mkdir -p $@

clean:
	rm -rf $(BUILD)
