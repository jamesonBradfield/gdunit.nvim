.PHONY: test test-specific clean

# Run all tests
test:
	nvim -l ./tests/busted.lua tests/

# Run a specific test file
# Usage: make test-specific TEST=cmd_utils_spec.lua
test-specific:
	@if [ -z "$(TEST)" ]; then \
		echo "Error: No test specified. Usage: make test-specific TEST=cmd_utils_spec.lua"; \
		exit 1; \
	fi
	nvim -l ./tests/busted.lua tests/$(TEST)

# Clean test artifacts
clean:
	rm -rf .tests
	rm -f luacov.stats.out luacov.report.out
