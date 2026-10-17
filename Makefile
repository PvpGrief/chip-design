SRC    := $(wildcard src/*.v)
TOP    := tt_um_falling_leaves
BUILD  := build
SIM    := $(BUILD)/obj/sim_falling_leaves

FRAMES ?= 1080
EVERY  ?= 3
STORM  ?= 660:840

.PHONY: all lint test sim gif synth playground clean

all: lint test sim

lint:
	verilator --lint-only -Wall -Isrc $(SRC) --top-module $(TOP)

# Icarus Verilog smoke test (2 frames: sync timing + known pixels)
test: $(BUILD)/tb.vvp
	vvp -n $<

$(BUILD)/tb.vvp: $(SRC) test/tb.v | $(BUILD)
	iverilog -g2005 -Wall -o $@ -s tb test/tb.v $(SRC)

# Verilator "virtual monitor": decodes the pins, checks timing over many
# frames, verifies leaves fall and freeze works.
sim: $(SIM)
	$(SIM) --frames 600 --storm 300:420 --freeze 500:540

$(SIM): $(SRC) sim/sim_main.cpp | $(BUILD)
	verilator --cc --exe --build -O3 -Wall -Isrc $(SRC) $(abspath sim/sim_main.cpp) \
	  --top-module $(TOP) -Mdir $(BUILD)/obj -o sim_falling_leaves -CFLAGS -O2

# Render an animated preview to docs/preview.gif
gif: $(SIM)
	rm -rf $(BUILD)/frames && mkdir -p $(BUILD)/frames
	$(SIM) --frames $(FRAMES) --every $(EVERY) --storm $(STORM) --out $(BUILD)/frames
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
