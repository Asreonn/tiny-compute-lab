GODOT ?= godot

.PHONY: test import

# Import first: registers new class_name scripts in .godot/global_script_class_cache.cfg
import:
	$(GODOT) --headless --path . --import >/dev/null 2>&1 || true

test: import
	$(GODOT) --headless --path . -s tests/run_tests.gd
