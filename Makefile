GODOT ?= godot
SMOKES := tools_smoke views_smoke menu_smoke desk_smoke motion_check group_smoke audio_smoke

.PHONY: test import smoke check

# Import first: registers new class_name scripts in .godot/global_script_class_cache.cfg
import:
	$(GODOT) --headless --path . --import >/dev/null 2>&1 || true

test: import
	$(GODOT) --headless --path . -s tests/run_tests.gd

# Headless end-to-end smokes (real ToolController / HUD / desk / title flows). Each prints PASS.
# Any SCRIPT ERROR / Parse Error in a smoke's output fails the target (a HUD panel whose script
# does not compile still lets the smoke print PASS).
smoke: import
	@set -e; for s in $(SMOKES); do out=$$(timeout 90 $(GODOT) --headless --path . -s tools/$$s.gd 2>&1); \
		echo "$$out" | grep -E "PASS|FAIL" | tail -1; \
		if echo "$$out" | grep -qE "SCRIPT ERROR|Parse Error"; then echo "$$s: SCRIPT ERROR"; echo "$$out" | grep -E -A2 "SCRIPT ERROR|Parse Error" | head -12; exit 1; fi; done
	@out=$$(timeout 90 $(GODOT) --headless --fixed-fps 60 --path . -s tools/title_smoke.gd 2>&1); \
		echo "$$out" | grep -E "PASS|FAIL" | tail -1; \
		if echo "$$out" | grep -qE "SCRIPT ERROR|Parse Error"; then echo "title_smoke: SCRIPT ERROR"; exit 1; fi

# The full regression: unit tests + every smoke.
check: test smoke
